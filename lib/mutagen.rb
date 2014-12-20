require 'mutagen/version'
require 'mutagen/metadata'
require 'mutagen/util'
require 'mutagen/id3'
require 'mutagen/aiff'
require 'mutagen/apev2'
require 'mutagen/asf'

module Mutagen

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
