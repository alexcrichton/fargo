module Fargo
  module Protocol
    class Hub < EventMachine::Connection

      include Fargo::Protocol::DC
      include Fargo::Utils

      attr_reader :hubname

      # See <http://www.teamfair.info/DC-Protocol.htm> for specifics on
      # the DC protocol
      def receive_message type, message
        case type
          when :lock
            @validated = false
            send_message 'Key', generate_key(message[:lock])
          when :hubname
            @hubname = message[:name]
            send_message 'ValidateNick', @client.config.nick unless @validated
          when :getpass
            send_message 'MyPass', @client.config.password
          when :badpass, :hubfull
            Fargo.logger.warn "Disconnecting because of: #{message.inspect}"
            close_connection
          when :hello
            if message[:who] == @client.config.nick
              Fargo.logger.info "Connected to DC Hub #{@hubname}"
              @validated = true

              send_message 'Version', '1,0091'
              send_message 'GetNickList'
              send_message 'MyInfo', "$ALL #{@client.config.nick} " +
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

            # proxy all messages from them back to the client and delete the
            # connection if necessary
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
            # Let the client handle the results
            @results = @client.search_files message

            # Send all the results to the peer. Take care of active/passive
            # connections
            @results.each { |r|
              if message[:address]
                r.active_send @client.config.nick, message[:ip], message[:port]
              else
                send_message 'SR', "#{@client.config.nick} #{r}"
              end
            }

          when :revconnect
            # TODO: Don't send RevConnectToMe when we're passive and
            # receiving is passive
            if @client.config.passive
              send_message 'RevConnectToMe',
                  "#{@client.config.nick} #{message[:who]}"
            else
              send_message 'ConnectToMe', "#{@client.config.nick} #{@client.config.address}:#{@client.config.extport}"
            end

          # proxy this message on up the stack if we don't handle it
          else
            @client.channel << [message[:type], message]

        end
      end

    end
  end
end
