module Fargo
  class Server
    
    include Fargo::Utils::Publisher
  
    def initialize options = {}
      @options = options
      @options[:address] = '0.0.0.0'
      @peers = []
    end
    
    def connected?
      !@server.nil?
    end

    def connect
      return if connected?
      
      Fargo.logger.info "#{self}: Starting server on #{@options[:address]}:#{@options[:port]}"

      @server = TCPServer.new @options[:address], @options[:port]
    
      @active_thread = Thread.start { loop {
        
        connection = @options[:connection].new @options.merge(:first => false)
        
        connection_type = self.class.name.split("::").last.downcase
        disconnect_symbol = :"#{connection_type}_disconnected"
        
        connection.subscribe{ |type, hash|
          @peers.delete connection if type == disconnect_symbol
        }
        
        connection.socket = @server.accept
        connection.listen
        @peers << connection
      } }
    end
  
    def disconnect
      Fargo.logger.info "#{self}: disconnecting..."
      @active_thread.exit if @active_thread
      
      @server.close if @server rescue nil
      @server = nil
      
      @peers.each{ |p| p.disconnect } 
      @peers.clear
    end
  
  end
end