module Fargo
  module Protocol
    module Hub

      include Utils
      include Protocol::DC

      attr_reader :hubname

      def connection_type
        :hub
      end

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
            Fargo.logger.info "Disconnecting because of: #{message.inspect}"
            close_connection_after_writing
          when :hello
            if message[:nick] == @client.config.nick
              Fargo.logger.info "Connected to DC Hub #{@hubname}"
              @validated = true

              send_message 'Version', '1,0091'
              send_message 'MyINFO', "$ALL #{@client.config.nick} " +
                "#{@client.description}$ $#{@client.config.speed}" +
                "#{@status || 1.chr}$#{@client.config.email}" +
                "$#{@client.share_size}$"
              send_message 'GetNickList'
            end

          when :connect_to_me
            EventMachine.connect message[:address], message[:port],
                Protocol::Peer do |conn|
              conn.client     = @client
              conn.send_lock # We connect first, we send lock first
            end

          when :search
            # Let the client handle the results
            search = Search.new message
            listings = @client.search_local_listings search

            results = listings.map do |l|
              file = l.path.gsub '/', "\\"
              if l.tth.nil?
                s = file
              else
                s = "#{file}\005#{l.size}"
              end

              s + sprintf(" %d/%d\005%s (%s:%d)", @client.open_upload_slots,
                                                  @client.config.upload_slots,
                                                  l.tth.nil? ? @hubname :
                                                    'TTH:' + l.tth,
                                                  @client.config.hub_address,
                                                  @client.config.hub_port)
            end

            # Send all the results to the peer. Take care of active/passive
            # connections
            if message[:address]
              socket = EventMachine.open_datagram_socket '0.0.0.0', 0
              results.each{ |r|
                data = "$SR #{@client.config.nick} #{r}|"
                client.debug "out-user", data, RED
                socket.send_datagram data, message[:address], message[:port]
              }
              socket.close_connection_after_writing
            else
              results.each{ |r|
                send_message 'SR',
                  "#{@client.config.nick} #{r}\005#{message[:searcher]}"
              }
            end

          when :revconnect
            if @client.config.passive
              send_message 'RevConnectToMe',
                  "#{@client.config.nick} #{message[:who]}"
            else
              send_message 'ConnectToMe', "#{message[:who]} #{@client.config.address}:#{@client.config.active_port}"
            end

          # proxy this message on up the stack if we don't handle it
          else
            super

        end
      end

    end
  end
end
