module Fargo
  module Supports

    # Provides the functionality for searching the hub for files based on
    # various criterion. Searches are stored and are then able to be reviewed,
    # but are periodically cleaned out.
    module Searches
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_search_caches
      end

      # Searches the hub based on the specified search object.
      #
      # @param [Fargo::Search, String] search either a string representing the
      #   query to search by, or a Search object containing the data about the
      #   search query.
      # @raises [ConnectionError] if the hub isn't connected yet
      def search search
        raise ConnectionException.new 'Not connected yet!' unless connected?

        search = normalize search
        @searches[search.to_s]       = []
        @search_objects[search.to_s] = search
        search_hub search

        # 10 minutes from now, we don't care about the search.
        EventMachine.add_timer(600) { remove_search search }
      end

      # Return an array of all of the queries sent as search that we currently
      # remember.
      #
      # @return [Array<String>] all queries sent to the hub
      def searches
        search_objects.map{ |s| s.query }
      end

      # Returns the objects that represent the searches sent to the hub
      #
      # @return [Array<Fargo::Search>] all searches sent to the hub.
      def search_objects
        @searches.keys.map { |k| @search_objects[k] }
      end

      # Returns the search results for a search.
      #
      # @param [Fargo::Search, String] the search sent to the hub either in its
      #   string form or Fargo::Search form
      def search_results search
        search = normalize search
        @searches[search.to_s]
      end

      # Removes records of a search.
      #
      # @param [Fargo::Search, String] the search sent to the hub either in its
      #   string form or Fargo::Search form
      def remove_search search
        search = normalize search
        @searches.delete search.to_s
        @search_objects.delete search.to_s
      end

      protected

      # Searches the hub based on the query specified. The query will be
      # serialized via #to_s.
      #
      # @param [Object] query the query to send to the hub
      # @raises [ConnectionError] if the hub isn't connected yet
      def search_hub query
        raise ConnectionError.new('Not connected Yet!') unless connected?

        if config.passive_search
          location = "Hub:#{config.nick}"
        else
          location = "#{config.address}:#{config.search_port}"
        end

        hub.send_message 'Search', "#{location} #{query.to_s}"
      end

      # Normalizes a search to be a Fargo::Search object
      #
      # @param [Fargo::Search, String] the search object or query string
      # @return [Fargo::Search] represents the query specified.
      def normalize search
        if search.is_a? Search
          search
        else
          Search.new :query => search
        end
      end

      def initialize_search_caches
        @searches       = {}
        @search_objects = {}

        channel.subscribe do |type, map|
          if type == :search_result
            map[:tth] = map[:hub] if map[:hub] =~ /^TTH:/

            @searches.keys.each do |search|
              if @search_objects[search].matches?(map)
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
