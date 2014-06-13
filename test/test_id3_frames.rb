require_relative 'test_helper'
include Mutagen::ID3::ParentFrames
include Mutagen::ID3::Frames
include Mutagen::ID3::Frames_2_2

class ParentFrameSanityChecks < MiniTest::Test
  def test_text_frame
     assert_kind_of TextFrame, TextFrame.new(text:'text')
  end

  def test_url_frame
    assert_kind_of UrlFrame, UrlFrame.new('url')
  end

  def test_numeric_text_frame
    assert_kind_of NumericTextFrame, NumericTextFrame.new(text:'1')
  end

  def test_numeric_part_text_frame
    assert_kind_of NumericPartTextFrame, NumericPartTextFrame.new(text:'1/2')
  end

  def test_multi_text_frame
    assert_kind_of TextFrame, TextFrame.new(text: %w(a b))
  end
end

class FrameSanityChecker < MiniTest::Test
  def test_WXXX
    assert_kind_of WXXX, WXXX.new(url:'durl')
  end

  def test_TXXX
    assert_kind_of TXXX, TXXX.new(desc:'d', text:'text')
  end

  def test_22_uses_direct_ints
    data = "TT1\x00\x00\x83\x00".b + ('123456789abcdef' * 16)
    tag = begin
      frame = nil
      ID3_22.read_frames(data, Mutagen::ID3::Frames_2_2) {|f| frame = f; break }
      frame
    end
    assert_equal data[7...7+0x82], tag.text[0]
  end

  def test_frame_too_small
    data = []; ID3_24.read_frames('012345678', Mutagen::ID3::Frames) {|f| data << f }
    assert_equal [], data
    data = []; ID3_23.read_frames('012345678', Mutagen::ID3::Frames) {|f| data << f }
    assert_equal [], data
    data = []; ID3_22.read_frames('01234', Mutagen::ID3::Frames_2_2) {|f| data << f }
    assert_equal [], data
    data = []; ID3_22.read_frames('TT1'+"\x00"*3, Mutagen::ID3::Frames_2_2) {|f| data << f }
    assert_equal [], data
  end

  def test_unknown_22_frame
    data = "XYZ\x00\x00\x01\x00".b
    frame = begin
      box = []
      ID3_22.read_frames(data, nil) {|f| box << f; break }
      box
    end
    assert_equal [data], frame
  end

  def test_zlib_latin1
    tag = TPE1.from_data(ID3_24, 0x9, "\x00\x00\x00\x0fx\x9cc(\xc9\xc8,V\x00\xa2D\xfd\x92\xd4\xe2\x12\x00&\x7f\x05%")
    assert_equal 0, tag.encoding
    assert_equal ['this is a/test'], tag.to_a
  end

  def test_data_size_but_not_compressed
    tag = TPE1.from_data(ID3_24, 0x01, "\x00\x00\x00\x06\x00A test")
    assert_equal 0, tag.encoding
    assert_equal ['A test'], tag.to_a
  end

  def test_utf8
    tag = TPE1.from_data(ID3_23, 0x00, "\x03this is a test")
    assert_equal 3, tag.encoding
    assert_equal 'this is a test', tag.to_s
  end

  def test_zlib_utf16
    data =  "\x00\x00\x00\x1fx\x9cc\xfc\xff\xaf\x84!\x83!\x93\xa1\x98A\x01J&2\xe83\x940\xa4\x02\xd9%\x0c\x00\x87\xc6\x07#".b
    tag = TPE1.from_data(ID3_23, 0x80, data)
    assert_equal 1, tag.encoding
    assert_equal 'this is a/test', tag.to_a.first.encode('UTF-8')

    tag = TPE1.from_data(ID3_24, 0x08, data)
    assert_equal 1, tag.encoding
    assert_equal 'this is a/test', tag.to_a.first.encode('UTF-8')
  end


  def test_load_write
    artists = ["\xc2\xb5", "\xe6\x97\xa5\xe6\x9c\xac"].map {|s| s.force_encoding 'UTF-8' }
    artist = TPE1.new encoding:3, text:artists
    id3 = ID3Data.new
    tag = nil
    id3.read_frames(id3.save_frame(artist), Mutagen::ID3::Frames) {|f| tag = f; break }
    assert_equal 'TPE1', tag.class.name.split('::').last
    assert_equal artist.text, tag.text
  end

  def test_22_to_24
    id3 = ID3Data.new
    tt1 = TT1.new encoding:0, text:'whatcha staring at'
    id3.add(tt1)
    tit1 = id3['TIT1']

    assert_equal tt1.encoding, tit1.encoding
    assert_equal tt1.instance_variable_get(:@text), tit1.text
    refute_includes id3, 'TT1'
  end

  def test_single_TXYZ
    assert_equal TIT2.new(text:'a').hash_key, TIT2.new(text:'b').hash_key
  end

  def test_multi_TXXX
    assert_equal TXXX.new(text:'a').hash_key, TXXX.new(text:'b').hash_key
    refute_equal TXXX.new(desc:'a').hash_key, TXXX.new(desc:'b').hash_key
  end

  def test_multi_WXXX
    assert_equal WXXX.new(text:'a').hash_key, WXXX.new(text:'b').hash_key
    refute_equal WXXX.new(desc:'a').hash_key, WXXX.new(desc:'b').hash_key
  end

  def test_multi_COMM
    assert_equal COMM.new(text:'a').hash_key, COMM.new(text:'b').hash_key
    refute_equal COMM.new(desc:'a').hash_key, COMM.new(desc:'b').hash_key
    refute_equal COMM.new(lang:'abc').hash_key, COMM.new(lang:'def').hash_key
  end

  def test_multi_RVA2
    assert_equal RVA2.new(gain:1).hash_key, RVA2.new(gain:2).hash_key
    refute_equal RVA2.new(desc:'a').hash_key, RVA2.new(desc:'b').hash_key
  end

  def test_multi_APIC
    assert_equal APIC.new(data: '1').hash_key, APIC.new(data: '2').hash_key
    refute_equal APIC.new(desc:'a').hash_key, APIC.new(desc:'b').hash_key
  end

  def test_multi_POPM
    assert_equal POPM.new(count:1).hash_key, POPM.new(count:2).hash_key
    refute_equal POPM.new(email:'a').hash_key, POPM.new(email:'b').hash_key
  end

  def test_multi_GEOB
    assert_equal GEOB.new(data: '1').hash_key, GEOB.new(data: '2').hash_key
    refute_equal GEOB.new(desc:'a').hash_key, GEOB.new(desc:'b').hash_key
  end

  def test_multi_UFID
    assert_equal UFID.new(data: '1').hash_key, UFID.new(data: '2').hash_key
    refute_equal UFID.new(owner:'a').hash_key, UFID.new(owner:'b').hash_key
  end

  def test_multi_USER
    assert_equal USER.new(text:'a').hash_key, USER.new(text:'b').hash_key
    refute_equal USER.new(lang:'abc').hash_key, USER.new(lang:'def').hash_key
  end
end

class TestTextFrame < MiniTest::Test
  def test_list_iface
    frame = TextFrame.new
    frame << 'a'
    frame.push *%w(b c)
    assert_equal %w(a b c), frame.text
  end

  def test_list_iter
    frame = TextFrame.new
    frame.push *%w(a b c)
    assert_equal %w(a b c), frame.map {|c| c}
  end
end

class TestGenres < MiniTest::Test
  TCON = TCON
  GENRES = Mutagen::Constants::GENRES

  def _g(s)
    TCON.new(text:s).genres
  end

  def test_empty
    assert_equal [], _g('')
  end

  def test_num
    GENRES.each_with_index do |genre, i|
      assert_equal [genre], _g('%02d' % i)
    end
  end

  def test_parened_num
    GENRES.each_with_index do |genre, i|
      assert_equal [genre], _g('(%02d)' % i)
    end
  end

  def test_unknwon
    assert_equal ['Unknown'], _g('(255)')
    assert_equal ['Unknown'], _g('199')
    refute_equal ['Unknown'], _g('256')
  end

  def test_parened_multi
    assert_equal ['Blues', 'Country'], _g('(00)(02)')
  end

  def test_cover_remix
    assert_equal ['Cover'], _g('CR')
    assert_equal ['Cover'], _g('(CR)')
    assert_equal ['Remix'], _g('RX')
    assert_equal ['Remix'], _g('(RX)')
  end

  def test_parened_text
    assert_equal ['Blues', 'Country', 'Real Folk Blues'], _g('(00)(02)Real Folk Blues')
  end

  def test_escape
    assert_equal ['Blues', '(A genre)'], _g('(0)((A genre)')
    assert_equal ['New Age', '(20)'], _g('(10)((20)')
  end

  def test_null_sep
    assert_equal ['Blues', 'A genre'], _g("0\x00A genre")
  end

  def test_null_sep_empty
    assert_equal ['Blues', 'A genre'], _g("\x000\x00A genre")
  end

  def test_crazy
    assert_equal %w(Alternative Cover Fusion Another Techno-Industrial Hooray), _g("(20)(CR)\x0030\x00\x00Another\x00(51)Hooray")
  end

  def test_repeat
    assert_equal ['Alternative'], _g('(20)Alternative')
    assert_equal %w(Alternative Alternative), _g("(20)\x00Alternative")
  end

  def test_set_genre
    gen = TCON.new encoding:0, text:''
    assert_equal [], gen.genres
    gen.genres = ['a genre', 'another']
    assert_equal ['a genre', 'another'], gen.genres
  end

  def test_set_string
    gen = TCON.new encoding:0, text:''
    gen.genres = 'foo'
    assert_equal ['foo'], gen.genres
  end

  def test_no_double_decode
    gen = TCON.new encoding:1, text: '(255)genre'
    gen.genres = gen.genres
    assert_equal %w(Unknown genre), gen.genres
  end
end

class TestTimeStamp < Minitest::Test
  Stamp = Mutagen::ID3::Specs::ID3TimeStamp

  def test_Y
    s = Stamp.new '1234'
    assert_equal 1234, s.year
    assert_equal '1234', s.text
  end

  def test_yM
    s = Stamp.new '1234-56'
    assert_equal 1234, s.year
    assert_equal 56, s.month
    assert_equal '1234-56', s.text
  end

  def test_ymD
    s = Stamp.new '1234-56-78'
    assert_equal 1234, s.year
    assert_equal 56, s.month
    assert_equal 78, s.day
    assert_equal '1234-56-78', s.text
  end

  def test_ymdH
    s = Stamp.new '1234-56-78T12'
    assert_equal 1234, s.year
    assert_equal 56, s.month
    assert_equal 78, s.day
    assert_equal 12, s.hour
    assert_equal '1234-56-78 12', s.text
  end

  def test_ymdhM
    s = Stamp.new '1234-56-78T12:34'
    assert_equal 1234, s.year
    assert_equal 56, s.month
    assert_equal 78, s.day
    assert_equal 12, s.hour
    assert_equal 34, s.minute
    assert_equal '1234-56-78 12:34', s.text
  end

  def test_ymdhmS
    s = Stamp.new '1234-56-78T12:34:56'
    assert_equal 1234, s.year
    assert_equal 56, s.month
    assert_equal 78, s.day
    assert_equal 12, s.hour
    assert_equal 34, s.minute
    assert_equal 56, s.second
    assert_equal '1234-56-78 12:34:56', s.text
  end

  def test_Ymdhms
    s = Stamp.new '1234-56-78T12:34:56'
    s.month = nil
    assert_equal '1234', s.text
  end

  def test_alternate_reprs
    s = Stamp.new '1234-56.78 12:34:56'
    assert_equal s.text, '1234-56-78 12:34:56'
  end

  def test_order
    s = Stamp.new '1234'
    t = Stamp.new '1233-12'
    u = Stamp.new '1234-01'
    assert t < s and s < u
    assert u > s and s > t
  end
end

class NoHashFrame < MiniTest::Test
  def test_frame
    assert_raises(TypeError) { {}[TIT1.new(encoding:0, text: 'foo')] = nil }
  end
end

class FrameIDValidate < MiniTest::Test
  def test_valid
    assert Mutagen::ID3::is_valid_frame_id 'APIC'
    assert Mutagen::ID3::is_valid_frame_id 'TPE2'
  end

  def test_invalid
    refute Mutagen::ID3::is_valid_frame_id 'MP3e'
    refute Mutagen::ID3::is_valid_frame_id '+ABC'
  end
end

class TestTimeStampTextFrame < MiniTest::Test
  def test_compare_to_unicode
    frame = TimeStampTextFrame.new encoding:0, text: %w(1987 1988)
    assert_equal frame, frame.to_s
  end
end

class TestRVA2 < MiniTest::Test
  def test_basic
    r = RVA2.new gain:1, channel:1, peak:1
    assert_equal r, r
    refute_equal r, 42
  end
end