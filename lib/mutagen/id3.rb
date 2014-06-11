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
# implemented as a different class (e.g. TIT2 as Mutagen::ID3::TIT2). Each
# frame's documentation contains a list of its attributes.
#
# Since this file's documentation is a little unwieldy, you are probably
# interested in the {ID3} class to start with.

require 'mutagen/util'
require 'mutagen/metadata'
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
    V24 = [2, 4, 0]
    V23 = [2, 3, 0]
    V22 = [2, 2, 0]
    V11 = [1, 1]

    attr_accessor :version

    def initialize(*args, **kwargs)
      @filename, @crc, @unknown_version = nil
      @size, @flags, @readbytes = 0

      @dict = {}  # Need this for our DictProxy
      @unknown_frames = []
      super(*args, **kwargs)
    end

    private
    def fullread(size)
      unless @fileobj.nil?
        raise Mutagen::ValueError, "Requested bytes (#{size}) less than zero" if size < 0
        if size > @fileobj.size
          raise EOFError, ('Requested %#x of %#x (%s)' % [size.to_i, @fileobj.size, filename])
        end
      end
      data = @fileobj.read size
      raise EOFError if data.size != size
      @readbytes += size
      data
    end

    public
    # Load tags from a filename
    #
    # @param filename [String] filename to load tag data from
    # @param known_frames [Hash] hash mapping frame IDs to Frame objects
    # @param translate [Bool] Update all the tags to ID3v2.3/4 internally. If you
    #                         intend to save, this must be true or you have to call
    #                         update_to_v23 / update_to_v24 manually.
    # @param v2_version [Fixnum] the minor version number of v2 to use
    def load(filename, known_frames:nil, translate:true, v2_version:4)
      raise Mutagen::ValueError, 'Only 3 and 4 possible for v2_version' unless [3, 4].include? v2_version
      @filename = filename
      @known_frames = known_frames
      File.open(filename, 'r') do |f|
        @fileobj = f
        begin
          load_header
        rescue EOFError
          @size = 0
          raise ID3NoHeaderError, "#{filename} too small (#{f.size} bytes)"
        rescue ID3NoHeaderError, ID3UnsupportedVersionError => err
          @size = 0
          begin
            f.seek(-128, IO::SEEK_END)
          rescue Errno::EINVAL
            raise err
          else
            frames = ParseID3v1(f.read(128))
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
          read_frames(data, frames:frames).each do |frame|
            if frame.is_a? Frame
              add frame
            else
              @unknown_frames << frame
            end
          end
        end
      end
      @fileobj = nil
      (v2_version == 3) ? update_to_v23 : update_to_v24 if translate
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
        each_pair.map{|s, v| v if s.start_with? key }.compact
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
      frames = values.map{ |v| Frame.pprint(v) }.sort.join("\n")
    end

    # @deprecated use the add method
    def loaded_frame(tag)
      warn '[DEPRECATION] `loaded_frame` is deprecated.  Please use `add` instead.'
      # turn 2.2 into 2.3/2.4 tags
      tag = tag.class.superclass.new(tag) if tag.class.to_s.size == 3
      self[tag.hash_key] = tag
    end

    # add = loaded_frame (and vice versa) break applications that
    # expect to be able to override loaded_frame (e.q. Quod Libet)
    # as does making loaded _frame call add

    # Add a frame to the tag
    def add(frame)
      loaded_frame(frame)
    end

    private
    def load_header
      data = fullread(10)
      id3, vmaj, vrev, flags, size = data.unpack('a3C3a4')
      @flags = flags
      @size = BitPaddedInteger.new(size) + 10
      @version = [2, vmaj, vrev]
      raise ID3NoHeaderError, "#{@filename} doesn't start with an ID3 tag" unless id3 == "ID3"
      raise ID3UnsupportedVersionError, "#{@filename} ID3v2.#{vmaj} not supported" unless [2,3,4].include? vmaj

      if PEDANTIC
        raise Mutagen::ValueError, "Header size not synchsafe" unless BitPaddedInteger.has_valid_padding(size)
        if (V24 <= @version or (V23 <= @version and @version < V24)) and (flags & 0x1f)
          raise Mutagen::ValueError, ("#{@filename} has invalid flags %#02x" % [flags])
        end
      end

      unless @f_extended.nil?
        extsize = fullread 4
        if Frames.constants.include? extsize.to_sym
          # Some tagger sets the extended header flag but
          # doesn't write an extended header; in this case, the
          # ID3 data follows immediately. Since no extended
          # header is going to be long enough to actually match
          # a frame, and if it's *not* a frame we're going to be
          # completely lost anyway, this seems to be the most
          # correct check.
          # http://code.google.com/p/quodlibet/issues/detail?id=126
          @flags ^= 0x40
          @extsize = 0
          @fileobj.seek(-4, IO::SEEK_CUR)
          @readbytes -= 4
        elsif @version >= V24
          # "Where the 'Extended header size' is the size of the whole
          # extended header, stored as a 32 bit synchsafe integer."
          @extsize = BitPaddedInteger.new(extsize) - 4
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
          @extsize = fullread(@extsize)
        else
          @extsize = ""
        end
      end
    end

    def determine_bpi(data, frames, empty:"\x00" * 10)
      if @version < V24
        Integer
      end
      # have to special case whether to use bitpaddedints here
      # spec says to use them, but iTunes has it wrong

      # count number of tags found as BitPaddedInt and how far past
      o = 0
      asbpi = 0
      flag = true
      while o < (data.size - 10)
        part = data[o...o+10]
        if part == empty
          bpioff = -((data.size - o) % 10)
          flag = false
          break
        end
        name, size, flags = part.unpack('a4L>S>')
        size = BitPaddedInteger(size)
        o += 10 + size
        if frames.constants.include? name.to_sym
          asbpi += 1
        end
      end
      if o >= (data.size - 10) and flag
        bpioff = o - data.size
      end

      # count number of tags found as int and how far past
      o = 0
      asint = 0
      flag = true
      while o < (data.size - 10)
        part = data[o...o + 10]
        if part == empty
          intoff = -((data.size - o) % 10)
          flag = false
          break
        end
        name, size, flags = part.unpack('a4L>S>')
        o += 10 + size
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
      if @version < V24 and @f_unsynch
        begin
          data = Unsynch.decode(data)
        rescue Mutagen::ValueError
          # ignore exception
        end
      end

      if V23 <= @version
        bpi = determine_bpi(data, frames)
        while data > 0
          header = [0...10]
          if (vals = header.unpack('a4L>S>')).include? nil
            return # not enough header
          else
            name, size, flags = vals
          end
          if name.strip("\x00").empty?
            return
          end
          size = bpi(size)
          framedata = data[10...10+size]
          data = data[10+size..-1]
          if size == 0
            next # drop empty frames
          end

          # TODO: turn this into if frames.constants.include? name.to_sym
          begin
            tag = frames.const_get(name.to_sym)
          rescue NameError
            yield(header + framedata) if is_valid_frame_id(name)
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
        while data > 0
          header = data[0...6]
          if (vals = header.unpack('a3a3')).include? nil
            return              # not enough header
          else
            name, size = vals
          end
          size, _ = ("\x00" + size),unpack('L>')
          if name.strip("\x00").empty?
            return
          end
          framedata = data[6...6+size]
          data = data[6+size..-1]
          if size == 0
            next # drop empty frames
          end
          begin
            tag = frames.const_get(name.to_sym)
          rescue NameError
            yield(header + framedata) if is_valid_frame_id(name)
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
      order = %w(TIT2 TPE1 TRCK TALB TPOS TDRC TCON).each_with_index.to_a
      last = order.size
      frames = items
      frames.sort_by! { |a| [order[a[0][0...4]] || last, a[0]] }

      framedata = frames.each {|_, frame| save_frame(frame, version: version, v23_sep:v23_sep) }

      # only write unknown frames if they were loaded from the version
      # we are saving with or upgraded it to
      if @unknown_version == version
        framedata.push *@unknown_frames.select {|d| d.size > 10 }
      end

      framedata.join
    end

    def prepare_id3_header(original_header, framesize, v2_version)
    end
  end
end
