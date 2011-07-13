require 'zlib'

module Fargo
  module Protocol

    # A peer connection represents a connection directly between this client
    # and the peer. This protocol is slightly different from the Hub, but only
    # in format. The same syntax still applies for the underlying data.
    #
    # A peer can either request a download of a file from us or we can request
    # a download from them. Both types of functionality are supported as part of
    # this module.
    #
    # Published events are all messages received on this connection which aren't
    # specifically handled by any of the Peer* protocols. Also:
    #   :peer_connected => Published when a remote peer has connected and we
    #                      have determined their nick. Keys are those of
    #                      #publish_args and :connection
    #
    # @see Fargo::Protocol::PeerDownload
    # @see Fargo::Protocol::PeerUpload
    module Peer

      include Utils
      include Protocol::DC
      include PeerDownload
      include PeerUpload

      attr_accessor :client

      def connection_type
        :peer
      end

      # After this connection is established, generate ourselves a lock to send
      # and initialize our handshake step.
      def post_init
        super

        @lock, @pk = generate_lock
        @handshake_step = 0
      end

      # Sends our lock information to the peer, along with our nick.
      def send_lock
        @lock_sent = true
        send_message 'MyNick', @client.config.nick
        send_message 'Lock', "#{@lock} Pk=#{@pk}"
      end

      # List of extensions that Fargo currently supports
      def supports
        'MiniSlots XmlBZList ADCGet TTHF ZLIG GetZBlock'
      end

      # Implementation of the handshake between the peer and us. Make sure that
      # we correctly identify who they are and we identify with them.
      def receive_message type, message
        case type
          when :mynick
            if @handshake_step == 0
              @handshake_step  = 1
              @other_nick      = message[:nick]

              client.channel << [:peer_connected,
                  publish_args.merge(:connection => self)]
              @download = @client.lock_next_download! @other_nick, self

              @direction = @download.nil? ? 'Upload' : 'Download'
            else
              error "#{type} received at wrong step of handshake"
            end

          when :lock
            if @handshake_step == 1
              @remote_lock    = message[:lock]
              @handshake_step = 2

              # Depending on who connected first, we might have already sent
              # our lock information.
              send_lock unless @lock_sent

              send_message 'Supports', supports
              send_message 'Direction', "#{@direction} #{@my_num = rand(10000)}"
              send_message 'Key', generate_key(@remote_lock)
            else
              error "#{type} received at wrong step of handshake"
            end

          when :supports
            if @handshake_step == 2
              @peer_extensions = message[:extensions]
              @handshake_step    = 3
            else
              error "#{type} received at wrong step of handshake"
            end

          when :direction
            if @handshake_step == 3
              @client_num     = message[:number]
              @handshake_step = 4
            else
              error "#{type} received at wrong step of handshake"
            end

          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]
              @handshake_step = 5

              begin_download! if @direction == 'Download'

            else
              error "#{type} received at wrong step of handshake" +
                " or the peer's lock is incorrect and doesn't match their key"
            end

          # This wasn't handled by us, proxy it on up to the client
          else
            super

        end
      end

      # Overridable method for the information that is published when this
      # connection is opened.
      def publish_args
        {:nick => @other_nick}
      end

      protected

      # Helpful utility for closing this connection with a specified message.
      def error message
        Fargo.logger.warn @last_error = message

        close_connection
      end

    end
  end
end
