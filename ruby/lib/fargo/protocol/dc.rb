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
        @buffer = BufferedTokenizer.new '|'
        @parsing = true
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

        client.debug "out-#{connection_type}", data, RED
        send_data data
      end

      # Receives an arbitrary chunk of data manages internal state of parsing as
      # well. This method will only parse data
      #
      # This is an implementation of the EM api.
      def receive_data data
        return receive_binary_data data unless @parsing

        @buffer.extract(data).each do |chunk|
          if @parsing
            chunk.chomp! '|'
            client.debug "in-#{connection_type}", chunk, GREEN
            hash = parse_message chunk
            receive_message hash[:type], hash
          else
            receive_binary_data chunk + '|'
          end
        end

        if !@parsing
          buffer = @buffer.flush
          receive_binary_data buffer if buffer.length > 0
        end
      end

      # Override this data if you ever set the @parsing variable to false. This
      # method will be called from the #receive_data method whenever data is
      # received on the connection.
      def receive_binary_data data
        raise 'Needs to be overridden if @parsing is false'
      end

      # Overridable method to publish different arguments.
      def publish_args
        {}
      end

      # Human-readable type of connection this is.
      def connection_type
        :dc
      end

      def inspect
        "#<Connection(#{connection_type}) ...>"
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
