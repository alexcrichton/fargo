module Fargo
  module Supports
    module Searches
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_search_caches
      end

      # see parser#@@search for what's passed in
      #
      # searches this client's files based on those options and returns an array
      # of SearchResult(s)
      def search_files options
        # TODO: implement me
        []
      end

      def search_hub query
        raise ConnectionError.new('Not connected Yet!') unless connected?

        if config.passive
          location = "Hub:#{config.nick}"
        else
          location = "#{config.address}:#{config.search_port}"
        end

        hub.send_message 'Search', "#{location} #{query.to_s}"
      end

      def search search
        raise ConnectionException.new 'Not connected yet!' unless connected?

        search                       = normalize search
        @searches[search.to_s]       = []
        @search_objects[search.to_s] = search
        search_hub search
      end

      def searches
        @searches.keys.map { |k| @search_objects[k] }
      end

      def search_results search
        search = normalize search
        @searches[search.to_s]
      end

      def remove_search search
        search = normalize search
        @searches.delete search.to_s
        @search_objects.delete search.to_s
      end

      protected

      def normalize search
        unless search.is_a? Fargo::Search
          search = Fargo::Search.new :query => search
        end

        search
      end

      def initialize_search_caches
        @searches       = {}
        @search_objects = {}

        channel.subscribe do |type, map|
          if type == :search_result
            @searches.keys.each do |search|
              if @search_objects[search].matches_result?(map)
                @searches[search] << map
              end
            end
          elsif type == :hub_disconnected
            @searches.clear
            @search_objects.clear
          end
        end
      end

    end
  end
end
