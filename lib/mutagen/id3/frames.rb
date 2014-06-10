require 'mutagen/constants'
require 'mutagen/id3/util'
require 'mutagen/id3/specs'
require 'zlib'

module Mutagen::ID3
  def is_valid_frame_id(frame_id)
    true
  end

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
          self.class.send("attr_accessor", checker.name.to_sym)
        end
      else
        self.class::FRAMESPEC.zip(args) do |checker, val|
          instance_variable_set("@#{checker.name}", checker.validate(self, val))
          self.class.send("attr_reader", checker.name.to_sym)
        end
        self.class::FRAMESPEC[args.size..-1].each do |checker|
          begin
            #TODO: does checker.name.to_sym improve performance?
            validated = checker.validate(self, kwargs[checker.name])
          rescue Mutagen::ValueError => e
            raise e.exception("#{checker.name}: #{e.message}")
          end
          instance_variable_set("@#{checker.name}", validated)
          self.class.send("attr_accessor", checker.name.to_sym)
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
      this.class.to_s
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
      frame          = self.class.new
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
          instance_variable_set('@'+spec.name, validated)
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
        instance_variable_set('@'+reader.name, value)
      end
      unless data.nil? or data.empty?
        self.class::OPTIONALSPEC.each do |reader|
          break if data.empty?
          value, data = reader.read(self, data)
          instance_variable_set('@'+reader.name, value)
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
        data << writer.write(self, instance_variable_get('@'+writer.name))
      end
      self.class::OPTIONALSPEC.each do |writer|
        #TODO: Maybe we should store the ivar and check `.nil?` instead?
        break unless instance_variable_defined? '@'+writer.name
        data << writer.write(self, instance_variable_get('@'+writer.name))
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
        EncodingSpec.new('encoding'),
        MultiSpec.new('text', EncodedTextSpec.new('text'), sep: "\u0000")
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
        EncodingSpec.new('encoding'),
        MultiSpec.new('text', EncodedNumericPartTextSpec.new('text'), sep:"\u0000")
    ]

    # Get the numerical value of the string
    def to_i
      text[0].to_i
    end
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
        EncodingSpec.new('encoding'),
        MultiSpec.new('text', EncodedNumericPartTextSpec.new('text'), sep:"\u0000")
    ]

    def to_i
      text[0].split('/')[0].to_i
    end
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
        EncodingSpec.new('encoding'),
        MultiSpec.new('text', TimeStampSpec.new('stamp'), sep:','),
    ]

    def to_s
      text.map{|stamp| stamp.text }.join(',')
    end

    def _pprint
      text.map{|stamp| stamp.text }.join(' / ')
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
    FRAMESPEC = [Latin1TextSpec.new('url')]

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

  # Album
  class TALB < TextFrame; end

  # Beats per Minute
  class TBPM < NumericTextFrame; end

  # Composer
  class TCOm < TextFrame; end

  # Content type (Genre)
  #
  # ID3 has several ways genres can be represented; for convenience.
  # Use the 'genres' property rather than the 'text' attribute
  class TCON < TextFrame
    GENRES = Mutagen::Constants::GENRES

    def genres
      genres = []
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
          newgenres = []
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
  class TCOP < TextFrame; end

  #iTunes Compilation Flag
  class TCMP < NumericTextFrame; end

  # Date of recording (DDMM)
  class TDAT < TextFrame; end

  # Encoding Time
  class TDEN < TimeStampTextFrame; end
      

  # iTunes Podcast Description
  class TDES < TextFrame; end

  # Original Release Time
  class TDOR < TimeStampTextFrame; end 

  # Audio Delay (ms)
  class TDLY < NumericTextFrame; end

  # Recording Time
  class TDRC < TimeStampTextFrame; end
  
  # Release Time
  class TDRL < TimeStampTextFrame; end
      

  # Tagging Time
  class TDTG < TimeStampTextFrame; end

  # Encoder
  class TENC < TextFrame; end

  # Lyricist
  class TEXT < TextFrame; end

  # File type
  class TFLT < TextFrame; end

  # iTunes Podcast Identifier
  class TGID < TextFrame; end
      

  # Time of recording (HHMM)
  class TIME < TextFrame; end

  # Content group description
  class TIT1 < TextFrame; end

  # Title
  class TIT2 < TextFrame; end 


  # Subtitle/Description refinement
  class TIT3 < TextFrame; end

  # Starting Key
  class TKEY < TextFrame; end


  # Audio Languages
  class TLAN < TextFrame; end

  # Audio Length (ms)
  class TLEN < NumericTextFrame; end

  # Source Media Type
  class TMED < TextFrame; end

  # Mood
  class TMOO < TextFrame; end


  # Original Album
  class TOAL < TextFrame; end


  # Original Filename
  class TOFN < TextFrame; end


  # Original Lyricist
  class TOLY < TextFrame; end


  # Original Artist/Performer
  class TOPE < TextFrame; end


  # Original Release Year
  class TORY < NumericTextFrame; end


  # Owner/Licensee
  class TOWN < TextFrame; end


  # Lead Artist/Performer/Soloist/Group
  class TPE1 < TextFrame; end


  # Band/Orchestra/Accompaniment
  class TPE2 < TextFrame; end

  # Conductor
  class TPE3 < TextFrame; end

  # Interpreter/Remixer/Modifier
  class TPE4 < TextFrame; end

  # Part of set
  class TPOS < NumericPartTextFrame; end

  # Produced (P)
  class TPRO < TextFrame; end

  # Publisher
  class TPUB < TextFrame; end

  # Track Number
  class TRCK < NumericPartTextFrame; end

  # Recording Dates
  class TRDA < TextFrame; end

  # Internet Radio Station Name
  class TRSN < TextFrame; end

  # Internet Radio Station Owner
  class TRSO < TextFrame; end

  # Size of audio data  < bytes)
  class TSIZ < NumericTextFrame; end

  # iTunes Album Artist Sort
  class TSO2 < TextFrame; end

  # Album Sort Order key
  class TSOA < TextFrame; end

  # iTunes Composer Sort
  class TSOC < TextFrame; end

  # Perfomer Sort Order key
  class TSOP < TextFrame; end

  # Title Sort Order key
  class TSOT < TextFrame; end


  # International Standard Recording Code  < ISRC)
  class TSRC < TextFrame; end

  # Encoder settings
  class TSSE < TextFrame; end

  # Set Subtitle
  class TSST < TextFrame; end

  # Year of recording
  class TYER < NumericTextFrame; end

  # User-defined text data.
  #
  # TXXX frames have a 'desc' attribute which is set to any Unicode
  # value (though the encoding of the text and the description must be
  # the same). Many taggers use this frame to store freeform keys.
  class TXXX < TextFrame
    FRAMESPEC = [
        EncodingSpec.new('encoding'),
        EncodedTextSpec.new('desc'),
        MultiSpec.new('text', EncodedTextSpec.new('text'), sep:'\u0000'),
    ]

    def hash_key
      "#{frame_id}:#{self.desc}"
    end

    def _pprint
      "#{self.desc}=#{text.join(' / ')}"
    end
  end

  # Commercial Information
  class WCOM < UrlFrameU; end

  # Copyright Information
  class WCOP < UrlFrame; end

  # iTunes Podcast Feed
  class WFED < UrlFrame; end

  # Official File Information
  class WOAF < UrlFrame; end

  # Official Artist/Performer Information
  class WOAR < UrlFrameU; end

  # Official Source Information
  class WOAS < UrlFrame; end

  # Official Internet Radio Information
  class WORS < UrlFrame; end

  # Payment Information
  class WPAY < UrlFrame; end

  # Official Publisher Information
  class WPUB < UrlFrame; end

  # User defined URL data
  #
  # Like TXX, this has a freeform description associated with it
  class WXXX < UrlFrame
    FRAMESPEC = [
        EncodingSpec.new('encoding'),
        EncodedTextSpec.new('desc'),
        Latin1TextSpec.new('url')
    ]

    def hash_key
      "#{frame_id}:#{self.desc}"
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
        EncodingSpec.new('encoding'),
        MultiSpec.new('people',
                      EncodedTextSpec.new('involvement'),
                      EncodedTextSpec.new('person'))
    ]

    def ==(other)
      people == other
    end
  end


  # Involved People list
  class TIPL < PairedTextFrame; end

  # Musicians Credits List
  class TMCL < PairedTextFrame; end

  # Involved People List
  class IPLS < TIPL; end

  # Binary data
  #
  # The 'data' attribute contains the raw byte string
  class BinaryFrame < Frame
    FRAMESPEC = [BinaryDataSpec.new('data')]

    def ==(other)
      data == other
    end
  end

  # Binary dump of CD's TOC
  class MCDI < BinaryFrame; end

  # Event timing code
  class ETCO < Frame
    FRAMESPEC = [
        ByteSpec.new('format'),
        KeyEventSpec.new('events')
    ]

    def ==(other)
      events == other
    end
  end

  # MPEG location lookup table
  #
  # This frame's attributes may be changed in the future based
  # on feedback from real-world use
  class MLLT < Frame
    FRAMESPEC = [
        SizedIntegerSpec.new('frames', 2),
        SizedIntegerSpec.new('bytes', 3),
        SizedIntegerSpec.new('milliseconds', 3),
        ByteSpec.new('bits_for_bytes'),
        ByteSpec.new('bits_for_milliseconds'),
        BinaryDataSpec.new('data')
    ]

    def ==(other)
      data == other
    end
  end


  # Synchronised tempo codes.
  #``
  # This frame's attributes may be changed in the future based on
  # feedback from real-world use.
  class SYTC < Frame
    FRAMESPEC = [
        ByteSpec.new('format'),
        BinaryDataSpec.new('data')
    ]

    def ==(other)
      data == other
    end
  end

  # Unsynchronized lyrics/text transcription.
  #
  # Lyrics have a three letter ISO language code ('lang'), a
  # description ('desc'), and a block of plain text ('text')
  class USLT < Frame
    FRAMESPEC = [
        EncodingSpec.new('encoding'),
        StringSpec.new('lang', 3),
        EncodedTextSpec.new('desc'),
        EncodedTextSpec.new('text')
    ]

    def to_s
      text.encode('utf-8')
    end

    def ==(other)
      text == other
    end
  end

end
