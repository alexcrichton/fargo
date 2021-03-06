require 'drb'
require 'em-http-request'

module Fargo
  module CLI
    module Logging

      attr_accessor :client, :client_uri

      def setup_console
        super

        add_logger(:chat) do |message|
          "<#{message[:from]}>: #{message[:text]}"
        end

        add_logger(:hub_disconnected) do |_|
          puts "Hub disconnected, exiting..."
          exit
        end
      end

      def add_logger type, &block
        @logging[type.to_s] << block
      end

      def client
        @client ||= DRbObject.new_with_uri client_uri
      end

      def log_published_messages
        @logging = Hash.new{ |h, k| h[k] = [] }

        if client.is_a?(Fargo::Client)
          client.channel.subscribe do |type, message|
            @logging[type.to_s].each{ |l|
              to_log = l.call message
              Readline.above_prompt{ puts to_log } unless to_log.nil?
            }
          end
        else
          streamer = proc {
            host = "ws://#{client.config.websocket_host}" +
                      ":#{client.config.websocket_port}/"

            ws = EventMachine::HttpRequest.new(host).get(:timeout => 0)

            ws.disconnect { Fargo.logger.info "Stopping logging stream." }
            ws.callback { Fargo.logger.info "Streaming logging messages." }
            ws.stream { |msg|
              to_log = nil
              type, message = Marshal.load(Base64.decode64(msg))

              @logging[type.to_s].each{ |l|
                to_log = l.call message
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
      end

      protected

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
