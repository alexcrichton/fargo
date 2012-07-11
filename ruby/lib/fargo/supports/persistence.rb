module Fargo
  module Supports

    # Implements persistent connections with remote peers. These connections are
    # kept track of so that the overhead of re-creating connections need not
    # be paid for sequential downloads of files from the same user.
    #
    # There is no timeout for connections enforced here, so the connections can
    # be terminated at any time.
    #
    # Also contains the implementation for establishing the initial connections
    # to peers. This initial connection has a time limit of 10 seconds to
    # be responded to from the peer.
    #
    # Published events are:
    #     :connection_timeout => Occurs when a connection is requested with a
    #                            peer, but no response was heard for 10s. Keys
    #                            are :nick
    module Persistence
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_connection_caches
      end

      # Establish a connection with a remote peer. If no response is heard for
      # 10 seconds, then the connection is considered timed out.
      #
      # @param [String] nick the nick to connect with.
      def connect_with nick
        debug 'connect', "Requesting connection with #{nick}"
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

      # Fetches the persistent connection for nick
      #
      # @param [String] nick the nick to lookup a connection for
      # @return [Fargo::Protocol::Peer] the open connection with the nick or
      #   nil if one doesn't exist.
      def connection_for nick
        @connection_cache[nick]
      end

      # Tests whether we're connected with the remote nick
      #
      # @param [String] nick the nick to test the connection for
      # @return [Boolean] whether we're connected with the nick
      def connected_with? nick
        @connection_cache.has_key? nick
      end

      # Disconnects from the specified nick.
      #
      # @param [String] nick the nick to disconnect from.
      def disconnect_from nick
        c = @connection_cache.delete nick
        c.try :close_connection_after_writing
      end

      # Returns a list of all nicks that we're connected with.
      #
      # @return [Array<String>] all nicks that there are connections open with.
      def nicks_connected_with
        @connection_cache.keys
      end

      protected

      def initialize_connection_caches
        @connection_cache = {}

        channel.subscribe do |type, hash|
          if type == :hub_disconnected
            nicks_connected_with.each{ |n| disconnect_from n }
          elsif type.to_s =~ /_disconnected$/
            next if hash[:nick].nil?
            if !connected_with?(hash[:nick])
              raise "#{hash[:nick]} should have a previously opened connection!"
            end
            @connection_cache.delete hash[:nick]
          elsif type.to_s =~ /_connected$/
            if connected_with?(hash[:nick])
              raise 'Should not have a previously opened connection!'
            end
            @connection_timeouts.delete(hash[:nick]).try(:cancel)
            @connection_cache[hash[:nick]] = hash[:connection]
          end
        end
      end

    end
  end
end
