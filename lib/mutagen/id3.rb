# ID3 Support for Mutagen


# ID3v2 reading and writing.
#
# This is based off of the following references:
#
# * http://id3.org/id3v2.4.0-structure
# * http://id3.org/id3v2.4.0-frames
# * http://id3.org/id3v2.3.0
# * http://id3.org/id3v2-00
# * http://id3.org/ID3v1
#
# Its largest deviation from the above (versions 2.3 and 2.2) is that it
# will not interpret the / characters as a separator, and will almost
# always accept null separators to generate multi-valued text frames.
#
# Because ID3 frame structure differs between frame types, each frame is
# implemented as a different class (e.g. TIT2 as {Mutagen::ID3::Frames::TIT2}). Each
# frame's documentation contains a list of its attributes.
#
# Since this file's documentation is a little unwieldy, you are probably
# interested in the {ID3} class to start with.

require 'mutagen/util'
require 'mutagen/metadata'
require 'mutagen/filetype'
require 'mutagen/streaminfo'
require 'mutagen/id3/util'
require 'mutagen/id3/specs'
require 'mutagen/id3/frames'

module Mutagen

# A file with an ID3v2 tag.
#
# Attributes:
#
# * version -- ID3 tag version as a tuple
# * unknown_frames -- raw frame data of any unknown frames found
# * size -- the total size of the ID3 tag, including the header
  class ID3 < Mutagen::Metadata
    include Mutagen::DictProxy

    PEDANTIC = true
    V24      = Gem::Version.new '2.4.0'
    V23      = Gem::Version.new '2.3.0'
    V22      = Gem::Version.new '2.2.0'
    V11      = Gem::Version.new '1.1'

    attr_reader :version, :size

    def initialize(*args, ** kwargs)
      @version = V24
      @filename, @crc, @unknown_version = nil
      @size, @flags, @readbytes         = 0, 0, 0

      @dict           = {} # Need this for our DictProxy
      @unknown_frames = []
      super(*args, ** kwargs)
    end

    def fullread(size)
      unless @fileobj.nil?
        raise Mutagen::ValueError, "Requested bytes (#{size}) less than zero" if size < 0
        if size > @fileobj.size
          raise EOFError, ('Requested %#x of %#x (%s)' % [size.to_i, @fileobj.size, @filename])
        end
      end
      data = @fileobj.read size
      raise EOFError if not data.nil? and data.size != size
      @readbytes += size
      data
    end

    # Load tags from a filename
    #
    # @param filename [String] filename to load tag data from
    # @param known_frames [Hash] hash mapping frame IDs to Frame objects
    # @param translate [Bool] Update all the tags to ID3v2.3/4 internally. If you
    #                         intend to save, this must be true or you have to call
    #                         update_to_v23 / update_to_v24 manually.
    # @param v2_version [Fixnum] the minor version number of v2 to use
    def load(filename, known_frames: nil, translate: true, v2_version: 4)
      raise Mutagen::ValueError, 'Only 3 and 4 possible for v2_version' unless [3, 4].include? v2_version
      @filename     = case filename
                      when Hash;
                        filename[:filename]
                      else
                        filename
                      end
      @known_frames = known_frames
      @fileobj      = File.open(@filename, 'r')
      begin
        load_header
      rescue EOFError
        @size = 0
        raise ID3NoHeaderError, "#{@filename} too small (#{@fileobj.size} bytes)"
      rescue ID3NoHeaderError, ID3UnsupportedVersionError => err
        @size = 0
        begin
          @fileobj.seek(-128, IO::SEEK_END)
        rescue Errno::EINVAL
          raise err
        else
          frames = ParseID3v1(@fileobj.read(128))
          if frames.nil?
            raise err
          else
            @version = V11
            frames.values.each { |v| add v }
          end
        end
      else
        frames = @known_frames
        if frames.nil?
          if V23 <= @version
            frames = Frames
          elsif V24 <= @version
            frames = Frames_2_2
          end
        end
        data = fullread(@size - 10)
        read_frames(data, frames) do |frame|
          if frame.is_a? ParentFrames::Frame
            add frame
          else
            @unknown_frames << frame
          end
        end
      ensure
        @fileobj.close
        @fileobj  = nil
        @filesize = nil
        if translate
          (v2_version == 3) ? update_to_v23 : update_to_v24
        end
      end
    end

    # Return all frames with a given name (the list may be empty).
    #
    # This is best explained by examples::
    #
    #     id3.getall('TIT2') == [id3['TIT2']]
    #     id3.getall('TTTT') == []
    #     id3.getall('TXXX') == [TXXX.new(desc='woo', text='bar'),
    #                            TXXX.new(desc='baz', text='quuuux'), ...]
    #
    # Since this is based on the frame's hash_key, which is
    # colon-separated, you can use it to do things like
    # ``getall('COMM:MusicMatch')`` or ``getall('TXXX:QuodLibet:')``.
    def get_all(key)
      if has_key? key
        self[key]
      else
        key += ':'
        each_pair.map { |s, v| v if s.start_with? key }.compact
      end
    end

    # Delete all tags of a given kind; see getall.
    def delete_all(key)
      if has_key? key
        delete key
      else
        key += ':'
        keys.select { |s| s.start_with? key }.each do |k|
          delete k
        end
      end
    end

    # Delete frames of the given type  and add frames in 'values'
    def set_all(key, values)
      delete_all key
      values.each do |tag|
        self[tag.hash_key] = tag
      end
    end

    # Return tags in a human-readable format.
    #
    # "Human-readable" is used loosely here. The format is intended
    # to mirror that used for Vorbis or APEv2 output, e.g.
    #
    #     ``TIT2=My Title``
    #
    # However, ID3 frames can have multiple keys:
    #
    #     ``POPM=user@example.org=3 128/255``
    def pprint
      # based on Frame.pprint (but we can't call unbound methods)
      values.map { |v| Frame.pprint(v) }.sort.join("\n")
    end

    # @deprecated use the add method
    def loaded_frame(tag)
      warn '[DEPRECATION] `loaded_frame` is deprecated.  Please use `add` instead.'
      # turn 2.2 into 2.3/2.4 tags
      tag                = tag.class.superclass.new(tag) if tag.class.to_s.size == 3
      self[tag.hash_key] = tag
    end

    # add = loaded_frame (and vice versa) break applications that
    # expect to be able to override loaded_frame (e.q. Quod Libet)
    # as does making loaded _frame call add

    # Add a frame to the tag
    def add(tag)
      # turn 2.2 into 2.3/2.4 tags
      if tag.class.name.split('::').last.length == 3
        tag = tag.class.superclass.new(tag)
      end
      self[tag.hash_key] = tag
    end

    def load_header
      data                         = fullread(10)
      id3, vmaj, vrev, flags, size = data.unpack('a3C3a4')
      @flags                       = flags
      @size                        = BitPaddedInteger.new(size).to_i + 10
      @version                     = Gem::Version.new "2.#{vmaj}.#{vrev}"
      raise ID3NoHeaderError, "#{@filename} doesn't start with an ID3 tag" unless id3 == "ID3"
      raise ID3UnsupportedVersionError, "#{@filename} ID3v2.#{vmaj} not supported" unless [2, 3, 4].include? vmaj

      if PEDANTIC
        raise Mutagen::ValueError, "Header size not synchsafe" unless BitPaddedInteger.has_valid_padding(size)
        if V24 <= @version and (flags & 0x0f > 0)
          raise Mutagen::ValueError, ("#{@filename} has invalid flags %#02x" % [flags])
        elsif (V23 <= @version and @version < V24) and (flags & 0x1f > 0)
          raise Mutagen::ValueError, ("#{@filename} has invalid flags %#02x" % [flags])
        end
      end

      if f_extended != 0
        extsize = fullread 4
        if not extsize.nil? and Frames.constants.include? extsize.to_sym
          # Some tagger sets the extended header flag but
          # doesn't write an extended header; in this case, the
          # ID3 data follows immediately. Since no extended
          # header is going to be long enough to actually match
          # a frame, and if it's *not* a frame we're going to be
          # completely lost anyway, this seems to be the most
          # correct check.
          # http://code.google.com/p/quodlibet/issues/detail?id=126
          @flags   ^= 0x40
          @extsize = 0
          @fileobj.seek(-4, IO::SEEK_CUR)
          @readbytes -= 4
        elsif @version >= V24
          # "Where the 'Extended header size' is the size of the whole
          # extended header, stored as a 32 bit synchsafe integer."
          @extsize = BitPaddedInteger.new(extsize).to_i - 4
          if PEDANTIC
            unless BitPaddedInteger.has_valid_padding(extsize)
              raise Mutagen::ValueError, 'Extended header size not synchsafe'
            end
          end
        else
          # "Where the 'Extended header size', currently 6 or 10 bytes,
          # excludes itself."
          @extsize = extsize.unpack('L>')[0]
        end

        if not @extsize.nil? and @extsize > 0
          @extdata = fullread(@extsize)
        else
          @extdata = ""
        end
      end
    end

    def determine_bpi(data, frames, empty: "\x00" * 10)
      if @version < V24
        return Integer
      end
      # have to special case whether to use bitpaddedints here
      # spec says to use them, but iTunes has it wrong

      # count number of tags found as BitPaddedInt and how far past
      o     = 0
      asbpi = 0
      flag  = true
      while o < (data.size - 10)
        part = data[o...o+10]
        if part == empty
          bpioff = -((data.size - o) % 10)
          flag   = false
          break
        end
        name, size, flags = part.unpack('a4L>S>')
        size              = BitPaddedInteger.new size
        o                 += 10 + size.to_i
        if frames.constants.include? name.to_sym
          asbpi += 1
        end
      end
      if o >= (data.size - 10) and flag
        bpioff = o - data.size
      end

      # count number of tags found as int and how far past
      o     = 0
      asint = 0
      flag  = true
      while o < (data.size - 10)
        part = data[o...o + 10]
        if part == empty
          intoff = -((data.size - o) % 10)
          flag   = false
          break
        end
        name, size, flags = part.unpack('a4L>S>')
        o                 += 10 + size
        if frames.constants.include? name.to_sym
          asint += 1
        end
      end
      if o >= (data.size - 10) and flag
        intoff = o - data.size
      end

      # if more tags as int, or equal and bpi is past and int is not
      if asint > asbpi or (asint == asbpi and (bpioff >= 1 and intoff <= 1))
        Integer
      else
        BitPaddedInteger
      end
    end

    def read_frames(data, frames)
      if @version < V24 and f_unsynch != 0
        begin
          data = Unsynch.decode(data)
        rescue Mutagen::ValueError
          # ignore exception
        end
      end

      if V23 <= @version
        bpi = determine_bpi(data, frames)
        until data.empty?
          header = data[0...10]
          vals = header.unpack('a4L>S>')
          # not enough header
          return if vals.include? nil
          name, size, flags = vals
          return if Mutagen.strip_arbitrary(name, "\x00").empty?
          size      = if Integer == bpi then size.to_i else bpi.new(size) end
          framedata = data[10...10+size.to_i]
          data      = data[10+size.to_i..-1]
          if size == 0
            next # drop empty frames
          end

          # TODO: turn this into if frames.constants.include? name.to_sym
          begin
            tag = frames.const_get(name.to_sym)
          rescue NameError
            yield(header + framedata) if ID3::is_valid_frame_id(name)
          else
            begin
              yield load_framedata(tag, flags, framedata)
            rescue NotImplementedError
              yield header + framedata
            rescue ID3JunkFrameError
              # ignore exception
            end
          end
        end
      elsif V22 <= @version
        until data.empty?
          header = data[0...6]
          vals = header.unpack('a3a3')
          # Not enough header. 6 corresponds to the header unpacking string
          return if vals.inject(:+).bytesize != 6
          name, size = vals

          size, _ = ("\x00" + size).unpack('L>')
          return if Mutagen::strip_arbitrary(name, "\x00").empty?
          framedata = data[6...6+size]
          data      = data[6+size..-1]
          if size == 0
            next # drop empty frames
          end
          begin
            tag = frames.const_get(name.to_sym)
          rescue NameError
            yield(header + framedata) if ID3::is_valid_frame_id(name)
          else
            begin
              yield load_framedata(tag, 0, framedata)
            rescue NotImplementedError
              yield(header + framedata)
            rescue ID3JunkFrameError
              # ignore exception
            end
          end
        end
      end
    end

    def load_framedata(tag, flags, framedata)
      tag.from_data(self, flags, framedata)
    end

    def f_unsynch
      @flags & 0x80
    end

    def f_extended
      @flags & 0x40
    end

    def f_experimental
      @flags & 0x20
    end

    def f_footer
      @flags & 0x10
    end

    # def f_crc
    #   @extflags & 0x8000
    # end

    def prepare_framedata(v2_version, v23_sep)
      if v2_version == 3
        version = V23
      elsif v2_version == 4
        version = V24
      else
        raise ArgumentError, 'Only 3 or 4 allowed for v2_version'
      end

      # Sort frames by 'importance'
      order  = %w(TIT2 TPE1 TRCK TALB TPOS TDRC TCON).each_with_index.to_a
      last   = order.size
      frames = items
      frames.sort_by! { |a| [order[a[0][0...4]] || last, a[0]] }

      framedata = frames.each { |_, frame| save_frame(frame, version: version, v23_sep: v23_sep) }

      # only write unknown frames if they were loaded from the version
      # we are saving with or upgraded it to
      if @unknown_version == version
        framedata.push *@unknown_frames.select { |d| d.size > 10 }
      end

      framedata.join
    end

    def prepare_id3_header(original_header, framesize, v2_version)
      if (val = original_header.unpack('a3C3a4')).include? nil
        id3, insize = '', 0
      else
        id3, vmaj, vrev, flags, insize = val
      end
      insize = BitPaddedInteger.new insize
      if id3 != 'ID3'.b
        insize = -10
      end

      if insize >= framesize
        outsize = insize
      else
        outsize = (framesize + 1023) & ~0x3FF
      end

      framesize = BitPaddedInteger.to_str(outsize, width:4)
      header = ['ID3'.b, v2_version, 0, 0, framesize].pack('a3C3a4')
      return header, outsize, insize
    end

    # save #########################

    # Remove tags from a file.
    #
    # If no filename is given, the one most recently loaded is used.
    #
    # Keyword arguments:
    #
    # * delete_v1 -- delete any ID3v1 tag
    # * delete_v2 -- delete any ID3v2 tag
    def delete_tags(filename:nil, delete_v1:true, delete_v2:true)
      if filename.nil? or filename.empty?
        filename = @filename
      end
      ID3::delete(filename, delete_v1, delete_v2)
    end

    def save_frame(frame, name:nil, version:V24, v23_sep:nil)
      flags = 0
      if PEDANTIC and frame.is_a? TextFrame
        return '' if frame.to_s.empty?
      end

      if version == V23
        framev23 = frame.get_v23_frame(sep:v23_sep)
        framedata = framev23.write_data
      else
        framedata = frame.write_data
      end

      # usize = framedata.size
      # if usize > 2048
      #   # Disabled as this causes iTunes and other programs
      #   # fail to find these frames, which usually includes
      #   # e.g. APIC.
      #   #framedata = BitPaddedInt.to_str(usize) + framedata.encode('zlib')
      #   #flags |= Frame.FLAG24_COMPRESS | Frame.FLAG24_DATALEN
      # end

      if version == V24
        bits = 7
      elsif version == V23
        bits = 8
      else
        raise ArgumentError, "Version is not valid"
      end

      datasize = BitPaddedInteger.to_str(framedata.size, width:4, bits:bits)
      frame_name = frame.class.name.split("::").last.encode('ASCII-8BIT')
      header = [(name or frame_name), datasize, flags].pack('a4a4S>')
      header + framedata
    end

    # Updates done by both v23 and v24 update
    def update_common
      if self.include? 'TCON'
        # Get rid of "(xx)Foobr" format.
        self['TCON'].genres = self['TCON'].genres
      end

      if @version < V23
        # ID3v2.2 PIC frames are slightly different
        pics = get_all "APIC"
        mimes= {'PNG'=> 'image/png', 'JPG'=> 'image/jpeg'}
        delete_all 'APIC'
        pics.each do |pic|
          newpic = APIC.new(encoding:pic.encoding, mime:(mimes[pic.mime] or pic.mime), type: pic.type, desc: pic.desc, data: pic.data)
          add newpic
        end
        delete_all 'LINK'
      end
    end

    # Convert older tags into an ID3v2.4 tag.
    #
    # This updates old ID3v2 frames to ID3v2.4 ones (e.g. TYER to
    # TDRC). If you intend to save tags, you must call this function
    # at some point; it is called by default when loading the tag.
    def update_to_v24
      update_common

      if @unknown_version == V23
        # convert unknown 2.3 frames (flags/size) to 2.4
        converted = []
        @unknown_frames.each do |frame|
          if (val = frame[0...10]).include? nil
            next
          else
            name, size, flags = val
            frame             = ParentFrames::BinaryFrame.from_data(self, flags, frame[10..-1])
          end
          converted << save_frame(frame, name:name)
        end
      end

      # TDAT, TYER, and TIME have been turned into TDRC
      begin
        unless Mutagen::strip_arbitrary((self['TYER'] or '').to_s, "\x00").empty?
          date = @dict.delete('TYER').to_s
          unless Mutagen::strip_arbitrary((self['TDAT'] or '').to_s, "\x00").empty?
            dat = @dict.delete('TDAT').to_s
            date = "#{date}-#{dat[0...2]}-#{dat[2..-1]}"
            unless Mutagen::strip_arbitrary((self['TIME'] or '').to_s, "\x00").empty?
              time = @dict.delete('TIME').to_s
              date += "T#{time[0...2]}:#{time[2..-1]}:00"
            end
          end
          unless include? 'TDRC'
            add(Frames::TDRC.new(encoding:0, text:date))
          end
        end
      rescue EncodingError
        # Ignore
      end

      # TORY can be the first part of TDOR
      if include? 'TORY'
        f = @dict.delete['TORY']
        unless include? 'TDOR'
          begin
            add Frames::TDOR.new(encoding:0, text:f.to_s)
          rescue EncodingError
            # Ignore
          end
        end
      end

      # IPLC is now TIPL
      if include? 'IPLS'
        f = @dict.delete 'IPLS'
        unless include? "TIPL"
          add Frames::TIPl.new(encoding:f.encoding, people:f.people)
        end
      end

      # These can't be trivially translated to any ID3v2.4 tags, or
      # should have been removed already
      %w(RVAD EQUA TRDA TSIZ TDAT TIME CRM).each do |key|
        @dict.delete key if include? key
      end
    end

    # Convert older (and newer) tags into an ID3v2.3 tag.
    #
    # This updates incompatible ID3v2 frames to ID3v2.3 ones. If you
    # intend to save tags as ID3v2.3, you must call this function
    # at some point.
    #
    # If you want to to go off spec and include some v2.4 frames
    # in v2.3, remove them before calling this and add them back afterwards.
    def update_to_v23
      update_common

      # we could downgrade unknown v2.4 frames here, but given that
      # the main reason to save v2.3 is compatibility and this
      # might increase the chance of some parser breaking.. better not

      # TMCL, TIPL -> TIPL
      if include?('TIPL') or include?('TMCL')
        people = []
        people.push(*@dict.delete('TIPL').people) if include? 'TIPL'
        people.push(*@dict.delete('TMCL').people) if include? 'TMCL'
        unless include? 'IPLS'
          add IPLS.new(encoding: f.encoding, people:people)
        end
      end

      # TDOR -> TORY
      if include? 'TDOR'
        f = @dict.delete 'TDOR'
        unless f.text.empty?
          d = f.text.first
          unless d.year.nil? or d.year.empty? or include? "TORY"
            add Frames::TORY.new(encoding:f.encoding, text: ("%04d" % [d.year]))
          end
        end
      end

      # TDRC -> TYER, TDAT, TIME
      if include? 'TDRC'
        f = @dict.delete 'TDRC'
        unless f.text.nil? or f.text.empty?
          d = f.text.first
          unless d.year.nil? or d.year.empty? or include? 'TYER'
            add Frames::TYER.new(encoding:f.encoding, text: ("%04d" % [d.year]))
          end
          unless d.day.nil? or d.day.empty? or
              d.month.nil? or d.month.empty? or include? 'TDAT'
            add Frames::TDAT.new(encoding:f.encoding, text: ("%02d%02d" % [d.day, d.month]))
          end
          unless d.hour.nil? or d.minute.empty? or
              d.month.nil? or d.month.empty? or include? 'TIME'
            add Frames::TIME.new(encoding:f.encoding, text: ("%02d%02d" % [d.hour, d.minute]))
          end
        end
      end

      # New frames added in v2.4
      v24_frames = %w(ASPI EQU2 RVA2 SEEK SIGN TDEN TDOR TDRC TDRL TDTG TIPL TMCL TMOO TPRO TSOA TSOP TSOT TSST)
      v24_frames.each { |key| @dict.delete key if include? key }
    end

    # Remove tags from a file.
    #
    # Keyword arguments:
    #
    # * delete_v1 -- delete any ID3v1 tag
    # * delete_v2 -- delete any ID3v2 tag
    def self.delete(filename:nil, delete_v1:true, delete_v2:true)
      File.open(filename) do |f|
        if delete_v1
          flag = true
          begin
            f.seek -128, IO::SEEK_END
          rescue IOError
            flag = false
            # ignore
          end
          if flag and f.read(3) == 'TAG'
            f.seek -128, IO::SEEK_END
            f.truncate f.pos
          end
        end

        # technically an insize=0 tag is invalid, but we delete it anyway
        # (primarily because we used to write it)
        if delete_v2
          f.rewind
          idata = f.read 10
          begin
            val = idata.unpack('a3C4a4')
            if val.include? nil or
                val.first.bytesize != 3 or
                val.last.bytesize != 4
              id3, insize = '', -1
            else
              id3, vmaj, vrev, flags, insize = val
            end
            insize = BitPaddedInteger.new insize
            if id3 == 'ID3' and insize >= 0
              Mutagen::delete_bytes(f, insize + 10, 0)
            end
          end
        end
      end
    end

    # Parse an ID3v1 tag, returning a list of ID3v2.4 frames.
    def parse_ID3v1(string)
      idx = string.index('TAG')
      return if idx.nil?
      string = string.fetch(idx)
      return if 128 < string.size or string.size < 124

      # Issue #69 - Previous versions of Mutagen, when encountering
      # out-of-spec TDRC and TYER frames of less than four characters,
      # wrote only the characters available - e.g. "1" or "" - into the
      # year field. To parse those, reduce the size of the year field.
      # Amazingly, "0s" works as a struct format string.
      unpack_fmt =  'a3a30a30a30a%da29CC' % (string.size - 124)

      val = string.unpack unpack_fmt
      return if val.include? nil# or val.any? {|i| i.empty?}
      tag, title, artist, album, year, comment, track, genre = val
      return if tag != 'TAG'

      def fix(string)
        string.split("\x00").first.strip.force_encoding("ISO-8859-1")
      end

      [title, artist, album, year, comment].map! { |e| fix e }

      frames = {}
      unless title.nil? or title.empty?
        frames['TIT2'] = TIT2.new encoding:0, text:title
      end
      unless artist.nil? or artist.empty?
        frames['TPE1'] = TPE1.new encoding:0, text:[artist]
      end
      unless album.nil? or album.empty?
        frames['TALB'] = TALB.new encoding:0, text:album
      end
      unless year.nil? or year.empty?
        frames['TDRC'] = TDRC.new encoding:0, text:year
      end
      unless comment.nil? or comment.empty?
        frames['COMM'] = COMM.new encoding:0, lang:'eng', desc:'ID3v1 Comment', text:comment
      end
      # Don't read a track number if it looks like the comment was
      # padded with spaces instead of nulls (thanks, WinAmp).
      if not track.nil? and not track.empty? and
          (track != 32 or string[-3] == "\x00")
          frames['TRCK'] = TRCK encoding:0, text:track.to_s
      end
      if genre != 255
          frames['TCON'] = TCON.new encoding:0, text:genre.to_s
      end
      frames
    end


    # An unknown type of file with ID3 tags
    class ID3FileType < Mutagen::FileType

      class Info < Mutagen::StreamInfo
        def initialize(fileobj, offset)
          @length = 0
        end
        def pprint
          'Unknown format with ID3 tag'
        end
      end

      def score(filename, fileobj, header)
        header.start_with? 'ID3'
      end


      # Add an empty ID3 tag to the file
      #
      # A custom tag reader may be  used instead of the default
      # Mutagen::ID3::ID3
      def add_tags(id3:nil)

      end

    end
  end
end
