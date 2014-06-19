require 'mutagen/util'

module Mutagen
  module APEv2
    def self.is_valid_apev2_key(key)
      raise ArgumentError, "Keys need to be Strings" unless key.is_a? String

      (2 <= key.size and
          key.size <= 255 and
          key.each_char.min >= ' ' and
          key.each_char.max <= '~' and
          not %w(OggS TAG ID3 MP+).include?(key))
    end

    # There are three different kinds of APE tag values.
    # "0: Item contains text information coded in UTF-8
    #  1: Item contains binary information
    #  2: Item is a locator of external stored information [e.g. URL]
    #  3: reserved"
    TEXT, BINARY, EXTERNAL = [0,1,2]
    HAS_HEADER = 1 << 31
    HAS_NO_FOOTER = 1 << 30
    IS_HEADER = 1 <<29

    class APEv2Error < IOError
    end

    class APENoHeaderError < APEv2Error
    end

    class APEUnsupportedVersionError < APEv2Error
    end

    class APEBadItemError < APEv2Error
    end

    class APEv2DataOther
      def initialize(fileobj)
        # Store offsets of the important parts of the file.
        @start, @header, @data, @footer, @end = nil

        # Footer or header; seek here and read 32 to get version/size/items/flags
        @metadata = nil
        # Actual tag data
        @tag = nil

        @version, @size, @items = nil
        @flags = 0

        # The tag is at the start rather than the end. A tag at both
        # the start and end of the file (i.e. the tag is the whole file)
        # is not considered to be at the start.
        @is_at_start = false


        find_metdata(fileobj)

        if @header.nil?
          @metadata = @footer
        elsif @footer.nil?
          @metadata = @header
        else
          @metadata = [@header, @footer].max
        end

        return if @metadata.nil?

        fill_missing(fileobj)
        fix_brokenness(fileobj)

        unless @data.nil?
          fileobj.seek @data
          @tag = fileobj.read @size
        end
      end

      private

      # Try to find a header or footer
      # Check for a simple footer
      def find_metadata(fileobj)
        begin
          fileobj.seek -32, IO::SEEK_END
        rescue SystemCallError => err
          raise err unless err.is_a? Errno::EINVAL
          fileobj.seek 0, IO::SEEK_END
          return
        end

        if fileobj.read(8) == 'APETAGEX'
          fileobj.seek(-8, IO::SEEK_CUR)
          @footer = @metadata = fileobj.pos
          return
        end

        begin
          fileobj.seek -128, IO::SEEK_END
          if fileobj.read(3) == 'TAG'

            fileobj.seek -35, IO::SEEK_CUR  # 'TAG' + header length
            if fileobj.read(8) == 'APETAGEX'
              fileobj.seek -8, IO::SEEK_CUR
              @footer = fileobj.pos
              return
            end

            # ID3v1 tag at the end, maybe preceded by Lyrics3v2.
            # (http://www.id3.org/lyrics3200.html)
            # (header length - "APETAGEX") - "LYRICS200"
            fileobj.seek 15, IO::SEEK_CUR
            if fileobj.read(9) == 'LYRICS200'
              fileobj.seek -15, IO::SEEK_CUR  # "LYRICS200" + size tag
              begin
                offset = Integer fileobj.read(6)
              rescue ArgumentError
                raise IOError
              end

              fileobj.seek -32 - offset - 6, IO::SEEK_CUR
              if fileobj.read(8) == 'APETAGEX'
                fileobj.seek -8, IO::SEEK_CUR
                @footer = fileobj.pos
                return
              end
            end
          end
        rescue IOError
          # ignore
        end

        # check for a tag at the start
        fileobj.rewind
        if fileobj.read(8) == 'APETAGEX'
          @is_at_start = true
          @header = 0
        end
      end

      def fill_missing(fileobj)
        fileobj.seek(@metadata + 8)
        @version = fileobj.read(4)
        # @size = Mutagen::Util::CData::uint_le fileobj.read(4)
        # @items = Mutagen::Util::CData::uint_le fileobj.read(4)
        # @flags = Mutagen::Util::CData::uint_le fileobj.read(4)

        @size, @items, @flags = fileobj.read(12).unpack('I<3')

        if not @header.nil?
          @data = @header + 32
          # If we're reading the header, the size is the header
          # offset + the size, which includes the footer.
          @end = @data + @size
          fileobj.seek @end - 32
          if fileobj.read(8) == 'APETAGEX'
            @footer = @end - 32
          end

        elsif not @footer.nil?
          @end = @footer + 32
          @data = @end - @size
          if @flags & HAS_HEADER
            @header = @data - 32
          else
            @header = @data
          end
        else
          raise APENoHeaderError, 'No APE tag found'
        end

        # exclude the footer from size
        @size -= 32 unless @footer.nil?
      end

      def fix_brokenness(fileobj)
        # Fix broken taags written with PyMusepack
        start = @header.nil? ? @data : @header
        fileobj.seek start

        while start > 0
          # Clean up broken writing from pre-Mutagen PyMusepack.
          # It didn't remove the first 24 bytes of header.
          begin
            fileobj.seek(-24, IO::SEEK_CUR)
          rescue SystemCallError => err
            raise err unless err.is_a? Errno::EINVAL
          else
            if fileobj.read(8) == 'APETAGEX'
              fileobj.seek(-8, IO::SEEK_CUR)
              start = fileobj.pos
            else
              break
            end
          end
        end
        @start = start
      end
    end

    module CIDictProxy
      include Mutagen::Util::HashMixin
      def initialize(*args, **kwargs)
        @casemap = {}
        @dict = {}
        super(*args, **kwargs)
      end

      def [](key)
        @dict[key.downcase]
      end

      def []=(key, value)
        lower = key.downcase
        @casemap[lower] = key
        @dict[lower] = value
      end

      def delete(key)
        lower = key.downcase
        @casemap.delete lower
        @dict.delete lower
      end

      def keys
        @dict.keys.map {|key| @casemap.fetch(key, key) }
      end
    end
  end
end