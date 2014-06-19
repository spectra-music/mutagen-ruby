require_relative 'test_helper'

class TestAIFF < MiniTest::Test
  SILENCE_1 = File.expand_path('../data/11k-1ch-2s-silence.aif', __FILE__)
  SILENCE_2 = File.expand_path('../data/48k-2ch-s16-silence.aif', __FILE__)
  SILENCE_3 = File.expand_path('../data/8k-1ch-1s-silence.aif', __FILE__)
  SILENCE_4 = File.expand_path('../data/8k-1ch-3.5s-silence.aif', __FILE__)
  SILENCE_5 = File.expand_path('../data/8k-4ch-1s-silence.aif', __FILE__)


  HAS_TAGS  = File.expand_path('../data/with-id3.aif', __FILE__)
  NO_TAGS   =  File.expand_path('../data/8k-1ch-1s-silence.aif', __FILE__)

  def setup
    @filename_1 = Tempfile.new(%w(silence .aif))
    @filename_1.close
    FileUtils.cp HAS_TAGS, @filename_1.path

    @filename_2 = Tempfile.new(%w(silence .aif))
    @filename_2.close
    FileUtils.cp NO_TAGS, @filename_2.path

    @aiff_tmp_id3 = Mutagen::AIFF::AIFFData.new @filename_1.path
    @aiff_tmp_no_id3 = Mutagen::AIFF::AIFFData.new @filename_2.path

    @aiff_1 = Mutagen::AIFF::AIFFData.new SILENCE_1
    @aiff_2 = Mutagen::AIFF::AIFFData.new SILENCE_2
    @aiff_3 = Mutagen::AIFF::AIFFData.new SILENCE_3
    @aiff_4 = Mutagen::AIFF::AIFFData.new SILENCE_4
    @aiff_5 = Mutagen::AIFF::AIFFData.new SILENCE_5
  end

  def teardown
    File.unlink @filename_1
    File.unlink @filename_2
  end

  def test_channels
    assert_equal 1, @aiff_1.info.channels
    assert_equal 2, @aiff_2.info.channels
    assert_equal 1, @aiff_3.info.channels
    assert_equal 1, @aiff_4.info.channels
    assert_equal 4, @aiff_5.info.channels
  end

  def test_length
    assert_equal 2, @aiff_1.info.length
    assert_equal 0.1, @aiff_2.info.length
    assert_equal 1, @aiff_3.info.length
    assert_equal 3.5, @aiff_4.info.length
    assert_equal 1, @aiff_5.info.length
  end

  def test_bitrate
    assert_equal 176400, @aiff_1.info.bitrate
    assert_equal 1536000, @aiff_2.info.bitrate
    assert_equal 128000, @aiff_3.info.bitrate
    assert_equal 128000, @aiff_4.info.bitrate
    assert_equal 512000, @aiff_5.info.bitrate
  end

  def test_sample_rate
    assert_equal 11025, @aiff_1.info.sample_rate
    assert_equal 48000, @aiff_2.info.sample_rate
    assert_equal 8000, @aiff_3.info.sample_rate
    assert_equal 8000, @aiff_4.info.sample_rate
    assert_equal 8000, @aiff_5.info.sample_rate
  end

  def test_sample_size
    assert_equal 16, @aiff_1.info.sample_size
    assert_equal 16, @aiff_2.info.sample_size
    assert_equal 16, @aiff_3.info.sample_size
    assert_equal 16, @aiff_4.info.sample_size
    assert_equal 16, @aiff_5.info.sample_size
  end

  def test_not_aiff
    assert_raises(Mutagen::AIFF::AIFFError) { Mutagen::AIFF::AIFFData.new File.expand_path('../../README.md', __FILE__) }
  end

  def test_pprint
    assert @aiff_1.respond_to? :pprint
    refute_nil @aiff_1.pprint
    assert @aiff_tmp_id3.respond_to? :pprint
    refute_nil @aiff_tmp_id3.pprint
  end

  def test_delete_tags
    @aiff_tmp_id3.delete_tags
    assert_empty @aiff_tmp_id3.tags
    assert_nil Mutagen::AIFF::AIFFData.new(@filename_1).tags
  end

  def test_module_delete
    Mutagen::AIFF::delete_chunk(@filename_1)
    assert_nil Mutagen::AIFF::AIFFData.new(@filename_1).tags
  end

  def test_module_double_delete
    Mutagen::AIFF::delete_chunk(@filename_1)
    Mutagen::AIFF::delete_chunk(@filename_1)
  end

  def test_pprint_no_tags
    @aiff_tmp_id3.instance_variable_set(:@tags, nil)
    refute_nil @aiff_tmp_id3.pprint
  end

  def test_save_no_tags
    @aiff_tmp_id3.instance_variable_set(:@tags, nil)
    assert_raises(RuntimeError) { @aiff_tmp_id3.save_tags }
  end

  def test_add_tags_already_there
    refute_empty @aiff_tmp_id3.tags
    assert_raises(Mutagen::AIFF::AIFFError) { @aiff_tmp_id3.add_tags }
  end

  def test_mime
    assert_includes @aiff_1.mime, 'audio/aiff'
    assert_includes @aiff_1.mime, 'audio/x-aiff'
  end

  def test_loaded_tags
    assert_equal 'AIFF title', @aiff_tmp_id3['TIT2'].to_s
  end

  def test_roundtrip
    assert_equal ['AIFF title'], @aiff_tmp_id3['TIT2'].to_a
    @aiff_tmp_id3.save_tags
    new = Mutagen::AIFF::AIFFData.new @aiff_tmp_id3.filename
    assert_equal ['AIFF title'], new['TIT2'].to_a
  end

  def test_save_tags
    tags = @aiff_tmp_id3.tags
    tags.add Mutagen::ID3::Frames::TIT1.new(encoding:3, text:'foobar')
    tags.save
    new = Mutagen::AIFF::AIFFData.new @aiff_tmp_id3.filename
    assert_equal %w(foobar), new['TIT1'].to_a
  end

  def test_save_with_ID3_chunk
    @aiff_tmp_id3['TIT1'] = Mutagen::ID3::Frames::TIT1.new(encoding:3, text:'foobar')
    @aiff_tmp_id3.save_tags
    assert_equal 'foobar', Mutagen::AIFF::AIFFData.new(@filename_1)['TIT1'].to_s
    assert_equal 'AIFF title', @aiff_tmp_id3['TIT2'].to_s
  end

  def test_save_without_ID3_chunk
    @aiff_tmp_no_id3['TIT1'] = Mutagen::ID3::Frames::TIT1.new(encoding:3, text:'foobar')
    @aiff_tmp_no_id3.save_tags
    assert_equal 'foobar', Mutagen::AIFF::AIFFData.new(@filename_2)['TIT1'].to_s
  end
end

class TestAIFFInfo < MiniTest::Test
  def test_empty
    fileobj = StringIO.new ''
    assert_raises(Mutagen::AIFF::InvalidChunk) { Mutagen::AIFF::AIFFInfo.new fileobj}
  end
end