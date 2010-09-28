module Fargo
  module Protocol
    module PeerUpload

      CHUNKSIZE = 16 * 1024

      def receive_message type, message
        case type
          when :adcget, :getzblock, :getblock, :get
            if message[:file] == 'files.xml.bz2'
              @listing = 'filelist'
            else
              @listing = @client.listing_for message[:file].gsub("\\", '/')
            end
            @size   = message[:size] == -1 ? listing.size : message[:size]
            @offset = message[:offset]

            @zlib = message[:zlib]

            if @listing.nil?
              if type == :getzblock || type == :getblock
                send_message 'Failed', 'File Not Available'
              else
                send_message 'Error', 'File Not Available'
              end
            elsif @client.open_upload_slots == 0
              send_message 'MaxedOut'
            elsif type == :adcget
              send_message 'ADCSND',
                  "#{message[:kind]} #{message[:file]} #{@offset} #{@size}"

              begin_streaming
            elsif type == :getzblock || type == :getblock
              if message[:size] == -1
                send_message 'Sending'
              else
                send_message 'Sending', @size
              end

              begin_streaming
            else
              send_message 'FileLength', @size
            end

          when :send
            begin_streaming

          when :cancel
            cancel_streaming

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
        end
      end

    end
  end
end
