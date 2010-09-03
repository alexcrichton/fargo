module Fargo
  class Search
    
    autoload :Result
  
    ANY = 1
    AUDIO = 2
    COMPRESSED = 3
    DOCUMENT = 4
    EXECUTABLE = 5
    VIDEO = 7
    FOLDER = 8
  
    attr_accessor :size_restricted, :is_minimum_size, :size, :filetype, :pattern
  
    def initialize opts = {}
      self.size_restricted = opts[:size_restricted]
      self.is_minimum_size = opts[:is_minimum_size]
      self.size = opts[:size]
      self.filetype = opts[:filetype] || ANY
      if opts[:pattern]
        self.pattern = opts[:pattern]
      elsif opts[:query]
        self.query = opts[:query]
      end
    end
  
    def query= query
      self.pattern = query.split(' ').join('$')
    end
    
    def queries
      self.pattern.split("$")
    end
    
    def query
      self.pattern.gsub('$', ' ')
    end
    
    def matches_result? map
      file = map[:file].downcase
      matches_query = queries.inject(true) { |last, word| last && file.index(word.downcase) }
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