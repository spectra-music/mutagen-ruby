require 'mutagen/id3/util'
module Mutagen::ID3
class Spec
  def initialize(name)
    @name = name
  end

  # return a possible modified value which, if
  # written, results in valid id3v2.3 data
  def _validate23(frame, value, **kwargs)
    value
  end
end


class ByteSpec < Spec
  def read(frame, data)
    return data[0].ord, data[1..-1]
  end

  def write(frame, value)
    raise TypeError, 'value is not a Numeric' unless value.is_a? Numeric
    value.chr
  end

  def validate(frame, value)
    value.chr unless value.nil?
    value
  end
end

class IntegerSpec < Spec
  def read(frame, data)
    BitPaddedInteger.new(data, 8).to_int
  end

  def write(frame, value)
    BitPaddedInteger.to_str(value, bits:8, width:-1)

  end

  def validate(frame, value)
    value
  end
end

class SizedIntegerSpec < Spec
  def initialize(name, size)
    @name = name
    @size = size
  end

  def read(frame, data)
    return BitPaddedInteger(data, bits:8).to_int, ''
  end

  def write(frame, value)
    BitPaddedInteger.to_str(value, bits:8, width:-1)
  end

  def validate(frame, value)
    value
  end
end

class EncodingSpec < ByteSpec
  def read(frame, data)
    enc, data = super(frame, data)
    if enc < 16
      return enc, data
    else
      return 0, (enc.chr + data)
    end
  end

  def validate(frame, value)
    return nil if value.nil?
    return value if 0 <= value <= 3
    raise ArgumentError, "Invalid Encoding: #{value}"
  end

  def _validate23(frame, value, **kwargs)
    # only 0, 1 are vaid in v2.3, default to utf-16
    [1,value].min
  end
end

class StringSpec < Spec
  def initialize(name, length)
    super(name)
    @len = length
  end

  def read(frame, data)
    return data[0..@len-1], data[@len..-1]
  end

  def write(frame, value)
    if value.nil?
      "\x00" * @len
    else
      (value + "\x00" * @len)[0..@len-1]
    end
  end

  def validate(frame, value)
    if value.nil?
      return nil
    end

    if value.size == @len
      return value
    end
    raise ArgumentError, "Invalid StringSpec[#{@len}] data: #{value}"
  end
end
end

