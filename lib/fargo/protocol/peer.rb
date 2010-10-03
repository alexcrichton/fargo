require 'zlib'

module Fargo
  module Protocol
    module Peer

      include Utils
      include Protocol::DC
      include PeerDownload
      include PeerUpload

      attr_accessor :download, :client

      def connection_type
        :peer
      end

      def post_init
        super

        set_comm_inactivity_timeout 20

        @lock, @pk      = generate_lock
        @handshake_step = 0
      end

      def send_lock
        @lock_sent = true
        send_message 'MyNick', @client.config.nick
        send_message 'Lock', "#{@lock} Pk=#{@pk}"
      end

      def supports
        'TTHF ADCGet ZLIG XmlBZList MiniSlots GetZBlock'
      end

      def receive_message type, message
        case type
          when :mynick
            if @handshake_step == 0
              @handshake_step  = 1
              @other_nick      = message[:nick]

              client.channel << [:download_opened,
                  publish_args.merge(:connection => self)]
              @download = @client.lock_next_download! @other_nick, self

              @direction = @download.nil? ? 'Upload' : 'Download'
            else
              error 'Premature disconnect when mynick received'
            end

          when :lock
            if @handshake_step == 1
              @remote_lock    = message[:lock]
              @handshake_step = 2

              send_lock unless @lock_sent

              send_message 'Supports', supports
              send_message 'Direction', "#{@direction} #{@my_num = rand(10000)}"
              send_message 'Key', generate_key(@remote_lock)
            else
              error 'Premature disconnect when lock received'
            end

          when :supports
            if @handshake_step == 2
              @client_extensions = message[:extensions]
              @handshake_step    = 3
            else
              error 'Premature disconnect when supports received'
            end

          when :direction
            if @handshake_step == 3
              @client_num     = message[:number]
              @handshake_step = 4
            else
              error 'Premature disconnect when direction received'
            end

          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]
              @handshake_step = 5

              begin_download! if @direction == 'Download'

            else
              error 'Premature disconnect when key received'
            end

          # This wasn't handled by us, proxy it on up to the client
          else
            super

        end
      end

      def publish_args
        {:nick => @other_nick}
      end

      protected

      def error message
        Fargo.logger.warn @last_error = message

        close_connection
      end

    end
  end
end
