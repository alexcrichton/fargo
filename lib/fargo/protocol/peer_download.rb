module Fargo
  module Protocol
    module PeerDownload

      def receive_data data
        # only download if we're at the correct handshake step
        return super if @handshake_step != 6 || @download.nil?

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
          when :file_length, :adcsnd, :sending
            if @handshake_step == 5
              @recvd          = 0
              @handshake_step = 6

              @zlib   = message[:zlib] unless @getblock_sent
              @length = message[:size]

              send_message 'Send' if @get_sent

              if @zlib
                Fargo.logger.debug(
                  "Enabling zlib compression on: #{@download.file}")
              end

              @client.channel << [:download_started, {:file => download_path,
                                         :download  => @download,
                                         :nick      => @other_nick}]
            else
              error "Premature disconnect when #{message[:type]} received"
            end

          when :noslots
            if @download
              Fargo.logger.debug "#{self}: No Slots for #{@download}"

              download_failed! 'No Slots'
            end

          # This wasn't handled by us, proxy it on up to the client
          else
            super
        end
      end

      def begin_download!
        FileUtils.mkdir_p File.dirname(download_path), :mode => 0755
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

          zlig = @client_extensions.include?('ZLIG') ? 'ZL1' : ''

          send_message 'ADCGET', "file #{download_query} #{@download.offset} #{@download.size} #{zlig}"

        # See http://www.teamfair.info/wiki/index.php?title=XmlBZList for
        # what the $Supports extensions mean for the U?GetZ?Block commands
        elsif @client_extensions.include? 'GetZBlock'
          @getblock_sent = true
          @zlib          = true
          send_message 'UGetZBlock',
            "#{@download.offset} #{@download.size} #{@download.file}"
        elsif @client_extensions.include? 'XmlBZList'
          @getblock_sent = true
          @zlib          = false
          send_message 'UGetBlock',
            "#{@download.offset} #{@download.size} #{@download.file}"

        else
          @get_sent = true
          send_message 'Get', "#{@download.file}$#{@download.offset + 1}"
        end

        Fargo.logger.debug "#{self}: Beginning download of #{@download}"
      end

      def unbind
        super

        Fargo.logger.debug "#{self} Disconnected from: #{@other_nick}"

        if @download
          download_failed! @last_error, :recvd => @recvd, :length => @length
        end

        reset_download
      end

      protected

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

      def reset_download
        @file.close unless @file.nil? || @file.closed?

        if @file_path && File.exists?(@file_path) && File.size(@file_path) == 0
          File.delete(@file_path)
        end

        # clear out these variables
        @inflator = @file_path = @zlib = @download = @length = @recvd = nil
        @get_sent = @getblock_sent = false

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

    end
  end
end
