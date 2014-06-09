module Mutagen::ID3
  class NoHeaderError < StandardError; end
  class BadUnsynchData < StandardError; end
  class BadCompressedData < StandardError; end
  class TagError < StandardError; end
  class UnsupportedVersionError < StandardError; end
  class EncryptionUnsupportedError < StandardError; end
  class JunkFrameError < StandardError; end
  class Warning < StandardError; end

  module Unsynch
    def self.decode(value)
      output = []
      safe = true
      value.each do |val|
        if safe
          output << val
          safe = (val != 0xFF)
        else
          if val >= 0xE0
            raise 'invalid sync-safe string'
          elsif val != 0x00
            output << val
          end
          safe = true
        end
      end
      raise 'string ended unsafe' unless safe
      return output
    end

    def self.encode(value)
      output = []
      safe = true
      value.each do |val|
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
      to_str(@value, bits, bigendian, width, minwidth)
    end

    def self.to_str(value, bits:7, bigendian:true, width:4, minwidth:4)
      mask = (1 << bits) - 1

      if width != -1
        index = 0
        bytes_ = Array.new(width, "\x00")
        while value > 0
          raise "Value too wide (#{width} bytes)" if index > width
          bytes_[index] = value & mask
          value >>= bits
          index += 1
        end
      else
        # PCNT and POPM use growing integers
        # of at least 4 bytes (=minwidth) as counters
        bytes_ = []
        while value > 0
          bytes_ << (value & mask)
          value >>= bits
        end
        bytes_.fill(0, bytes_.length..minwidth)
      end
      bytes_.reverse! if bigendian
      bytes_
    end

    # Check if a value is properly padded
    # @param value [Array, Integer] the value to check
    # @return [Bool] whether or not the padding was valid
    def self.has_valid_padding(value, bits=7)
      raise ArgumentError if bits > 8

      mask = (((1 << (8 - bits)) - 1) << bits)

      case value
      when Integer
        while value > 0
          return false if (value & mask)
          value >>= 8
        end
      when Array
        value.each { |byte| return false if (byte & mask) }
      else
        raise TypeError, "Expected either an Integer or an Array, not #{value.class}"
      end
      true
    end
  end

  class BitPaddedInteger
    include BitPaddedMixin
    attr_reader :bits, :bigendian, :value

    def initialize(value, bits:7, bigendian:true)
      mask = (1 << (bits)) - 1
      numeric_value = 0
      shift = 0
      case value
      when Integer
        while value > 0
          numeric_value += ((value & mask) << shift)
          value >>= 8
          shift += bits
        end
      when Array
        value.reverse! if bigendian
        value.each do |byte|
          numeric_value += ((byte & mask) << shift)
          shift += bits
        end
      else
        raise TypeError, "Expected either an Integer or an Array, not #{value.class}"
      end
      @value = numeric_value
      @bits = bits
      @bigendian = bigendian
    end

    def to_int
      Integer(@value)
    end

    def method_missing(name, *args, &blk)
      ret = @number.send(name, *args, &blk)
      ret.is_a?(Numeric) ? BitPaddedInteger.new(ret) : ret
    end
  end
end