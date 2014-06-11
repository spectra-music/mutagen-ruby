require 'mutagen/constants'
require 'mutagen/id3/util'
require 'mutagen/id3/specs'
require 'zlib'


module Mutagen
  module ID3
    include Specs

    def is_valid_frame_id(frame_id)
      true
    end

    module ParentFrames
      # Fundamental unit of ID3 data.
      #
      # ID3 tags are split into frames. Each frame has a potentially
      # different structure, and so this base class is not very featureful.
      class Frame

        FLAG23_ALTERTAG  = 0x8000
        FLAG23_ALTERFILE = 0x4000
        FLAG23_READONLY  = 0x2000
        FLAG23_COMPRESS  = 0x0080
        FLAG23_ENCRYPT   = 0x0040
        FLAG23_GROUP     = 0x0020

        FLAG24_ALTERTAG  = 0x4000
        FLAG24_ALTERFILE = 0x2000
        FLAG24_READONLY  = 0x1000
        FLAG24_GROUPID   = 0x0040
        FLAG24_COMPRESS  = 0x0008
        FLAG24_ENCRYPT   = 0x0004
        FLAG24_UNSYNCH   = 0x0002
        FLAG24_DATALEN   = 0x0001

        attr_accessor :encoding

        FRAMESPEC = []

        #TODO: Refactor first condition into a .clone method
        def initialize(*args, ** kwargs)
          # If we've only got one argument, and the other argument is the same class,
          # we're going to clone the other object's fields into ours.
          if args.size == 1 and kwargs.size == 0 and args[0].is_a? self.class
            other = args[0]
            self.class::FRAMESPEC.each do |checker|
              #if other.instance_variable_defined?('@'+checker.name)
              begin
                val = checker.validate(self, other.instance_variable_get("@#{checker.name}"))
              rescue Mutagen::ValueError => e
                raise e.exception("#{checker.name}: #{e.message}")
              end
              #else
              #  raise "#{checker.name}: No instance variable for checker on #{other}"
              #end
              instance_variable_set("@#{checker.name}", val)
              self.class.send('attr_reader', checker.name.to_sym)
            end
          else
            self.class::FRAMESPEC[0...args.size].zip(args) do |checker, val|
              instance_variable_set("@#{checker.name}", checker.validate(self, val))
              self.class.send('attr_reader', checker.name.to_sym)
            end
            self.class::FRAMESPEC[args.size..-1].each do |checker|
              begin
                #TODO: does checker.name.to_sym improve performance?
                validated = checker.validate(self, kwargs[checker.name])
              rescue Mutagen::ValueError => e
                raise e.exception("#{checker.name}: #{e.message}")
              end
              instance_variable_set("@#{checker.name}", validated)
              self.class.send("attr_reader", checker.name.to_sym)
            end
          end
        end

        # Returns a frame copy which is suitable for writing into a v2.3 tag
        #
        # kwargs get passed to the specs
        def _get_v23_frame(** kwargs)
          new_kwargs = {}
          self.class::FRAMESPEC.each do |checker|
            name             = checker.name
            value            = instance_variable_get('@'+name)
            new_kwargs[name] = checker._validate23(value, ** kwargs)
          end
          self.class.new(** new_kwargs)
        end

        # An internal key used to ensure frame uniqueness in a tag
        def hash_key
          frame_id
        end

        # ID3v2 three or four character frame ID
        def frame_id
          self.class.to_s
        end

        # represention of a frame
        # The string returned is a valid ruby expression
        # to construct a copy of this frame
        def repr
          kw = []
          self.class::FRAMESPEC.each do |attr|
            kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
          end
          "#{self.class.to_s}.new(#{kw.join(', ')})"
        end

        protected
        def read_data(data)
          odata = data
          self.class::FRAMESPEC.each do |reader|
            raise ID3JunkFrameError if data.emtpy?
            begin
              value, data = reader.read(self, data)
              #rescue
              #  raise ID3JunkFrameError
            end
            instance_variable_set('@'+reader.name, value)
          end
          leftover = Mutagen.strip_arbitrary(data, "\x00")
          unless leftover.empty?
            warn "Leftover data: #{self.class}: #{data} (from #{odata})"
          end
        end

        def write_data
          data = []
          self.class::FRAMESPEC.each do |writer|
            data << writer.write(self, instance_variable_get('@'+writer.name))
          end
          data.join
        end

        # Return a human-readable representation of the frame
        def pprint
          inspect
        end

        def _pprint
          '[unrepresentable data]'
        end

        alias_method :to_s, :_pprint

        def inspect
          "#<#{self.class} #{self.to_s}>"
        end


        # Construct this ID3 frame from raw string dta
        def self.from_data(id3, tflags, data)
          if id3._V24 <= id3.version
            if tflags & (Frame::FLAG24_COMPRESS | Frame::FLAG24_DATALEN)
              # The data length int is syncsafe in 2.4 (but not 2.3).
              # However, we don't actually need the data length int,
              # except to work around a QL 0.12 bug, and in that case
              # all we need are the raw bytes.
              datalen_bytes = data[0...4]
              data          = data[4..-1]
            end
            if tflags & Frame::FLAG24_UNSYNCH or id3.f_unsynch
              begin
                data = Unsynch.decode data
              rescue Mutagen::ValueError => err
                raise ID3BadUnsynchData, "#{err}:#{data}" if id3.PEDANTIC
              end
            end
            raise ID3EncryptionUnsupportedError if tflags & Frame::FLAG24_ENCRYPT
            if tflags & Frame::FLAG24_COMPRESS
              begin
                data = Zlib::Deflate(data)
              rescue Zlib::Error
                # the initial mutagen that went out with QL 0.12 did not
                # write the 4 bytes of uncompressed size. Compensate.
                data = datalen_bytes + data
                begin
                  data = Zlib::Deflate(data)
                rescue Zlib::Error => err
                  raise ID3BadCompressedData, "#{err}: #{data}" if id3.PEDANTIC
                end
              end
            end
          elsif id3._V23 <= id3.version
            if tflags & Frame::FLAG23_COMPRESS
              usize, _ = unpack('L>', data[0...4])
              data     = data[4..-1]
            end
            raise ID3EncryptionUnsupportedError if tflags & Frame::FLAG23_ENCRYPT
            if tflags & Frame::FLAG23_COMPRESS
              begin
                data = Zlib::Deflate(data)
              rescue Zlib::Error => err
                raise ID3BadCompressedData, "#{err}: #{data}"
              end
            end
          end
          frame = self.class.new
          frame.instance_variable_set(:raw_data, data)
          frame.singleton_class.class_eval { attr_reader :raw_data }
          frame.instance_variable_set(:flags, tflags)
          frame.singleton_class.class_eval { attr_reader :flags }
          frame.read_data(data)
          frame
        end
      end

      # A frame with optional parts
      #
      # Some ID3 frames have optional data; this lass extnds Frame to
      # provide support for those parts.
      class FrameOpt < Frame
        OPTIONALSPEC = []

        def initialize
          super(*args, ** kwargs)
          self.class::OPTIONALSPEC.each do |spec|
            if kwargs.has_key? spec.name
              validated = spec.validate(self, kwargs[spec.name])
              instance_variable_set("@#{spec.name}", validated)
              self.class.send('attr_reader', spec.name.to_sym)
            else
              break
            end
          end
        end

        protected
        def read_data(data)
          odata = data
          self.class::FRAMESPEC.each do |reader|
            raise ID3JunkFrameError if data.empty?
            value, data = reader.read(self, data)
            instance_variable_set("@#{reader.name}", value)
            self.class.send('attr_reader', spec.name.to_sym) unless self.respond_to? spec.name.to_sym
          end
          unless data.nil? or data.empty?
            self.class::OPTIONALSPEC.each do |reader|
              break if data.empty?
              value, data = reader.read(self, data)
              instance_variable_set("@#{reader.name}", value)
              self.class.send('attr_reader', spec.name.to_sym) unless self.respond_to? spec.name.to_sym
            end
          end
          leftover = Mutagen.strip_arbitrary(data, "\x00")
          unless leftover.empty?
            warn "Leftover data: #{self.class}: #{data} (from #{odata})"
          end
        end

        def write_data
          data = []
          self.class::FRAMESPEC.each do |writer|
            data << writer.write(self, instance_variable_get("@#{writer.name}"))
          end
          self.class::OPTIONALSPEC.each do |writer|
            #TODO: Maybe we should store the ivar and check `.nil?` instead?
            break unless instance_variable_defined? '@'+writer.name
            data << writer.write(self, instance_variable_get("@#{writer.name}"))
          end
          data.join
        end


        def repr
          kw = []
          self.class::FRAMESPEC.each do |attr|
            kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
          end
          self.class::OPTIONALSPEC.each do |attr|
            if instance_variable_defined? '@'+attr.name
              kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
            end
          end
          "#{self.class}.new(#{kw.join(', ')})"
        end
      end

      # Text strings.
      #
      # Text frames support casts to unicode or str objects, as well as
      # list-like indexing, extend, and append.
      #
      # Iterating over a TextFrame iterates over its strings, not its
      # characters.
      #
      # Text frames have a 'text' attribute which is the list of strings,
      # and an 'encoding' attribute; 0 for ISO-8859 1, 1 UTF-16, 2 for
      # UTF-16BE, and 3 for UTF-8. If you don't want to worry about
      # encodings, just set it to 3.
      class TextFrame < Frame
        include Enumerable

        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::MultiSpec.new('text', Specs::EncodedTextSpec.new('text'), sep: "\u0000")
        ]

        def to_s
          @text.join("\u0000")
        end

        def ==(other)
          if other.is_a? String
            self.to_s == other
          else
            @text == other
          end
        end

        def [](index)
          @text[index]
        end

        def []=(index, value)
          @text[index, value]
        end

        def each(&block)
          @text.each(&block)
        end

        def push(*args)
          @text.push(*args)
        end

        def <<(value)
          @text << value
        end

        # def method_missing(method_sym, *args, **kwargs)
        #   if @text.methods.include? method_sym
        #     @text.send(method_sym, *args)
        #   end
        # end

        def _pprint
          @text.join ' / '
        end

        def text
          @text
        end
      end

      # Numerical text strings.
      #
      # The numeric value of these frames can be gotten with `to_i`, e.g.
      # @example
      #    frame = TLEN.new '12345'
      #    length = frame.to_i
      class NumericTextFrame < TextFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::MultiSpec.new('text', Specs::EncodedNumericPartTextSpec.new('text'), sep: "\u0000")
        ]

        # Get the numerical value of the string
        def to_i
          text[0].to_i
        end

        alias_method :+@, :to_i
      end

      # Multivalue numerical text strings
      #
      # These strings indicate 'part (e.g. track) X of Y', and `.to_i`
      # returns the first value:
      # @example
      #    frame = TRCK('4/15')
      #    track = frame.to_i # track == 4
      class NumericPartTextFrame < TextFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::MultiSpec.new('text', Specs::EncodedNumericPartTextSpec.new('text'), sep: "\u0000")
        ]

        def to_i
          text[0].split('/')[0].to_i
        end

        alias_method :+@, :to_i
        alias_method :first, :to_i

        def second
          text[0].split('/')[1].to_i
        end
      end

      # A list of time stamps.
      #
      # The 'text' attribute in this frame is a list of ID3TimeStamp
      # objects, not a list of strings
      class TimeStampTextFrame < TextFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::MultiSpec.new('text', Specs::TimeStampSpec.new('stamp'), sep: ','),
        ]

        def to_s
          text.map { |stamp| stamp.text }.join(',')
        end

        def _pprint
          text.map { |stamp| stamp.text }.join(' / ')
        end
      end

      # A frame containing a URL string.
      #
      # The ID3 specification is silent about IRIs and normalized URL
      # forms. Mutagen assumes all URLs in files are encoded as Latin 1,
      # but string conversion of this frame returns a UTF-8 representation
      # for compatibility with other string conversions.
      #
      # The only sane way to handle URLs in MP3s is to restrict them to
      # ASCII.
      class UrlFrame < Frame
        FRAMESPEC = [Specs::Latin1TextSpec.new('url')]

        def to_s
          url
        end

        def ==(other)
          url == other
        end

        def _pprint
          url
        end
      end

      class UrlFrameU < UrlFrame
        def hash_key
          "#{frame_id}:#{url}"
        end
      end


      # Paired text strings.
      #
      # Some ID3 frames pair text strings, to associate names with a more
      # specific involvement in the song. The 'people' attribute of these
      # frames contains a list of pairs::
      #
      #      [['trumpet', 'Miles Davis'], ['bass', 'Paul Chambers']]
      #
      # Like text frames, these frames also have an encoding attribute.
      class PairedTextFrame < Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::MultiSpec.new('people',
                                 Specs::EncodedTextSpec.new('involvement'),
                                 Specs::EncodedTextSpec.new('person'))
        ]

        def ==(other)
          people == other
        end
      end

      # Binary data
      #
      # The 'data' attribute contains the raw byte string
      class BinaryFrame < Frame
        FRAMESPEC = [Specs::BinaryDataSpec.new('data')]

        def ==(other)
          data == other
        end
      end
    end
    module Frames

      # Album
      class TALB < ParentFrames::TextFrame
      end

      # Beats per Minute
      class TBPM < ParentFrames::NumericTextFrame
      end

      # Composer
      class TCOM < ParentFrames::TextFrame
      end

      # Content type (Genre)
      #
      # ID3 has several ways genres can be represented; for convenience.
      # Use the 'genres' property rather than the 'text' attribute
      class TCON < ParentFrames::TextFrame
        GENRES = Mutagen::Constants::GENRES

        def genres
          genres   = []
          genre_re = /((?:\(([0-9]+|RX|CR)\))*)(.+)?/
          text.each do |value|
            # 255 possible entries in id3v1
            if value =~ /[[:digit:]]/ and value.to_i < 256
              genre = GENRES[value.to_i]
              genres << (genre.nil? ? 'Unknown' : genre)
            elsif value == 'CR'
              genres << 'Cover'
            elsif value == 'RX'
              genres << 'Remix'
            elsif not value.nil?
              newgenres                 = []
              genreid, dummy, genrename = value.match(genre_re).to_a[1...-1]

              unless genreid.empty?
                genreid[1..-1].split(")(").each do |gid|
                  if gid =~ /[[:digit]]/ and gid.to_i < GENRES.size
                    gid = GENRES[gid.to_i].to_s
                    newgenres << gid
                  elsif gid == 'CR'
                    newgenres << 'Cover'
                  elsif gid == 'RX'
                    newgenres << 'Remix'
                  else
                    newgenres << "Unknown"
                  end
                end
              end

              unless genrename.empty?
                # 'Unescaping' the first parentheses
                if genrename.start_with? "(("
                  genrename = genrename[1..-1]
                end
                unless newgenres.include? genrename
                  newgenres << genrename
                end
              end
              genres.push(*newgenres)
            end
          end
          genres
        end


        def genres=(genre_list)
          if genre_list.is_a? String
            genre_list = [genre_list]
          end
          @text = genre_list
        end

        def _pprint
          genres.join ' / '
        end
      end

      # Copyright "(c)"
      class TCOP < ParentFrames::TextFrame
      end

      #iTunes Compilation Flag
      class TCMP < ParentFrames::NumericTextFrame
      end

      # Date of recording (DDMM)
      class TDAT < ParentFrames::TextFrame
      end

      # Encoding Time
      class TDEN < ParentFrames::TimeStampTextFrame
      end


      # iTunes Podcast Description
      class TDES < ParentFrames::TextFrame
      end

      # Original Release Time
      class TDOR < ParentFrames::TimeStampTextFrame
      end

      # Audio Delay (ms)
      class TDLY < ParentFrames::NumericTextFrame
      end

      # Recording Time
      class TDRC < ParentFrames::TimeStampTextFrame
      end

      # Release Time
      class TDRL < ParentFrames::TimeStampTextFrame
      end


      # Tagging Time
      class TDTG < ParentFrames::TimeStampTextFrame
      end

      # Encoder
      class TENC < ParentFrames::TextFrame
      end

      # Lyricist
      class TEXT < ParentFrames::TextFrame
      end

      # File type
      class TFLT < ParentFrames::TextFrame
      end

      # iTunes Podcast Identifier
      class TGID < ParentFrames::TextFrame
      end


      # Time of recording (HHMM)
      class TIME < ParentFrames::TextFrame
      end

      # Content group description
      class TIT1 < ParentFrames::TextFrame
      end

      # Title
      class TIT2 < ParentFrames::TextFrame
      end


      # Subtitle/Description refinement
      class TIT3 < ParentFrames::TextFrame
      end

      # Starting Key
      class TKEY < ParentFrames::TextFrame
      end


      # Audio Languages
      class TLAN < ParentFrames::TextFrame
      end

      # Audio Length (ms)
      class TLEN < ParentFrames::NumericTextFrame
      end

      # Source Media Type
      class TMED < ParentFrames::TextFrame
      end

      # Mood
      class TMOO < ParentFrames::TextFrame
      end


      # Original Album
      class TOAL < ParentFrames::TextFrame
      end


      # Original Filename
      class TOFN < ParentFrames::TextFrame
      end


      # Original Lyricist
      class TOLY < ParentFrames::TextFrame
      end


      # Original Artist/Performer
      class TOPE < ParentFrames::TextFrame
      end


      # Original Release Year
      class TORY < ParentFrames::NumericTextFrame
      end


      # Owner/Licensee
      class TOWN < ParentFrames::TextFrame
      end


      # Lead Artist/Performer/Soloist/Group
      class TPE1 < ParentFrames::TextFrame
      end


      # Band/Orchestra/Accompaniment
      class TPE2 < ParentFrames::TextFrame
      end

      # Conductor
      class TPE3 < ParentFrames::TextFrame
      end

      # Interpreter/Remixer/Modifier
      class TPE4 < ParentFrames::TextFrame
      end

      # Part of set
      class TPOS < ParentFrames::NumericPartTextFrame
      end

      # Produced (P)
      class TPRO < ParentFrames::TextFrame
      end

      # Publisher
      class TPUB < ParentFrames::TextFrame
      end

      # Track Number
      class TRCK < ParentFrames::NumericPartTextFrame
      end

      # Recording Dates
      class TRDA < ParentFrames::TextFrame
      end

      # Internet Radio Station Name
      class TRSN < ParentFrames::TextFrame
      end

      # Internet Radio Station Owner
      class TRSO < ParentFrames::TextFrame
      end

      # Size of audio data  < bytes)
      class TSIZ < ParentFrames::NumericTextFrame
      end

      # iTunes Album Artist Sort
      class TSO2 < ParentFrames::TextFrame
      end

      # Album Sort Order key
      class TSOA < ParentFrames::TextFrame
      end

      # iTunes Composer Sort
      class TSOC < ParentFrames::TextFrame
      end

      # Perfomer Sort Order key
      class TSOP < ParentFrames::TextFrame
      end

      # Title Sort Order key
      class TSOT < ParentFrames::TextFrame
      end


      # International Standard Recording Code  < ISRC)
      class TSRC < ParentFrames::TextFrame
      end

      # Encoder settings
      class TSSE < ParentFrames::TextFrame
      end

      # Set Subtitle
      class TSST < ParentFrames::TextFrame
      end

      # Year of recording
      class TYER < ParentFrames::NumericTextFrame
      end

      # User-defined text data.
      #
      # TXXX frames have a 'desc' attribute which is set to any Unicode
      # value (though the encoding of the text and the description must be
      # the same). Many taggers use this frame to store freeform keys.
      class TXXX < ParentFrames::TextFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::MultiSpec.new('text', Specs::EncodedTextSpec.new('text'), sep: '\u0000'),
        ]

        def hash_key
          "#{frame_id}:#{@desc}"
        end

        def _pprint
          "#{desc}=#{text.join(' / ')}"
        end
      end

      # Commercial Information
      class WCOM < ParentFrames::UrlFrameU
      end

      # Copyright Information
      class WCOP < ParentFrames::UrlFrame
      end

      # iTunes Podcast Feed
      class WFED < ParentFrames::UrlFrame
      end

      # Official File Information
      class WOAF < ParentFrames::UrlFrame
      end

      # Official Artist/Performer Information
      class WOAR < ParentFrames::UrlFrameU
      end

      # Official Source Information
      class WOAS < ParentFrames::UrlFrame
      end

      # Official Internet Radio Information
      class WORS < ParentFrames::UrlFrame
      end

      # Payment Information
      class WPAY < ParentFrames::UrlFrame
      end

      # Official Publisher Information
      class WPUB < ParentFrames::UrlFrame
      end

      # User defined URL data
      #
      # Like TXX, this has a freeform description associated with it
      class WXXX < ParentFrames::UrlFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::Latin1TextSpec.new('url')
        ]

        def hash_key
          "#{frame_id}:#{desc}"
        end
      end

      # Involved People list
      class TIPL < ParentFrames::PairedTextFrame
      end

      # Musicians Credits List
      class TMCL < ParentFrames::PairedTextFrame
      end

      # Involved People List
      class IPLS < TIPL
      end

      # Binary dump of CD's TOC
      class MCDI < ParentFrames::BinaryFrame
      end

      # Event timing code
      class ETCO < ParentFrames::Frame
        FRAMESPEC = [
            Specs::ByteSpec.new('format'),
            Specs::KeyEventSpec.new('events')
        ]

        def ==(other)
          events == other
        end
      end

      # MPEG location lookup table
      #
      # This frame's attributes may be changed in the future based
      # on feedback from real-world use
      class MLLT < ParentFrames::Frame
        FRAMESPEC = [
            Specs::SizedIntegerSpec.new('frames', 2),
            Specs::SizedIntegerSpec.new('bytes', 3),
            Specs::SizedIntegerSpec.new('milliseconds', 3),
            Specs::ByteSpec.new('bits_for_bytes'),
            Specs::ByteSpec.new('bits_for_milliseconds'),
            Specs::BinaryDataSpec.new('data')
        ]

        def ==(other)
          data == other
        end
      end


      # Synchronised tempo codes.
      #
      # This frame's attributes may be changed in the future based on
      # feedback from real-world use.
      class SYTC < ParentFrames::Frame
        FRAMESPEC = [
            Specs::ByteSpec.new('format'),
            Specs::BinaryDataSpec.new('data')
        ]

        def ==(other)
          data == other
        end
      end

      # Unsynchronized lyrics/text transcription.
      #
      # Lyrics have a three letter ISO language code ('lang'), a
      # description ('desc'), and a block of plain text ('text')
      class USLT < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::StringSpec.new('lang', 3),
            Specs::EncodedTextSpec.new('desc'),
            Specs::EncodedTextSpec.new('text')
        ]

        def to_s
          text.encode('utf-8')
        end

        def ==(other)
          text == other
        end
      end

      # Synchronized lyrics/text
      class SYLT < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::StringSpec.new('lang', 3),
            Specs::ByteSpec.new('format'),
            Specs::ByteSpec.new('type'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::SynchronizedTextSpec.new('text')
        ]

        def hash_key
          "#{frame_id}:#{desc}:#{lang}"
        end

        def ==(other)
          self.to_s == other
        end

        def to_s
          text.map { |text, _| text }.join
        end
      end

      # User comment
      #
      # User comment frames have a description, like TXXX, and also
      # a three letter ISO languge code in the 'lang' attribute.
      class COMM < ParentFrames::TextFrame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::StringSpec.new('lang', 3),
            Specs::EncodedTextSpec.new('desc'),
            Specs::MultiSpec.new('text', Specs::EncodedTextSpec.new('text'), sep: "\u0000")
        ]

        def hash_key
          "#{frame_id}:#{desc}:#{lang}"
        end

        def _pprint
          "#{desc}=#{lang}=#{text.join(' / ')}"
        end
      end

      # Relative volume adjustment (2).
      #
      # This frame is used to implemented volume scaling, and in
      # particular, normalization using ReplayGain.
      #
      # Attributes:
      #
      # * desc -- description or context of this adjustment
      # * channel -- audio channel to adjust (master is 1)
      # * gain -- a + or - dB gain relative to some reference level
      # * peak -- peak of the audio as a floating point number, [0, 1]
      #
      # When storing ReplayGain tags, use descriptions of 'album' and
      # 'track' on channel 1.
      class RVA2 < ParentFrames::Frame

        FRAMESPEC = [
            Specs::Latin1TextSpec.new('desc'),
            Specs::ChannelSpec.new('channel'),
            Specs::VolumeAdjustmentSpec.new('gain'),
            Specs::VolumePeakSpec.new('peak'),
        ]

        CHANNELS = ['Other', 'Master volume', 'Front right', 'Front left',
                    'Back right', 'Back left', 'Front centre', 'Back centre',
                    'Subwoofer']

        def hash_key
          "#{frame_id}, #{desc}"
        end

        def ==(other)
          (self.to_s == other) or
              (desc == other.desc and
                  channel == other.channel and
                  gain == other.gain and
                  peak == other.peak)
        end

        def to_s
          '%s: %+0.4f dB/%0.4f' % [CHANNELS[channel], gain, peak]
        end

      end

      # Equalisation (2).

      # Attributes:
      # method -- interpolation method (0 = band, 1 = linear)
      # desc -- identifying description
      # adjustments -- list of (frequency, vol_adjustment) pairs
      class EQU2 < ParentFrames::Frame
        FRAMESPEC = [
            Specs::ByteSpec.new('method'),
            Specs::Latin1TextSpec.new('des'),
            Specs::VolumeAdjustmentSpec.new('adjustments')
        ]

        def ==(other)
          adjustments = other
        end

        def hash_key
          "#{frame_id}:#{desc}"
        end
      end

      # class RVAD: unsupported
      # class EQUA: unsupported

      # Reverb
      class RVRB < ParentFrames::Frame
        FRAMESPEC = [
            Specs::SizedIntegerSpec.new('left', 2),
            Specs::SizedIntegerSpec.new('right', 2),
            Specs::ByteSpec.new('bounce_left'),
            Specs::ByteSpec.new('bounce_right'),
            Specs::ByteSpec.new('feedback_ltl'),
            Specs::ByteSpec.new('feedback_ltr'),
            Specs::ByteSpec.new('feedback_rtr'),
            Specs::ByteSpec.new('feedback_rtl'),
            Specs::ByteSpec.new('premix_ltr'),
            Specs::ByteSpec.new('premix_rtl'),
        ]

        def ==(other)
          [left, right] == other
        end
      end

      # Attached (or linked) Picture.
      #
      # Attributes:
      #
      # * encoding -- text encoding for the description
      # * mime -- a MIME type (e.g. image/jpeg) or '-->' if the data is a URI
      # * type -- the source of the image (3 is the album front cover)
      # * desc -- a text description of the image
      # * data -- raw image data, as a byte string
      #
      # Mutagen will automatically compress large images when saving tags.
      class APIC < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::Latin1TextSpec.new('mime'),
            Specs::ByteSpec.new('type'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::BinaryDataSpec.new('data'),
        ]

        def hash_key
          "#{frame_id}:#{desc}"
        end

        def _pprint
          "#{desc} (#{mime}, #{data.bytesize} bytes)"
        end
      end

      # Play counter.
      #
      # The 'count' attribute contains the (recorded) number of times this
      # file has been played.
      #
      # This frame is basically obsoleted by POPM.
      class PCNT < ParentFrames::Frame
        FRAMESPEC = [Specs::IntegerSpec.new('count')]

        def ==(other)
          count == other
        end

        def to_i
          count.to_i
        end

        def +@
          count
        end

        def _pprint
          count
        end
      end

      # Popularimeter.
      #
      # This frame keys a rating (out of 255) and a play count to an email
      # address.
      #
      # Attributes:
      #
      # * email -- email this POPM frame is for
      # * rating -- rating from 0 to 255
      # * count -- number of times the files has been played (optional)
      class POPM < ParentFrames::FrameOpt
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('email'),
            Specs::ByteSpec.new('rating')
        ]

        OPTIONALSPEC = [Specs::IntegerSpec.new('count')]

        def hash_key
          "#{frame_id}:#{email}"
        end

        def ==(other)
          rating == other
        end

        def +@
          rating
        end

        def to_i
          rating.to_i
        end

        def _pprint
          '%s=%r %r/255' % [email, @count, rating]
        end
      end

      # General Encapsulated Object.
      #
      # A blob of binary data, that is not a picture (those go in APIC).
      #
      # Attributes:
      #
      # * encoding -- encoding of the description
      # * mime -- MIME type of the data or '-->' if the data is a URI
      # * filename -- suggested filename if extracted
      # * desc -- text description of the data
      # * data -- raw data, as a byte string
      class GEOB < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::Latin1TextSpec.new('mime'),
            Specs::EncodedTextSpec.new('filename'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::BinaryDataSpec.new('data')
        ]

        def hash_key
          "#{frame_id}:#{desc}"
        end

        def ==(other)
          data == other
        end
      end

      # Recommended buffer size.
      #
      # Attributes:
      #
      # * size -- recommended buffer size in bytes
      # * info -- if ID3 tags may be elsewhere in the file (optional)
      # * offset -- the location of the next ID3 tag, if any
      #
      # Mutagen will not find the next tag itself.
      class RBUF < ParentFrames::FrameOpt
        FRAMESPEC = [Specs::SizedIntegerSpec.new('size', 3)]

        OPTIONALSPEC = [
            Specs::ByteSpec.new('info'),
            Specs::SizedIntegerSpec.new('offset', 4)
        ]

        def ==(other)
          size == other
        end

        def +@
          size
        end

        def to_i
          size.to_i
        end
      end


      # Audio encryption.
      #
      # Attributes:
      #
      # * owner -- key identifying this encryption type
      # * preview_start -- unencrypted data block offset
      # * preview_length -- number of unencrypted blocks
      # * data -- data required for decryption (optional)
      #
      # Mutagen cannot decrypt files.
      class AENC < ParentFrames::FrameOpt
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::SizedIntegerSpec.new('preview_start', 2),
            Specs::SizedIntegerSpec.new('preview_length', 2)
        ]

        OPTIONALSPEC = [Specs::BinaryDataSpec.new('data')]

        def hash_key
          "#{frame_id}:#{owner}"
        end

        def to_s
          owner
        end

        def ==(other)
          owner == other
        end
      end

      # Linked information.
      #
      # Attributes:
      #
      # * frameid -- the ID of the linked frame
      # * url -- the location of the linked frame
      # * data -- further ID information for the frame
      class LINK < ParentFrames::FrameOpt
        FRAMESPEC = [
            Specs::StringSpec.new('frameid', 4),
            Specs::Latin1TextSpec.new('url')
        ]

        OPTIONALSPEC = [Specs::BinaryDataSpec.new('data')]

        def hash_key
          str = "#{frame_id}:#{frameid}:#{url}"
          str << ":#{data}" unless data.nil?
          str
        end

        def ==(other)
          (data.nil? ? [frame_id, url, data] : [frame_id, url]) == other
        end
      end

      # Position synchronisation frame
      #
      # Attribute:
      #
      # * format -- format of the position attribute (frames or milliseconds)
      # * position -- current position of the file
      class POSS < ParentFrames::Frame
        FRAMESPEC = [
            Specs::ByteSpec.new('format'),
            Specs::IntegerSpec.new('position')
        ]

        def to_i
          position.to_i
        end

        def +@
          position
        end

        def ==(other)
          position == other
        end
      end

      # Unique file identifier.
      #
      # Attributes:
      #
      # * owner -- format/type of identifier
      # * data -- identifier
      class UFID < ParentFrames::Frame
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::BinaryDataSpec.new('data'),
        ]

        def hash_key
          "#{frame_id}:#{owner}"
        end

        def ==(other)
          if other.is_a? Frames_2_2::UFI
            owner == other.owner and data == other.data
          else
            data == other
          end
        end

        def _pprint
          if data.max.ord < 128
            "#{owner}=#{data}"
          else
            "#{owner} (#{data.bytesize} bytes)"
          end
        end
      end

      # Terms of use.
      #
      # Attributes:
      #
      # * encoding -- text encoding
      # * lang -- ISO three letter language code
      # * text -- licensing terms for the audio
      class USER < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::StringSpec.new('lang', 3),
            Specs::EncodedTextSpec.new('text')
        ]

        def hash_key
          "#{frame_id}:#{lang}"
        end

        def to_s
          text
        end

        def ==(other)
          text == other
        end

        def _pprint
          "#{lang}=#{text}"
        end
      end

      # Ownership Frame
      class OWNE < ParentFrames::Frame
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::Latin1TextSpec.new('price'),
            Specs::StringSpec.new('date', 8),
            Specs::EncodedTextSpec.new('seller')
        ]

        def to_s
          seller
        end

        def ==(other)
          seller == other
        end
      end

      # Commercial Frame
      class COMR < ParentFrames::FrameOpt
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::Latin1TextSpec.new('price'),
            Specs::StringSpec.new('valid_until', 8),
            Specs::Latin1TextSpec.new('contact'),
            Specs::ByteSpec.new('format'),
            Specs::EncodedTextSpec.new('seller'),
            Specs::EncodedTextSpec.new('desc'),
        ]

        OPTIONALSPEC = [
            Specs::Latin1TextSpec.new('mime'),
            Specs::BinaryDataSpec.new('logo'),
        ]

        def hash_key
          "#{frame_id}:#{write_data}"
        end

        def ==(other)
          write_data == other.write_data
        end
      end

      # Encryption method registration
      #
      # The standard does not allow multiple ENCR frames with the same owner
      # or the same method. Mutagen only verifies that the owner is unique.
      class ENCR < ParentFrames::Frame
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::ByteSpec.new('method'),
            Specs::BinaryDataSpec.new('data')
        ]

        def hash_key
          "#{frame_id}:#{owner}"
        end

        def to_s
          data
        end

        def ==(other)
          data == other
        end
      end

      # Group identification registration
      class GRID < ParentFrames::FrameOpt
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::ByteSpec.new('group')
        ]

        OPTIONALSPEC = [Specs::BinaryDataSpec.new('data')]

        def hash_key
          "#{frame_id}:#{group}"
        end

        def to_i
          group.to_i
        end

        def +@
          group
        end

        def to_s
          owner
        end

        def ==(other)
          owner == other or group == other
        end
      end

      # Private frame.
      class PRIV < ParentFrames::Frame
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::BinaryDataSpec.new('data')
        ]

        def hash_key
          "#{frame_id}:#{owner}:#{data}"
        end

        def to_s
          data
        end

        def ==(other)
          data == other
        end

        def _pprint
          if data.max.ord < 128
            "#{owner}:#{data}"
          else
            "#{owner} (#{data} bytes)"
          end
        end
      end

      # Signature frame
      class SIGN < ParentFrames::Frame
        FRAMESPEC = [
            Specs::ByteSpec.new('group'),
            Specs::BinaryDataSpec.new('sig')
        ]

        def hash_key
          "#{frame_id}:#{group}:#{sig}"
        end

        def to_s
          sig
        end

        def ==(other)
          sig == other
        end
      end

      #  Seek frame.
      #
      # Mutagen does not find tags at seek offsets.
      class SEEK < ParentFrames::Frame
        FRAMESPEC = [Specs::IntegerSpec.new('offset')]

        def to_i
          offset.to_i
        end

        def +@
          offset
        end

        def ==(other)
          offset == other
        end
      end

      # Audio seek point index.
      #
      # Attributes: S, L, N, b, and Fi. For the meaning of these, see
      # the ID3v2.4 specification. Fi is a list of integers.
      class ASPI < ParentFrames::Frame
        FRAMESPEC = [
            Specs::SizedIntegerSpec.new("S", 4),
            Specs::SizedIntegerSpec.new("L", 4),
            Specs::SizedIntegerSpec.new("N", 2),
            Specs::ByteSpec.new('b'),
            Specs::ASPIIndexSpec.new('Fi'),
        ]

        def ==(other)
          Fi == other
        end
      end
    end
    module Frames_2_2
      # Unique File Identifier
      class UFI < Frames::UFID
      end

      # Content group description
      class TTI < Frames::TIT1
      end

      # Title
      class TT2 < Frames::TIT2
      end

      # Subtitle/Description refinement
      class TT3 < Frames::TIT3
      end

      #Lead Artist/Performer/Soloist/Group
      class TP1 < Frames::TPE1
      end

      #Band/Orchestra/Accompaniment
      class TP2 < Frames::TPE2
      end

      #Conductor
      class TP3 < Frames::TPE3
      end

      #Interpreter/Remixer/Modifier
      class TP4 < Frames::TPE4
      end

      #Composer
      class TCM < Frames::TCOM
      end

      #Lyricist
      class TXT < Frames::TEXT
      end

      #Audio Language (s)
      class TLA < Frames::TLAN
      end

      #Content Type  (Genre)
      class TCO < Frames::TCON
      end

      #Album
      class TAL < Frames::TALB
      end

      #Part of set
      class TPA < Frames::TPOS
      end

      #Track Number
      class TRK < Frames::TRCK
      end

      #International Standard Recording Code (ISRC)
      class TRC < Frames::TSRC
      end

      #Year of recording
      class TYE < Frames::TYER
      end

      #Date of recording (DMM)
      class TDA < Frames::TDAT
      end

      #Time of recording  (HHMM)
      class TIM < Frames::TIME
      end

      #Recording Dates
      class TRD < Frames::TRDA
      end

      #Source Media Type
      class TMT < Frames::TMED
      end

      #File Type
      class TFT < Frames::TFLT
      end

      #Beats per minute
      class TBP < Frames::TBPM
      end

      #iTunes Compilation Flag
      class TCP < Frames::TCMP
      end

      #Copyright  (C)
      class TCR < Frames::TCOP
      end

      #Publisher
      class TPB < Frames::TPUB
      end

      #Encoder
      class TEN < Frames::TENC
      end

      #Encoder settings
      class TSS < Frames::TSSE
      end

      #Original Filename
      class TOF < Frames::TOFN
      end

      #Audio Length  (ms)
      class TLE < Frames::TLEN
      end

      #Audio Data size (bytes)
      class TSI < Frames::TSIZ
      end

      #Audio Delay (ms)
      class TDY < Frames::TDLY
      end

      #Starting Key
      class TKE < Frames::TKEY
      end

      #Original Album
      class TOT < Frames::TOAL
      end

      #Original Artist/Perfomer
      class TOA < Frames::TOPE
      end

      #Original Lyricist
      class TOL < Frames::TOLY
      end

      #Original Release Year
      class TOR < Frames::TORY
      end

      #User-defined Text
      class TXX < Frames::TXXX
      end

      #Official File Information
      class WAF < Frames::WOAF
      end

      #Official Artist/Performer Information
      class WAR < Frames::WOAR
      end

      #Official Source Information
      class WAS < Frames::WOAS
      end

      #Commercial Information
      class WCM < Frames::WCOM
      end

      #Copyright Information
      class WCP < Frames::WCOP
      end

      #Official Publisher Information
      class WPB < Frames::WPUB
      end

      #User-defined URL
      class WXX < Frames::WXXX
      end

      #Involved people list
      class IPL < Frames::IPLS
      end

      #Binary dump of CD's TOC
      class MCI < Frames::MCDI
      end

      #Event timing codes
      class ETC < Frames::ETCO
      end

      #MPEG location lookup table
      class MLL < Frames::MLLT
      end

      #Synced tempo codes
      class STC < Frames::SYTC
      end

      #Unsychronised lyrics/text transcription
      class ULT < Frames::USLT
      end

      #Synchronised lyrics/text
      class SLT < Frames::SYLT
      end

      #Comment
      class COM < Frames::COMM
      end

      #class RVA < RVAD
      #class EQU < EQUA

      # Reverb
      class REV < Frames::RVRB
      end

      # Attached Picture.
      #
      # The 'mime' attribute of an ID3v2.2 attached picture must be either
      # 'PNG' or 'JPG'.
      class PIC < Frames::APIC
        FRAMESPEC = [
            Specs::EncodingSpec.new('encoding'),
            Specs::StringSpec.new('mime', 3),
            Specs::ByteSpec.new('type'),
            Specs::EncodedTextSpec.new('desc'),
            Specs::BinaryDataSpec.new('data')
        ]
      end

      # General Encapsulated Object
      class GEO < Frames::GEOB
      end

      # Play counter
      class CNT < Frames::PCNT
      end

      # Popularimeter
      class POP < Frames::POPM
      end

      class BUF < Frames::RBUF
      end

      # Encrypted meta frame
      class CRM < ParentFrames::Frame
        FRAMESPEC = [
            Specs::Latin1TextSpec.new('owner'),
            Specs::Latin1TextSpec.new('desc'),
            Specs::BinaryDataSpec.new('data')
        ]

        def ==(other)
          data == other
        end
      end

      # Audio encryption
      class CRA < Frames::AENC
      end

      # Linked information
      class LNK < Frames::LINK
        FRAMESPEC = [
            Specs::StringSpec.new('frameid', 3),
            Specs::Latin1TextSpec.new('url'),
        ]

        OPTIONALSPEC = [
            Specs::BinaryDataSpec.new('data')
        ]
      end
    end
  end
end

