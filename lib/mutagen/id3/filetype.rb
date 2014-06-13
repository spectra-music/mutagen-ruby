module Mutagen
  module ID3
    # An unknown type of file with ID3 tags
    class ID3FileType < Mutagen::FileType

      class Info < Mutagen::StreamInfo
        def initialize(fileobj, offset)
          @length = 0
        end
        def pprint
          'Unknown format with ID3 tag'
        end
      end

      def score(filename, fileobj, header)
        header.start_with? 'ID3'
      end


      # Add an empty ID3 tag to the file
      #
      # A custom tag reader may be  used instead of the default
      # Mutagen::ID3::ID3
      def add_tags(id3:nil)

      end

    end
  end
end