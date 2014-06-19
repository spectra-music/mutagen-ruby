require_relative 'test_helper'

class FakeHash
  include Mutagen::Util::HashMixin
  def initialize;  @d = {}; end
  def keys; @d.keys; end
  def [](*args); @d.send(:[], *args); end
  def []=(*args); @d.send(:[]=, *args); end
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
    assert @fdict.has_key? 'foo'
    refute @fdict.has_key? 'bar'
  end

  def test_iter
    assert_equal @fdict.map { |i| i }, ['foo']
  end

  def test_clear
    @fdict.clear
    @rdict.clear
    assert @fdict.empty?
  end

  def test_keys
    assert_equal @fdict.keys, @rdict.keys
    fkeys = rkeys = []
    @fdict.each_key { |k| fkeys << k }
    @rdict.each_key { |k| rkeys << k }
    assert_equal fkeys, rkeys
  end

  def test_values
    assert_equal @fdict.values, @rdict.values
    fvals = rvals = []
    @fdict.each_value { |v| fvals << v }
    @rdict.each_value { |v| rvals << v }
    assert_equal fvals, rvals
  end

  def test_items
    assert_equal @fdict.items, @rdict.to_a
    fitems = ritems = []
    @fdict.each_pair { |p| fitems << p }
    @rdict.each_pair { |p| ritems << p }
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
    assert_raises(KeyError) { @fdict.pop_item }
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
    @fdict.merge!(a: 1, b: 2)
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

class TestCData < MiniTest::Test
  ZERO = "\x00\x00\x00\x00"
  LEONE = "\x01\x00\x00\x00"
  BEONE = "\x00\x00\x00\x01"
  NEGONE = "\xff\xff\xff\xff"


  def test_int_le
    assert_equal(Mutagen::Util::CData.int_le(ZERO), 0)
    assert_equal(Mutagen::Util::CData.int_le(LEONE), 1)
    assert_equal(Mutagen::Util::CData.int_le(BEONE), 16777216)
    assert_equal(Mutagen::Util::CData.int_le(NEGONE), -1)
  end

  def test_uint_le
    assert_equal(Mutagen::Util::CData.uint_le(ZERO), 0)
    assert_equal(Mutagen::Util::CData.uint_le(LEONE), 1)
    assert_equal(Mutagen::Util::CData.uint_le(BEONE), 16777216)
    assert_equal(Mutagen::Util::CData.uint_le(NEGONE), 2**32-1)
  end


  def test_longlong_le
    assert_equal(Mutagen::Util::CData.longlong_le(ZERO * 2), 0)
    assert_equal(Mutagen::Util::CData.longlong_le(LEONE + ZERO), 1)
    assert_equal(Mutagen::Util::CData.longlong_le(NEGONE * 2), -1)
  end

  def test_ulonglong_le
    assert_equal(Mutagen::Util::CData.ulonglong_le(ZERO * 2), 0)
    assert_equal(Mutagen::Util::CData.ulonglong_le(LEONE + ZERO), 1)
    assert_equal(Mutagen::Util::CData.ulonglong_le(NEGONE * 2), 2**64-1)
  end

  def test_invalid_lengths
    assert_equal Mutagen::Util::CData.int_le(''), nil
    assert_equal Mutagen::Util::CData.longlong_le(''), nil
    assert_equal Mutagen::Util::CData.uint_le(''), nil
    assert_equal Mutagen::Util::CData.ulonglong_le(''), nil
  end

  def test_test
    assert(Mutagen::Util::CData.test_bit((1), 0))
    refute(Mutagen::Util::CData.test_bit(1, 1))


    assert(Mutagen::Util::CData.test_bit(2, 1))
    refute(Mutagen::Util::CData.test_bit(2, 0))

    v = (1 << 12) + (1 << 5) + 1
    assert(Mutagen::Util::CData.test_bit(v, 0))
    assert(Mutagen::Util::CData.test_bit(v, 5))
    assert(Mutagen::Util::CData.test_bit(v, 12))
    refute(Mutagen::Util::CData.test_bit(v, 3))
    refute(Mutagen::Util::CData.test_bit(v, 8))
    refute(Mutagen::Util::CData.test_bit(v, 13))
  end
end

class TestFileHandling < MiniTest::Test
  def temp_file(contents)
    require 'tempfile'
    temp = Tempfile.new('foo')
    temp.write(contents)
    temp.flush
    temp.rewind
    yield(temp)
    temp.unlink
  end

  def read(fobj)
    fobj.rewind
    fobj.read
  end

  def test_insert_into_empty
    temp_file('') do |f|
      Mutagen::Util::insert_bytes(f, 8, 0)
      assert_equal 8, f.size
      assert_equal "\x00" * 8, read(f)
    end
  end

  def test_insert_before_one
    temp_file('a') do |f|
      Mutagen::Util::insert_bytes f, 8, 0
      assert_equal 9, f.size
      assert_equal 'a' + "\x00" * 7 + 'a', read(f)
    end
  end

  def test_insert_after_one
    temp_file('a') do |f|
      Mutagen::Util::insert_bytes f, 8, 1
      assert_equal 9, f.size
      assert_equal 'a' + "\x00" * 8, read(f)
    end
  end

  def test_smaller_than_file_middle
    temp_file('abcdefghij') do |f|
      before_size = f.size
      Mutagen::Util::insert_bytes f, 4, 4
      assert_equal before_size + 4, f.size
      assert_equal 'abcdefghefghij', read(f)
    end
  end

  def test_smaller_than_file_to_end
    temp_file('abcdefghij') do |f|
      before_size = f.size
      Mutagen::Util::insert_bytes f, 4, 6
      assert_equal before_size + 4, f.size
      assert_equal 'abcdefghijghij', read(f)
    end
  end

  def test_smaller_than_file_across_end
    temp_file('abcdefghij') do |f|
      before_size = f.size
      Mutagen::Util::insert_bytes f, 4, 8
      assert_equal before_size + 4, f.size
      assert_equal "abcdefghij\x00\x00ij", read(f)
    end
  end

  def test_smaller_than_file_at_end
    temp_file('abcdefghij') do |f|
      before_size = f.size
      Mutagen::Util::insert_bytes f, 3, 10
      assert_equal before_size + 3, f.size
      assert_equal "abcdefghij\x00\x00\x00", read(f)
    end
  end

  def test_smaller_than_file_at_beginning
    temp_file('abcdefghij') do |f|
      before_size = f.size
      Mutagen::Util::insert_bytes f, 3, 0
      assert_equal before_size + 3, f.size
      assert_equal 'abcabcdefghij', read(f)
    end
  end

  def test_zero
    temp_file('abcdefghij') do |f|
      assert_raises(ArgumentError) { Mutagen::Util::insert_bytes(f, 0, 1) }
    end
  end

  def test_negative
    temp_file('abcdefghij') do |f|
      assert_raises(ArgumentError) { Mutagen::Util::insert_bytes(f, 8, -1) }
    end
  end

  def test_delete_one
    temp_file('a') do |f|
      Mutagen::Util::delete_bytes f, 1, 0
      assert_equal 0, f.size
      assert_equal '', read(f)
    end
  end

  def test_delete_first_of_two
    temp_file('ab') do |f|
      Mutagen::Util::delete_bytes f, 1, 0
      assert_equal 1, f.size
      assert_equal 'b', read(f)
    end
  end

  def test_delete_second_of_two
    temp_file('ab') do |f|
      Mutagen::Util::delete_bytes f, 1, 1
      assert_equal 1, f.size
      assert_equal 'a', read(f)
    end
  end

  def test_delete_third_of_two
    temp_file('ab') do |f|
      assert_raises(ArgumentError) { Mutagen::Util::delete_bytes f, 1, 2 }
    end
  end

  def test_delete_middle
    temp_file('abcdefg') do |f|
      before_size = f.size
      Mutagen::Util::delete_bytes f, 3, 2
      assert_equal before_size - 3, f.size
      assert_equal 'abfg', read(f)
    end
  end

  def test_delete_across_end
    temp_file('abcdefg') do |f|
      assert_raises(ArgumentError) { Mutagen::Util::delete_bytes f, 4, 8 }
    end
  end

  def test_delete_zero
    temp_file('abcdefg') do |f|
      assert_raises(ArgumentError) { Mutagen::Util::delete_bytes f, 4, 8 }
    end
  end

  def test_many_changes(num_runs=5, num_changes=300,
      min_change_size=500, max_change_size=1000)
    assert((min_change_size < max_change_size), 'Given testing parameters make this test useless')

    data = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" * 1024
    num_runs.times do
      filesize = data.size
      temp_file(data) do |f|
        changes = []
        num_changes.times do
          change_size = rand(min_change_size..max_change_size)
          change_offset = rand(0..filesize)
          filesize += change_size
          changes << [change_offset, change_size]
        end

        changes.each do |offset, size|
          Mutagen::Util::insert_bytes(f, size, offset)
        end
        f.rewind
        refute_equal f.read(data.size), data
        f.seek(0, IO::SEEK_END)
        assert_equal f.pos, filesize

        changes.reverse.each do |offset, size|
          Mutagen::Util::delete_bytes(f, size, offset)
        end
        f.rewind
        assert_equal(f.read, data)
      end
    end
  end
end