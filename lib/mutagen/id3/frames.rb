require 'mutagen/id3/util'
require 'mutagen/id3/specs'
require 'zlib'

module Mutagen::ID3

# Fundamental unit of ID3 data.
#
# ID3 tags are split into frames. Each frame has a potentially
# different structure, and so this base class is not very featureful.
class Frame

  FLAG23_ALTERTAG = 0x8000
  FLAG23_ALTERFILE = 0x4000
  FLAG23_READONLY = 0x2000
  FLAG23_COMPRESS = 0x0080
  FLAG23_ENCRYPT = 0x0040
  FLAG23_GROUP = 0x0020

  FLAG24_ALTERTAG = 0x4000
  FLAG24_ALTERFILE = 0x2000
  FLAG24_READONLY = 0x1000
  FLAG24_GROUPID = 0x0040
  FLAG24_COMPRESS = 0x0008
  FLAG24_ENCRYPT = 0x0004
  FLAG24_UNSYNCH = 0x0002
  FLAG24_DATALEN = 0x0001

  attr_accessor :encoding

  def initialize(*args, **kwargs)
    @framespec = []
    if args.size == 1 and kwargs.size == 0 and args[0].is_a? self.class
      other = args[0]
      @framespec.each do |checker|
        #if other.instance_variable_defined?('@'+checker.name)
        begin
          val = checker.validate(self, other.instance_variable_get('@'+checker.name))
        rescue ValueError => e
          raise e.exception("#{checker.name}: #{e.message}")
        end
        #else
        #  raise "#{checker.name}: No instance variable for checker on #{other}"
        #end
        instance_variable_set('@'+checker.name, val)
      end
    else
      @framespec.zip(args) do |checker, val|
        instance_variable_set('@'+checker.name, checker.validate(self, val))
      end
      @framespec[args.size..-1].each do |checker|
        begin
          # TODO: does checker.name.to_sym improve performance?
          validated = checker.validate(self, kwargs[checker.name])
        rescue ValueError => e
          raise e.exception("#{checker.name}: #{e.message}")
        end
        instance_variable_set('@'+checker.name, validated)
      end
    end
  end

  # Returns a frame copy which is suitable for writing into a v2.3 tag
  #
  # kwargs get passed to the specs
  def _get_v23_frame(**kwargs)
    new_kwargs = {}
    @framespec.each do |checker|
      name = checker.name
      value = instance_variable_get('@'+name)
      new_kwargs[name] = checker._validate23(value, **kwargs)
    end
    self.class.new(**new_kwargs)
  end

  # An internal key used to ensure frame uniqueness in a tag
  def hash_key
    frame_id
  end

  # ID3v2 three or four character frame ID
  def frame_id
    this.class.to_s
  end

  # represention of a frame
  # The string returned is a valid ruby expression
  # to construct a copy of this frame
  def repr
    kw = []
    @framespec.each do |attr|
      kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
    end
    "#{this.class.to_s}.new(#{kw.join(', ')})"
  end

  protected
  def read_data(data)
    odata = data
    @framespec.each do |reader|
      raise ID3JunkFrameError if data.emtpy?
      begin
        value, data = reader.read(self, data)
      #rescue
      #  raise ID3JunkFrameError
      end
      instance_variable_set('@'+reader.name, value)
    end
    leftover = Mutagen.strip_arbitrary(data, "\x00")
    unless leftover.empty?
      warn "Leftover data: #{self.class}: #{data} (from #{odata})"
    end
  end

  def write_data
    data = []
    @framespec.each do |writer|
      data << writer.write(self, instance_variable_get('@'+writer.name))
    end
    data.join
  end

  def to_s
    '[unrepresentable data]'
  end

  def inspect
    "#<#{self.class} #{self.to_s}>"
  end


  # Construct this ID3 frame from raw string dta
  def self.from_data(id3, tflags, data)
    if id3._V24 <= id3.version
      if tflags & (Frame::FLAG24_COMPRESS | Frame::FLAG24_DATALEN)
        # The data length int is syncsafe in 2.4 (but not 2.3).
        # However, we don't actually need the data length int,
        # except to work around a QL 0.12 bug, and in that case
        # all we need are the raw bytes.
        datalen_bytes = data[0...4]
        data = data[4..-1]
      end
      if tflags & Frame::FLAG24_UNSYNCH or id3.f_unsynch
        begin
          data = Unsynch.decode data
        rescue ValueError => err
          raise ID3BadUnsynchData, "#{err}:#{data}" if id3.PEDANTIC
        end
      end
      raise ID3EncryptionUnsupportedError if tflags & Frame::FLAG24_ENCRYPT
      if tflags & Frame::FLAG24_COMPRESS
      begin
        data = Zlib::Deflate(data)
      rescue Zlib::Error
        # the initial mutagen that went out with QL 0.12 did not
        # write the 4 bytes of uncompressed size. Compensate.
        data = datalen_bytes + data
        begin
          data = Zlib::Deflate(data)
        rescue Zlib::Error => err
          raise ID3BadCompressedData, "#{err}: #{data}" if id3.PEDANTIC
        end
      end
      end
    elsif id3._V23 <= id3.version
      if tflags & Frame::FLAG23_COMPRESS
        usize, _ = unpack('L>', data[0...4])
        data = data[4..-1]
      end
      raise ID3EncryptionUnsupportedError if tflags & Frame::FLAG23_ENCRYPT
      if tflags & Frame::FLAG23_COMPRESS
        begin
          data = Zlib::Deflate(data)
        rescue Zlib::Error => err
          raise ID3BadCompressedData, "#{err}: #{data}"
        end
      end
    end
    frame = self.class.new
    frame.raw_data = data
    frame.flags = tflags
    frame.read_data(data)
    frame
  end
end

# A frame with optional parts
#
# Some ID3 frames have optional data; this lass extnds Frame to
# provide support for those parts.
class FrameOpt < Frame
  @optionalspec = []

  def initialize
    @optionalspec = []
    super(*args, **kwargs)
    @optionalspec.each do |spec|
      if kwargs.has_key? spec.name
        validated = spec.validate(self, kwargs[spec.name])
        instance_variable_set('@'+spec.name, validated)
      else break
      end
    end
  end

  protected
  def read_data(data)
    odata = data
    @framespec.each do |reader|
      raise ID3JunkFrameError if data.empty?
      value, data = reader.read(self, data)
      instance_variable_set('@'+reader.name, value)
    end
    unless data.nil? or data.empty?
      @optionalspec.each do |reader|
        break if data.empty?
        value, data = reader.read(self, data)
        instance_variable_set('@'+reader.name, value)
      end
    end
    leftover = Mutagen.strip_arbitrary(data, "\x00")
    unless leftover.empty?
      warn "Leftover data: #{self.class}: #{data} (from #{odata})"
    end
  end

  def write_data
    data = []
    @framespec.each do |writer|
      data << writer.write(self, instance_variable_get('@'+writer.name))
    end
    @optionalspec.each do |writer|
      #TODO: Maybe we should store the ivar and check `.nil?` instead?
      break unless instance_variable_defined? '@'+writer.name
      data << writer.write(self, instance_variable_get('@'+writer.name))
    end
    data.join
  end


  def repr
    kw = []
    @framespec.each do |attr|
      kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
    end
    @optionalspec.each do |attr|
      if instance_variable_defined? '@'+attr.name
        kw << "#{attr.name} => #{instance_variable_get('@'+attr.name)}"
      end
    end
    "#{self.class}.new(#{kw.join(', ')})"
  end
end


# Text strings.
#
# Text frames support casts to unicode or str objects, as well as
# list-like indexing, extend, and append.
#
# Iterating over a TextFrame iterates over its strings, not its
# characters.
#
# Text frames have a 'text' attribute which is the list of strings,
# and an 'encoding' attribute; 0 for ISO-8859 1, 1 UTF-16, 2 for
# UTF-16BE, and 3 for UTF-8. If you don't want to worry about
# encodings, just set it to 3.
class TextFrame < Frame
  @framespec = [
      EncodingSpec.new('encoding'),
      MultiSpec.new('text', EncodedTextSpec.new('text'), sep:"\x00")
  ]
end

end
