require 'mutagen/util'
require 'pp'

module Mutagen
  # An abstract object wrapping tags and
  # audio stream information
  class FileType
    include Util::HashMixin

    # Stream information (length, bitrate, sample rate)
    attr :info

    # Metadata tags, if any
    attr :tags

    MIMES = ['appliation/octet-stream']

    def initialize(filename=nil, *args, **kwargs)
      if filename.nil?
        raise ArgumentError, 'FileType constructor requires a filename'
      end
      self.load(filename, *args, **kwargs)
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
      @tags.save(filename, ** kwargs)
    end

    # TODO: make this work with 'pp' or 'to_s'
    # Print stream information and comment key=value pairs
    def pprint
      stream = "#{@info.pprint} #{mime[0]}"
      tags = tags.pretty_inspect
      stream + tags
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
      self.class.ancestors.each do |parent|
        if parent.const_defined? 'MIMES'
          parent.const_get('MIMES').each do |mime|
            unless mimes.include? mime
              mimes << mime
            end
          end
        end
      end
      mimes
    end

    def self.score(filename, file, header)
      raise NotImplementedError
    end
  end
end