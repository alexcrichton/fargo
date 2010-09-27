require 'zlib'

module Fargo
  module Protocol
    class Download < EventMachine::Connection

      include Fargo::Utils
      include Fargo::Protocol::DC

      attr_accessor :download, :client

      def post_init
        super

        set_comm_inactivity_timeout 20

        @lock, @pk      = generate_lock
        @handshake_step = 0
      end

      # This would be done in post_init, but it needs @client to be defined.
      # Apparently when the connection is configured after it is yielded from
      # a call to EM#connect post_init has already been called :(
      def initialize_connection
        send_message 'MyNick', @client.config.nick
        send_message 'Lock', "#{@lock} Pk=#{@pk}"
      end

      def receive_data data
        # only download if we're at the correct handshake step
        return super if @handshake_step != 6

        if @zlib
          @inflator = Zlib::Inflate.new if @inflator.nil?
          data      = @inflator.inflate data
        end

        @file << data
        @recvd += data.length

        if @recvd > @length
          error "#{self} #{@recvd} > #{@length}!!!"
          download_finished!
        else
          percent = @recvd.to_f / @length
          if percent - @last_published > 0.05
            @file.flush
            @client.channel << [:download_progress, {:percent => percent,
                                        :file           => download_path,
                                        :nick           => @other_nick,
                                        :download       => @download,
                                        :size           => @recvd,
                                        :compressed     => @zlib}]

            @last_published = percent
          end

          download_finished! if @recvd == @length
        end
      end

      def receive_message type, message
        case type
          when :mynick
            if @handshake_step == 0
              @handshake_step  = 1
              @other_nick      = message[:nick]

              @client.connected_with! @other_nick
              @client.lock_connection_with! @other_nick, self
              @download = @client.lock_next_download! @other_nick, self

              if @download.try(:file).nil?
                error "Nothing to download from:#{@other_nick}!"
              end
            else
              error 'Premature disconnect when mynick received'
            end

          when :lock
            if @handshake_step == 1
              @remote_lock = message[:lock]
              @handshake_step = 2

              send_message 'Supports', 'TTHF ADCGet ZLIG'
              send_message 'Direction', "Download #{@my_num = rand(10000)}"
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
            if @handshake_step == 3 && message[:direction] == 'upload'
              @client_num     = message[:number]
              @handshake_step = 4
            else
              error 'Premature disconnect when direction received'
            end

          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]

              FileUtils.mkdir_p File.dirname(download_path), :mode => 0755

              begin_download!

            else
              error 'Premature disconnect when key received'
            end

          when :file_length, :adcsnd
            if @handshake_step == 5
              @recvd          = 0
              @handshake_step = 6

              @zlib   = message[:zlib]
              @length = message[:size]

              send_message 'Send' unless @client_extensions.include? 'ADCGet'

              @client.channel << [:download_started, {:file => download_path,
                                         :download  => @download,
                                         :nick      => @other_nick}]
            else
              error "Premature disconnect when #{message[:type]} received"
            end

          when :noslots
            if @download
              Fargo.logger.debug "#{self}: No Slots for #{self[:download]}"

              download_failed! 'No Slots'
            end

          when :error
            Fargo.logger.warn @last_error = "#{self}: Error! #{message[:message]}"
            download_failed! message[:message]

          # This wasn't handled by us, proxy it on up to the client
          else
            @client.channel << [message[:type], message]

        end
      end

      def begin_download!
        @file = File.open download_path, 'wb'

        @file.seek @download.offset
        @handshake_step = 5
        @last_published = 0

        if @download.file_list?
          if @client_extensions.include? 'XmlBZList'
            @download.file = 'files.xml.bz2'
          elsif @client_extensions.include? 'BZList'
            @download.file = 'MyList.bz2'
          else
            @download.file = 'MyList.DcLst' # TODO: support this?
          end
        end

        if @client_extensions.include? 'ADCGet'
          download_query = @download.file
          if @download.tth && @client_extensions.include?('TTHF')
            download_query = 'TTH/' + @download.tth
          end

          zlig = ''
          if @client_extensions.include? 'ZLIG'
            zlig = 'ZL1'
            Fargo.logger.debug "Enabling zlib compression on: #{@download.file}"
          end

          send_message 'ADCGET', "file #{download_query} #{@download.offset} #{@download.size} #{zlig}"
        else
          send_message 'Get', "#{@download.file}$#{@download.offset + 1}"
        end

        Fargo.logger.debug "#{self}: Beginning download of #{@download}"
      end

      def download_failed! msg, opts = {}
        Fargo.logger.debug "#{self}: #{msg} #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        @client.channel << [:download_failed, opts.merge(:nick => @other_nick,
                                             :download   => download,
                                             :file       => path,
                                             :last_error => msg)]
      end

      def download_finished!
        Fargo.logger.debug "#{self}: Finished download of #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        @client.channel << [:download_finished,
            {:file => path, :download => download, :nick => @other_nick}]

        close_connection_after_writing if download.file_list?
      end

      def disconnect_publish_args
        {:nick => @other_nick}
      end

      def unbind
        super

        Fargo.logger.debug "#{self} Disconnected from: #{@other_nick}"

        if @download
          download_failed! @last_error, :recvd => @recvd, :length => @length
        end

        reset_download
      end

      private

      def reset_download
        @file.close unless @file.nil? || @file.closed?

        if @file_path && File.exists?(@file_path) && File.size(@file_path) == 0
          File.delete(@file_path)
        end

        # clear out these variables
        @inflator = @file_path = @zlib = @download = @length = @recvd = nil

        # Go back to the get step
        @handshake_step = 5
      end

      def download_path
        return nil if @download.try(:file).nil?

        @file_path ||= begin
          prefix   = @client.config.download_dir
          filename = File.basename @download.file.gsub("\\", '/')
          path     = File.join(prefix, @other_nick, filename)

          unless @download.file_list?
            i = 0
            while File.exists?(path)
              i += 1
              path = File.join(prefix, @other_nick, "#{i}-#{filename}")
            end
          end

          path
        end
      end

      def error message
        Fargo.logger.warn @last_error = message

        close_connection
      end

    end
  end
end
