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

  def test_stringspec
    s = StringSpec.new('name', 3)
    assert_equal ['abc', 'defg'], s.read(nil, 'abcdefg')
    assert_equal 'abc', s.write(nil, 'abcdefg')
    assert_equal "\x00\x00\x00", s.write(nil, nil)
    assert_equal "\x00\x00\x00", s.write(nil, "\x00")
    assert_equal "a\x00\x00", s.write(nil, "a")
  end

  def test_binarydataspec
    s = BinaryDataSpec.new('nam')
    assert_equal ['abcdefg',''], s.read(nil, 'abcdefg')
    assert_equal '', s.write(nil, nil)
    assert_equal '43', s.write(nil, 43)
    assert_equal 'abc', s.write(nil, 'abc')
  end

  def test_encodedtextspec
    s = EncodedTextSpec.new('name')
    f = Frame.new
    f.encoding = 0
    assert_equal ['abcd', 'fg'], s.read(f, "abcd\x00fg")
    assert_equal "abcdefg\x00", s.write(f, 'abcdefg')
    assert_raises(NoMethodError) { s.write f, nil }
  end

  def test_timestampspec
    s = TimeStampSpec.new 'name'
    f = Frame.new
    f.encoding = 0
    assert_equal [ID3TimeStamp.new('ab'), 'fg'], s.read(f, "ab\x00fg")
    assert_equal [ID3TimeStamp.new('1234'), ''], s.read(f, "1234\x00")
    assert_equal "1234\x00", s.write(f, ID3TimeStamp.new('1234'))
    assert_raises(NoMethodError) { s.write(f, nil) }
    assert_equal ID3TimeStamp.new('2000-01-01').to_s, '2000-01-01'
  end
end