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
        @other_nick ? @other_nick : :peer
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
            else
              error "#{type} received at wrong step of handshake"
            end

          when :lock
            if @handshake_step == 1
              # According to this url:
              # http://www.teamfair.info/wiki/index.php?title=$Direction, if we
              # choose a number higher than 0x7fff, then other clients can
              # just automatically disconnect.
              @remote_lock    = message[:lock]
              @handshake_step = 2
              @my_num         = rand(0x7fff)
              @my_direction   =
                @client.download_for?(@other_nick) ? 'Download' : 'Upload'

              # Depending on who connected first, we might have already sent
              # our lock information.
              send_lock unless @lock_sent

              send_message 'Supports', supports
              # Always indicate that we want to Upload. We can just download
              # on this connection later so long as nothing is requested from
              # the other side.
              send_message 'Direction', "#{@my_direction} #{@my_num}"
              send_message 'Key', generate_key(@remote_lock)
            else
              error "#{type} received at wrong step of handshake"
            end

          when :supports
            if @handshake_step == 2
              @peer_extensions  = message[:extensions]
              @handshake_step   = 3
            else
              error "#{type} received at wrong step of handshake"
            end

          when :direction
            if @handshake_step == 3
              @peer_num       = message[:number]
              @peer_direction = message[:direction]
              @handshake_step = 4
            else
              error "#{type} received at wrong step of handshake"
            end

          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]
              @handshake_step = 5
              client.channel << [:peer_connected,
                  publish_args.merge(:connection => self)]

              if @my_direction == 'Download'
                # If we've both requested downloads, then we fall back to
                # the numbers we generated to figure out who goes first. If we
                # sent the same numbers, then we're supposed to terminate the
                # connection.
                if @peer_direction == 'Upload' || @peer_num < @my_num
                  @download = client.download_for! @other_nick
                  begin_download!
                elsif @peer_num == @my_num
                  close_connection_after_writing
                end
              end

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
