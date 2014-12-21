require 'mutagen/streaminfo'
require 'mutagen/metadata'

module Mutagen
  module ASF
    class Error < IOError
    end
    class ASFError < Error
    end
    class ASFHeaderError < Error
    end

    STANDARD_ATTRIBUTE_NAMES = %w(Title Author Copyright Description Rating)

    # ASF Stream information
    class ASFInfo < Mutagen::StreamInfo
      def initialize
        @length = 0.0
        @sample_rate = 0
        @bitrate = 0
        @channels = 0
      end

      def pprint
        "Windows Media Audio #{@bitrate}, #{@sample_rate} Hz, #{@channels}, %.2f" % [@length]
      end
    end

    class ASFTags < Mutagen::Metadata
      include Mutagen::Util::DictProxy

      def pprint
        items.map { |k,v| "#{k}=#{v}" }.join "\n"
      end

      # A list of values for the key
      #
      # This is a copy, so comment['title'].append('a title') will not work
      def [](key)
        @dict[key]
      end

      # Set a key's value or values
      #
      # Setting a value overwrites all old ones. The value may be a
      # list of Unicode or UTF-8 strings, or a single Unicode or UTF-8
      # string.
      def []=(key, values)
        values = [values] unless value.is_a? Array
        @dict.delete key
        values.each do |value|
          value =
              if STANDARD_ATTRIBUTE_NAMES.include? key
                value.to_s
              elsif not value.is_a? ASFBaseAttribute
                if value.is_a? String
                  ASFUnicodeAttribute.new value
                elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
                  ASFBoolAttribute.new value
                elsif value.is_a? Numeric
                  ASFWordAttribute.new value
                end
              end
          if @dict.has_key? key
            @dict[key] << value
          else
            @dict[key] = [value]
          end
        end
      end
    end

    # Generic attribute
    module ASFBaseAttribute
      TYPE = nil

      def initialize(value:nil, data:nil, language:nil, stream:nil, **kwargs)
        @language = language
        @stream = stream
        if data.nil?
          @value = value
        else
          @value = parse data, ** kwargs
        end
      end

      def data_size
        raise NotImplementedError
      end

      def render(name)
        name = name.encode('UTF-16') + "\00\x00"
        data = _render
        return [name.size.to_s].pack('<S') + name + [], 0
      end
    end


  end
end