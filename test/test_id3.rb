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
    name = File.expand_path("../data/does/not/exist")
    assert_raises(Errno::ENOENT) { ID3Data.new(name) }
  end

  def test_header_empty
    id3 = ID3Data.new
    id3.instance_variable_set("@fileobj", File.open(EMPTY, 'r'))
    assert_raises(EOFError) { id3.send(:load_header)}
  end


  def test_header_silence
    id3 = ID3Data.new
    id3.instance_variable_set("@fileobj", File.open(SILENCE, 'r'))
    id3.send(:load_header)
    assert_equal ID3Data::V23, id3.version
    assert_equal 1314, id3.size
  end

  def test_header_2_4_invalid_flags
    id3 = ID3Data.new
    id3.instance_variable_set("@fileobj", StringIO.new("ID3\x04\x00\x1f\x00\x00\x00\x00"))
    exception = assert_raises(Mutagen::ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0x1f', exception.message
  end

  def test_header_2_4_unsynch_flags
    id3 = ID3Data.new
    id3.instance_variable_set("@fileobj", StringIO.new("ID3\x04\x00\x10\x00\x00\x00\xFF"))
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
    assert_equal "\x5a", id3.instance_variable_get("@extdata")
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
    assert_equal 0, id3.instance_variable_get("@extsize")
    assert_equal '', id3.instance_variable_get("@extdata")
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
    assert_equal "\x00\x00\x56\x78\x9a\xbc".b, id3.instance_variable_get("@extdata")
  end

  def test_unsynch
    id3 = ID3Data.new
    id3.instance_variable_set('@version', ID3Data::V24)
    id3.instance_variable_set('@flags', 0x80)
    badsync = "\x00\xff\x00ab\x00".b
    assert_equal "\xffab".b, id3.send(:load_framedata,
                                      ID3Data::Frames.const_get(:TPE2),
                                      0, badsync).to_a.first.b

    id3.instance_variable_set('@flags', 0x00)
    assert_equal "\xffab".b, id3.send(:load_framedata,
                                      ID3Data::Frames.const_get(:TPE2),
                                      0x02, badsync).to_a.first.b
    assert_equal ["\xff".b, "ab".b], id3.send(:load_framedata,
                                              ID3Data::Frames.const_get(:TPE2),
                                              0, badsync).to_a.map{|s| s.b}
  end

  def test_load_v23_unsynch
    id3 = ID3Data.new UNSYNC
    tag = id3['TPE1'].instance_variable_get("@text").first.encode('UTF-8')
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
    assert_includes @id3, "TIT2"
    assert_includes @id3, "TALB"
  end

  def test_tit2_value
    assert_equal @id3["TIT2"].text, ["Punk To Funk"]
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
    assert_raises(Mutagen::ValueError) { ID3Data::Frames::TPE1.new(encoding:9, text:"ab") }
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
    assert_raises(Mutagen::ID3::ID3JunkFrameError) { ID3Data::Frames::TPE1.from_data ID3_24, 0, ""}
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
           cmt:"wxyz",
           year:"1234" }

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
           cmt:"wxyz",
           year:"1234" }

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
    empty = "TAG" + "\x00" * 124 + "\xff"
    assert_equal empty, id3.make_ID3v1({})
    assert_equal empty, id3.make_ID3v1({ 'TCON' => Frames::TCON.new })
    assert_equal empty, id3.make_ID3v1({ 'COMM' => Frames::COMM.new(encoding:0,
                                                                    text:'')})
  end

  def test_make_v1_from_tyer
    id3 = Mutagen::ID3
    assert_equal id3.make_ID3v1({"TDRC"=> Frames::TDRC.new(text:'2010-10-10')}),
                 id3.make_ID3v1({"TYER"=> Frames::TYER.new(text:'2010')})
    assert_equal id3.parse_ID3v1(id3.make_ID3v1({"TDRC"=> Frames::TDRC.new(text:'2010-10-10')})),
                 id3.parse_ID3v1(id3.make_ID3v1({"TYER"=> Frames::TYER.new(text:'2010')}))
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
