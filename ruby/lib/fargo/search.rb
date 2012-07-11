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

    # Creates a new search object from the specified parameters
    #
    # Recognized options:
    #   :query => (String|nil) the string to search the hub for. No escaping or
    #             anything is necessary. Default = nil
    #   :pattern => (String|nil) this is the raw pattern that is send on the
    #               socket to the hub. Spaces should be replaced with '$'. When
    #               in doubt, provide an arbitrary string via the :query option.
    #               Overrides the :query parameter given
    #   :filetype => (Integer) The filetype option to search. This is used to
    #                restrict results returned. The options are:
    #                   Fargo::Search::ANY
    #                   Fargo::Search::AUDIO
    #                   Fargo::Search::COMPRESSED
    #                   Fargo::Search::DOCUMENT
    #                   Fargo::Search::EXECUTABLE
    #                   Fargo::Search::PICTURE
    #                   Fargo::Search::VIDEO
    #                   Fargo::Search::FOLDER
    #                   Fargo::Search::TTH
    #                Default is Fargo::Search::ANY
    #   :size => (Integer|nil) the size parameter to send with the search query.
    #            See the below two options for what this parameter can
    #            indicate. Default = nil
    #   :size_restricted => (true|false) whether the search should restrict
    #                       results based on the size given in the :size
    #                       option. Default = false
    #   :is_minimum_size => (true|false) if the :size_restricted key is given
    #                       along with :size, this key says whether the the size
    #                       is to be considered a minimum size or a maximum
    #                       size. Default = false
    #
    # @param [Hash] opts the supplied options for the query.
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
