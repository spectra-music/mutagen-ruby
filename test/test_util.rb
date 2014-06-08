require 'minitest_helper'
require 'pp'

class FakeHash
  include Mutagen::HashMixin
  def initialize; @d = {}; end
  def keys; @d.keys; end
  def [](*args); @d.send(:[],*args); end
  def []=(*args); @d.send(:[]=,*args); end
  def delete(*args); @d.delete(*args); end
  def to_s(*args); @d.to_s(*args); end
  def inspect(*args); @d.inspect(*args); end
end

# The default dictionary doesn't have a set_default,
# so we add the refinement to pass the test
module HashExtended
  refine Hash do
    def set_default(key, default)
      if self[key].nil?
        self[key] = default
      else
        self[key]
      end
    end
  end
end

class TestDictMixin < MiniTest::Test
  using HashExtended
  def setup
    @fdict = FakeHash.new
    @rdict = {}
    @fdict['foo'] = @rdict['foo'] = 'bar'
  end

  def test_getsetitem
    assert @fdict['foo'], 'bar'
    assert_nil @fdict['bar']
  end

  def test_has_key_contains
    assert @fdict.has_key 'foo'
    refute @fdict.has_key 'bar'
  end

  def test_iter
    assert_equal @fdict.map{|i| i}, ['foo']
  end

  def test_clear
    @fdict.clear
    @rdict.clear
    assert @fdict.empty?
  end

  def test_keys
    assert_equal @fdict.keys, @rdict.keys
    fkeys = rkeys = []
    @fdict.each_key{|k| fkeys << k}
    @rdict.each_key{|k| rkeys << k}
    assert_equal fkeys, rkeys
  end

  def test_values
    assert_equal @fdict.values, @rdict.values
    fvals = rvals = []
    @fdict.each_value{|v| fvals << v}
    @rdict.each_value{|v| rvals << v}
    assert_equal fvals, rvals
  end

  def test_items
    assert_equal @fdict.items, @rdict.to_a
    fitems = ritems = []
    @fdict.each_pair{|p| fitems << p}
    @rdict.each_pair{|p| ritems << p}
    assert_equal fitems, ritems
  end

  def test_pop
    assert_equal @fdict.delete('foo'), @rdict.delete('foo')
    assert @fdict.delete('').nil?
  end
  
  def test_pop_item
    key= @rdict.keys.first
    item = [key, @rdict.delete(key)]
    assert_equal @fdict.pop_item, item
    assert_raises(KeyError) {@fdict.pop_item}
  end

  def test_update_other
    other = {"a" => 1, "b" => 2}
    @fdict.update(other)
    @rdict.update(other)
  end

  def test_update_other_is_list
    other = [["a", 1], ["b", 2]]
    @fdict.update(other)
    @rdict.update(Hash[other])
  end

  def test_merge_kwargs
    @fdict.merge!(a:1, b:2)
    other = {a: 1, b: 2}
    @rdict.merge!(other)
    assert_equal @fdict, @rdict
  end

  def test_set_default
    @fdict.set_default('foo', 'baz')
    @rdict.set_default('foo', 'baz')
    @fdict.set_default('bar', 'baz')
    @rdict.set_default('bar', 'baz')
  end

  def test_get
    assert_equal @rdict["a"], @fdict["a"]
    assert_equal @rdict["foo"], @fdict["foo"]
  end

  # def test_repr
  #   assert_equal(repr(@rdict), repr(@fdict))
  # end

  def test_size
    assert_equal @rdict.size, @fdict.size
  end

  def teardown
    assert_equal @fdict, @rdict
    assert_equal @rdict, @fdict
  end
end