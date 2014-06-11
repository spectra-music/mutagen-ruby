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
    V24 = [2, 4, 0].freeze
    V23 = [2, 3, 0].freeze
    V22 = [2, 2, 0].freeze
    V11 = [1, 1].freeze

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
        each_pair.map{|s, v| v if s.start_with? key }
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
      frames = values.map{ |v| "#{v.class}=#{v.to_s}" }.sort.join("\n")
    end

    # @deprecated use the add method
    def loaded_frame(tag)
      warn '[DEPRECATION] `loaded_frame` is deprecated.  Please use `add` instead.'
      # turn 2.2 into 2.3/2.4 tags
      tag = tag.class.superclass.new(tag) if tag.class.to_s.size == 3
      self[tag.hash_key] = tag
    end
  end
end