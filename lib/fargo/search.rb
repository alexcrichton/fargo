module Fargo
  class Search

    ANY        = 1
    AUDIO      = 2
    COMPRESSED = 3
    DOCUMENT   = 4
    EXECUTABLE = 5
    VIDEO      = 7
    FOLDER     = 8
    TTH        = 9

    attr_accessor :size_restricted, :is_minimum_size, :size, :filetype, :pattern

    def initialize opts = {}
      @size_restricted = opts[:size_restricted]
      @is_minimum_size = opts[:is_minimum_size]
      @size            = opts[:size]
      @filetype        = opts[:filetype] || ANY

      if opts[:pattern]
        @pattern = opts[:pattern]
      elsif opts[:query]
        self.query = opts[:query]
      end
    end

    def query= query
      @pattern = query.split(' ').join('$')
    end

    def queries
      pattern.split('$')
    end

    def query
      pattern.gsub('$', ' ')
    end

    def matches? map
      if map.is_a?(Listing)
        listing = map
        map     = {
          :file => listing.name,
          :size => listing.size,
          :tth  => listing.tth
        }
      end

      file = map[:file].downcase

      if @filetype == TTH
        matches_query = (@pattern =~ /^TTH:(\w+)$/ && map[:tth] == $1)
      else
        matches_query = queries.inject(true) do |last, word|
          last && file.index(word.downcase)
        end
      end

      if size_restricted == 'T'
        if is_minimum_size
          matches_query && map[:size] > size
        else
          matches_query && map[:size] < size
        end
      else
        matches_query
      end
    end

    def to_s
      if size_restricted
        "#{size_restricted ? 'T' : 'F' }?#{!size_restricted || is_minimum_size ? 'T' : 'F'}?#{size || 0}?#{filetype}?#{pattern}"
      else
        "F?T?#{size || 0}?#{filetype}?#{pattern}"
      end
    end

  end
end
