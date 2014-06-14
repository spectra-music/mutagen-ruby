module Mutagen
  module ID3
    # An unknown type of file with ID3 tags
    class ID3FileType < Mutagen::FileType
      def initialize
        @id3 = Mutagen::ID3::ID3Data
        super
      end

      class Info < Mutagen::StreamInfo
        def initialize(fileobj, offset)
          @length = 0
        end
        def pprint(**kwargs)
          'Unknown format with ID3 tag'
        end
      end

      def score(filename, fileobj, header)
        header.start_with? 'ID3'
      end


      # Add an empty ID3 tag to the file
      #
      # A custom tag reader may be  used instead of the default
      # Mutagen::ID3::ID3Data
      def add_tags(id3:nil)
        id3 = @id3 if id3.nil?
        if @tags.nil?
          @id3 = id3
          @tags = id3.new
        else
          raise 'An ID3 tag already exists'
        end
      end

      # Load stream and tag information from a file.
      #
      # A custom tag reader may be used in instead of the default
      # mutagen.id3.ID3 object, e.g. an EasyID3 reader.
      def load(filename, id3:nil, **kwargs)
        if id3.nil?
          id3 = @id3
        else
          # If this was initialized with EasyID3, remember that for
          # when tags are auto-instantiated in add_tags.
          @id3 = id3
        end

        @filename = filename

        begin
          @id3 = id3.new(filename, **kwargs)
        rescue
          @tags = nil
        end
        unless @tags.nil?
          begin
            @offset = @tags.size
          rescue NoMethodError
            # ignore
          end
        end
        begin
          File.open(filename, 'r') do |f|
            @info = Info(f, @offset)
          end
        end
      end
    end
  end
end