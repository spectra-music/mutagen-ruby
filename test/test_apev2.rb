require_relative 'test_helper'

SAMPLE = File.expand_path('../data/click.mpc', __FILE__)
OLD = File.expand_path('../data/oldtag.apev2', __FILE__)
BROKEN = File.expand_path('../data/brokentag.apev2', __FILE__)
LYRICS2 = File.expand_path('../data/apev2-lyricsv2.mp3', __FILE__)
INVAL_ITEM_COUNT = File.expand_path('../data/145-invalid-item-count.apev2', __FILE__)

class TestValidAPEv2Key < MiniTest::Test
  def test_valid
    ['foo', 'Foo', '   f ~~~'].each do |key|
      assert Mutagen::APEv2::is_valid_apev2_key key
    end
  end

  def test_invalid
    ["\x11hi", "ffoo\xFF", "\u1234", "a", "", "foo" * 100].each do |key|
      refute Mutagen::APEv2::is_valid_apev2_key key
    end
  end
end

class TestAPEInvalidItemCount < MiniTest::Test
  # http://code.google.com/p/mutagen/issues/detail?id=145

  def test_load
    x = Mutagen::APEv2::APEv2Data.new INVAL_ITEM_COUNT
    assert_equal 17, x.keys.size
  end
end

class TestAPEWriter < MiniTest::Test
  def setup
    @offset = 0
    FileUtils.cp SAMPLE, SAMPLE + '.new'
    FileUtils.cp BROKEN, BROKEN + '.new'
    tag = Mutagen::APEv2::APEv2Data.new
    @values = {
        'artist' => "Joe Wreschnig\0unittest",
        'album' => 'Mutagen tests',
        'title' => 'Not really a song'
    }
    @values.each_pair do |k, v|
      tag[k] = v
    end
    tag.save(SAMPLE + '.new')
    tag.save(SAMPLE + '.justtag')
    tag.save(SAMPLE + '.tag_at_start')
    File.open(SAMPLE + ".tag_at_start", 'ab') do |f|
      f.write 'tag garbage' * 1000
    end
    @tag = Mutagen::APEv2::APEv2Data.new(SAMPLE + '.new')
  end

  def teardown
    File.unlink SAMPLE + '.new'
    File.unlink BROKEN + '.new'
    File.unlink SAMPLE + '.justtag'
    File.unlink SAMPLE + '.tag_at_start'
  end

  def test_changed
    size = File.size(SAMPLE + '.new')
    @tag.save
    assert_equal size - @offset, File.size(SAMPLE + '.new')
  end

  def test_fix_broken
    # Clean up garbage from a bug in pre-Mutagen APEv2.
    # This also tests removing ID3v1 tags on writes.
    refute_equal File.size(OLD), File.size(BROKEN)
    tag = Mutagen::APEv2::APEv2Data.new(BROKEN)
    tag.save(BROKEN + '.new')
    assert_equal File.size(OLD), File.size(BROKEN + '.new')
  end

  def test_readback
    @tag.items.each do |k,v|
      assert_equal v.to_s, @values[k]
    end
  end

  def test_size
    assert_equal File.size(SAMPLE) + File.size(SAMPLE + '.justtag'), File.size(SAMPLE + '.new')
  end

  def test_delete
    Mutagen::APEv2::delete(SAMPLE + '.justtag')
    tag = Mutagen::APEv2::APEv2Data.new SAMPLE + '.new'
    tag.delete_tags
    assert_equal File.size(SAMPLE) + @offset, File.size(SAMPLE + '.new')
    refute_nil tag
  end

  def test_empty
    assert_raises(Mutagen::APEv2::APENoHeaderError) do
      Mutagen::APEv2::APEv2Data.new File.expand_path('../data/emptyfile.mp3', __FILE__)
    end
  end

  def test_tag_at_start
    filename = SAMPLE + '.tag_at_start'
    tag = Mutagen::APEv2::APEv2Data.new filename
    assert_equal 'Mutagen tests', tag['album'].to_s
  end

  def test_tag_at_start_write
    filename = SAMPLE + '.tag_at_start'
    tag = Mutagen::APEv2::APEv2Data.new filename
    tag.save
    tag = Mutagen::APEv2::APEv2Data.new filename
    assert_equal 'Mutagen tests', tag['album'].to_s
    assert_equal File.size(filename) - 'tag garbage'.size * 1000, File.size(SAMPLE + '.justtag')
  end

  def test_tag_at_start_delete
    filename = SAMPLE + '.tag_at_start'
    tag = Mutagen::APEv2::APEv2Data.new filename
    tag.delete_tags
    assert_raises(Mutagen::APEv2::APENoHeaderError) do
      Mutagen::APEv2::APEv2Data.new filename
    end
    assert_equal 'tag garbage'.size * 1000, File.size(filename)
  end

  def test_case_preservation
    Mutagen::APEv2::delete(SAMPLE + '.justtag')
    tag = Mutagen::APEv2::APEv2Data.new(SAMPLE + '.new')
    tag['FoObaR'] = 'Quux'
    tag.save
    tag = Mutagen::APEv2::APEv2Data.new(SAMPLE + '.new')
    assert_includes tag.keys, 'FoObaR'
    refute_includes tag.keys, 'foobar'
  end

  def test_unicode_key
    # http://code.google.com/p/mutagen/issues/detail?id=123
    tag = Mutagen::APEv2::APEv2Data.new(SAMPLE + ".new")
    tag['abc'] = "\xf6\xe4\xfc"
    tag['cba'] = 'abc'
    tag.save
  end
end

class TestAPEv2ThenID3v1Writer < TestAPEWriter

  def setup
    super
    @offset = 128
    f = File.open(SAMPLE + '.new', 'ab+')
    f.write('TAG' + "\x00" * 125)
    f.close
    f = File.open(BROKEN + '.new', 'ab+')
    f.write('TAG' + "\x00" * 125)
    f.close
    f = File.open(SAMPLE + '.justtag', 'ab+')
    f.write('TAG' + "\x00" * 125)
    f.close
  end

  def test_tag_at_start_write
  end
end

class TestAPEv2 < MiniTest::Test
  def setup
    @file = Tempfile.new(['test', '.apev2'])
    @filename = @file.path
    @file.close
    FileUtils.cp OLD, @filename
    @audio = Mutagen::APEv2::APEv2Data.new @filename
  end

  def teardown
    File.unlink(@filename)
  end

  def test_invalid_key
    assert_raises(KeyError) { @audio["\u1234"] = "foo" }
  end

  def test_guess_text
    @audio['test'] = 'foobar'
    assert_equal 'foobar', @audio['test'].to_s
    assert_instance_of Mutagen::APEv2::APETextValue, @audio['test']
  end

  def test_guess_text_list
    @audio['test'] = ['foobar', 'quuxbarz']
    assert_equal "foobar\x00quuxbarz", @audio['test'].to_s
    assert_instance_of Mutagen::APEv2::APETextValue, @audio['test']
  end

  def test_guess_utf8
    @audio['test'] = 'foobar'
    assert_equal 'foobar', @audio['test'].to_s
    assert_instance_of Mutagen::APEv2::APETextValue, @audio['test']
  end

  def test_guess_not_utf8
    @audio['test'] = "\xa4woo".b
    assert_instance_of Mutagen::APEv2::APEBinaryValue, @audio['test']
    assert_equal 4, @audio['test'].to_s.size
  end

  def test_bad_value_type
    assert_raises(ArgumentError) { Mutagen::APEv2::APEValue.new('foo', 99) }
  end

  def test_module_delete_empty
    Mutagen::APEv2::delete File.expand_path('../data/emptyfile.mp3', __FILE__)
  end

  def test_invalid
    assert_raises(Errno::ENOENT) { Mutagen::APEv2::APEv2Data.new "dne" }
  end

  def test_no_tag
    assert_raises(Mutagen::APEv2::APENoHeaderError) { Mutagen::APEv2::APEv2Data.new File.expand_path('../data/emptyfile.mp3', __FILE__) }
  end

  def test_cases
    assert_equal @audio['artist'].to_s, @audio['ARTIST'].to_s
    assert_includes @audio, 'artist'
    assert_includes @audio, 'artisT'
  end

  def test_keys
    assert_includes @audio.keys, 'Track'
    assert_includes @audio.values, 'AnArtist'
    assert_equal @audio.items, @audio.keys.zip(@audio.values).to_a
  end

  def test_key_types
    assert_instance_of String, @audio.keys[0]
  end

  def test_invalid_keys
    assert_raises(KeyError) { @audio.fetch("\x00") }
    assert_raises(KeyError) { @audio["\x00"] }
    assert_raises(KeyError) { @audio["\x00"] = "" }
    assert_raises(KeyError) { @audio.fetch("\x00") }
    assert_raises(KeyError) { @audio["\x00"] }
  end

  def test_dictlike
    refute_nil @audio.fetch('track')
    refute_nil @audio.fetch('Track')
  end

  def test_del
    s = @audio['artist']
    @audio.delete('artist')
    refute_includes @audio, 'artist'
    assert_nil @audio['artist']
    assert_raises(KeyError) { @audio.fetch 'artist' }
    @audio['Artist'] = s
    assert_equal 'AnArtist', @audio['artist'].to_s
  end

  def test_values
    assert_equal @audio['artist'].to_s, @audio['artist'].to_s
    assert_operator @audio['artist'].to_s, :< , @audio['title'].to_s
    assert_equal 'AnArtist', @audio['artist'].to_s
    assert_equal 'Some Music', @audio['title'].to_s
    assert_equal 'A test case', @audio['album'].to_s
    assert_equal '07', @audio['track'].to_s
  end
end

class TestAPEv2ThenID3v1 < TestAPEv2
  def setup
    super
    f = File.open(@filename, 'ab+')
    f.write "TAG" + "\x00" * 125
    f.close
    @audio = Mutagen::APEv2::APEv2Data.new @filename
  end
end

class TestAPEv2WithLyrics2 < MiniTest::Test
  def setup
    @tag = Mutagen::APEv2::APEv2Data.new LYRICS2
  end

  def test_values
    assert_equal '000,179', @tag['MP3GAIN_MINMAX'].to_s
    assert_equal '-4.080000 dB', @tag['REPLAYGAIN_TRACK_GAIN'].to_s
    assert_equal '1.008101', @tag['REPLAYGAIN_TRACK_PEAK'].to_s
  end
end

class TestAPEBinaryValue < MiniTest::Test
  def setup
    @sample = "\x12\x45\xde"
    @value = Mutagen::APEv2::APEValue.new @sample, Mutagen::APEv2::BINARY
  end

  def test_type
    assert_instance_of Mutagen::APEv2::APEBinaryValue, @value
    # assert_raises(TypeError) { Mutagen::APEv2::APEValue.new "abc", Mutagen::APEv2::BINARY }
  end

  def test_const
    assert_equal @sample, @value.to_s
  end

  def test_pprint
    assert_respond_to @value, :pprint
  end

end

class TestAPETextValue < MiniTest::Test
  def setup
    @sample = %w(foo bar baz)
    @value = Mutagen::APEv2::APEValue.new @sample.join("\0"), Mutagen::APEv2::TEXT
  end

  def test_type
    assert_instance_of Mutagen::APEv2::APETextValue, @value
    # assert_raises(TypeError) { Mutagen::APEv2::APEValue.new "abc", Mutagen::APEv2::BINARY }
  end

  def test_list
    assert_equal @sample, @value.to_a
  end

  def test_get_item
    @value.size.times do |i|
      assert_equal @sample[i], @value[i]
    end
  end

  def test_set_item_list
    @value[2] = @sample[2] = 'quux'
    test_list
    test_get_item
    @value[2] = @sample[2] = 'baz'
  end

  def test_pprint
    assert_respond_to @value, :pprint
  end
end

class TestAPEExtValue < MiniTest::Test
  def setup
    @sample = 'http://foo'
    @value = Mutagen::APEv2::APEValue.new @sample, Mutagen::APEv2::EXTERNAL
  end

  def test_type
    assert_instance_of Mutagen::APEv2::APEExtValue, @value
    # assert_raises(TypeError) { Mutagen::APEv2::APEValue.new "abc", Mutagen::APEv2::BINARY }
  end

  def test_const
    assert_equal @sample, @value.to_s
  end

  def test_pprint
    assert_respond_to @value, :pprint
  end
end

class TestAPEv2File < MiniTest::Test
  def setup
    @audio = Mutagen::APEv2::APEv2File.new File.expand_path('../data/click.mpc', __FILE__)
  end

  def test_add_tags
    assert_nil @audio.tags
    @audio.add_tags
    refute_nil @audio.tags
    assert_raises(Mutagen::Util::ValueError) { @audio.add_tags }
  end

  def test_unknown_info
    info = @audio.info
    assert_respond_to info, :pprint
    info.pprint
  end
end