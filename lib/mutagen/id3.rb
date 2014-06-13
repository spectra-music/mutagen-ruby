# ID3 Support for Mutagen


# ID3v2 reading and writing.
#
# This is based off of the following references:
#
# * http://id3.org/id3v2.4.0-structure
# * http://id3.org/id3v2.4.0-frames
# * http://id3.org/id3v2.3.0
# * http://id3.org/id3v2-00
# * http://id3.org/ID3v1
#
# Its largest deviation from the above (versions 2.3 and 2.2) is that it
# will not interpret the / characters as a separator, and will almost
# always accept null separators to generate multi-valued text frames.
#
# Because ID3 frame structure differs between frame types, each frame is
# implemented as a different class (e.g. TIT2 as {Mutagen::ID3::Frames::TIT2}). Each
# frame's documentation contains a list of its attributes.
#
# Since this file's documentation is a little unwieldy, you are probably
# interested in the {ID3} class to start with.

require 'mutagen/util'
require 'mutagen/metadata'
require 'mutagen/filetype'
require 'mutagen/streaminfo'
require 'mutagen/id3/id3data'
require 'mutagen/id3/util'
require 'mutagen/id3/specs'
require 'mutagen/id3/frames'
require 'mutagen/id3/filetype'

module Mutagen
  module ID3

    # Parse an ID3v1 tag, returning a list of ID3v2.4 frames.
    def self.parse_ID3v1(string)
      idx = string.index('TAG')
      return if idx.nil?
      string = string.fetch(idx)
      return if 128 < string.size or string.size < 124

      # Issue #69 - Previous versions of Mutagen, when encountering
      # out-of-spec TDRC and TYER frames of less than four characters,
      # wrote only the characters available - e.g. "1" or "" - into the
      # year field. To parse those, reduce the size of the year field.
      # Amazingly, "0s" works as a struct format string.
      unpack_fmt =  'a3a30a30a30a%da29CC' % (string.size - 124)

      val = string.unpack unpack_fmt
      return if val.include? nil# or val.any? {|i| i.empty?}
      tag, title, artist, album, year, comment, track, genre = val
      return if tag != 'TAG'

      def fix(string)
        string.split("\x00").first.strip.force_encoding('ISO-8859-1')
      end

      [title, artist, album, year, comment].map! { |e| fix e }

      frames = {}
      unless title.nil? or title.empty?
        frames['TIT2'] = TIT2.new encoding:0, text:title
      end
      unless artist.nil? or artist.empty?
        frames['TPE1'] = TPE1.new encoding:0, text:[artist]
      end
      unless album.nil? or album.empty?
        frames['TALB'] = TALB.new encoding:0, text:album
      end
      unless year.nil? or year.empty?
        frames['TDRC'] = TDRC.new encoding:0, text:year
      end
      unless comment.nil? or comment.empty?
        frames['COMM'] = COMM.new encoding:0, lang:'eng', desc:'ID3v1 Comment', text:comment
      end
      # Don't read a track number if it looks like the comment was
      # padded with spaces instead of nulls (thanks, WinAmp).
      if not track.nil? and not track.empty? and
          (track != 32 or string[-3] == "\x00")
        frames['TRCK'] = TRCK encoding:0, text:track.to_s
      end
      if genre != 255
        frames['TCON'] = TCON.new encoding:0, text:genre.to_s
      end
      frames
    end

    # Return an ID3v1.1 tag string from a Hash of ID3v2.4 frames
    # @param [Hash] id3
    def self.make_ID3v1(id3)
      v1 = {}

      {
          'TIT2' => 'title',
          'TPE1' => 'artist',
          'TALB' => 'album'
      }.each_pair do |v2id, name|
        text = id3.include?(v2id) ? id3[v2id].text.first.encode('ISO-8859-1', undef: :replace)[0...30] : ""
        v1[name] = text + ("\x00" * (30 - text.bytesize))
      end

      cmnt = id3.has_key?('COMM') ? id3['COMM'].text.first.encode('ISO-8859-1', undef: :replace)[0...28] : ""
      v1["comment"] = cmnt + ("\x00" * (29 - cmnt.size))

      if id3.has_key?('TRCK')
        v1['track'] =  begin
          (+id3.fetch('TRCK')).to_s
        rescue KeyError
          "\x00"
        end
      else
        v1['track'] = "\x00"
      end

      if id3.has_key?('TCON')

      end
    end
  end
end
