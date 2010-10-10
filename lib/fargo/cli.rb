require 'drb'
require 'irb'
require 'em-http-request'
require 'fargo/ext/readline'
require 'fargo/ext/irb'

module Fargo
  module CLI

    def self.start
      Fargo.logger = ActiveSupport::BufferedLogger.new WrappingLogger.new
      Fargo.logger.level = ActiveSupport::BufferedLogger::INFO

      begin
        client.connected?
      rescue DRb::DRbConnError
        Thread.start{ EventMachine.run{
          self.client = Fargo::Client.new
          client.connect
        } }
      end

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
              to_log = "New search result"
          end

          Readline.above_prompt{ puts to_log } unless to_log.nil?
        }
      }

      if EventMachine.reactor_running?
        EventMachine.schedule streamer
      else
        Thread.start{ EventMachine.run streamer }
      end

      IRB.start_session binding

      EventMachine.stop
    end

    class WrappingLogger
      def write str
        Readline.above_prompt{ puts str }
      end
    end

    module Helpers
      def client
        @fargo_client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
      end

      def client= client
        @fargo_client = client
      end

      def results str
        results = client.search_results(str).dup

        if results.nil?
          puts "No search results for: #{str.inspect}!"
          return
        end

        results.each{ |r| r[:file] = File.basename(r[:file].gsub("\\", '/')) }

        max_nick_size = results.map{ |r| r[:nick].size }.max

        results.each_with_index do |r, i|
          printf "%3d: %#{max_nick_size}s %9s -- %s\n", i,
            r[:nick], humanize_bytes(r[:size]), r[:file]
        end

        true
      end

      def search str
        client.search str
      end

      def download index, search = nil
        search ||= client.searches[0]

        item = client.search_results(search)[index]

        if item.nil?
          puts 'That is not something to download!'
        else
          client.download item[:nick], item[:file], item[:tth]
        end
      end

      def who
        client.nicks.each do |n|
          printf "%10s %s\n", humanize_bytes(client.info(n)[:sharesize]), n
        end

        true
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

    extend Helpers
  end
end
