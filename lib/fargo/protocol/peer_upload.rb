module Fargo
  module Protocol
    module PeerUpload

      def receive_message type, message
        case type
          when :adcget, :getzblock, :getblock, :get
            listing = @client.listing_for message[:file]
            size = message[:size] == -1 ? listing.size : message[:size]
            offset = message[:offset]

            zlib = message[:zlib]
            size = message[:size]
            # respond with ADCSND
            # http://www.teamfair.info/wiki/index.php?title=$ADCGET
            #
            # Respond with $Sending
            # http://www.teamfair.info/wiki/index.php?title=GetZBlock
            #
            # respond with $FileLength
            # http://www.teamfair.info/wiki/index.php?title=$FileLength
            #
            # errors
            # http://www.teamfair.info/wiki/index.php?title=$Error

            # Start the download here after responding if necessary
          when :send
            # Begin sending file with $get
        end
      end

      protected

      def stream_file
      end

    end
  end
end
