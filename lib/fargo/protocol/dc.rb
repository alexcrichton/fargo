module Fargo
  module Protocol
    module DC

      include Parser
      attr_accessor :client

      def post_init
        @received_data = ''
      end

      def receive_message type, message
        client.channel << [type, message] if client
      end

      def send_message method, args = nil
        if args
          data = "$#{method} #{args}|"
        else
          data = "$#{method}|"
        end

        Fargo.logger.debug "#{self} Sending: #{data.inspect}"
        send_data data
      end

      def receive_data_chunk chunk
        chunk.chomp! '|'
        Fargo.logger.debug "#{self}: Received: #{chunk.inspect}"
        hash = parse_message chunk
        receive_message hash[:type], hash
      end

      def parse_data?
        true
      end

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

      def publish_args
        {}
      end

      def connection_type
        :dc
      end

      def unbind
        if client
          args = [:"#{connection_type}_disconnected", publish_args]
          client.channel << args
        end
      end

    end
  end
end
