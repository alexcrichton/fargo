module Fargo
  module Protocol
    # Implementation for the protocol of uploading files to peers. This is meant
    # to be included in the Peer module and it will handle the necessary methods
    # to upload files. This module does not contain the implementation of the
    # initial handshake, but rather assumes that it's taken care of elsewhere.
    #
    # Files are uploaded in chunks of CHUNKSIZE and the upload is cancellable.
    # This module publishes no events to its client's channel.
    module PeerUpload

      CHUNKSIZE = 16 * 1024

      # There are multiple ways to download a file, but all known ways are
      # supported here. Mostly they're just differences in syntax, and you
      # can tell below what's what.
      def receive_message type, message
        case type
          when :adcget, :getblock, :get
            if @handshake_step != 5
              error "#{type} received before handshake complete"
              return
            end

            if message[:file] == 'files.xml.bz2'
              @listing = 'filelist'
            else
              @listing = @client.listing_for message[:file].gsub("\\", '/')
            end

            if message[:size] == -1
              if @listing == 'filelist'
                @size = File.size @client.local_file_list_path
              else
                @size = @listing.try :size
              end
            else
              @size = message[:size]
            end

            @offset = message[:offset]
            @zlib   = message[:zlib]

            # Send the correct error message if there's no actual file
            if @listing.nil?
              if type == :getblock
                send_message 'Failed', 'File Not Available'
              else
                send_message 'Error', 'File Not Available'
              end

            # As per MiniSlots, file lists don't take up a slot
            elsif @listing != 'filelist' && !@client.take_slot!
              send_message 'MaxedOut'

            # Handle each upload type separately
            elsif type == :adcget
              zl = @zlib ? ' ZL1' : ''
              send_message 'ADCSND',
                "#{message[:kind]} #{message[:file]} #{@offset} #{@size}#{zl}"

              begin_streaming
            elsif type == :getblock
              if message[:size] == -1
                send_message 'Sending'
              else
                send_message 'Sending', @size
              end

              begin_streaming
            else
              # Actual streaming beings when the $Send command is received
              @handshake_step = 10

              send_message 'FileLength', @size
            end

          when :send
            if @handshake_step == 10
              begin_streaming
            else
              error ":send received before handshake or FileLength received"
            end

          when :cancel
            if @handshake_step == 11
              cancel_streaming
            else
              error "Cancel received when we're not streaming"
            end

          else
            super
        end
      end

      # Makes sure that all streaming has finished before we completely exit
      def unbind
        super

        if @listing
          Fargo.logger.debug "Upload disconnected"
          finish_streaming
        end
      end

      protected

      # Actually begins the raw streaming of the file. The file will be sent in
      # chunks, and the first chunk is sent immediately. On the next tick of the
      # EM reactor where the first chunk is sent, the next chunk will be
      # uploaded to the peer.
      def begin_streaming
        # As per MiniSlots, file lists don't take up a slot
        if @listing == 'filelist'
          @file = File.open @client.local_file_list_path, 'rb'
        else
          @file = File.open File.join(@listing.root, @listing.name), 'rb'
        end

        @handshake_step = 11
        @file.seek @offset
        @deflator = Zlib::Deflate.new if @zlib
        @sent     = 0
        @looping  = true

        stream_file
      end

      # Concludes all streaming, closing the file handle for uploading and
      # releasing our upload slot back to the client. All other state variables
      # are reset as well.
      def finish_streaming
        @file.close unless @file.nil?

        if @listing != 'filelist'
          @client.release_slot!
        end

        @deflator = @file = @sent = @size = @offset = @listing = @zlib = nil
        @looping = @canceled = false
        @handshake_step = 5
      end

      # Cancel all streaming. A little more data will be sent, but eventually
      # the upload will be canceled and no more new data will be queued for
      # upload. This happens asynchronously in the stream_file function.
      def cancel_streaming
        @looping = false
        @canceled = true
      end

      # Stream chunks of the file to the peer. This function will queue up
      # chunks to be sent so long as they're being received at the same rate.
      # Otherwise, after enough data has been queued up for sending, streaming
      # will defer to the next tick of the reactor to continue streaming.
      #
      # This loop is cancellable via #cancel_streaming.
      def stream_file
        while @looping do
          if @sent < @size
            if get_outbound_data_size > 4 * CHUNKSIZE
              EventMachine.next_tick{ stream_file }
              break
            else
              to_send = [CHUNKSIZE, @size - @sent].min
              @sent += to_send

              data = @file.read to_send
              if @zlib
                flush_flag = (@sent == @size ? Zlib::FINISH : Zlib::NO_FLUSH)
                data = @deflator.deflate data, flush_flag
              end

              send_data data
            end
          else
            finish_streaming
            break
          end
        end

        if @canceled
          send_message 'Canceled'
          finish_streaming
        end
      end

    end
  end
end
