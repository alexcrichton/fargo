module Fargo
  module Supports
    module Searches
      extend ActiveSupport::Concern
      
      included do
        set_callback :setup, :after, :subscribe_to_searches
      end

      def search search
        raise ConnectionException.new 'Not connected yet!' unless connected?

        search                       = normalize search
        @searches[search.to_s]       = []
        @search_objects[search.to_s] = search
        search_hub search
      end

      def searches
        @searches.keys.map { |k| @search_objects[k] } if @searches
      end

      def search_results search
        search = normalize search
        @searches[search.to_s] if @searches
      end

      def remove_search search
        search = normalize search
        @searches.delete search.to_s if @searches
        @search_objects.delete search.to_s if @search_objects
      end

      private

      def normalize search
        unless search.is_a? Fargo::Search
          search = Fargo::Search.new :query => search
        end

        search
      end
            
      def subscribe_to_searches
        @searches       = {}
        @search_objects = {}
        
        subscribe do |type, map|
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
