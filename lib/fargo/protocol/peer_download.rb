module Fargo
  module Protocol
    # Implementation of downloading files from peers. All known download
    # implementations are available, but the ADC syntax is preferred.
    #
    # Published events to the client's channel are:
    #     :download_progress => occurs when progress on a download is made. The
    #                           hash has :percent, :file, :nick, :download,
    #                           :size, and :compressed keys
    #     :download_started  => published when a download starts. Contains the
    #                           :file, :download, :length, and :nick keys
    #     :download_failed   => if a download fails, then this event is fired.
    #                           Contains the :file, :download, :nick, :nick,
    #                           and :last_error keys.
    #     :download_finished => published when a download finishes successfully.
    #                           Contains the keys :file, :nick, and :download.
    module PeerDownload

      attr_accessor :download

      # This method is overwritten because when receiving file data, the binary
      # data shouldn't be parsed. This method delegates upward if we're not
      # in the middle of downloading a file, however.
      def receive_data_chunk data
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
          @download.percent = percent

          # Only periodically publish our download progress for better
          # performance
          if percent - @last_published > 0.05
            @file.flush
            @client.channel << [:download_progress, {:percent => percent,
                                        :file           => download_path,
                                        :nick           => @other_nick,
                                        :download       => @download.to_h,
                                        :size           => @recvd,
                                        :compressed     => @zlib}]

            @last_published = percent
          end

          download_finished! if @recvd == @length
        end

        true
      end

      # Overload this method to tell that we don't want to parse when we're in
      # the middle of a download.
      def parse_data?
        @handshake_step != 6
      end

      # Implementation for receiving files of any protocol.
      def receive_message type, message
        case type
          when :file_length, :adcsnd, :sending
            if @handshake_step != 5
              error "#{type} received before handshake complete."
              return
            end

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
                                       :download  => @download.to_h,
                                       :length    => @length,
                                       :nick      => @other_nick}]

          when :noslots
            download_failed! 'No Slots' if @download

          when :error
            download_failed! message[:message] if @download

          # This wasn't handled by us, proxy it on up to the client
          else
            super
        end
      end

      # Begins download of the requested file. This requires that the handshake
      # have been previously completed and that the @download instance variable
      # (via the #download= method) be set to the Fargo::Download that is
      # desired from the connected peer.
      #
      # This doesn't fire the :download_started event. That occurs when the
      # response from the peer that the file will be sent is received.
      def begin_download!
        FileUtils.mkdir_p File.dirname(download_path), :mode => 0755
        @file = File.open download_path, 'wb'

        @file.seek @download.offset
        @handshake_step = 5
        @last_published = 0

        # Figure out the correct file name to send
        if @download.file_list?
          if @client_extensions.include? 'XmlBZList'
            @download.file = 'files.xml.bz2'
          elsif @client_extensions.include? 'BZList'
            @download.file = 'MyList.bz2'
          else
            @download.file = 'MyList.DcLst' # TODO: support this?
          end
        end

        # Prefer certain extensions, but support all of them depending on the
        # extensions that the peer offers.
        if @client_extensions.include? 'ADCGet'
          download_query = @download.file
          if @download.tth && @client_extensions.include?('TTHF')
            download_query = 'TTH/' + @download.tth
          end

          zlig = @client_extensions.include?('ZLIG') ? ' ZL1' : ''

          send_message 'ADCGET', "file #{download_query} " +
            "#{@download.offset} #{@download.size}#{zlig}"

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

      # When closing this connection, make sure that we've finished any
      # current download and published all necessary events.
      def unbind
        super

        Fargo.logger.debug "#{self} Disconnected from: #{@other_nick}"

        if @download
          download_failed! @last_error, :recvd => @recvd, :length => @length
        end

        reset_download
      end

      protected

      # Fail a download for a specific reason. The current download will be
      # finished and events will be published as necessary.
      def download_failed! msg, opts = {}
        Fargo.logger.info "[download-failed] - #{msg} #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        @client.channel << [:download_failed, opts.merge(:nick => @other_nick,
                                             :download   => download.to_h,
                                             :file       => path,
                                             :last_error => msg)]
      end

      # Called when a download finishes. Resets the download and the state of
      # this connection so we're back to being able to download again.
      def download_finished!
        Fargo.logger.debug "#{self}: Finished download of #{@download}"

        # cache because publishing must be at end of method and we're about to
        # clear these
        path, download = download_path, @download

        reset_download

        @client.channel << [:download_finished,
            {:file => path, :download => download.to_h, :nick => @other_nick}]

        # We don't want to keep around connections for file lists. It's not a
        # high change we'll download anything from this peer anyway.
        close_connection_after_writing if download.file_list?
      end

      # Reset all state information of this connection. The current download,
      # if any, is cancelled afterwards.
      def reset_download
        @file.close unless @file.nil? || @file.closed?

        # Clean up empty files to prevent litter.
        if @file_path && File.exists?(@file_path) && File.size(@file_path) == 0
          File.delete(@file_path)
        end

        # clear out these variables
        @inflator = @file_path = @zlib = @download = @length = @recvd = nil
        @get_sent = @getblock_sent = false

        # Go back to the get step
        @handshake_step = 5
      end

      # Helper to generate a unique filename to download a file into. The result
      # is cached in the @file_path variable.
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
