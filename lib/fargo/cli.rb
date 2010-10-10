require 'drb'
require 'irb'
require 'em-http-request'
require 'hirb'
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
        ws = EventMachine::HttpRequest.new('ws://localhost:9091/').get(
          :timeout => 0)

        ws.stream { |msg|
          Readline.above_prompt{
            puts "Recieved: #{Marshal.load(msg).inspect}"
          }
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

    module Methods
      include Hirb::Console

      def client
        @fargo_client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
      end

      def client= client
        @fargo_client = client
      end

      def results str
        results = client.search_results str

        to_print = results.map do |r|
          {
            :nick => r[:nick],
            :ext  => File.extname(r[:file]),
            :file => File.basename(r[:file].gsub("\\", '/')),
            :size => '%.2f' % [r[:size] / 1024.0 / 1024]
          }
        end

        to_print.each_with_index do |r, i|
          r[:index] = i
        end

        Readline.above_prompt {
          table to_print, :fields => [:index, :nick, :ext, :size, :file]
        }
      end

      def search str
        client.search str
        sleep 1

        results str
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

    end

    extend Methods
  end
end
