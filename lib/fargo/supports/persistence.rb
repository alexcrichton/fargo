module Fargo
  module Supports
    module Persistence
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_connection_caches
      end

      def connect_with nick
        @connection_timeouts[nick] = EventMachine::Timer.new(10) do
          @connection_timeouts.delete(nick)
          channel << [:connection_timeout, {:nick => nick}]
        end

        if config.passive
          hub.send_message 'RevConnectToMe', "#{self.config.nick} #{nick}"
        else
          hub.send_message 'ConnectToMe',
            "#{nick} #{config.address}:#{config.active_port}"
        end
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

      protected

      def initialize_connection_caches
        @connection_cache = {}

        channel.subscribe do |type, hash|
          if type == :hub_disconnected
            nicks_connected_with.each{ |n| disconnect_from n }
          elsif type == :download_disconnected
            @connection_cache.delete hash[:nick]
          elsif type == :download_opened
            @connection_timeouts.delete(hash[:nick]).try(:cancel)
            @connection_cache[hash[:nick]] = hash[:connection]
          end
        end
      end

    end
  end
end
