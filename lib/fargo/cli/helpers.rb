require 'drb'
require 'em-http-request'

module Fargo
  module CLI
    module Helpers

      def client
        @fargo_client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
      end

      def client= client
        @fargo_client = client
      end

      def log_published_messages
        streamer = proc {
          host = "ws://#{client.config.websocket_host}" +
                    ":#{client.config.websocket_port}/"
          ws = EventMachine::HttpRequest.new(host).get(:timeout => 0)

          ws.stream { |msg|
            to_log = nil
            type, message = Marshal.load(msg)

            case type
              when :chat
                to_log = "<#{message[:from]}>: #{message[:text]}"
              when :search_result
                obj = client.search_objects.detect{ |s| s.matches? message }
                if obj
                  to_log = "New search result for: #{obj.query.inspect}"
                else
                  to_log = "New search result"
                end
            end

            Readline.above_prompt{ puts to_log } unless to_log.nil?
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
