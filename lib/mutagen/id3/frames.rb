require 'mutagen/id3/util'
require 'mutagen/id3/specs'

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

  def initialize(*args, **kwargs)
    if args.size == 1 and kwargs.size == 0 and args[0].is_a? self.class
      other = args[0]
      @framespec.each do |checker|
        #if other.instance_variable_defined?('@'+checker.name)
        begin
          val = checker.validate(self, other.instance_variable_get('@'+checker.name))
        rescue ArgumentError => ae
          raise ae.exception("#{checker.name}: #{ae.message}")
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
        rescue ArgumentError => ae
          raise ae.exception("#{checker.name}: #{ae.message}")
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
    @name
  end
end

end
