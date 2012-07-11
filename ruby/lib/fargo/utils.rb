module Fargo
  module Utils

    def generate_key lock
      lock_bytes = lock.bytes.to_a
      bytes = []
      bytes << (lock_bytes[0] ^ lock_bytes[-1] ^ lock_bytes[-2] ^ 5)

      (1..lock.length-1).each{ |i|
        bytes << (lock_bytes[i] ^ lock_bytes[i - 1])
      }

      key = ''
      bytes.each{ |b| key << encode_char(((b << 4) | (b >> 4)) & 0xff) }
      key
    end

    # Generates a lock between 80 and 134 random characters, and a pk of 16
    # random characters. At least in theory, other clients were doing exactly
    # this, so I just mirrored them.
    def generate_lock
      lock = 'EXTENDEDPROTOCOL'
      [lock + ('ABC' * 6), 'ABCD' * 4]
    end

    def encode_char c
      # Watch out for those special ones...
      if [0, 5, 36, 96, 124, 126].include? c
        sprintf '/%%DCN%03d%%/', c
      else
        c.chr
      end
    end

  end
end
