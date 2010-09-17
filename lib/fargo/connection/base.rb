require 'active_support/configurable'
require 'active_support/callbacks'

module Fargo
  class ConnectionError < RuntimeError; end

  module Connection
    class Base

      include ActiveSupport::Configurable
      include ActiveSupport::Callbacks
      include Fargo::Publisher

      attr_accessor :socket
      define_callbacks :listen

      def initialize client
        @outgoing = Queue.new
        @client   = client
        config.quit_on_disconnect = true
      end

      def connect
        Fargo.logger.info(
          "#{self}: Opening connection with #{config.address}, #{config.port}"
        )

        open_socket
        listen

        connection_type = self.class.name.split('::').last.downcase
        @client.publish :"#{connection_type}_connection_opened"
      end

      def receive
        raise 'Implement me!'
      end

      def open_socket
        @socket ||= TCPSocket.open config.address, config.port
      rescue Errno::ECONNREFUSED
        raise Fargo::ConnectionError.new "Couldn't open a connection to #{config.address}:#{config.port}"
      end

      def connected?
        val = !@socket.nil? && !@socket.closed?
        Fargo.logger.debug "#{self} Testing if connected: #{val}"
        val
      end

      def listen
        return unless @threads.nil? || @threads.size == 0

        run_callbacks :listen do
          @threads = []
          @looping = true

          # Start a thread to read the socket
          @threads << Thread.start { read_data while @looping }

          # Start a thread to send information from the queue
          @threads << Thread.start { write_data @outgoing.pop while @looping }

          @threads.each { |t| t.abort_on_exception = true }
        end
      end

      def disconnect
        Fargo.logger.debug "#{self}: Disconnecting connection"

        write "$Quit #{@client.config.nick}" if config.quit_on_disconnect

        @looping = false

        if @threads
          @threads.each{ |t| t.exit unless t == Thread.current }
          @threads.clear
        end

        if @socket
          begin
            @socket.close
          rescue => e
            Fargo.logger.error "Error closing socket: #{e}"
          end
        end

        @socket = nil
        @outgoing.clear

        connection_type = self.class.name.split('::').last.downcase
        @client.publish :"#{connection_type}_disconnected"
      end

      def write string
        string << '|' unless string.end_with?('|')
        @outgoing << string # append this to the queue of things to be written
        true
      end

      private

      def read_data
        data = @socket.gets '|'
        raise ConnectionError.new('Received nil data!') if data.nil?

        Fargo.logger.debug "#{self} Received: #{data.inspect}"
        receive data.chomp('|')
      rescue => e
        unless @socket.closed?
          Fargo.logger.warn "#{self}: Error reading data, going away: #{e}"
          disconnect
        end
      end

      def write_data data
        Fargo.logger.debug "#{self} Sending: #{data.inspect}"
        @socket << data
      rescue => e
        unless @socket.closed?
          Fargo.logger.warn "#{self}: Error writing data, going away: #{e}"
          disconnect
        end
      end

    end
  end
end
