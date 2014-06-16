require 'mutagen/id3/util'
module Mutagen
  module ID3
    module Specs

      class Spec
        attr_reader :name

        def initialize(name)
          @name = name
        end

        # return a possible modified value which, if
        # written, results in valid id3v2.3 data
        def _validate23(frame, value, ** kwargs)
          value
        end
      end


      class ByteSpec < Spec
        def read(frame, data)
          return data[0].ord, data[1..-1]
        end

        def write(frame, value)
          raise TypeError, 'value is not a Numeric' unless value.is_a? Numeric
          value.chr
        end

        def validate(frame, value)
          begin
            value.chr unless value.nil?
          rescue RangeError
            raise Mutagen::ValueError, "#{value} cannot be converted to char"
          end
          value
        end
      end

      class IntegerSpec < Spec
        def read(frame, data)
          BitPaddedInteger.new(data, bits:8).to_int
        end

        def write(frame, value)
          BitPaddedInteger.to_str(value, bits: 8, width: -1)

        end

        def validate(frame, value)
          value
        end
      end

      class SizedIntegerSpec < Spec
        def initialize(name, size)
          @name = name
          @size = size
        end

        def read(frame, data)
          return BitPaddedInteger.new(data[0...@size], bits: 8).to_int, data[@size..-1]
        end

        def write(frame, value)
          BitPaddedInteger.to_str(value, bits: 8, width: @size)
        end

        def validate(frame, value)
          value
        end
      end

      class EncodingSpec < ByteSpec
        def read(frame, data)
          enc, data = super(frame, data)
          if enc < 16
            return enc, data
          else
            return 0, (enc.chr + data)
          end
        end

        def validate(frame, value)
          return nil if value.nil?
          return value if 0 <= value.to_i and value.to_i <= 3
          raise Mutagen::ValueError, "Invalid Encoding: #{value}"
        end

        def _validate23(frame, value, ** kwargs)
          # only 0, 1 are valid in v2.3, default to utf-16
          [1, value].min
        end
      end

      class StringSpec < Spec
        def initialize(name, length)
          super(name)
          @len = length
        end

        def read(frame, data)
          return data[0...@len], data[@len..-1]
        end

        def write(frame, value)
          if value.nil?
            "\x00" * @len
          else
            (value + "\x00" * @len)[0...@len]
          end
        end

        def validate(frame, value)
          if value.nil?
            return nil
          end

          unless value.is_a? String
            value = value.to_s.encode 'ASCII-8BIT'
          end

          if value.size == @len
            return value
          end
          raise Mutagen::ValueError, "Invalid StringSpec[#{@len}] data: #{value}"
        end
      end

      class BinaryDataSpec < Spec
        def read(frame, data)
          return data, ''
        end

        def write(frame, value)
          if value.nil?
            ''.b
          elsif value.is_a? String
            value.b
          else
            value.to_s.encode('ASCII-8BIT')
          end
        end

        def validate(frame, value)
          value.is_a?(String) ? value : value.to_s.encode('ascii')
        end
      end

      class EncodedTextSpec < Spec
        # Okay, seriously. This is private and defined explicitly and
        # completely by the ID3 specification. You can't just add
        # encodings here however you want.
        ENCODINGS = [
            ['ISO-8859-1', "\x00"], # aka Latin-1
            ['UTF-16', "\x00\x00"],
            ['UTF-16BE', "\x00\x00"],
            ['UTF-8', "\x00"]
        ]

        def initialize(*args)
          super(*args)
        end

        def read(frame, data)
          enc, term = ENCODINGS.fetch(frame.encoding)
          ret       = ''
          if term.bytesize == 1
            if data.include? term
              data, ret = data.split(term, 2)
            end
          else
            offset = -1
            while true
              offset = data.index(term, offset+1)
              break if offset.nil?
              next if offset & 1 != 0
              data, ret = data[0...offset], data[offset+2..-1]
              break
            end
          end
          if data.bytesize < term.bytesize
            return '', ret
          else
            return data.force_encoding(enc).encode('utf-8'), ret
          end
        end

        # @raise [NoMethodError] if value doesn't have `.encode`
        def write(frame, value)
          enc, term = ENCODINGS[frame.encoding]
          value.encode(enc) + term
        end

        def validate(frame, value)
          value.to_s
        end
      end

      class MultiSpec < Spec
        def initialize(name, *specs, ** kwargs)
          super(name)
          @specs = specs
          @sep   = kwargs[:sep]
        end

        def read(frame, data)
          values = []
          until data.empty?
            record = @specs.map do |spec|
              value, data = spec.read(frame, data)
              value
            end
            if @specs.size != 1
              values << record
            else
              values << record[0]
            end
          end
          return values, data
        end

        def write(frame, value)
          data = []
          if @specs.size == 1
            value.each do |v|
              data << @specs[0].write(frame, v)
            end
          else
            value.each do |record|
              record.zip(@specs).each do |v, s|
                data << s.write(frame, v)
              end
            end
          end
          data.join
        end

        def validate(frame, value)
          return [] if value.nil?

          if not @sep.nil? and value.is_a? String
            value = value.split(@sep)
          end

          if value.is_a? Array
            if @specs.size == 1
              return value.map { |v| @specs[0].validate(frame, v) }
            else
              return value.map { |val| val.zip(@specs).map { |v, s| s.validate(frame, v) } }
            end
          end
        end

        def _validate23(frame, value, ** kwargs)
          if @specs.size != 1
            return value.map { |val| val.zip(@specs).map { |v, s| s._validate23(frame, v, ** kwargs) } }
          end

          spec = @specs[0]

          # Merge single txt spec multispecs only
          # (TimeStampSpec) being the exception, but it's not a valid v2.3 frame
          if not spec.is_a? EncodedTextSpec or spec.is_a? TimeStampSpec
            return value
          end

          value = value.map { |v| spec._validate23(frame, v, ** kwargs) }
          if kwargs.has_key? :sep
            return [spec.validate(frame, kwargs[:sep].join(value))]
          end
          value
        end
      end

      class EncodedNumericTextSpec < EncodedTextSpec;
      end
      class EncodedNumericPartTextSpec < EncodedTextSpec;
      end

      # Latin1 is known as "ISO-8859-1" in Ruby
      class Latin1TextSpec < EncodedTextSpec
        def read(frame, data)
          if data.include? "\x00"
            data, ret = data.split("\x00".b, 2)
          else
            ret = ''
          end
          return data.encode, ret
        end

        def write(data, value)
          value.encode('ISO-8859-1') + "\x00"
        end

        def validate(frame, value)
          value.to_s
        end
      end


      # A time stamp in ID3v2 format.
      #
      # This is a restricted form of the ISO 8601 standard; time stamps
      # take the form of:
      #     YYYY-MM-DD HH:MM:SS
      # Or some partial form (YYYY-MM-DD HH, YYYY, etc.).
      #
      # The '@text' ivar contains the raw text data of the time stamp.
      class ID3TimeStamp
        include Comparable

        attr_accessor :year, :month, :day, :hour, :minute, :second

        def initialize(text)
          if text.is_a? ID3TimeStamp
            text = text.text
          elsif not text.is_a? String
            raise TypeError, "text is not a String: #{text}"
          end
          self.text = text
        end

        def formats
          ['%04d'] + ['%02d'] * 5
        end

        def seps
          ['-', '-', ' ', ':', ':', 'x']
        end

        def text
          parts  = [@year, @month, @day, @hour, @minute, @second]
          pieces = []
          parts.each_with_index do |part, i|
            break if part.nil?
            pieces << formats[i] % part + seps[i]
          end
          pieces.join[0...-1] unless pieces.empty?
        end


        def text=(text, splitre=/[-T:\/.]|\s+/)
          year, month, day, hour, minute, second =
              (text + ':::::').split(splitre)[0...6]
          [:year, :month, :day, :hour, :minute, :second].each do |a|
            v = if binding.local_variable_defined?(a) and
                binding.local_variable_get(a) =~ /^\d+$/
                  binding.local_variable_get(a).to_i
                end
            instance_variable_set("@#{a.to_s}", v)
          end
        end

        alias_method :to_s, :text

        def ==(other)
          text == other.text
        end

        def <=>(other)
          return nil unless other.is_a? ID3TimeStamp
          text <=> other.text
        end

        def encode!(*args)
          self.text = text.encode(*args)
        end

        def encode(*args)
          text.encode(*args)
        end
      end

      class TimeStampSpec < EncodedTextSpec
        def read(frame, data)
          value, data = super(frame, data)
          return validate(frame, value), data
        end

        def write(frame, data)
          super frame, data.text.sub(' ', 'T')
        end

        def validate(frame, value)
          begin
            return ID3TimeStamp.new(value)
          rescue TypeError
            raise Mutagen::ValueError, "Invalid ID3TimeStamp: #{value}"
          end
        end
      end

      class ChannelSpec < ByteSpec
        (OTHER, MASTER, FRONTRIGHT, FRONTLEFT, BACKRIGHT, BACKLEFT, FRONTCENTRE, BACKCENTRE, SUBWOOFER) = (0...9).to_a
      end

      class VolumeAdjustmentSpec < Spec
        def read(frame, data)
          value, _ = data[0...2].unpack('s>')
          return value/512.0, data[2..-1]
        end

        def write(frame, value)
          number = (value*512).round
          unless -32768 <= number and number <= 32767
            raise Mutagen::ValueError, 'Short out of range'
          end
          [number].pack('s>')
        end

        def validate(frame, value)
          unless value.nil?
            self.write(frame, value) # This transparently passes the exception up
          end
          value
        end
      end

      class VolumePeakSpec < Spec
        def read(frame, data)
          # http://bugs.xmms.org/attachment.cgi?id=113&action=view
          peak  = 0
          bits  = data[0].ord
          bytes = [4, ((bits + 7) >> 3)].min
          # not enough frame data
          if bytes + 1 > data.size
            raise ID3JunkFrameError
          end
          shift = ((8 - (bits & 7)) & 7) + (4 - bytes) * 8
          (1..bytes).each do |i|
            peak *= 256
            peak += data[i].ord
          end
          peak *= 2 ** shift
          return (peak.to_f / (2**31-1)), data[1+bytes..-1]
        end

        def write(frame, value)
          number = (value*32768).round
          unless 0 <= number and number <= 65535
            raise Mutagen::ValueError, 'Unsigned Short out of range'
          end
          # Always write as 16bits for sanity
          "\x10" + [number].pack('S>')
        end

        def validate(frame, value)
          unless value.nil?
            self.write(frame, value)
          end
          value
        end
      end

      class SynchronizedTextSpec < EncodedTextSpec
        def read(frame, data)
          texts          = []
          encoding, term = ENCODINGS[frame.encoding]
          until data.empty?
            l         = term.size
            value_idx = data.index(term)
            raise ID3JunkFrameError if value_idx.nil?
            value = data[0...value_idx].encode
            raise ID3JunkFrameError if data.size < value_idx + l + 4
            time, _ = data[value_idx + l ... value_idx + l + 4].unpack('I!>')
            texts << [value, time]
            data = data[value_idx+l+4..-1]
          end
          return texts, ''
        end

        def write(frame, value)
          data           = []
          encoding, term = ENCODINGS[frame.encoding]
          frame.text.each do |text, time|
            text = text.encode(encoding) + term
            data << text + [time].pack('I>')
          end
          data.join
        end

        def validate(frame, value)
          value
        end
      end

      class KeyEventSpec < Spec
        def read(frame, data)
          events = []
          while data.size >= 5
            events << data[0...5].unpack('cI!>')
            data = data[5..-1]
          end
          return events, data
        end

        def write(frame, value)
          value.map { |event| event.pack('cI!>') }.join
        end

        def validate(frame, value)
          value
        end
      end

# Not to be confused with VolumeAdjustmentSpec
      class VolumeAdjustmentsSpec < Spec
        def read(frame, data)
          adjustments = {}
          while data.size >= 4
            freq, adj         = data[0...4].unpack('S>s>')
            data              = data[4..-1]
            freq              /= 2.0
            adj               /= 512.0
            adjustments[freq] = adj
          end
          adjustments = adjustments.to_a
          adjustments.sort!
          return adjustments, data
        end

        def write(frame, value)
          value.sort!
          value.map { |freq, adj| [(freq * 2).to_i, (adj * 512).to_i].pack('S>s>') }.join
        end

        def validate(frame, value)
          value
        end
      end

      class ASPIIndexSpec < Spec
        def read(frame, data)
          if frame.b == 16
            format = 'S>'
            size   = 2
          elsif frame.b == 8
            format = 'C'
            size   = 1
          else
            warn "invalid bit count in ASPI (#{frame.b})"
            return [], data
          end
          indexes = data[0 ... frame.N * size]
          data    = data[frame.N * size .. -1]
          return indexes.unpack(format * frame.N), data
        end

        def write(frame, values)
          if frame.b == 16
            format = 'S>'
          elsif frame.b == 8
            format = 'C'
          else
            raise ValueError, "frame.b must be 8 or 16, not #{frame.b}"
          end
          values.pack(format * frame.N)
        end

        def validate(frame, values)
          values
        end
      end
    end
  end
end