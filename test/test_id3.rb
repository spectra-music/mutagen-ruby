require_relative 'test_helper'
include Mutagen::ID3

ID3_22 = ID3Data.new; ID3_22.instance_variable_set('@version', ID3Data::V22)
ID3_23 = ID3Data.new; ID3_23.instance_variable_set('@version', ID3Data::V23)
ID3_24 = ID3Data.new; ID3_24.instance_variable_set('@version', ID3Data::V24)

class ID3GetSetDel < MiniTest::Test
  def setup
    @i = ID3Data.new
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
    def initialize(k: 'FOOB:ar')
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

class ID3Loading < MiniTest::Test
  EMPTY = File.expand_path('../data/emptyfile.mp3', __FILE__)
  SILENCE = File.expand_path('../data/silence-44-s.mp3', __FILE__)
  UNSYNC = File.expand_path('../data/id3v23_unsynch.id3', __FILE__)

  def test_empty_file
    # assert_raises(Mutagen::Mutagen::ValueError) { ID3.new(filename:name) }
    assert_raises(Mutagen::ID3::ID3NoHeaderError) { ID3Data.new(filename:EMPTY) }
    #from_name = ID3(name)
    #obj = open(name, 'rb')
    #from_obj = ID3(fileobj=obj)
    #self.assertEquals(from_name, from_explicit_name)
    #self.assertEquals(from_name, from_obj)
  end

  def test_nonexistant_file
    name = File.expand_path('../data/does/not/exist')
    assert_raises(Errno::ENOENT) { ID3Data.new(name) }
  end

  def test_header_empty
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', File.open(EMPTY, 'r'))
    assert_raises(EOFError) { id3.send(:load_header)}
  end


  def test_header_silence
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', File.open(SILENCE, 'r'))
    id3.send(:load_header)
    assert_equal ID3Data::V23, id3.version
    assert_equal 1314, id3.size
  end

  def test_header_2_4_invalid_flags
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x1f\x00\x00\x00\x00"))
    exception = assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0x1f', exception.message
  end

  def test_header_2_4_unsynch_flags
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x10\x00\x00\x00\xFF"))
    exception = assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
    assert_equal 'Header size not synchsafe', exception.message
  end

  def test_header_2_4_allow_footer
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x10\x00\x00\x00\x00"))
    id3.send(:load_header)
  end

  def test_header_2_3_invalid_flags
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x1f\x00\x00\x00\x00"))
    ex = assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0x1f', ex.message
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x0f\x00\x00\x00\x00"))
    ex = assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0xf', ex.message
  end

  def test_header_2_2
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x02\x00\x00\x00\x00\x00\x00"))
    id3.send :load_header
    assert_equal ID3Data::V22, id3.version
  end

  def test_header_2_1
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x01\x00\x00\x00\x00\x00\x00"))
    assert_raises(ID3Data::ID3UnsupportedVersionError) { id3.send :load_header }
  end

  def test_header_too_small
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x01\x00\x00\x00\x00\x00"))
    assert_raises(EOFError) { id3.send(:load_header) }
  end

  def test_header_2_4_extended
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00\x00\x00\x00\x05\x5a"))
    id3.send(:load_header)
    assert_equal 1, id3.instance_variable_get('@extsize')
    assert_equal "\x5a", id3.instance_variable_get('@extdata')
  end

  def test_header_2_4_extended_unsynch_size
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00\x00\x00\x00\xFF\x5a"))
    assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
  end

  def test_header_2_4_extended_but_not
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00TIT1\x00\x00\x00\x01a"))
    id3.send :load_header
    assert_equal 0, id3.instance_variable_get('@extsize')
    assert_equal '', id3.instance_variable_get('@extdata')
  end

  def test_header_2_4_extended_but_not_but_not_tag
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00TIT9"))
    assert_raises(EOFError) { id3.send :load_header }
  end

  def test_header_2_3_extended
    id3 = ID3Data.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x40\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x56\x78\x9a\xbc"))
    id3.send(:load_header)
    assert_equal 6, id3.instance_variable_get('@extsize')
    assert_equal "\x00\x00\x56\x78\x9a\xbc".b, id3.instance_variable_get('@extdata')
  end

  def test_unsynch
    id3 = ID3Data.new
    id3.instance_variable_set('@version', ID3Data::V24)
    id3.instance_variable_set('@flags', 0x80)
    badsync = "\x00\xff\x00ab\x00".b
    assert_equal "\xffab".force_encoding('ISO-8859-1').encode('utf-8'), id3.send(:load_framedata,
                                      ID3Data::Frames.const_get(:TPE2),
                                      0, badsync).to_a.first

    id3.instance_variable_set('@flags', 0x00)
    assert_equal "\xffab".force_encoding('ISO-8859-1').encode('utf-8'), id3.send(:load_framedata,
                                      ID3Data::Frames.const_get(:TPE2),
                                      0x02, badsync).to_a.first
    assert_equal ["\xff", 'ab'].map{|e| e.force_encoding('ISO-8859-1').encode('utf-8')}, id3.send(:load_framedata,
                                              ID3Data::Frames.const_get(:TPE2),
                                              0, badsync).to_a
  end

  def test_load_v23_unsynch
    id3 = ID3Data.new UNSYNC
    tag = id3['TPE1'].instance_variable_get('@text').first.encode('UTF-8')
    assert_equal 'Nina Simone', tag
  end

  # def test_insane_ID3_fullread
  #   id3 = ID3.new
  #   id3.instance_variable_set('@filesize', 0)
  #   assert_raises(NoMethodError) { id3.send(:fullread, -3) }
  #   assert_raises(NoMethodError) { id3.send(:fullread, 3) }
  # end
end


class Issue21 < MiniTest::Test
  # Files with bad extended header flags failed to read tags.
  # Ensure the extended header is turned off, and the frames are
  # read.
  def setup
      @id3 = ID3Data.new File.expand_path('../data/issue_21.id3', __FILE__)
  end

  def test_no_ext
    assert_equal 0, @id3.f_extended
  end

  def test_has_tags
    assert_includes @id3, 'TIT2'
    assert_includes @id3, 'TALB'
  end

  def test_tit2_value
    assert_equal @id3['TIT2'].text, ['Punk To Funk']
  end
end

class ID3Tags < MiniTest::Test
  def setup
    @silence = File.expand_path('../data/silence-44-s.mp3', __FILE__)
  end

  def test_nil
    m = Module.new do
      def self.const_get(*args)
        raise NameError
      end
    end
    # GOOD GOD why is testing with clean modules so hard?
    id3 = ID3Data.new @silence, known_frames: m
    assert_equal 0, id3.keys.size
    assert_equal 9, id3.instance_variable_get('@unknown_frames').size
  end

  def test_23
    id3 = ID3Data.new @silence
    assert_equal 8, id3.keys.size
    assert_equal 0, id3.instance_variable_get('@unknown_frames').size
    assert_equal 'Quod Libet Test Data', id3['TALB'].to_s
    assert_equal 'Silence', id3['TCON'].to_s
    assert_equal 'Silence', id3['TIT1'].to_s
    assert_equal 'Silence', id3['TIT2'].to_s
    assert_equal 3000, +id3['TLEN']
    refute_equal ['piman','jzig'], id3['TPE1'].to_a
    assert_equal '02/10', id3['TRCK'].to_s
    assert_equal 2, +id3['TRCK']
    assert_equal '2004', id3['TDRC'].to_s
  end

  class ID3hack < ID3Data
    # Override 'correct' behavior with desired behavior
    def loaded_frame(tag)
      if include? tag.hash_key
        self[tag.hash_key].push(*tag.to_a)
      else
        self[tag.hash_key] = tag
      end
    end
  end

  def test_23_multiframe_hack
    id3 = ID3hack.new @silence
    assert_equal 8, id3.keys.size
    assert_equal 0, id3.instance_variable_get('@unknown_frames').size
    assert_equal 'Quod Libet Test Data', id3['TALB'].to_s
    assert_equal 'Silence', id3['TCON'].to_s
    assert_equal 'Silence', id3['TIT1'].to_s
    assert_equal 'Silence', id3['TIT2'].to_s
    assert_equal 3000, +id3['TLEN']
    refute_equal ['piman','jzig'], id3['TPE1'].to_a
    assert_equal '02/10', id3['TRCK'].to_s
    assert_equal 2, +id3['TRCK']
    assert_equal '2004', id3['TDRC'].to_s
  end

  def test_bad_encoding
    assert_raises(IndexError) { ID3Data::Frames::TPE1.from_data(ID3_24, 0, "\x09ab") }
    assert_raises(Mutagen::ValueError) { ID3Data::Frames::TPE1.new(encoding:9, text: 'ab') }
  end

  def test_bad_sync
    assert_raises(Mutagen::ID3::ID3BadUnsynchData) { ID3Data::Frames::TPE1.from_data(ID3_24, 0x02, "\x00\xff\xfe") }
  end

  def test_no_encrypt
    assert_raises(Mutagen::ID3::ID3EncryptionUnsupportedError) { ID3Data::Frames::TPE1.from_data ID3_24, 0x04, "\x00" }
    assert_raises(Mutagen::ID3::ID3EncryptionUnsupportedError) { ID3Data::Frames::TPE1.from_data ID3_23, 0x40, "\x00" }
  end

  def test_bad_compress
    assert_raises(Mutagen::ID3::ID3BadCompressedData) { ID3Data::Frames::TPE1.from_data ID3_24, 0x08, "\x00\x00\x00\x00#"}
    assert_raises(Mutagen::ID3::ID3BadCompressedData) { ID3Data::Frames::TPE1.from_data ID3_23, 0x80, "\x00\x00\x00\x00#"}
  end

  def test_junk_frame
    assert_raises(Mutagen::ID3::ID3JunkFrameError) { ID3Data::Frames::TPE1.from_data ID3_24, 0, ''
    }
  end

  def test_bad_sylt
    assert_raises(Mutagen::ID3::ID3JunkFrameError) { ID3Data::Frames::SYLT.from_data ID3_24, 0x0, "\x00eng\x01description\x00foobar"}
    assert_raises(Mutagen::ID3::ID3JunkFrameError) { ID3Data::Frames::SYLT.from_data ID3_24, 0x0, "\x00eng\x01description\x00foobar\x00\xFF\xFF\xFF".b}
  end

  def test_extra_data
    #assert_warning(ID3Warning) { ID3::Frames::RVRB.send(:read_data, "L1R1BBFFFFPP#xyz")}
    #assert_warning(ID3Warning) { ID3::Frames::RBUF.send(:read_data, "\x00\x01\x00\x01\x00\x00\x00\x00#xyz")}
  end
end

class TestID3v1Tags < MiniTest::Test
  SILENCE = File.expand_path('../data/silence-44-s-v1.mp3', __FILE__)

  def setup
    @id3 = Mutagen::ID3::ID3Data.new SILENCE
  end

  def test_album
    assert_equal 'Quod Libet Test Data', @id3['TALB'].to_s
  end

  def test_genre
    assert_equal 'Darkwave', @id3['TCON'].genres.first
  end

  def test_title
    assert_equal 'Silence', @id3['TIT2'].to_s
  end

  def test_artist
    assert_equal 'piman', @id3['TPE1'].first
  end

  def test_track
    assert_equal '2', @id3['TRCK'].to_s
    assert_equal 2, +@id3['TRCK']
    assert_equal 2, @id3['TRCK'].to_i
  end

  def test_year
    assert_equal '2004', @id3['TDRC'].to_s
  end

  def test_v1_not_v11
    @id3['TRCK'] = Frames::TRCK.new encoding:0, text:'32'
    tag = Mutagen::ID3::make_ID3v1(@id3)
    assert_equal 32, Mutagen::ID3::parse_ID3v1(tag)['TRCK'].to_i
    @id3.delete 'TRCK'
    tag = Mutagen::ID3::make_ID3v1(@id3)
    tag = tag[0...125] + '  ' + tag[-1]
    refute tag.include? 'TRCK'
  end

  def test_nulls
    s = "TAG%<title>30s%<artist>30s%<album>30s%<year>4s%<cmt>29s\x03\x01"
    s %= { artist:"abcd\00fg",
           title:"hijklmn\x00p",
           album:"qrst\x00v",
           cmt: 'wxyz',
           year: '1234' }

    tags = Mutagen::ID3::parse_ID3v1(s.encode('ASCII-8BIT'))
    assert_equal 'abcd', tags['TPE1'].to_s
    assert_equal 'hijklmn', tags['TIT2'].to_s
    assert_equal 'qrst', tags['TALB'].to_s
  end

  def test_non_ascii
    s = "TAG%<title>30s%<artist>30s%<album>30s%<year>4s%<cmt>29s\x03\x01"
    s %= { artist:"abcd\xe9fg",
           title:"hijklmn\xf3p",
           album:"qrst\xfcv",
           cmt: 'wxyz',
           year: '1234' }

    tags = Mutagen::ID3::parse_ID3v1(s.force_encoding('ISO-8859-1'))
    assert_equal "abcd\xe9fg".force_encoding('ISO-8859-1'), tags['TPE1'].to_s
    assert_equal "hijklmn\xf3p".force_encoding('ISO-8859-1'), tags['TIT2'].to_s
    assert_equal "qrst\xfcv".force_encoding('ISO-8859-1'), tags['TALB'].to_s
    assert_equal 'wxyz', tags['COMM'].to_s
    assert_equal '3', tags['TRCK'].to_s
    assert_equal '1234', tags['TDRC'].to_s
  end

  def test_roundtrip
    id3 = Mutagen::ID3
    frames = {}
    %w(TIT2 TALB TPE1 TDRC).each { |key| frames[key] = @id3[key] }
    assert_equal frames.sort, id3::parse_ID3v1(id3::make_ID3v1(frames)).sort
  end

  def test_make_from_empty
    id3 = Mutagen::ID3
    empty = 'TAG' + "\x00" * 124 + "\xff"
    assert_equal empty, id3.make_ID3v1({})
    assert_equal empty, id3.make_ID3v1({ 'TCON' => Frames::TCON.new })
    assert_equal empty, id3.make_ID3v1({ 'COMM' => Frames::COMM.new(encoding:0,
                                                                    text:'')})
  end

  def test_make_v1_from_tyer
    id3 = Mutagen::ID3
    assert_equal id3.make_ID3v1({ 'TDRC' => Frames::TDRC.new(text:'2010-10-10')}),
                 id3.make_ID3v1({ 'TYER' => Frames::TYER.new(text:'2010')})
    assert_equal id3.parse_ID3v1(id3.make_ID3v1({ 'TDRC' => Frames::TDRC.new(text:'2010-10-10')})),
                 id3.parse_ID3v1(id3.make_ID3v1({ 'TYER' => Frames::TYER.new(text:'2010')}))
  end

  def test_invalid
    assert_nil Mutagen::ID3.parse_ID3v1('')
  end

  def test_invalid_track
    id3 = Mutagen::ID3
    tag = {}
    tag['TRCK'] = Frames::TRCK.new(encoding:0, text:'not a number')
    v1tag = id3.make_ID3v1(tag)
    refute_includes id3.parse_ID3v1(v1tag), 'TRCK'
  end

  def test_v1_genre
    id3 = Mutagen::ID3
    tag = {}
    tag['TCON'] = Frames::TCON.new(encoding:0, text:'Pop')
    v1tag = id3.make_ID3v1(tag)
    assert_equal ['Pop'], id3.parse_ID3v1(v1tag)['TCON'].genres
  end
end

class TestWriteID3v1 < MiniTest::Test
  require 'tempfile'
  SILENCE = File.expand_path('../data/silence-44-s.mp3', __FILE__)

  def setup
    @temp = Tempfile.new(['silence', '.mp3'], encoding: 'ISO-8859-1')
    IO.write(@temp.path, IO.read(SILENCE))
    @audio = Mutagen::ID3::ID3Data.new @temp.path
  end

  def fail_if_v1
    File.open(@temp.path) do |f|
      f.seek(-128, IO::SEEK_END)
      refute_equal 'TAG', f.read(3)
    end
  end

  def fail_unless_v1
    File.open(@temp.path) do |f|
      f.seek(-128, IO::SEEK_END)
      assert_equal 'TAG', f.read(3)
    end
  end

  def test_save_delete
    @audio.save v1:0
    fail_if_v1
  end

  def test_save_add
    @audio.save v1:2
    fail_unless_v1
  end

  def test_save_defaults
    @audio.save v1:0
    fail_if_v1
    @audio.save v1:1
    fail_if_v1
    @audio.save v1:2
    fail_unless_v1
    @audio.save v1:1
    fail_unless_v1
  end

  def teardown
    @temp.unlink
    @temp.close
  end
end

class TestV22Tags < MiniTest::Test
  def setup
    path = File.expand_path('../data/id3v22-test.mp3', __FILE__)
    @tags = Mutagen::ID3::ID3Data.new path
  end

  def test_tags
    assert_equal ['3/11'], @tags['TRCK'].text
    assert_equal ['Anais Mitchell'], @tags['TPE1'].text
  end
end

module TestTags
  tests = [
      ['TALB', "\x00a/b".b, 'a/b','', {encoding: 0}],
      ['TBPM', "\x00120".b, '120', 120, {encoding:0}],
      ['TCMP', "\x001".b, '1', 1, {encoding:0}],
      ['TCMP', "\x000".b, '0', 0, {encoding:0}],
      ['TCOM', "\x00a/".b, 'a/', '', {encoding:0}],
      ['TCON', "\x00(21}Disco".b, '(21}Disco', '', {encoding:0}],
      ['TCOP', "\x001900 c".b, '1900 c', '', {encoding:0}],
      ['TDAT', "\x00a/".b, 'a/', '', {encoding:0}],
      ['TDEN', "\x001987".b, '1987', '', {encoding:0, year:[1987]}],
      ['TDOR', "\x001987-12".b, '1987-12', '',
                {encoding:0, year:[1987], month:[12]}],
      ['TDRC', "\x001987\x00".b, '1987', '', {encoding:0, year:[1987]}],
      ['TDRL', "\x001987\x001988".b, '1987,1988', '',
                {encoding:0, year:[1987,1988]}],
      ['TDTG', "\x001987".b, '1987', '', {encoding:0, year:[1987]}],
      ['TDLY', "\x001205".b, '1205', 1205, {encoding:0}],
      ['TENC', "\x00a b/c d".b, 'a b/c d', '', {encoding:0}],
      ['TEXT', "\x00a b\x00c d", ['a b', 'c d'], '', {encoding:0}],
      ['TFLT', "\x00MPG/3".b, 'MPG/3', '', {encoding:0}],
      ['TIME', "\x001205".b, '1205', '', {encoding:0}],
      # Ruby compares encodings on a byte level; "a" in UTF-16BE is '\x00a'
      ['TIPL', "\x02\x00a\x00\x00\x00b", [%w(a b)], '', {encoding:2}],
      ['TIT1', "\x00a/".b, 'a/', '', {encoding:0}],
      # TIT2 checks misaligned terminator "\x00\x00" across crosses utf16 chars
      ['TIT2', "\x01\xff\xfe\x38\x00\x00\x38", "8\u3800", '', {encoding:1}],
      ['TIT3', "\x00a/".b, 'a/', '', {encoding:0}],
      ['TKEY', "\x00A#m".b, 'A#m', '', {encoding:0}],
      ['TLAN', "\x006241".b, '6241', '', {encoding:0}],
      ['TLEN', "\x006241".b, '6241', 6241, {encoding:0}],
      ['TMCL', "\x02\x00a\x00\x00\x00b".b, [%w(a b)], '', {encoding:2}],
      ['TMED', "\x00med".b, 'med', '', {encoding:0}],
      ['TMOO', "\x00moo".b, 'moo', '', {encoding:0}],
      ['TOAL', "\x00alb".b, 'alb', '', {encoding:0}],
      ['TOFN', "\x0012 : bar".b, '12 : bar', '', {encoding:0}],
      ['TOLY', "\x00lyr".b, 'lyr', '', {encoding:0}],
      ['TOPE', "\x00own/lic".b, 'own/lic', '', {encoding:0}],
      ['TORY', "\x001923".b, '1923', 1923, {encoding:0}],
      ['TOWN', "\x00own/lic".b, 'own/lic', '', {encoding:0}],
      ['TPE1', "\x00ab".b, ['ab'], '', {encoding:0}],
      ['TPE2', "\x00ab\x00cd\x00ef".b, %w(ab cd ef), '', {encoding:0}],
      ['TPE3', "\x00ab\x00cd".b, %w(ab cd), '', {encoding:0}],
      ['TPE4', "\x00ab\x00".b, %w(ab), '', {encoding:0}],
      ['TPOS', "\x0008/32".b, '08/32', 8, {encoding:0}],
      ['TPRO', "\x00pro".b, 'pro', '', {encoding:0}],
      ['TPUB', "\x00pub".b, 'pub', '', {encoding:0}],
      ['TRCK', "\x004/9".b, '4/9', 4, {encoding:0}],
      ['TRDA', "\x00Sun Jun 12".b, 'Sun Jun 12', '', {encoding:0}],
      ['TRSN', "\x00ab/cd".b, 'ab/cd', '', {encoding:0}],
      ['TRSO', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSIZ', "\x0012345".b, '12345', 12345, {encoding:0}],
      ['TSOA', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSOP', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSOT', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSO2', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSOC', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TSRC', "\x0012345".b, '12345', '', {encoding:0}],
      ['TSSE', "\x0012345".b, '12345', '', {encoding:0}],
      ['TSST', "\x0012345".b, '12345', '', {encoding:0}],
      ['TYER', "\x002004".b, '2004', 2004, {encoding:0}],

      ['TXXX', "\x00usr\x00a/b\x00c", %w(a/b c), '',
                {encoding:0, desc: 'usr' }],

      ['WCOM', 'http://foo', 'http://foo', '', {}],
      ['WCOP', 'http://bar', 'http://bar', '', {}],
      ['WOAF', 'http://baz', 'http://baz', '', {}],
      ['WOAR', 'http://bar', 'http://bar', '', {}],
      ['WOAS', 'http://bar', 'http://bar', '', {}],
      ['WORS', 'http://bar', 'http://bar', '', {}],
      ['WPAY', 'http://bar', 'http://bar', '', {}],
      ['WPUB', 'http://bar', 'http://bar', '', {}],

      ['WXXX', "\x00usr\x00http".b, 'http', '', {encoding:0, desc: 'usr' }],

      ['IPLS', "\x00a\x00A\x00b\x00B\x00", [['a', 'A'],['b', 'B']], '',
                {encoding:0}],

      ['MCDI', "\x01\x02\x03\x04".b, "\x01\x02\x03\x04".b, '', {}],

      ['ETCO', "\x01\x12\x00\x00\x7f\xff".b, [[18, 32767]], '', {format:1}],

      ['COMM', "\x00ENUT\x00Com".b, 'Com', '',
                {desc: 'T', lang: 'ENU', encoding:0}],
      # found in a real MP3
      ['COMM', "\x00\x00\xcc\x01\x00     ".b, '     ', '',
                {desc:'', lang:"\x00\xcc\x01".b, encoding:0}],

      ['APIC', "\x00-->\x00\x03cover\x00cover.jpg", 'cover.jpg', '',
               {mime: '-->', type:3, desc: 'cover', encoding:0}],
      ['USER', "\x00ENUCom".b, 'Com', '', {lang: 'ENU', encoding:0}],

      ['RVA2', "testdata\x00\x01\xfb\x8c\x10\x12\x23".b,
       'Master volume: -2.2266 dB/0.1417', '',
                {desc: 'testdata', channel:1, gain:-2.22656, peak:0.14169}],

      ['RVA2', "testdata\x00\x01\xfb\x8c\x24\x01\x22\x30\x00\x00".b,
       'Master volume: -2.2266 dB/0.1417', '',
                {desc: 'testdata', channel:1, gain:-2.22656, peak:0.14169}],

      ['RVA2', "testdata2\x00\x01\x04\x01\x00".b,
       'Master volume: +2.0020 dB/0.0000', '',
                {desc: 'testdata2', channel:1, gain:2.001953125, peak:0}],

      ['PCNT', "\x00\x00\x00\x11".b, 17, 17, {count:17}],
      ['POPM', "foo@bar.org\x00\xde\x00\x00\x00\x11".b, 222, 222,
      {email: 'foo@bar.org', rating:222, count:17}],
      ['POPM', "foo@bar.org\x00\xde\x00".b, 222, 222,
                {email: 'foo@bar.org', rating:222, count:0}],
      # Issue #33 - POPM may have no playcount at all.
      ['POPM', "foo@bar.org\x00\xde".b, 222, 222,
                {email: 'foo@bar.org', rating:222}],

      ['UFID', "own\x00data".b, 'data', '', {data: 'data', owner: 'own' }],
      ['UFID', "own\x00\xdd".b, "\xdd".b, '', {data:"\xdd".b, owner: 'own' }],

      ['GEOB', "\x00mime\x00name\x00desc\x00data".b, 'data', '',
                {encoding:0, mime: 'mime', filename: 'name', desc: 'desc' }],

      ['USLT', "\x00engsome lyrics\x00woo\nfun".b, "woo\nfun".b, '',
                {encoding:0, lang: 'eng', desc: 'some lyrics', text:"woo\nfun"}],

      ['SYLT', "\x00eng\x02\x01some lyrics\x00foo\x00\x00\x00\x00\x01bar\x00\x00\x00\x00\x10", 'foobar', '',
          {encoding:0, lang: 'eng', type:1, format:2, desc: 'some lyrics' }],

      ['POSS', "\x01\x0f".b, 15, 15, {format:1, position:15}],
      ['OWNE', "\x00USD10.01\x0020041010CDBaby".b, 'CDBaby', 'CDBaby',
                {encoding:0, price: 'USD10.01', date: '20041010', seller: 'CDBaby' }],

      ['PRIV', "a@b.org\x00random data", 'random data', 'random data',
                {owner: 'a@b.org', data: 'random data' }],
      ['PRIV', "a@b.org\x00\x53", "\x53", "\x53",
                {owner: 'a@b.org', data:"\x53"}],

      ['SIGN', "\x92huh?".b, 'huh?', 'huh?', {group:0x92, sig: 'huh?' }],
      ['ENCR', "a@b.org\x00\x92Data!".b, 'Data!', 'Data!',
                {owner: 'a@b.org', method:0x92, data: 'Data!' }],
      ['SEEK', "\x00\x12\x00\x56".b, 0x12*256*256+0x56, 0x12*256*256+0x56,
                {offset:0x12*256*256+0x56}],

      ['SYTC', "\x01\x10obar".b, "\x10obar".b, '', {format:1, data:"\x10obar"}],

      ['RBUF', "\x00\x12\x00".b, 0x12*256, 0x12*256, {size:0x12*256}],
      ['RBUF', "\x00\x12\x00\x01".b, 0x12*256, 0x12*256,
                {size:0x12*256, info:1}],
      ['RBUF', "\x00\x12\x00\x01\x00\x00\x00\x23".b, 0x12*256, 0x12*256,
                {size:0x12*256, info:1, offset:0x23}],

      ['RVRB', "\x12\x12\x23\x23\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11".b,
                [0x12*256+0x12, 0x23*256+0x23], '',
                {left:0x12*256+0x12, right:0x23*256+0x23} ],

      ['AENC', "a@b.org\x00\x00\x12\x00\x23".b, 'a@b.org', 'a@b.org',
                {owner: 'a@b.org', preview_start:0x12, preview_length:0x23}],
      ['AENC', "a@b.org\x00\x00\x12\x00\x23!".b, 'a@b.org', 'a@b.org',
                {owner: 'a@b.org', preview_start:0x12, preview_length:0x23, data: '!' }],

      ['GRID', "a@b.org\x00\x99".b, 'a@b.org', 0x99,
                {owner: 'a@b.org', group:0x99}],
      ['GRID', "a@b.org\x00\x99data".b, 'a@b.org', 0x99,
                {owner: 'a@b.org', group:0x99, data: 'data' }],

      ['COMR', "\x00USD10.00\x0020051010ql@sc.net\x00\x09Joe\x00A song\x00x-image/fake\x00some data".b,
   Mutagen::ID3::Frames::COMR.new(encoding:0, price: 'USD10.00', valid_until: '20051010', contact: 'ql@sc.net', format:9, seller: 'Joe', desc: 'A song', mime: 'x-image/fake', logo: 'some data'), '',
      {
          encoding:0, price: 'USD10.00', valid_until: '20051010',
          contact: 'ql@sc.net', format:9, seller: 'Joe', desc: 'A song',
          mime: 'x-image/fake', logo: 'some data' }],

      ['COMR', "\x00USD10.00\x0020051010ql@sc.net\x00\x09Joe\x00A song\x00".b,
                Mutagen::ID3::Frames::COMR.new(encoding:0, price: 'USD10.00', valid_until: '20051010',
                     contact: 'ql@sc.net', format:9, seller: 'Joe', desc: 'A song'), '',
          {
              encoding:0, price: 'USD10.00', valid_until: '20051010',
              contact: 'ql@sc.net', format:9, seller: 'Joe', desc: 'A song' }],

      ['MLLT', "\x00\x01\x00\x00\x02\x00\x00\x03\x04\x08foobar".b, 'foobar', '',
                {frames:1, bytes:2, milliseconds:3, bits_for_bytes:4,
                     bits_for_milliseconds:8, data: 'foobar' }],

      ['EQU2', "\x00Foobar\x00\x01\x01\x04\x00", [[128.5, 2.0]], '',
                {method:0, desc: 'Foobar' }],

      ['ASPI', "\x00\x00\x00\x00\x00\x00\x00\x10\x00\x03\x08\x01\x02\x03".b,
                [1, 2, 3], '', {S:0, L:16, N:3, b:8}],

      ['ASPI', "\x00\x00\x00\x00\x00\x00\x00\x10\x00\x03\x10\x00\x01\x00\x02\x00\x03".b, [1, 2, 3], '', {S:0, L:16, N:3, b:16}],

      ['LINK', "TIT1http://www.example.org/TIT1.txt\x00",
                ['TIT1', 'http://www.example.org/TIT1.txt'], '',
                {frameid: 'TIT1', url: 'http://www.example.org/TIT1.txt' }],
      ['LINK', "COMMhttp://www.example.org/COMM.txt\x00engfoo".b,
                ['COMM', 'http://www.example.org/COMM.txt', 'engfoo'], '',
                {frameid: 'COMM', url: 'http://www.example.org/COMM.txt',
                     data: 'engfoo' }],

      # iTunes podcast frames
      ['TGID', "\x00i".b, 'i', '', {encoding:0}],
      ['TDES', "\x00ii".b, 'ii', '', {encoding:0}],
      ['WFED', 'http://zzz', 'http://zzz', '', {}],

      # 2.2 tags
      ['UFI', "own\x00data".b, 'data', '', {data: 'data', owner: 'own' }],
      ['SLT', "\x00eng\x02\x01some lyrics\x00foo\x00\x00\x00\x00\x01bar\x00\x00\x00\x00\x10", 'foobar', '',
          {encoding:0, lang: 'eng', type:1, format:2, desc: 'some lyrics' }],
      ['TT1', "\x00ab\x00".b, 'ab', '', {encoding:0}],
      ['TT2', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TT3', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TP1', "\x00ab\x00".b, 'ab', '', {encoding:0}],
      ['TP2', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TP3', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TP4', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TCM', "\x00ab/cd".b, 'ab/cd', '', {encoding:0}],
      ['TXT', "\x00lyr".b, 'lyr', '', {encoding:0}],
      ['TLA', "\x00ENU".b, 'ENU', '', {encoding:0}],
      ['TCO', "\x00gen".b, 'gen', '', {encoding:0}],
      ['TAL', "\x00alb".b, 'alb', '', {encoding:0}],
      ['TPA', "\x001/9".b, '1/9', 1, {encoding:0}],
      ['TRK', "\x002/8".b, '2/8', 2, {encoding:0}],
      ['TRC', "\x00isrc".b, 'isrc', '', {encoding:0}],
      ['TYE', "\x001900".b, '1900', 1900, {encoding:0}],
      ['TDA', "\x002512".b, '2512', '', {encoding:0}],
      ['TIM', "\x001225".b, '1225', '', {encoding:0}],
      ['TRD', "\x00Jul 17".b, 'Jul 17', '', {encoding:0}],
      ['TMT', "\x00DIG/A".b, 'DIG/A', '', {encoding:0}],
      ['TFT', "\x00MPG/3".b, 'MPG/3', '', {encoding:0}],
      ['TBP', "\x00133".b, '133', 133, {encoding:0}],
      ['TCP', "\x001".b, '1', 1, {encoding:0}],
      ['TCP', "\x000".b, '0', 0, {encoding:0}],
      ['TCR', "\x00Me".b, 'Me', '', {encoding:0}],
      ['TPB', "\x00Him".b, 'Him', '', {encoding:0}],
      ['TEN', "\x00Lamer".b, 'Lamer', '', {encoding:0}],
      ['TSS', "\x00ab".b, 'ab', '', {encoding:0}],
      ['TOF', "\x00ab:cd".b, 'ab:cd', '', {encoding:0}],
      ['TLE', "\x0012".b, '12', 12, {encoding:0}],
      ['TSI', "\x0012".b, '12', 12, {encoding:0}],
      ['TDY', "\x0012".b, '12', 12, {encoding:0}],
      ['TKE', "\x00A#m".b, 'A#m', '', {encoding:0}],
      ['TOT', "\x00org".b, 'org', '', {encoding:0}],
      ['TOA', "\x00org".b, 'org', '', {encoding:0}],
      ['TOL', "\x00org".b, 'org', '', {encoding:0}],
      ['TOR', "\x001877".b, '1877', 1877, {encoding:0}],
      ['TXX', "\x00desc\x00val".b, 'val', '', {encoding:0, desc: 'desc' }],

      ['WAF', 'http://zzz', 'http://zzz', '', {}],
      ['WAR', 'http://zzz', 'http://zzz', '', {}],
      ['WAS', 'http://zzz', 'http://zzz', '', {}],
      ['WCM', 'http://zzz', 'http://zzz', '', {}],
      ['WCP', 'http://zzz', 'http://zzz', '', {}],
      ['WPB', 'http://zzz', 'http://zzz', '', {}],
      ['WXX', "\x00desc\x00http".b, 'http', '', {encoding:0, desc: 'desc' }],

      ['IPL', "\x00a\x00A\x00b\x00B\x00".b, [%w(a A), %w(b B)], '',
               {encoding:0}],
      ['MCI', "\x01\x02\x03\x04".b, "\x01\x02\x03\x04".b, '', {}],

      ['ETC', "\x01\x12\x00\x00\x7f\xff".b, [[18, 32767]], '', {format:1}],

      ['COM', "\x00ENUT\x00Com".b, 'Com', '',
               {desc: 'T', lang: 'ENU', encoding:0}],
      ['PIC', "\x00-->\x03cover\x00cover.jpg", 'cover.jpg', '',
               {mime: '-->', type:3, desc: 'cover', encoding:0}],

      ['POP', "foo@bar.org\x00\xde\x00\x00\x00\x11".b, 222, 222,
               {email: 'foo@bar.org', rating:222, count:17}],
      ['CNT', "\x00\x00\x00\x11".b, 17, 17, {count:17}],
      ['GEO', "\x00mime\x00name\x00desc\x00data".b, 'data', '',
               {encoding:0, mime: 'mime', filename: 'name', desc: 'desc' }],
      ['ULT', "\x00engsome lyrics\x00woo\nfun".b, "woo\nfun".b, '',
               {encoding:0, lang: 'eng', desc: 'some lyrics', text:"woo\nfun"}],

      ['BUF', "\x00\x12\x00".b, 0x12*256, 0x12*256, {size:0x12*256}],

      ['CRA', "a@b.org\x00\x00\x12\x00\x23".b, 'a@b.org', 'a@b.org',
               {owner: 'a@b.org', preview_start:0x12, preview_length:0x23}],
      ['CRA', "a@b.org\x00\x00\x12\x00\x23!".b, 'a@b.org', 'a@b.org',
               {owner: 'a@b.org', preview_start:0x12, preview_length:0x23, data: '!' }],

      ['REV', "\x12\x12\x23\x23\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11".b,
               [0x12*256+0x12, 0x23*256+0x23], '',
               {left:0x12*256+0x12, right:0x23*256+0x23} ],

      ['STC', "\x01\x10obar".b, "\x10obar".b, '', {format:1, data:"\x10obar"}],

      ['MLL', "\x00\x01\x00\x00\x02\x00\x00\x03\x04\x08foobar".b, 'foobar', '',
               {frames:1, bytes:2, milliseconds:3, bits_for_bytes:4,
                    bits_for_milliseconds:8, data: 'foobar' }],
      ['LNK', "TT1http://www.example.org/TIT1.txt\x00".b,
               ['TT1', 'http://www.example.org/TIT1.txt'], '',
               {frameid: 'TT1', url: 'http://www.example.org/TIT1.txt' }],
      ['CRM', "foo@example.org\x00test\x00woo".b,
       'woo', '', {owner: 'foo@example.org', desc: 'test', data: 'woo' }]

  ]
  load_tests = {}
  repr_tests = {}
  write_tests = {}

  tests.each_with_index do |arr,i|
    load_tests[("test_#{arr[0]}_#{i}").to_sym] =
        Proc.new do
          tag, data, value, intval, info = arr
          tag_class = Mutagen::ID3::Frames.const_get(tag) or Mutagen::ID3::Frames_2_2.const_get(tag)
          tag = tag_class.from_data(ID3_23, 0, data)
          assert tag.respond_to?(:hash_key)
          assert tag.respond_to?(:pprint)
          assert_equal tag, value
          unless info.include? :encoding
            assert_nil tag.instance_variable_get('@encoding')
          end
          info.each do |attr, value|
            t = tag
            unless value.is_a? Array or t.is_a? Array
              value = [value]
              t = [t]
            end
            value.zip(t).each do |value, t|
              if value.is_a? Float
                assert_in_delta value, t.instance_variable_get("@#{attr}")
              else
                assert_equal t.instance_variable_get("@#{attr}"), value
              end
              # if intval.is_a? Fixnum
              #   assert_equal intval, (+t)
              # end
            end
          end
        end

    write_tests[("test_write_#{arr[0]}_#{i}").to_sym] =
        Proc.new do
          tag, data, value, intval, info = arr
          tag_class = Mutagen::ID3::Frames.const_get(tag) or Mutagen::ID3::Frames_2_2.const_get(tag)
          tag = tag_class.from_data(ID3_24, 0, data)
          towrite = tag.send(:write_data)
          assert_equal Encoding::ASCII_8BIT, towrite.encoding
          tag2 = tag_class.from_data(ID3_24, 0, towrite)
          tag_class::FRAMESPEC.each do |spec|
            attr = spec.name
            assert_equal tag.instance_variable_get("@#{attr}"), tag2.instance_variable_get("@#{attr}")
          end
        end
  end

  test_read_tags = Object.const_set('TestReadTags', Class.new(MiniTest::Test))
  load_tests.each_pair do |name, proc|
    test_read_tags.class_eval { define_method(name, proc) }
  end

  test_write_tags = Object.const_set('TestWriteTags', Class.new(MiniTest::Test))
  write_tests.each_pair do |name, proc|
    test_write_tags.class_eval { define_method(name, proc) }
  end

  frames = Mutagen::ID3::Frames.constants.select {|c| Mutagen::ID3::Frames.const_get(c).is_a? Class }
  frames_2_2 = Mutagen::ID3::Frames_2_2.constants.select {|c| Mutagen::ID3::Frames_2_2.const_get(c).is_a? Class }
  check = (frames + frames_2_2).map{|k| [k, nil]}.to_h

  tested_tags = tests.map{|r| [r[0].to_sym, nil]}.to_h
  test_tested_tags = Object.const_set('TestTestedTags', Class.new(MiniTest::Test))
  check.each_pair do |tag,_|
    test_tested_tags.class_eval do
      define_method("test_#{tag}_tested") do
        assert self.class.const_get('TESTED_TAGS').has_key?(tag), "Didn't test tag #{tag}"
      end
    end
  end
  test_tested_tags.const_set('TESTED_TAGS', tested_tags)

end

class UpdateTo24 < MiniTest::Test
  def test_pic
    pic = Mutagen::ID3::Frames_2_2::PIC
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V22)
    id3.add(pic.new(encoding:0, mime: 'PNG', desc: 'cover', type:3, data:''))
    id3.update_to_v24
    assert_equal 'image/png', id3['APIC:cover'].mime
  end

  def test_tyer
    tyer = Mutagen::ID3::Frames::TYER
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add(tyer.new(encoding:0, text:'2006'))
    id3.update_to_v24
    assert_equal '2006', id3['TDRC'].to_s
  end

  def test_tyer_tdat
    tdat = Mutagen::ID3::Frames::TDAT
    tyer = Mutagen::ID3::Frames::TYER
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add(tyer.new(encoding:0, text:'2006'))
    id3.add(tdat.new(encoding:0, text:'0603'))
    id3.update_to_v24
    assert_equal '2006-03-06', id3['TDRC'].to_s
  end

  def test_tyer_tdat_time
    tdat = Mutagen::ID3::Frames::TDAT
    tyer = Mutagen::ID3::Frames::TYER
    time = Mutagen::ID3::Frames::TIME
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add(tyer.new(encoding:0, text:'2006'))
    id3.add(tdat.new(encoding:0, text:'0603'))
    id3.add(time.new(encoding:0, text:'1127'))
    id3.update_to_v24
    assert_equal '2006-03-06 11:27:00', id3['TDRC'].to_s
  end

  def test_tory
    tory = Mutagen::ID3::Frames::TORY
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add(tory.new(encoding:0, text:'2006'))
    id3.update_to_v24
    assert_equal '2006', id3['TDOR'].to_s
  end

  def test_ipls
    ipls = Mutagen::ID3::Frames::IPLS
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add(ipls.new(encoding:0, people:[%w(a b), %w(c d)]))
    id3.update_to_v24
    assert_equal [%w(a b), %w(c d)], id3['TIPL'].people
  end

  def test_dropped
    time = Mutagen::ID3::Frames::TIME
    id3 = Mutagen::ID3::ID3Data.new
    id3.instance_variable_set('@version', Mutagen::ID3::ID3Data::V23)
    id3.add time.new(encoding:0, text:['1155'])
    id3.update_to_v24
    assert_empty id3.get_all('TIME')
  end
end
