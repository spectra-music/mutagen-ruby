module Mutagen
# Utility class for Mutagen
# You should not rely on the interfaces here being stable.
# They are intended for internal use in Mutagen only


# total_ordering is not implemented here as it
# is basically a version of Ruby's <=> operator and Enumerable mixin


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

  def each(&block)
    keys.each(&block)
  end

  def has_key(key)
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

    return false unless other.size == size

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

  def size
    keys.size
  end
end


end # Mutagen module