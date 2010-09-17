module Fargo
  module Supports
    module Persistence
      extend ActiveSupport::Concern

      included do
        set_callback :setup, :after, :setup_connection_cache
      end

      def lock_connection_with! nick, connection
        @connection_cache[nick] = connection
      end

      def connection_for nick
        c = @connection_cache.try :[], nick
        if c.nil? || c.connected?
          Fargo.logger.debug "#{self} has connection with: #{nick}: #{c}"
          return c
        end

        # If it's present and not connected, remove it from the cache
        @connection_cache.try :delete, nick
        nil
      end

      def connected_with? nick
        c = @connection_cache.try :[], nick
        c.connected? unless c.nil?
      end

      def disconnect_from nick
        c = @connection_cache.try :delete, nick
        c.disconnect unless c.nil?
      end

      def nicks_connected_with
        return [] if @connection_cache.nil?

        nicks = @connection_cache.keys
        nicks.reject{ |n| !connected_with? n }
      end

      def setup_connection_cache
        @connection_cache = {}

        subscribe { |type, hash|
          if type == :hub_disconnected
            nicks_connected_with.each{ |n| disconnect_from n }
          end
        }
      end

    end
  end
end
