module Mutagen
# Utility class for Mutagen
# You should not rely on the interfaces here being stable.
# They are intended for internal use in Mutagen only


# total_ordering is not implemented here as it
# is basically a version of Ruby's <=> operator and Comparable mixin


  # Generic error class
  class ValueError < StandardError; end


# Implement the dict API using keys() and __*item__ methods.
#
# Similar to UserDict.DictMixin, this takes a class that defines
# [], []=, delete, and keys, and turns it
# into a full dict-like object.
#
# UserDict.DictMixin is not suitable for this purpose because it's
# an old-style class.
#
# This class is not optimized for very large dictionaries; many
# functions have linear memory requirements. I recommend you
# override some of these functions if speed is required.
module HashMixin
  include Enumerable

  # TODO: Switch this to iterating over items
  def each(&block)
    keys.each(&block)
  end

  def has_key?(key)
    not self[key].nil?
  end

  def each_key(&block)
    keys.each(&block)
  end

  def values
    keys.map { |k| self[k] }
  end

  def each_value(&block)
    values.each(&block)
  end

  def items
    keys.zip(values).to_a
  end

  alias_method :to_a, :items

  def to_hash
    Hash[items]
  end

  def each_item(&block)
    items.each(&block)
  end

  alias_method :each_pair, :each_item

  def empty?
    keys.empty?
  end

  def clear
    keys.to_a.each { |k| delete k }
  end

  def fetch(key, default=nil)
    if default.nil?
      raise KeyError, "No such key in Hash" unless has_key? key
    else
      return default
    end
    self[key]
  end

  def delete_item(key)
    if keys.empty?
      raise KeyError, 'dictionary is empty'
    end
    [key, delete(key)]
  end

  def pop_item
    if keys.empty?
      raise KeyError, 'dictionary is empty'
    end
    key = keys.first
    [key, delete(key)]
  end

  # Based on the RBX and YARV implementations
  def merge!(other, **kwargs)
    if other.nil?
      merge!(kwargs)
      other = {}
    end

    case other
      when Hash
        other
      else begin
        other = Hash[other]
      end
    end

    if block_given?
      other.each_pair do |key, value|
        self[key] = yield(key, self[key], value)
      end
    else
      other.each_pair do |key, value|
        self[key] = value
      end
    end
    self
  end

  alias_method :update, :merge!

  def merge(other, &block)
    self.dup.merge!(other, &block)
  end


  def set_default(key, default)
    if self[key].nil?
      self[key] = default
    else
      self[key]
    end
  end

  # def inspect
  #   Hash[items].inspect
  # end

  # Based on the RBX implementation
  def ==(other)
    return true if self.equal? other

    unless other.kind_of? Hash
      return false unless other.respond_to? :to_hash
      return other == self
    end

    return false unless other.length == length

    each_pair do |key, value|
      # Other doesn't even have this key
      return false unless other.has_key? key
      other_value = other[key]

      # Order of the comparison matters! We must compare our value with
      # the other Hash's value and not the other way around.
      unless value == other_value
        return false
      end
    end
    true
  end

  def <=>(other)
    unless other.kind_of? Hash
      return false unless other.respond_to? :to_a
    end
    other_items = other.to_a
    items <=> other_items
  end

  def length
    keys.length
  end

  alias_method :size, :length
end

module DictProxy
  include HashMixin
  def [](key)
    @dict[key]
  end

  def []=(key, value)
    @dict[key] = value
  end

  def delete(key)
    @dict.delete(key)
  end

  def keys
    @dict.keys
  end
end


# C character buffer to Ruby numeric type conversions
module CData
  # Convert from
  def self.short_le(data); data.unpack('s<')[0]; end
  def self.ushort_le(data); data.unpack('S<')[0]; end

  def self.short_be(data); data.unpack('s>')[0]; end
  def self.ushort_be(data); data.unpack('S>')[0]; end

  def self.int_le(data); data.unpack('i<')[0]; end
  def self.uint_le(data); data.unpack('I<')[0]; end

  def self.int_be(data); data.unpack('i>')[0]; end
  def self.uint_be(data); data.unpack('I>')[0]; end

  def self.longlong_le(data); data.unpack('q<')[0]; end
  def self.ulonglong_le(data); data.unpack('Q<')[0]; end

  def self.longlong_be(data); data.unpack('q>')[0]; end
  def self.ulonglong_be(data); data.unpack('Q>')[0]; end

  # Convert to
  def self.to_short_le(data); [data].unpack('s<'); end
  def self.to_ushort_le(data); [data].unpack('S<'); end

  def self.to_short_be(data); [data].unpack('s>'); end
  def self.to_ushort_be(data); [data].unpack('S>'); end

  def self.to_int_le(data); [data].unpack('i<'); end
  def self.to_uint_le(data); [data].unpack('I<'); end

  def self.to_int_be(data); [data].unpack('i>'); end
  def self.to_uint_be(data); [data].unpack('I>'); end

  def self.to_longlong_le(data); [data].unpack('q<'); end
  def self.to_ulonglong_le(data); [data].unpack('Q<'); end

  def self.to_longlong_be(data); [data].unpack('q>'); end
  def self.to_ulonglong_be(data); [data].unpack('Q>'); end

  BITSWAP = (0..255).map { |val| (0..7).map { |i| (((val >> i) & 1) << (7-i)) }.inject(:+).chr }.join

  def self.test_bit(value, n); ((value >> n) & 1) == 1; end
end

# Mutagen.lock and Mutagen.unlock are replaced with the Filelock gem

# Insert empty space into a file starting at (offset from end).
# fileobj must be an open file object, open rb+ or equivalent.
# @param fileobj [File] the file to insert into
# @param size [Fixnum] the number of bytes to insert
# @param offset [Fixnum] the offset from the beginning of the file to begin insertion at
def self.insert_bytes(fileobj, size, offset)
  raise ArgumentError, 'size cannot be less than 1' unless size > 0
  raise ArgumentError, 'offset cannot be less than 0' unless offset >= 0

  move_size = fileobj.size - offset   # the size of the block to move
  # If we want to add more bytes than the file has,
  # we need to append some to the file
  if size > fileobj.size or offset == fileobj.size
    append_size = size
    append_size -= fileobj.size if offset != fileobj.size
    # Append directly to the end of the file
    IO.write(fileobj.path, "\x00" * append_size, fileobj.size)
  end

  move_location =  offset + size      # the location the block will go
  # if we need to move the byte array,
  if move_size > 0
    IO.write(fileobj.path, IO.read(fileobj.path, move_size, offset), move_location)
  end
end

# Delete bytes from a file starting at offset
# @param fileobj [File] the file to delete from
# @param size [Fixnum] the number of bytes to delete
# @param offset [Fixnum] the offset from the beginning of the file to begin deletion at
def self.delete_bytes(fileobj, size, offset)
  raise ArgumentError, 'size cannot be less than 1' unless size > 0
  raise ArgumentError, 'offset cannot be less than 0' unless offset >= 0

  filesize = fileobj.size
  move_size = filesize - offset - size
  raise ArgumentError, "can't move less than 0 bytes" unless move_size >= 0

  if move_size > 0
    IO.write(fileobj.path, IO.read(fileobj.path, move_size, offset + size), offset)
  end
  fileobj.truncate(filesize - size)
end

def self.strip_arbitrary(s, chars)
    r = chars.chars.map { |c| Regexp.quote(c) }.join
    s.gsub(/(^[#{r}]*)|([#{r}]*$)/, '')
end

end # Mutagen module