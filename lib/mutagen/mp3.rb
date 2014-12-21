require_relative 'streaminfo'

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
      size = begin 
        File.size fileobj.path
      rescue ERRNO::ENOENT, IOError
        fileobj.seek(0, IO::SEEK_END)
        fileobj.tell
      end

      # If we don't get an offset, try to skip an ID3v2 tag.
      if offset.nil?
        fileobj.rewind
        idata = fileobj.read 10
        if (val = idata.unpack('a3xxxa4')).include? nil
          id3, insize = '', 0
        else
          id3, insize = val
        end

        insize = Mutagen::ID3::BitPaddedInteger.new insize

        if id3 == 'ID3' and insize > 0
          offset = insize + 10
        else
          offset = 0
        end
      end

      # Try to find two valid headers (meaning, very likely, MPEG data)
      # at the given offset, 30% through the file, 60% through the file,
      # and 90% through the file.
      flag = false
      [offset, 0.3*size, 0.6*size, 0.9*size].each do |i|
        begin 
          try(fileobj, Integer(i), size - offset)
        rescue Mutagen::MP3::ERROR
          pass
        else 
          flag = true
          break
        end
      end
      # If we can't find any two consecutive frames, try to find just
      # one frame back at the original offset given.
      unless flag
        try(fileobj, offset, size - offset, false)
        @sketchy = true
      end
    end

    def try(fileobj, offset, real_size, check_second=true)
      # This is going to be one really long function; bear with it
      # because there's not really a save point to cut it up
      fileobj.rewind

      # We "know" we have an MPEG file if we find two frames that look like
      # valid MPEG data. If we can't find them in 32k of reads, something
      # is horribly wrong (the longest frame can only be about 4k). This
      # is assuming the offset didn't lie.
      data = fileobj.read(32768)

      frame_1 = data.index "\xff"
      raise HeaderNotFoundError, "can't sync to an MPEG frame" if frame_1.nil?

      while 0 <= frame_1 <= (data.size - 4)
        frame_data = data[frame_1...(frame_1 + 4)].unpack("I>")[0]
        if (frame_data >> 16) & 0xE0 != 0xE0
          frame_1 = data.index("\xff", frame_1 + 2)
        else
          version = (frame_data >> 19) & 0x3
          layer = (frame_data >> 17) & 0x3
          protection = (frame_data >> 16) & 0x1
          bitrate = (frame_data >> 12) & 0xF
          sample_rate = (frame_data >> 10) & 0x3
          padding = (frame_data >> 9) & 0x1
          #private = (frame_data >> 8) & 0x1
          @mode = (frame_data >> 6) & 0x3
          #mode_extension = (frame_data >> 4) & 0x3
          #copyright = (frame_data >> 3) & 0x1
          #original = (frame_data >> 2) & 0x1
          #emphasis = (frame_data >> 0) & 0x3
          if version == 1 or layer == 0 or sample_rate == 0x3 or 
              bitrate == 0 or bitrate == 0xF
            frame_1 = data.index("\xff", frame_1 + 2)
          else 
            break
          end
        end
      end

      # There is a serious problem here, which is that many flags 
      # in an MPEG header are backwards
      @version = [2.5, nil, 2, 1,][version]
      @layer = 4 - layer
      @protected = !(protection != 0 and (!protection.nil?))
      @padding = (padding != 0 and (!padding.nil?))
      @bitrate = BITRATE[[@version, @layer]][bitrate] * 1000
      @sample_rate = RATES[@version][sample_rate]

      if @layer == 1
        frame_length = (12 * @bitrate / @sample_rate + padding) * 4
        frame_size = 384
      elsif @version >= 2 and @layer == 3
        frame_length = 72 * @bitrate / @sample_rate + padding
        frame_size = 576
      else
        frame_length = 144 * @bitrate / @sample_rate + padding
        frame_size = 1152
      end

      if check_second
        possible = Integer(frame_1 + frame_length)
        raise HeaderNotFoundError, "can't sync to second MPEG frame" if possible > data.size + 4
        frame_data = data[possible...possible+2].unpack("S>").first
        if frame_data.nil? || (frame_data & 0xFFE0 != 0xFFE0)
          raise HeaderNotFoundError, "can't sync to second MPEG frame"
        end
      end

      @length = 8 * real_size / Float(@bitrate)

      # Try and find/parse the Xing header, which trumps the above length
      # calculation
      fileobj.seek(offset, IO::SEEK_SET)
      data = fileobj.read(32768)
      xing = data[0...-4].index('Xing')
      if xing.nil? 
        # Try to find/parse the VBRI header, which trumps the above length
        # calculation
        vbri = data[0...-24].index('VBRI')
        unless vbri.nil?
          # If a VBRI header was found, this is definitely MPEG audio
          @sketchy = false
          vbri_version = data[vbri+4...vbri+6].unpack('S>').first
          if vbri_version == 1
            frame_count = data[vbri + 14 ... vbri + 18].unpack('I>').first
            samples = Float(frame_size * frame_count)
            len = (samples / @sample_rate)
            @length = len if len != 0
          end
        end
      else
        # If a Xing header was found, this is definitely MPEG audio.
        @sketchy = false
        flags = data[xing + 4 ... xing + 8].unpack('I>').first
        if flags & 0x1 != 0
          frame_count = data[xing + 8 ... xing + 12].first
          samples = Float(frame_size * frame_count)
          len = (samples / @sample_rate)
          @length = len if len != 0
        end
        if flags & 0x2 != 0
          bytes = data[xing + 12 ... xing + 16].first
          @bitrate = Integer(((bytes * 8) / @length).floor)
        end
      end
    end

    def pprint
      s = 'MPEG %s layer %d, %d bps, %s Hz, %.2f seconds' % [
        @version, @layer, @bitrate, @sample_rate, @length]
      s + ' (sketchy)' if @sketchy
    end

  end
end