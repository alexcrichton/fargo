module Fargo
  module Protocol
    module PeerUpload

      CHUNKSIZE = 16 * 1024

      def receive_message type, message
        case type
          when :adcget, :getblock, :get
            if @handshake_step == 5
              if message[:file] == 'files.xml.bz2'
                @listing = 'filelist'
              else
                @listing = @client.listing_for message[:file].gsub("\\", '/')
              end
              @size   = message[:size] == -1 ? listing.size : message[:size]
              @offset = message[:offset]
              @zlib   = message[:zlib]

              if @listing.nil?
                if type == :getblock
                  send_message 'Failed', 'File Not Available'
                else
                  send_message 'Error', 'File Not Available'
                end
              elsif @client.open_upload_slots == 0 && @listing != 'filelist'
                send_message 'MaxedOut'
              elsif type == :adcget
                send_message 'ADCSND',
                    "#{message[:kind]} #{message[:file]} #{@offset} #{@size}"

                begin_streaming
              elsif type == :getblock
                if message[:size] == -1
                  send_message 'Sending'
                else
                  send_message 'Sending', @size
                end

                begin_streaming
              else
                @handshake_step = 10

                send_message 'FileLength', @size
              end
            else
              error "Premature disconnect when #{type} received"
            end

          when :send
            if @handshake_step == 10
              begin_streaming
            else
              error "Premature disconnect when #{type} received"
            end

          when :cancel
            if @handshake_step == 11
              cancel_streaming
            else
              error "Premature disconnect when cancel received"
            end

          else
            super
        end
      end

      def unbind
        super

        if @listing
          Fargo.logger.debug "Upload disconnected"
          finish_streaming
        end
      end

      protected

      def begin_streaming
        @handshake_step = 11

        if @listing == 'filelist'
          @file = File.open @client.local_file_list_path, 'rb'
        else
          @client.take_slot! self
          @file = File.open File.join(@listing.root, @listing.name), 'rb'
        end

        @file.seek @offset
        @deflator = Zlib::Deflate.new if @zlib
        @sent     = 0
        @looping  = true

        stream_file
      end

      def finish_streaming
        @file.close

        if @listing == 'filelist'
          close_connection_after_writing
        else
          @client.release_slot!
        end

        @deflator = @file = @sent = @size = @offset = @listing = @zlib = nil
        @looping = false
        @handshake_step = 5
      end

      def cancel_streaming
        @looping = false
      end

      def stream_file
        while @looping do
          if @sent < @size
            if get_outbound_data_size > 4 * CHUNKSIZE
              EventMachine.next_tick{ stream_file }
              break
            else
              to_send = [CHUNKSIZE, @size - @read].min

              data = @file.read to_send
              data = @deflator.deflate data if @zlib

              send_data data
              @sent += to_send
            end
          else
            finish_streaming
            break
          end
        end

        if !@looping # Set to false because $Cancel was sent
          send_message 'Canceled'
          finish_streaming
        end
      end

    end
  end
end