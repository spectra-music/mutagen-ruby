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
      if instance_variable_defined? @filesize
        raise Mutagen::ValueError, "Requested bytes (#{size}) less than zero" if size < 0
        if size > @filesize
          raise EOFError, ('Requested %#x of %#x (%s)' % [size.to_i, @filesize.to_i, filename])
        end
      end
      data = @filobj.read size
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
    # @param v2_version [Fixnum]




    `

  end
end