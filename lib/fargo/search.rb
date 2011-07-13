module Fargo
  class Search

    ANY        = 1
    AUDIO      = 2
    COMPRESSED = 3
    DOCUMENT   = 4
    EXECUTABLE = 5
    PICTURE    = 6
    VIDEO      = 7
    FOLDER     = 8
    TTH        = 9

    # See http://www.teamfair.info/wiki/index.php?title=$Search for the full
    # list of extensions and what they map to
    EXTENSIONS = {
      AUDIO       => [/mp(2|3)/, 'wav', 'au', /(r|s)m/, 'mid', 'flac', 'm4a'],
      COMPRESSED  => ['zip', 'arj', 'rar', 'lzh', 'gz', 'z', 'arc', 'pak'],
      DOCUMENT    => [/docx?/, 'txt', 'wri', 'pdf', 'ps', 'tex'],
      EXECUTABLE  => ['pm', 'exe', 'bat', 'com'],
      PICTURE     => ['gif', /jpe?g/, 'bmp', 'pcx', 'png', 'wmf', 'psd'],
      VIDEO       => [/mpe?g/, 'avi', 'asf', 'mov', 'mkv']
    }

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

      file = map[:file].try(:downcase) || ''

      if @filetype == TTH
        matches_query = (@pattern =~ /^TTH:(\w+)$/ && map[:tth] == $1)
      else
        matches_query = queries.inject(true) do |last, word|
          last && file.index(word.downcase)
        end

        patterns = EXTENSIONS[@filetype]

        if patterns && matches_query
          ext = File.extname file
          matches_query = patterns.any?{ |p| ext =~ /^\.#{p}$/i }
        end
      end

      if size_restricted
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
      suffix = "?#{size || 0}?#{filetype}?#{pattern}"

      if size_restricted
        "#{size_restricted ? 'T' : 'F' }?#{!size_restricted || is_minimum_size ? 'T' : 'F'}" + suffix
      else
        "F?T" + suffix
      end
    end

  end
end
