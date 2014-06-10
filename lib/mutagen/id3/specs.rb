require 'mutagen/id3/util'
module Mutagen::ID3
class Spec
  attr_reader :name
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
    raise Mutagen::ValueError, "Invalid Encoding: #{value}"
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
    return data[0...@len], data[@len..-1]
  end

  def write(frame, value)
    if value.nil?
      "\x00" * @len
    else
      (value + "\x00" * @len)[0...@len]
    end
  end

  def validate(frame, value)
    if value.nil?
      return nil
    end

    unless value.is_a? Array
      value.to_s.encode 'ascii'
    end

    if value.size == @len
      return value
    end
    raise Mutagen::ValueError, "Invalid StringSpec[#{@len}] data: #{value}"
  end
end

class BinaryDataSpec < Spec
  def read(frame, data)
    return data, ''
  end

  def write(frame, value)
    if value.nil?
      ''
    elsif value.is_a? Array
      value
    else
      value.to_s.encode('ascii')
    end
  end

  def validate(frame,value)
    value.is_a?(Array) ? value : value.encode('ascii')
  end
end

class EncodedTextSpec < Spec
  # Okay, seriously. This is private and defined explicitly and
  # completely by the ID3 specification. You can't just add
  # encodings here however you want.

  def initialize(*args)
    @encodings = [
        ['ISO-8859-1', "\x00"], # aka Latin-1
        ['UTF-16', "\x00\x00"],
        ['UTF-16BE', "\x00\x00"],
        ['UTF-8', "\x00"]
    ]
    super(args)
  end

  def read(frame, data)
    enc, term = @encodings[frame.encoding]
    ret = ''
    if term.size == 1
      if data.include? term
        data, ret = data.split(term, 2)
      end
    else
      offset = -1
      begin
        while true
          offset = data.index(term, offset+1)
          next if offset & 1
          data, ret = data[0...offset], data[offset+2..-1]
          break
        end
      rescue ValueError
        # ignored
      end
    end
    if data.size < term.size
      return '', ret
    else
      return data.encode, ret
    end
  end

  # @raise [NoMethodError] if value doesn't have `.encode`
  def write(frame, value)
    enc, term = @encodings[frame.encoding]
    value.encode(enc) + term
  end

  def validate(frame, value)
    value.to_s
  end
end

class MultiSpec < Spec
  def initialize(name, *specs, **kwargs)
    super(name)
    @specs = specs
    @sep = kwargs[:sep]
  end

  def read(frame, data)
    values = []
    until data.empty?
      record = @specs.map do |spec|
        value, data = spec.read(frame, data)
        value
      end
      if @specs.size != 1
        values << record
      else
        values << record[0]
      end
    end
    return values, data
  end

  def write(frame, value)
    data = []
    if @specs.size == 1
      value.each do |v|
        data << @specs[0].write(frame, v)
      end
    else
      value.each do |record|
        record.zip(@specs).each do |v, s|
          data << s.write(frame, v)
        end
      end
    end
    data.join
  end

  def validate(frame, value)
    return [] if value.nil?

    if not @sep.nil? and value.is_a? String
      value = value.split(@sep)
    end

    if value.is_a? Array
      if @specs.size == 1
        return value.map { |v| @specs[0].validate(frame, v) }
      else
        return value.map { |val| val.zip(@specs).map { |v, s| s.validate(frame, v) } }
      end
    end
  end

  def _validate23(frame, value, **kwargs)
    if @specs.size != 1
      return value.map { |val| val.zip(@specs).map { |v,s| s._validate23(frame, v, **kwargs) } }
    end

    spec = @specs[0]

    # Merge single txt spec multispecs only
    # (TimeStampSpec) being the exception, but it's not a valid v2.3 frame
    if not spec.is_a? EncodedTextSpec or spec.is_a? TimeStampSpec
      return value
    end

    value = value.map { |v| spec._validate23(frame, v, **kwargs) }
    if kwargs.has_key? :sep
      return [spec.validate(frame, kwargs[:sep].join(value))]
    end
    value
  end
end

class EncodedNumericTextSpec < EncodedTextSpec; end
class EncodedNumericPartTextSpec < EncodedTextSpec; end

# Latin1 is known as "ISO-8859-1" in Ruby
class Latin1TextSpec < EncodedTextSpec
  def read(frame, data)
    if data.include? "\x00"
      data, ret = data.split("\x00", 2)
    else
      ret = ''
    end
    return data.encode, ret
  end

  def write(data, value)
    value.encode('ISO-8859-1') + "\x00"
  end

  def validate(frame, value)
    value.to_s
  end
end


# A time stamp in ID3v2 format.
#
# This is a restricted form of the ISO 8601 standard; time stamps
# take the form of:
#     YYYY-MM-DD HH:MM:SS
# Or some partial form (YYYY-MM-DD HH, YYYY, etc.).
#
# The '@text' ivar contains the raw text data of the time stamp.
class ID3TimeStamp
  include Comparable

  def initialize(text)
    if text.is_a? ID3TimeStamp
      text = text.text
    elsif not text.is_a? String
      raise TypeError, "text is not a String: #{text}"
    end
    self.text = text
  end

  def formats
    ['%04d'] + ['%02d'] * 5
  end

  def seps
    ['-', '-', ' ', ':', ':', 'x']
  end

  def text
    parts = [@year, @month, @day, @hour, @minute, @second]
    pieces = []
    parts.each_with_index do |part, i|
      break if part.nil?
      pieces << formats[i] % part + seps[i]
    end
    pieces.join[0...-1] unless pieces.nil?
  end


  def text=(text, splitre=/[-T:\/.]|\s+/)
    year, month, day, hour, minute, second =
        (text + ":::::").split(splitre)[0...6]
    [:year, :month, :day, :hour, :minute, :second].each do |a|
      v = if binding.local_variable_defined?(a) and binding.local_variable_get(a) =~ /^\d+$/
              Integer(binding.local_variable_get(a))
          end
      instance_variable_set("@#{a.to_s}", v)
    end
  end

  alias_method :to_s, :text

  def ==(other)
    text == other.text
  end

  def <=>(other)
    return nil unless other.is_a? ID3TimeStamp
    text <=> other.text
  end

  def encode!(*args)
    self.text = text.encode(*args)
  end

  def encode(*args)
    text.encode(*args)
  end
end


class TimeStampSpec < EncodedTextSpec
  def read(frame, data)
    value, data = super(frame, data)
    return validate(frame, value), data
  end

  def write(frame, data)
    super frame, data.text.sub(' ', 'T')
  end

  def validate(frame, value)
    begin
      return ID3TimeStamp.new(value)
    rescue TypeError
      raise ValueError, "Invalid ID3TimeStamp: #{value}"
    end
  end
end
end

