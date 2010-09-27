module Fargo
  module Supports
    module Persistence

      def initialize *args
        @connection_cache = {}

        channel.subscribe do |type, hash|
          if type == :hub_disconnected
            nicks_connected_with.each{ |n| disconnect_from n }
          elsif type == :download_disconnected
            @connection_cache.delete hash[:nick]
          end
        end
      end

      def lock_connection_with! nick, connection
        @connection_cache[nick] = connection
      end

      def connection_for nick
        @connection_cache[nick]
      end

      def connected_with? nick
        @connection_cache.has_key? nick
      end

      def disconnect_from nick
        c = @connection_cache.delete nick
        c.try :close_connection_after_writing
      end

      def nicks_connected_with
        @connection_cache.keys
      end

    end
  end
end
