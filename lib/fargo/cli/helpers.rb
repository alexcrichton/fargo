require 'drb'
require 'em-http-request'

module Fargo
  module CLI
    module Helpers
      extend ActiveSupport::Concern

      attr_writer :client

      included do
        add_logger(:chat) do |_, message|
          "<#{message[:from]}>: #{message[:text]}"
        end

        add_logger(:hub_disconnected) do |_, _|
          puts "Hub disconnected, exiting..."
          exit
        end
      end

      module ClassMethods
        def add_logger type, &block
          @logging ||= Hash.new{ |h, k| h[k] = [] }
          @logging[type.to_s] << block
        end

        def logging_for type
          @logging[type.to_s]
        end
      end

      def client
        @client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
      end

      def log_published_messages
        streamer = proc {
          host = "ws://#{client.config.websocket_host}" +
                    ":#{client.config.websocket_port}/"
          ws = EventMachine::HttpRequest.new(host).get(:timeout => 0)

          ws.stream { |msg|
            to_log = nil
            type, message = Marshal.load(msg)

            self.class.logging_for(type).each{ |l|
              to_log = l.call self, message
              Readline.above_prompt{ puts to_log } unless to_log.nil?
            }
          }
        }

        if EventMachine.reactor_running?
          EventMachine.schedule streamer
        else
          Thread.start{ EventMachine.run streamer }
        end
      end

      def humanize_bytes bytes
        suffix = 'B'
        while bytes > 1024
          suffix = case suffix
            when 'B' then 'K'
            when 'K' then 'M'
            when 'M' then 'G'
            when 'G' then 'T'
            when 'T' then break
          end

          bytes /= 1024.0
        end

        '%.2f %s' % [bytes, suffix]
      end

    end
  end
end
