module Fargo
  module Utils
    
    # Lord knows why they're doing this...
    def generate_key lock
      lock_bytes = lock.bytes.to_a
      bytes = []
      bytes << (lock_bytes[0] ^ lock_bytes[-1] ^ lock_bytes[-2] ^ 5)
      (1..lock.length-1).each{ |i| bytes << (lock_bytes[i] ^ lock_bytes[i - 1]) }
      key = ''
      bytes.each{ |b| key << encode_char(((b << 4) | (b >> 4)) & 0xff) }
      key
    end
  
    # Generates a lock between 80 and 134 random characters, and a pk of 16 random characters.
    def generate_lock
      lock = 'EXTENDEDPROTOCOL'
      [lock + ('ABC' * 6), 'ABCD' * 4]
    end
  
    # Watch out for those special ones...
    def encode_char c
      if [0, 5, 36, 96, 124, 126].include? c
        sprintf "/%%DCN%03d%%/", c
      else
        c.chr
      end
    end               
  end
end
