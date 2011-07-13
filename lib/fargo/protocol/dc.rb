module Fargo
  module Protocol

    # Implemtation of the syntax of the DC protocol. This module is used by both
    # Peer and Hub connections. Arbitrary chunks of data are parsed into
    # messages and delivered appropriately.
    #
    # Published events are:
    #   :#{connection_type}_disconnected => overridable human-readable
    #          description of what kind of connection just disconnected.
    #
    # @see Fargo::Parser
    module DC

      include Parser
      attr_accessor :client

      def post_init
        @received_data = ''
      end

      # Overridable method to receive a message from this connection. Other
      # modules/classes should override this behavior and delgate to this as
      # necessary. The default behavior is to publish the type/message to the
      # client and do nothing else
      #
      # @param [Symbol] type the type of message that was received
      # @param [Hash] message the hash of information associated with this type
      def receive_message type, message
        client.channel << [type, message] if client
      end

      # Send a DC message to the other end of this connection.
      #
      # @param [String] method the name of the method to send to the client. No
      #   extra parsing is done of this argument, so it should be the raw method
      #   name as dictated by the DC protocol
      # @param [String] args if present, these arguments will also be included
      #   in the message sent (no extra parsing)
      def send_message method, args = nil
        if args
          data = "$#{method} #{args}|"
        else
          data = "$#{method}|"
        end

        send_data data
      end

      # Receive a chunk of data from the connection. This chunk is either a
      # message delimited by '$' and '|', or it's binary data depending on the
      # current #parse_data?
      #
      # This method is overridable for downloads to receive binary data
      # correctly from the internal state management of this module. The default
      # functionality is to parse the chunk of data and then call
      # #receive_message.
      #
      # @param [String] chunk the data received.
      def receive_data_chunk chunk
        chunk.chomp! '|'
        Fargo.logger.debug "#{self}: Received: #{chunk.inspect}"
        hash = parse_message chunk
        receive_message hash[:type], hash
      end

      # Flag if data should be parsed currently. This is meant to stop parsing
      # when receiving binary data when downloading a file.
      #
      # @return [Boolean] whether to parse incoming data or send it directly to
      #   #receive_data_chunk
      def parse_data?
        true
      end

      # Receives an arbitrary chunk of data and makes necessary calls to
      # #receive_data_chunk. Manages internal state of parsing as well.
      #
      # This is an implementation of the EM api.
      def receive_data data
        if parse_data?
          @received_data << data

          while parse_data? && chunk = @received_data.slice!(/[^\|]+\|/)
            receive_data_chunk chunk
          end
        else
          receive_data_chunk @received_data + data
          @received_data = ''
        end
      end

      # Overridable method to publish different arguments.
      def publish_args
        {}
      end

      # Human-readable type of connection this is.
      def connection_type
        :dc
      end

      # Publishes disconnect information if we have a client.
      def unbind
        if client
          client.channel << [:"#{connection_type}_disconnected", publish_args]
        end
      end

    end
  end
end
