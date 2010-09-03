module Fargo
  
  class ConnectionError < RuntimeError; end

  module Connection  

    class Base
  
      include Fargo::Publisher
  
      attr_accessor :options, :socket
      
      def initialize opts = {}
        @outgoing = Queue.new
        @options = opts
        self[:quit_on_disconnect] = true
      end
  
      def [] key
        options[key]
      end
  
      def []= key, value
        Fargo.logger.debug "#{self}: setting #{key} to #{value}"
        options[key] = value
      end
  
      def connect
        raise Fargo::ConnectionError.new("There's no receive method!") unless respond_to? :receive

        Fargo.logger.info "#{self}: Opening connection with #{self[:address]}, #{self[:port]}"

        open_socket      
        listen
      
        connection_type = self.class.name.split("::").last.downcase
        self[:client].publish :"#{connection_type}_connection_opened"
      end
  
      def open_socket
        @socket ||= TCPSocket.open self[:address], self[:port]
      rescue Errno::ECONNREFUSED
        raise Fargo::ConnectionError.new "Couldn't open a connection to #{self[:address]}:#{self[:port]}"
      end

      def connected?
        !@socket.nil?
      end
    
      def listen
        return unless @threads.nil? || @threads.size == 0
        pre_listen if respond_to? :pre_listen
      
        @threads = []
      
        # Start a thread to read the socket
        @threads << Thread.start { loop { read_data } }
      
        # Start a thread to send information from the queue
        @threads << Thread.start { loop { write_data @outgoing.pop } }
      
        @threads.each { |t| t.abort_on_exception = true }
      
        post_listen if respond_to? :post_listen
      end
  
      def disconnect
        Fargo.logger.debug "#{self}: Disconnecting connection"
      
        write "$Quit #{self[:nick]}" if self[:quit_on_disconnect]
      
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
      
        connection_type = self.class.name.split("::").last.downcase
        self[:client].publish :"#{connection_type}_disconnected"
      end
  
      def write string
        string << '|' unless string =~ /\|$/
        @outgoing << string # append this to the queue of things to be written
        true
      end
    
      private
      def read_data
        if @socket.closed?
          Fargo.logger.debug "When reading data, socket was already closed!"
          disconnect
        else
          begin
            data = @socket.gets "|"
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
          return
        end

        Fargo.logger.debug "#{self} Sending: #{data.inspect}" 
        @socket << data
      rescue 
        self[:client].publish :write_error
        disconnect
      end
    
    end
  end
end