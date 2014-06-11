module Mutagen
  # An abstract dict-like object.
  # Metadata is the base class for many of the tag objects in Mutagen
  class Metadata
    def initialize(*args, **kwargs)
      if not args.empty? or not kwargs.empty?
        load(args, kwargs)
      end
    end

    def load(*args, **kwargs)
      raise NotImplementedError
    end

    # Save changes to a file
    def save(filename=nil)
      raise NotImplementedError
    end

    # Remove tags from a file
    def delete(filename=nil)
      raise NotImplementedError
    end
  end
end