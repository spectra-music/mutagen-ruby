require_relative 'test_helper'
include Mutagen


_22 = ID3.new; _22.instance_variable_set('@version', ID3::V22)
_23 = ID3.new; _23.instance_variable_set('@version', ID3::V23)
_24 = ID3.new; _24.instance_variable_set('@version', ID3::V24)

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

class ID3Loading < MiniTest::Test
  EMPTY = File.expand_path('../data/emptyfile.mp3', __FILE__)
  SILENCE = File.expand_path('../data/silence-44-s.mp3', __FILE__)

  def test_empty_file
    # assert_raises(Mutagen::ValueError) { ID3.new(filename:name) }
    assert_raises(Mutagen::ID3::ID3NoHeaderError) { ID3.new(filename:EMPTY) }
    #from_name = ID3(name)
    #obj = open(name, 'rb')
    #from_obj = ID3(fileobj=obj)
    #self.assertEquals(from_name, from_explicit_name)
    #self.assertEquals(from_name, from_obj)
  end

  def test_nonexistant_file
    name = File.expand_path("../data/does/not/exist")
    assert_raises(Errno::ENOENT) { ID3.new(name) }
  end

  def test_header_empty
    id3 = ID3.new
    id3.instance_variable_set("@fileobj", File.open(EMPTY, 'r'))
    assert_raises(EOFError) { id3.send(:load_header)}
  end


  def test_header_silence
    id3 = ID3.new
    id3.instance_variable_set("@fileobj", File.open(SILENCE, 'r'))
    id3.send(:load_header)
    assert_equal ID3::V23, id3.version
    assert_equal 1314, id3.size
  end

  def test_header_2_4_invalid_flags
    id3 = ID3.new
    id3.instance_variable_set("@fileobj", StringIO.new("ID3\x04\x00\x1f\x00\x00\x00\x00"))
    exception = assert_raises(ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0x1f', exception.message
  end

  def test_header_2_4_unsynch_flags
    id3 = ID3.new
    id3.instance_variable_set("@fileobj", StringIO.new("ID3\x04\x00\x10\x00\x00\x00\xFF"))
    exception = assert_raises(ValueError) { id3.send(:load_header) }
    assert_equal 'Header size not synchsafe', exception.message
  end

  def test_header_2_4_allow_footer
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x10\x00\x00\x00\x00"))
    id3.send(:load_header)
  end

  def test_header_2_3_invalid_flags
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x1f\x00\x00\x00\x00"))
    ex = assert_raises(ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0x1f', ex.message
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x0f\x00\x00\x00\x00"))
    ex = assert_raises(ValueError) { id3.send(:load_header) }
    assert_equal ' has invalid flags 0xf', ex.message
  end

  def test_header_2_2
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x02\x00\x00\x00\x00\x00\x00"))
    id3.send :load_header
    assert_equal ID3::V22, id3.version
  end

  def test_header_2_1
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x01\x00\x00\x00\x00\x00\x00"))
    assert_raises(ID3::ID3UnsupportedVersionError) { id3.send :load_header }
  end

  def test_header_too_small
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x01\x00\x00\x00\x00\x00"))
    assert_raises(EOFError) { id3.send(:load_header) }
  end

  def test_header_2_4_extended
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00\x00\x00\x00\x05\x5a"))
    id3.send(:load_header)
    assert_equal 1, id3.instance_variable_get('@extsize')
    assert_equal "\x5a", id3.instance_variable_get("@extdata")
  end

  def test_header_2_4_extended_unsynch_size
    id3 = ID3.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00\x00\x00\x00\xFF\x5a"))
    assert_raises(ValueError) { id3.send(:load_header) }
  end

  def test_header_2_4_extended_but_not
    id3 = ID3.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00TIT1\x00\x00\x00\x01a"))
    id3.send :load_header
    assert_equal 0, id3.instance_variable_get("@extsize")
    assert_equal '', id3.instance_variable_get("@extdata")
  end

  def test_header_2_4_extended_but_not_but_not_tag
    id3 = ID3.new
    id3.instance_variable_set('@fileobj',StringIO.new("ID3\x04\x00\x40\x00\x00\x00\x00TIT9"))
    assert_raises(EOFError) { id3.send :load_header }
  end

  def test_header_2_3_extended
    id3 = ID3.new
    id3.instance_variable_set('@fileobj', StringIO.new("ID3\x03\x00\x40\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x56\x78\x9a\xbc"))
    id3.send(:load_header)
    assert_equal 6, id3.instance_variable_get('@extsize')
    assert_equal "\x00\x00\x56\x78\x9a\xbc".b, id3.instance_variable_get("@extdata")
  end

  def test_unsynch
    id3 = ID3.new
    id3.instance_variable_set('@version', ID3::V24)
    id3.instance_variable_set('@flags', 0x80)
    badsync = "\x00\xff\x00ab\x00".b
    id3.send(:load_framedata,
             ID3::Frames.const_get(:TPE2),
             0, badsync).to_a
    assert_equal "\xffab".b, id3.send(:load_framedata,
                                      ID3::Frames.const_get(:TPE2),
                                      0, badsync).to_a.first
  end
end

