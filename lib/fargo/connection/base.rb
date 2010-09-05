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
        !@socket.nil?
      end

      def listen
        return unless @threads.nil? || @threads.size == 0
        
        run_callbacks :listen do
          @threads = []

          # Start a thread to read the socket
          @threads << Thread.start { loop { read_data } }

          # Start a thread to send information from the queue
          @threads << Thread.start { loop { write_data @outgoing.pop } }

          @threads.each { |t| t.abort_on_exception = true }
        end
      end

      def disconnect
        Fargo.logger.debug "#{self}: Disconnecting connection"

        write "$Quit #{@client.config.nick}" if config.quit_on_disconnect

        if @threads
          @threads.each &:exit
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
        if @socket.closed?
          Fargo.logger.debug 'When reading data, socket was already closed!'
          disconnect
        else
          begin
            data = @socket.gets '|'
            raise ConnectionError.new("Received nil data!") if data.nil?
          rescue => e
            Fargo.logger.warn "#{self}: Error reading data, disconnecting: #{e}"
            disconnect
          end

          Fargo.logger.debug "#{self} Received: #{data.inspect}" 
          receive data.chomp('|')
        end
      end

      def write_data data
        if @socket.closed?
          Fargo.logger.debug "When writing data, socket was already closed!"
          disconnect
        else
          begin
            Fargo.logger.debug "#{self} Sending: #{data.inspect}" 
            @socket << data
          rescue
            @client.publish :write_error
            disconnect
          end
        end
      end
    
    end
  end
end
