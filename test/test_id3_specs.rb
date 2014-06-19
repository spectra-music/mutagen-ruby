require 'test_helper'

class SpecSanityChecks < MiniTest::Test
  include Mutagen::ID3::Specs
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
    assert_equal ['abcdefg', ''], s.read(nil, 'abcdefg')
    assert_equal '', s.write(nil, nil)
    assert_equal '43', s.write(nil, 43)
    assert_equal 'abc', s.write(nil, 'abc')
  end

  def test_encodedtextspec
    s          = EncodedTextSpec.new('name')
    f          = Frame.new
    f.encoding = 0
    assert_equal ['abcd', 'fg'], s.read(f, "abcd\x00fg")
    assert_equal "abcdefg\x00", s.write(f, 'abcdefg')
    assert_raises(NoMethodError) { s.write f, nil }
  end

  def test_timestampspec
    s          = TimeStampSpec.new 'name'
    f          = Frame.new
    f.encoding = 0
    assert_equal [ID3TimeStamp.new('ab'), 'fg'], s.read(f, "ab\x00fg")
    assert_equal [ID3TimeStamp.new('1234'), ''], s.read(f, "1234\x00")
    assert_equal "1234\x00", s.write(f, ID3TimeStamp.new('1234'))
    assert_raises(NoMethodError) { s.write(f, nil) }
    assert_equal ID3TimeStamp.new('2000-01-01').to_s, '2000-01-01'
  end

  def test_volumeadjustmentspec
    s = VolumeAdjustmentSpec.new('gain')
    assert_equal [0.0, ''], s.read(nil, "\x00\x00")
    assert_equal [2.0, ''], s.read(nil, "\x04\x00")
    assert_equal [-2.0, ''], s.read(nil, "\xfc\x00")
    assert_equal "\x00\x00", s.write(nil, 0.0)
    assert_equal "\x04\x00", s.write(nil, 2.0)
    assert_equal "\xFC\x00".b, s.write(nil, -2.0)
  end
end

class SpecValidateChecks < MiniTest::Test
  include Mutagen::ID3::Specs
  def test_volumeadjustmentspec
    s = VolumeAdjustmentSpec.new('gain')
    assert_raises(Mutagen::Util::ValueError) { s.validate(nil, 65) }
  end

  def test_volumepeackspec
    s = VolumePeakSpec.new('peak')
    assert_raises(Mutagen::Util::ValueError) { s.validate(nil, 2) }
  end

  def test_bytespec
    s = ByteSpec.new('byte')
    assert_raises(Mutagen::Util::ValueError) { s.validate(nil, 1000) }
  end
end

class BitPaddedIntegerTest < MiniTest::Test
  include Mutagen
  def test_zero
    assert_equal 0, ID3::BitPaddedInteger.new("\x00\x00\x00\x00")
  end

  def test_1
    assert_equal 1, ID3::BitPaddedInteger.new("\x00\x00\x00\x01")
  end

  def test_1l
    assert_equal 1, ID3::BitPaddedInteger.new("\x01\x00\x00\x00", bigendian:false)
  end

  def test_129
    assert_equal 0x81, ID3::BitPaddedInteger.new("\x00\x00\x01\x01")
  end

  def test_129b
    assert_equal 0x81, ID3::BitPaddedInteger.new("\x00\x00\x01\x81")
  end

  def test_65
    assert_equal 0x41, ID3::BitPaddedInteger.new("\x00\x00\x01\x81", bits:6)
  end

  def test_32b
    assert_equal 0xFFFFFFFF, ID3::BitPaddedInteger.new("\xFF\xFF\xFF\xFF", bits:8)
  end

  def test_32bi
    assert_equal 0xFFFFFFFF, ID3::BitPaddedInteger.new(0xFFFFFFFF, bits:8)
  end

  def test_s32b
    assert_equal "\xFF\xFF\xFF\xFF", ID3::BitPaddedInteger.new("\xFF\xFF\xFF\xFF", bits:8).to_s

  end

  def test_s0
    assert_equal "\x00\x00\x00\x00", ID3::BitPaddedInteger.to_str(0)
  end

  def test_s1
    assert_equal "\x00\x00\x00\x01", ID3::BitPaddedInteger.to_str(1)
  end

  def test_s1l
    assert_equal "\x01\x00\x00\x00", ID3::BitPaddedInteger.to_str(1, bigendian:false)
  end

  def test_s129
    assert_equal "\x00\x00\x01\x01", ID3::BitPaddedInteger.to_str(129)
  end

  def test_s65
    assert_equal "\x00\x00\x01\x01", ID3::BitPaddedInteger.to_str(0x41, bits:6)
  end

  def test_w129
    assert_equal "\x01\x01", ID3::BitPaddedInteger.to_str(129, width:2)
  end

  def test_w129l
    assert_equal "\x01\x01", ID3::BitPaddedInteger.to_str(129, width:2, bigendian:false)
  end

  def test_wsmall
    assert_raises(Mutagen::Util::ValueError) { ID3::BitPaddedInteger.to_str(129, width:1) }
  end

  def test_str_int_init
    assert_equal(ID3::BitPaddedInteger.new(238).to_s,
                 ID3::BitPaddedInteger.new([238].pack('L!>')).to_s)
  end

  def test_varwidth
    assert_equal 4, ID3::BitPaddedInteger.to_str(100).bytesize

    assert_equal 4, ID3::BitPaddedInteger.to_str(100, width:-1).bytesize
    assert_equal 5, ID3::BitPaddedInteger.to_str(2**32, width:-1).bytesize
  end

  def test_minwidth
    assert_equal 6, ID3::BitPaddedInteger.to_str(100, width:-1, minwidth:6).bytesize
  end

  def test_inval_input
    assert_raises(TypeError) { ID3::BitPaddedInteger.new nil }
  end


  def test_has_valid_padding
    assert ID3::BitPaddedInteger.has_valid_padding("\xff\xff", bits:8)
    refute ID3::BitPaddedInteger.has_valid_padding("\xff")
    refute ID3::BitPaddedInteger.has_valid_padding("\x00\xff")
    assert ID3::BitPaddedInteger.has_valid_padding("\x7f\x7f")
    refute ID3::BitPaddedInteger.has_valid_padding("\x7f", bits:6)
    refute ID3::BitPaddedInteger.has_valid_padding("\x9f", bits:6)
    assert ID3::BitPaddedInteger.has_valid_padding("\x3f", bits:6)

    assert ID3::BitPaddedInteger.has_valid_padding(0xff, bits:8)
    refute ID3::BitPaddedInteger.has_valid_padding(0xff)
    refute ID3::BitPaddedInteger.has_valid_padding(0xff << 8)
    assert ID3::BitPaddedInteger.has_valid_padding(0x7f << 8)
    refute ID3::BitPaddedInteger.has_valid_padding(0x9f << 32, bits:6)
    assert ID3::BitPaddedInteger.has_valid_padding(0x3f << 16, bits:6)
  end
end

class TestUnsynch < MiniTest::Test
  def test_unsynch_encode
    un = Mutagen::ID3::Unsynch
    ["\xff\xff\xff\xff", "\xff\xf0\x0f\x00", "\xff\x00\x0f\xf0"].each do |d|
      assert_equal d.b, un.decode(un.encode(d))
      refute_equal d.b, un.encode(d)
    end
    assert_equal "\xff\x44".b, un.encode("\xff\x44")
    assert_equal "\xff\x00\x00".b, un.encode("\xff\x00")
  end

  def test_unsych_decode
    un = Mutagen::ID3::Unsynch
    assert_raises(Mutagen::Util::ValueError) { un.decode "\xff\xff\xff\xff" }
    assert_raises(Mutagen::Util::ValueError) { un.decode "\xff\xf0\x0f\x00" }
    assert_raises(Mutagen::Util::ValueError) { un.decode "\xff\xe0" }
    assert_raises(Mutagen::Util::ValueError) { un.decode "\xff" }
    assert_equal "\xff\x44".b, un.decode("\xff\x44")
  end
end