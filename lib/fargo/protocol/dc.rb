module Fargo
  module Protocol
    module DC

      include Fargo::Parser
      attr_accessor :client

      def post_init
        @received_data = ''
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
        Fargo.logger.debug "Receiving: #{data.inspect}"
        @received_data << data

        messages       = @received_data.split '|'
        @received_data = @received_data.end_with?('|') ? '' : messages.pop

        messages.each do |message|
          Fargo.logger.debug "#{self} Received: #{message}"
          hash = parse_message message
          receive_message hash[:type], hash
        end
      rescue => e
        Fargo.logger.warn "Error: #{e.message}"
        Fargo.logger.warn e.backtrace.join("\n")
      end

      def disconnect_publish_args
        {}
      end

      def unbind
        connection_type = self.class.name.split('::').last.downcase
        args = [:"#{connection_type}_disconnected", disconnect_publish_args]
        @client.channel.publish args
      end

    end
  end
end
