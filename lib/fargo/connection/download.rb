require 'zlib'

module Fargo
  module Connection
    class Download < Base

      include Fargo::Utils
      include Fargo::Parser

      set_callback :listen, :before, :pre_listen
      set_callback :listen, :after do |connection|
        send_lock if connection.config.first
      end

      attr_accessor :download

      def pre_listen
        Fargo.logger.debug "Initiating connection on: #{config.address}:#{config.port}"

        config.quit_on_disconnect = false
        @lock, @pk = generate_lock
        @handshake_step = 0

        @buffer_size = (2 << 12).freeze
      end

      def send_lock
        write "$MyNick #{@client.config.nick}|$Lock #{@lock} Pk=#{@pk}"
      end

      def read_data
        # only download if we're at the correct time
        return super if @handshake_step != 6

        @exit_time = 20 # reset our timeout time

        data = @socket.readpartial @buffer_size

        if @zlib
          @zs = Zlib::Inflate.new if @zs.nil?
          data = @zs.inflate data
        end

        @file << data
        @file.flush
        @recvd += data.length

        if @recvd > @length
          error "#{self} #{@recvd} > #{@length}!!!"
          download_finished!
        else
          publish :download_progress, :percent    => @recvd.to_f / @length,
                                      :file       => download_path,
                                      :nick       => @other_nick,
                                      :download   => @download,
                                      :size       => @length,
                                      :compressed => @zlib

          download_finished! if @recvd == @length
        end
      rescue IOError => e
        error "#{self}: IOError, disconnecting #{e}"
      end

      def receive data
        message = parse_message data

        case message[:type]
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
              send_lock unless config.first
              out = ''
              out << '$Supports TTHF ADCGet ZLIG|'
              out << "$Direction Download #{@my_num = rand(10000)}|"
              out << "$Key #{generate_key @remote_lock}|"
              write out
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

              write "$Send" unless @client_extensions.include? 'ADCGet'

              publish :download_started, :file     => download_path,
                                         :download => @download,
                                         :nick     => @other_nick
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
            @client.publish message[:type], message

        end
      end

      def begin_download!
        @file = File.open download_path, 'wb'

        @file.seek @download.offset
        @file.sync      = true
        @socket.sync    = true
        @handshake_step = 5

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

          write "$ADCGET file #{download_query} #{@download.offset} #{@download.size} #{zlig}"
        else
          write "$Get #{@download.file}$#{@download.offset + 1}"
        end

        # This is the thread for the timeout of a connection. The @exit_time
        # variable is reset to 20 after every bit of information is received.
        @exit_time = 20
        @exit_thread = Thread.start {
          while @exit_time > 0
            sleep 1
            @exit_time -= 1
            Fargo.logger.debug "#{self} time out in #{@exit_time} seconds"
          end

          download_failed! 'Download timeout!'
        }

        Fargo.logger.debug "#{self}: Beginning download of #{@download}"
      end

      def download_failed! msg, opts = {}
        Fargo.logger.debug "#{self}: #{msg} #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        publish :download_failed, opts.merge(:nick => @other_nick,
                                             :download   => download,
                                             :file       => path,
                                             :last_error => msg)

        @exit_thread = nil
      end

      def download_finished!
        Fargo.logger.debug "#{self}: Finished download of #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        publish :download_finished, :file => path, :download => download,
                                    :nick => @other_nick
        disconnect if download.file_list?
      end

      def disconnect
        Fargo.logger.debug "#{self} Disconnecting from: #{@other_nick}"

        super

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

        if @socket
          @socket.sync = false
          @socket.flush
        end

        # If this was called from exit thread, don't kill it
        if @exit_thread != Thread.current
          @exit_thread.exit if @exit_thread && @exit_thread.alive?
          @exit_thread = nil
        end

        # clear out these variables
        @zs = @file_path = @zlib = @download = @length = @recvd = nil

        # Go back to the get step
        @handshake_step = 5
      end

      def download_path
        return nil if @download.try(:file).nil?

        @file_path ||= begin
          prefix   = @client.config.download_dir
          filename = File.basename @download.file.gsub("\\", '/')
          path     = File.join(prefix, @other_nick, filename)

          i = 0
          while File.exists?(path)
            i += 1
            path = File.join(prefix, @other_nick, "#{i}-#{filename}")
          end

          path
        end
      end

      def error message
        Fargo.logger.warn @last_error = message
        disconnect
      end

    end
  end
end
