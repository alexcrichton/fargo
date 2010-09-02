module Fargo
  module Connection
    class Hub < Base
  
      include Fargo::Utils
      include Fargo::Parser
      
      # See <http://www.teamfair.info/DC-Protocol.htm> for specifics on protocol handling
      def receive data
        message = parse_message data

        case message[:type]
          when :lock 
            @validated = false
            write "$Key #{generate_key message[:lock]}"
          when :hubname
            self[:hubname] = message[:name]
            write "$ValidateNick #{self[:client].nick}" unless @validated
          when :getpass
            write "$MyPass #{self[:client].password || ''}"
          when :badpass, :hubfull
            Fargo.logger.warn "Disconnecting because of: #{message.inspect}"
            disconnect
          when :hello
            if message[:who] == self[:nick] 
              Fargo.logger.info "Connected to DC Hub #{self[:hubname]} (#{self[:address]}:#{self[:port]})"
              @validated = true
              write "$Version 1,0091"
              write "$GetNickList"
              write "$MyINFO $ALL #{self[:nick]} #{self[:client].description}$ $#{self[:client].speed || 'DSL'}#{self[:status] || 1.chr}$#{self[:client].email}$#{self[:client].share_size}$"
            end
            
          when :connect_to_me
            return unless self[:client].nicks.include?(message[:nick])
            @client_connections ||= []
            
            # we're going to initiate the download
            message[:first] = true
            
            # the message will contain the port and address of who to connect to
            connection = Fargo::Connection::Download.new self.options.merge(message)
            
            # proxy all messages from them back to the client and delete the connection if 
            # necessary
            connection.subscribe { |*args| 
              self[:client].publish *args
              @client_connections.delete connection unless connection.connected?
            }
            
            # establish the connection. This will also listen for data to be read/written
            connection.connect
            
            # keep track of who we're downloading from
            @client_connections << connection
            
          when :search
            # Make sure we received a valid search request
            return unless message[:searcher].nil? || self[:client].nicks.include?(message[:searcher])
            
            # Let the client handle the results
            @results = self[:client].search_files message
            
            # Send all the results to the peer. Take care of active/passive connections
            @results.each { |r| 
              if message[:address]
                r.active_send self[:client].nick, message[:ip], message[:port]
              else
                write "$SR #{self[:client].nick} #{r}" 
              end
            }
            
          when :revconnect
            # TODO: Don't send RevConnectToMe when we're passive and receiving is passive
            if self[:client].passive
              write "$RevConnectToMe #{self[:client].nick} #{message[:who]}"
            else
              write "$ConnectToMe #{self[:client].nick} #{self[:client].address}:#{self[:client].extport}"
            end
            
          # proxy this message on up the stack if we don't handle it
          else
            self[:client].publish message[:type], message
            
        end
      end
      
      def disconnect
        if @client_connections
          @client_connections.each &:disconnect
          @client_connections.clear
        end
        
        super
      end
      
    end # Hub
  end # Connection
end # Fargo