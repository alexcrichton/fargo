module Fargo
  module Connection
    class Hub < Base

      include Fargo::Utils
      include Fargo::Parser
      
      attr_reader :hubname
      
      configure do |config|
        config.address = '127.0.0.1'
        config.port    = 7314
      end

      # See <http://www.teamfair.info/DC-Protocol.htm> for specifics on 
      # the DC protocol
      def receive data
        message = parse_message data

        case message[:type]
          when :lock 
            @validated = false
            write "$Key #{generate_key message[:lock]}"
          when :hubname
            @hubname = message[:name]
            write "$ValidateNick #{@client.config.nick}" unless @validated
          when :getpass
            write "$MyPass #{@client.password}"
          when :badpass, :hubfull
            Fargo.logger.warn "Disconnecting because of: #{message.inspect}"
            disconnect
          when :hello
            if message[:who] == @client.config.nick
              Fargo.logger.info "Connected to DC Hub #{@hubname} (#{config.address}:#{config.port})"
              @validated = true

              write "$Version 1,0091"
              write "$GetNickList"
              write "$MyINFO $ALL #{@client.config.nick} " +
                "#{@client.description}$ $#{@client.config.speed || 'DSL'}" + 
                "#{@status || 1.chr}$#{@client.config.email}" +
                "$#{@client.share_size}$"
            end
            
          when :connect_to_me
            if !@client.nicks.include?(message[:nick])
              Fargo.logger.info "Invalid connect_to_me request from: #{message[:nick]}"
              return
            end

            @client_connections ||= []
            
            connection = Fargo::Connection::Download.new @client
            connection.config.address = message[:address]
            connection.config.port    = message[:port]
            # we're going to initiate the download
            connection.config.first   = true

            # proxy all messages from them back to the client and delete the connection if 
            # necessary
            connection.subscribe { |*args|
              @client.publish *args
              @client_connections.delete connection unless connection.connected?
            }
            
            # establish the connection. This will also listen for data to be
            # read/written
            connection.connect
            
            # keep track of who we're downloading from
            @client_connections << connection
            
          when :search
            # Make sure we received a valid search request
            if message[:searcher].nil? || !@client.nicks.include?(message[:searcher])
              Fargo.logger.info "Invalid search request: #{message.inspect}"
              return
            end
            
            # Let the client handle the results
            @results = @client.search_files message
            
            # Send all the results to the peer. Take care of active/passive
            # connections
            @results.each { |r| 
              if message[:address]
                r.active_send @client.config.nick, message[:ip], message[:port]
              else
                write "$SR #{@client.config.nick} #{r}" 
              end
            }

          when :revconnect
            # TODO: Don't send RevConnectToMe when we're passive and 
            # receiving is passive
            if @client.config.passive
              write "$RevConnectToMe #{@client.config.nick} #{message[:who]}"
            else
              write "$ConnectToMe #{@client.config.nick} #{@client.config.address}:#{@client.config.extport}"
            end
            
          # proxy this message on up the stack if we don't handle it
          else
            @client.publish message[:type], message
            
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
