module Mutagen
  # Abstract stream information object
  # provides attributes for length, bitrate, sample rate, etc.
  # See the implementations for details
  class StreamInfo
    # Print the string information
    def to_s
      raise NotImplementedError
    end
  end
end