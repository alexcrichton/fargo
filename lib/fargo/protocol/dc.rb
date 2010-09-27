module Fargo
  module Protocol
    module DC

      include Fargo::Parser
      attr_accessor :client

      def post_init
        @received_data = ''
        Fargo.logger.debug 'init'
      end

      def receive_message type, message
        raise 'Implement me please'
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

      def receive_data data
        @received_data << data

        while message = @received_data.slice!(/[^\|]+\|/)
          message.chomp! '|'
          Fargo.logger.debug "#{self}: Received: #{message.inspect}"
          hash = parse_message message
          receive_message hash[:type], hash
        end
      end

      def disconnect_publish_args
        {}
      end

      def unbind
        Fargo.logger.debug 'unbound'

        if client
          connection_type = self.class.name.split('::').last.downcase
          args = [:"#{connection_type}_disconnected", disconnect_publish_args]
          client.channel << args
        end
      end

    end
  end
end
