require 'minitest_helper'
include Mutagen::ID3

class SpecSanityChecks < MiniTest::Test

  def test_bytespec
    s = ByteSpec.new('name')
    assert_equal [97, 'bcdefg'], s.read(nil, 'abcdefg')
    assert_equal 'a', s.write(nil, 97)
    assert_raises(TypeError) { s.write(nil, 'abc') }
    assert_raises(TypeError) { s.write nil, nil }
  end

  def test_encodingspec
    s = EncodingSpec.new('name')
    assert_equal [0, 'abcdefg'], s.read(nil, 'abcdefg')
    assert_equal [3, 'abcdefg'], s.read(nil, "\x03abcdefg")
    assert_equal "\x00", s.write(nil, 0)
    assert_raises(TypeError) { s.write(nil, 'abc') }
    assert_raises(TypeError) { s.write(nil, 'a') }
  end
end