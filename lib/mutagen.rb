require 'mutagen/version'
require 'mutagen/util'
require 'mutagen/id3'

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



  # An abstract object wrapping tags and
  # audio stream information
  class FileType
    include HashMixin

    # Stream information (length, bitrate, sample rate)
    attr :info

    # Metadata tags, if any
    attr :tags

    def initialize(filename=nil, *args, **kwargs)
      if filename.nil?
        raise ArgumentError, 'FileType constructor requires a filename'
      end
      load(filename, *args, **kwargs)
    end

    # Look up a metadata key.
    #
    # If the file has no tags at all, a KeyError is raised
    # @raise [KeyError] raised if file has no tags
    def [](key)
      raise KeyError, key if @tags.nil?
      @tags[key]
    end

    # Set a metadata key
    #
    # If the file has no tags, an appropriate format is added
    # (but not written until save is called)
    def []=(key, value)
      add_tags if @tags.nil?
      @tags[key] = value
    end

    # Delete a metadata tag key
    #
    # If the file has no tags at all, a KeyError is raised
    # @raise [KeyError] raised if file has no tags
    def delete
      raise KeyError, key if @tags.nil?
      @tags.delete(key)
    end

    # Return a list of keys in the metadata tag.
    #
    # If the file has no tags at all, an empty list is returned
    # @return [Array] list of keys
    def keys
      @tags.nil? ? [] : @tags.keys
    end

    # Remove tags from file.
    def delete_tags
      @tags.delete_tags(@filename) unless @tags.nil?
    end

    # Save metadata tags
    def save_tags(**kwargs)
      raise 'No tags in file' if @tags.nil?
      @tags.save_tags(filename, ** kwargs)
    end

    # TODO: make this work with 'pp' or 'to_s'
    # Print stream information and comment key=value pairs
    def pprint
      stream = "#{@info.pprint} #{@mime[0]}"
      tags = @tags.pprint
      stream + tags.join("\n")
    end

    # Adds new tags to the file
    #
    # Raises if tags already exist
    def add_tags
      raise NotImplementedError
    end

    # A list of mime types
    def mime
      mimes = []
      ancestors.each do |parent|
        if parent.class_variable_defined? '@@mimes'
          parent.class_variable_get('@@mimes').each do |mime|
            unless mimes.include? mime
              mimes << mime
            end
          end
        end
      end
    end

    def self.score(filename, file, header)
      raise NotImplementedError
    end
  end

  # Abstract stream information object
  # provides attributes for length, bitrate, sample rate, etc.
  # See the implementations for details
  class StreamInfo
    # Print the string information
    def to_s
      raise NotImplementedError
    end
  end

  # Guess the type of the file and try to open it.
  #
  # The file type is decided by several things, such as the first 128
  # bytes (which usually contains a file type identifier), the
  # filename extension, and the presence of existing tags.
  #
  # If no appropriate type could be found, nil is returned.
  #
  # @param filename [String] the file to try and open
  # @param easy [Bool] If the easy wrappers should be returned if available.
  #                    For example {MP3::EasyMP3} instead of {MP3::MP3}
  #
  # @param options [Array] Sequence of {FileType} implementations, defaults to
  #                        all included ones.
  # TODO: Make this take a block as a parameter
  def self.open(filename, options:nil, easy:false)
    if options.nil?
      #TODO: make this full-fledged once all implementation are done
      options = [Mutagen::MP3::MP3]
    end

    if options.empty?
      return nil
    end

    results = []
    File.open(filename, 'r') do |file|
      header = file.read(128)
      raise "couldn't read the header of #{file.path}" if header.nil?
      results = options.map { |kind| [kind.score(filename, file, header), kind.to_s] }
    end
    results = results.zip(options)
    results.sort
    score, name, kind = results.last.flatten
    if score > 0
      return kind.new(filename)
    else
      return nil
    end
  end
end
