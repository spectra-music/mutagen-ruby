require 'streaminfo'

module Mutagen
  module MP3
    class Error < RuntimeError
    end
    class HeaderNotFoundError < IOError
    end
    class InvalidMPEGHeader < IOError
    end

    STEREO, JOINTSTEREO, DUALCHANNEL, MONO = [0...4]
  end


  class MPEGInfo < Mutagen::StreamInfo



  # Map (version, layer) tuples to bitrates.
  BITRATE = {
        [1,1] => [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
        [1, 2] => [0, 32, 48, 56, 64, 80, 96, 112, 128,
                   160, 192, 224, 256, 320, 384],
        [1, 3] => [0, 32, 40, 48, 56, 64, 80, 96, 112,
                   128, 160, 192, 224, 256, 320],
        [2, 1] => [0, 32, 48, 56, 64, 80, 96, 112, 128,
                   144, 160, 176, 192, 224, 256],
        [2, 2] => [0,  8, 16, 24, 32, 40, 48, 56, 64,
                   80, 96, 112, 128, 144, 160]
    }

    BITRATE[[2,3]] = BITRATE[[2,2]]
    [1...4].each do |i|
      BITRATE[[2.5, i]] = BITRATE[[2,i]]
    end

    # Map version to sample rates.
    RATES = {
        1 => [44100, 48000, 32000],
        2 => [22050, 24000, 16000],
        2.5 => [11025, 12000, 8000]
    }

    @sketchy = false

    # Parse MPEG stream information from a file-like object.
    #
    # If an offset argument is given, it is used to start looking
    # for stream information and Xing headers; otherwise, ID3v2 tags
    # will be skipped automatically. A correct offset can make
    # loading files significantly faster.
    def initialize(fileobj, offset=nil)

    end
  end
end