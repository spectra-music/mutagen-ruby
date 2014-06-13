module Mutagen
  module ID3
    class ID3NoHeaderError < ValueError
    end
    class ID3BadUnsynchData < ValueError
    end
    class ID3BadCompressedData < ValueError
    end
    class ID3TagError < ValueError
    end
    class ID3UnsupportedVersionError < NotImplementedError
    end
    class ID3EncryptionUnsupportedError < NotImplementedError
    end
    class ID3JunkFrameError < ValueError
    end
    class ID3Warning < ValueError
    end

    module Unsynch
      def self.decode(value)
        output = ''.b
        safe   = true
        value.each_byte do |val|
          if safe
            output << val
            safe = (val != 0xFF)
          else
            if val >= 0xE0
              raise Mutagen::ValueError, 'invalid sync-safe string'
            elsif val != 0x00
              output << val
            end
            safe = true
          end
        end
        raise Mutagen::ValueError, 'string ended unsafe' unless safe
        return output
      end

      def self.encode(value)
        output = ''.b
        safe   = true
        value.each_byte do |val|
          if safe
            output << val
            safe = false if val == 0xFF
          elsif val == 0x00 or val >= 0xE0
            output << 0x00
            output << val
            safe = (val != 0xFF)
          else
            output << val
            safe = true
          end
        end
        (output << 0x00) unless safe
        return output
      end
    end

    module BitPaddedMixin
      def to_s(width=4, minwidth=4)
        self.class.to_str(@value, bits: bits, bigendian: bigendian, width: width, minwidth: minwidth)
      end

      module ClassMethods
        def to_str(value, bits: 7, bigendian: true, width: 4, minwidth: 4)
          mask = (1 << bits) - 1

          if width != -1
            index  = 0
            bytes_ = "\x00" * width
            while value > 0
              raise Mutagen::ValueError, "Value too wide (#{width} bytes)" if index >= width
              bytes_.setbyte(index, value & mask)
              value >>= bits
              index += 1
            end
          else
            # PCNT and POPM use growing integers
            # of at least 4 bytes (=minwidth) as counters
            bytes_ = ''
            while value > 0
              # << takes a string, so turn our byte into a string
              bytes_ << (value & mask).chr
              value >>= bits
            end
            bytes_ = bytes_.ljust(minwidth, "\x00")
          end
          bytes_.reverse! if bigendian
          bytes_
        end

        # Check if a value is properly padded
        # @param value [Array, Integer] the value to check
        # @return [Bool] whether or not the padding was valid
        def has_valid_padding(value, bits: 7)
          raise ArgumentError if bits > 8

          mask = (((1 << (8 - bits)) - 1) << bits)

          case value
          when Integer
            while value > 0
              return false if (value & mask) > 0
              value >>= 8
            end
          when String
            value.each_byte { |byte| return false if (byte & mask) > 0 }
          else
            raise TypeError, "Expected either an Integer or a String, not #{value.class}"
          end
          true
        end
      end

      def self.included(base)
        base.extend ClassMethods
      end
    end

    class BitPaddedInteger
      include BitPaddedMixin
      attr_reader :bits, :bigendian, :value

      def initialize(value, bits: 7, bigendian: true)
        mask          = (1 << (bits)) - 1
        numeric_value = 0
        shift         = 0
        case value
        when Integer
          while value > 0
            numeric_value += ((value & mask) << shift)
            value         >>= 8
            shift         += bits
          end
        when String
          value.reverse! if bigendian
          value.each_byte do |byte|
            numeric_value += ((byte & mask) << shift)
            shift         += bits
          end
        else
          raise TypeError, "Expected either an Integer or an Array, not #{value.class}"
        end
        @value     = numeric_value
        @bits      = bits
        @bigendian = bigendian
      end

      def to_int
        Integer(@value)
      end

      alias_method :to_i, :to_int

      def method_missing(name, *args, &blk)
        ret = @value.send(name, *args, &blk)
        ret.is_a?(Numeric) ? BitPaddedInteger.new(ret) : ret
      end

      def ==(other)
        case other
        when BitPaddedInteger
          value == other.value
        when Numeric
          value == other
        else
          false
        end
      end
    end
  end
end