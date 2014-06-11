require_relative 'test_helper'
include Mutagen


_22 = ID3.new; _22.version = [2,2,0]
_23 = ID3.new; _23.version = [2,3,0]
_24 = ID3.new; _24.version = [2,4,0]

class ID3GetSetDel < MiniTest::Test
  def setup
    @i = ID3.new
    @i['BLAH'] = 1
    @i['QUUX'] = 2
    @i['FOOB:ar'] = 3
    @i['FOOB:az'] = 4
  end

  def test_get_normal
    assert @i.get_all('BLAH'), [1]
    assert @i.get_all('QUUX'), [2]
    assert @i.get_all('FOOB:ar'), [3]
    assert @i.get_all('FOOB:az'), [4]
  end

  def test_get_list
    assert_includes [[3,4],[4,3]], @i.get_all('FOOB')
    assert_equal [3,4].to_set, @i.get_all('FOOB').to_set
  end

  def test_delete_normal
    assert_includes @i, 'BLAH'
    @i.delete_all 'BLAH'
    refute_includes @i, 'BLAH'
  end

  def test_delete_one
    @i.delete_all('FOOB:ar')
    assert_equal [4], @i.get_all('FOOB')
  end

  def test_delete_all
    assert_includes @i, 'FOOB:ar'
    assert_includes @i, 'FOOB:az'
    @i.delete_all 'FOOB'
    refute_includes @i, 'FOOB:ar'
    refute_includes @i, 'FOOB:az'
  end

  class TEST;
    attr_reader :hash_key
    def initialize(k:"FOOB:ar")
      @hash_key = k
    end
  end
  def test_set_one
    t = TEST.new
    @i.set_all('FOOB', [t])
    assert_equal t, @i['FOOB:ar']
    assert_equal [t], @i.get_all('FOOB')
  end

  def test_set_two
    t = TEST.new; t2 = TEST.new(k:'FOOB:az')
    @i.set_all('FOOB', [t, t2])
    assert_equal t, @i['FOOB:ar']
    assert_equal t2, @i['FOOB:az']
    assert_includes [[t,t2],[t2,t]], @i.get_all('FOOB')
    assert_equal [t,t2].to_set, @i.get_all('FOOB').to_set
  end
end

