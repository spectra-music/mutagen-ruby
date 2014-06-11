require 'test_helper'

class TestMetadata < MiniTest::Test
  class FakeMeta < Mutagen::Metadata
    def initialize
    end
  end

  def test_virtual_constructor
    assert_raises(NotImplementedError) { Mutagen::Metadata.new 'filename' }
  end

  def test_load
    m = Mutagen::Metadata.new
    assert_raises(NotImplementedError) { m.load 'filename' }
  end

  def test_virtual_save
    assert_raises(NotImplementedError) { FakeMeta.new.save }
    assert_raises(NotImplementedError) { FakeMeta.new.save 'filename' }
  end

  def test_virtual_delete
    assert_raises(NotImplementedError) { FakeMeta.new.delete }
    assert_raises(NotImplementedError) { FakeMeta.new.delete 'filename' }
  end
end

# Can't test FileType yet (we need vorbis etc..)
# class TestFileType < MiniTest::Test
#   def setup
#
#   end
# end