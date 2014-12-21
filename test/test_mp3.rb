require_relative 'test_helper'

class TestMP3 < MiniTest::Test
  SILENCE = File.expand_path('../data/silence-44-s.mp3', __FILE__)
  SILENCE_NOV2 = File.expand_path('../data/silence-44-s-v1.mp3',__FILE__)
  SILENCE_MPEG2 = File.expand_path('../data/silence-44-s-mpeg2.mp3',__FILE__)
  SILENCE_MPEG25 = File.expand_path('../data/silence-44-s-mpeg25.mp3',__FILE__)

  def setup
  	@original = File.expand_path('../data/silence-44-s.mp3',__FILE__)
  	@filename = Tempfile.new(%w(silence .mp3))
  	@filename.close
  	FileUtils.cp @original, @filename.path

  	# @mp3 = Mutagen::MP3::MP3.new @filename.path
  	# @mp3_2 = Mutagen::MP3::MP3.new SILENCE_NOV2
  	# @mp3_3 = Mutagen::MP3::MP3.new SILENCE_MPEG2
  	# @mp3_4 = Mutagen::MP3::MP3.new SILENCE_MPEG25
  end

  def teardown 
  	File.unlink @filename
  end

  # def test_mode
  # 	assert_equal @mp3.info.mode, Mutagen::MP3::JOINTSTEREO
  # end
end
