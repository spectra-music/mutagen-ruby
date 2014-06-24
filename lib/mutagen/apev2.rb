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
      # Store offsets of the important parts of the file.
      attr_reader :start, :header, :data, :footer, :end

      # Footer or header; seek here and read 32 to get version/size/items/flags
      attr_reader :metadata

      # Actual tag data
      attr_reader :tag

      attr_reader :version, :size, :items, :flags

      def initialize(fileobj)
        @flags = 0

        @at_start = false

        find_metadata(fileobj)

        @metadata = if @header.nil?
                      @footer
                    elsif @footer.nil?
                      @header
                    else
                      [@header, @footer].max
                    end

        return if @metadata.nil?

        fill_missing(fileobj)
        fix_brokenness(fileobj)

        unless @data.nil?
          fileobj.seek @data
          @tag = fileobj.read @size
        end
      end

      # The tag is at the start rather than the end. A tag at both
      # the start and end of the file (i.e. the tag is the whole file)
      # is not considered to be at the start.
      def at_start?
        @at_start
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
                offset_s = fileobj.read(6)
                raise IOError unless offset_s =~ /\A[-+]?[0-9]+\z/
                offset = offset_s.to_i
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
          @at_start = true
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
        # Internally all names are stored as lowercase, but the case
        # they were set with is remembered and used when saving.  This
        # is roughly in line with the standard, which says that keys
        # are case-sensitive but two keys differing only in case are
        # not allowed, and recommends case-insensitive
        # implementations.
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

      def include?(object)
        return false unless object.is_a? String
        @dict.keys.any?{ |s| s.casecmp(object) == 0 }
      end
    end

    # A file with an APEv2 tag.
    #
    # ID3v1 tags are silently ignored and overwritten.
    class APEv2Data < Mutagen::Metadata
      include CIDictProxy

      # Return tag key=value pairs in a human readable format.
      def pprint
        local_items = items.sort
        local_items.map { |k,v| "#{k}=#{v}" }.join "\n"
      end

      # Load tags from a filename.
      def load(filename, **args)
        @filename = filename

        f = File.open(filename, 'rb')
        begin
          data = APEv2DataOther.new f
        ensure
          f.close
        end

        raise APENoHeaderError, 'No APE tag found' if data.tag.nil?
        clear
        parse_tag(data.tag, data.items)
      end

      private
      def parse_tag(tag, count)
        fileobj = StringIO.new tag

        count.times do |i|
          size_data = fileobj.read 4
          #someone writes wrong items count
          break if size_data.nil?

          size, flags = (size_data + fileobj.read(4)).unpack('I<2')

          # Bits 1 and 2 are flags, 0-3
          # Bit 0 is read/write flag, ignored
          kind = (flags & 6) >> 1
          if kind > 2
            raise APEBadItemError, 'value type must be 0, 1, or 2'
          end
          key = value = fileobj.read 1
          while key[-1] != "\x00" and not value.empty?
            value = fileobj.read 1
            key << value
          end
          key = key[0...-1] if key[-1] == "\x00"
          begin
            key = key.encode('utf-8')
          rescue EncodingError
            raise APEBadItemError
          end
          value = fileobj.read size

          value = case kind
                  when TEXT
                    APETextValue.new value, kind
                  when BINARY
                    APEBinaryValue.new value, kind
                  when EXTERNAL
                    APEExtValue.new value, kind
                  end
          self[key] = value
        end
      end

      public
      def [](key)
        raise KeyError, "#{key} is not a valid APEv2 key" unless Mutagen::APEv2::is_valid_apev2_key key
        super(key)
      end

      def delete(key)
        raise KeyError, "#{key} is not a valid APEv2 key" unless Mutagen::APEv2::is_valid_apev2_key key
        super(key)
      end

      def []=(key, value)
        raise KeyError, "#{key} is not a valid APEv2 key" unless Mutagen::APEv2::is_valid_apev2_key key
        unless value.is_a? APEByteValue
          # lets guess at the content if we're not already a value...
          if value.is_a?(String) and value.encoding == Encoding::ASCII_8BIT
            value = APEValue.new value, BINARY
          elsif value.is_a?(String) and value.encoding == Encoding::UTF_8
            # unicode? we've got to be text
            value = APEValue.new value, TEXT
          elsif value.is_a? Array
            value.each do |v|
              raise TypeError, 'item in list not String' unless v.is_a? String
            end
            # list? text.
            value = APEValue.new value.join("\0"), TEXT
          else
            raise ArgumentError, "Value #{value} is not valid"
          end
        end

        super(key, value)
      end

      # Save changes to a file.
      #
      # If no filename is given, the one most recently loaded is used.
      #
      # Tags are always written at the end of the file, and include
      # a header and a footer.
      def save(filename=@filename)
        fileobj = begin
          File.open filename, 'rb+'
        rescue SystemCallError
          File.open filename, 'wb+'
        end
        data = APEv2DataOther.new fileobj

        if data.at_start?
          Mutagen::Util::delete_bytes(fileobj, data.end - data.start, data.start)
        elsif not data.start.nil?
          fileobj.seek data.start
          # Delete an ID3v1 tag if present, too.
          fileobj.truncate fileobj.pos
        end
        fileobj.seek(0, IO::SEEK_END)

        # "APE tags items should be sorted ascending by size... This is
        # not a MUST, but STRONGLY recommended. Actually the items should
        # be sorted by importance/byte, but this is not feasible."
        tags = items.map { |k, v|  v.send(:internal, k) }.sort_by(&:length)
        num_tags = tags.size
        tags = tags.join

        header = 'APETAGEX'.b
        # version, tag size, item count, flags
        header << [2000, tags.size + 32, num_tags, HAS_HEADER | IS_HEADER].pack('I<4')
        header << "\0" * 8
        fileobj.write header

        fileobj.write tags
        footer = 'APETAGEX'.b
        footer << [2000, tags.size + 32, num_tags, HAS_HEADER].pack('I<4')
        footer << "\0" * 8

        fileobj.write footer
        fileobj.close
      end

      # Remove tags from a file
      def delete_tags(filename=@filename)
        File.open(filename, 'rb+') do |fileobj|
          data = APEv2DataOther.new fileobj
          unless data.start.nil? or data.size.nil?
            Mutagen::Util::delete_bytes(fileobj, data.end - data.start, data.start)
          end
          clear
        end
      end
    end

    # remove tags from a file
    def self.delete(filename)
      begin
        APEv2Data.new(filename).delete_tags
      rescue APENoHeaderError
        # ignore
      end
    end

    # APEv2 tag value factory.
    #
    # Use this if you need to specify the value's type manually.  Binary
    # and text data are automatically detected by APEv2.__setitem__.
    class APEValue
      class << self
        alias_method :__new__, :new

        def inherited(subclass)
          class << subclass
            alias_method :new, :__new__
          end
        end
      end

      def self.new(value, kind)
        if [TEXT, EXTERNAL].include? kind
          raise TypeError, 'String only for text/external values' unless value.is_a? String
          value = value.encode('utf-8')
        end

        case kind
        when TEXT
          APETextValue.new value, kind
        when BINARY
          APEBinaryValue.new value, kind
        when EXTERNAL
          APEExtValue.new value, kind
        else
          raise ArgumentError, 'kind must be TEXT, BINARY, or EXTERNAL'
        end
      end
    end

    class APEByteValue
      include Comparable
      attr_reader :kind, :value

      def initialize(value, kind)
        raise ArgumentError, 'value not String' unless value.is_a? String
        @kind = kind
        @value = value
      end

      def length
        value.bytesize
      end

      alias_method :size, :length

      def ==(other)
        @value == other
      end

      def <=>(other)
        @value <=> other
      end

      # Packed format for an item:
      # 4B: Value length
      # 4B: Value type
      # Key name
      # 1B: Null
      # Key value
      def internal(key)
        data = ''.b
        data << [@value.bytesize, @kind << 1].pack('I<2')
        data << key
        data << "\0"
        data << @value
      end

      def to_s
        "#{self.class.name}.new(#{@value}, #{@kind.to_i})"
      end
    end

    class APEUtf8Value < APEByteValue
      def to_s
        @value
      end

      def ==(other)
        to_s == other
      end

      def <=>(other)
        to_s <=> other
      end
    end

    # An APEv2 text value.
    #
    # Text values are Unicode/UTF-8 strings. They can be accessed like
    # strings (with a null separating the values), or arrays of strings.
    class APETextValue < APEUtf8Value
      include Enumerable
      # Iterate over the strings of the value (not the characters)
      def each(&block)
        to_s.split("\0").each(&block)
      end

      def [](index)
        to_s.split("\0")[index]
      end

      def length
        value.count("\0") + 1
      end

      alias_method :size, :length

      def []=(index, value)
        raise ArgumentError, 'value not String' unless value.is_a? String
        values = to_a
        values[index] = value
        @value = values.join("\0").encode('utf-8')
      end

      def pprint
        to_a.join " / "
      end
    end

    # An APEv2 binary value
    class APEBinaryValue < APEByteValue
      def pprint
        "[#{self.size} bytes]"
      end

      def to_s
        @value.to_s
      end
    end

    # An APEv2 external value.
    #
    # External values are usually URI or IRI strings.
    class APEExtValue < APEUtf8Value
      def pprint
        "[External] #{self.to_s}"
      end
    end

    class APEv2File < Mutagen::FileType
      class Info < Mutagen::StreamInfo
        attr_reader :length, :bitrate
        def initialize(fileobj)
          @length = 0
          @bitrate = 0
        end

        def pprint
          'Unknown format with APEv2 tag.'
        end
      end

      def load(filename, *args)
        @filename = filename
        @info = Info.new(File.open(filename, 'rb'))
        begin
          @tags = APEv2Data.new filename
        rescue APEv2Error
          @tags = nil
        end
      end

      def add_tags
        if @tags.nil?
          @tags = APEv2Data.new
        else
          raise Mutagen::Util::ValueError, "#{self} already has tags: #{@tags.inspect}"
        end
      end

      def self.score(filename, fileobj, header)
        begin
          fileobj.seek -160, 2
        rescue SystemCallError
          fileobj.rewind
        end
        footer = fileobj.read
        filename = filename.lower
        (footer.include? 'APETAGEX' ? 1 : 0) - (header.start_with?('ID3') ? 1 : 0)
      end
    end
  end
end