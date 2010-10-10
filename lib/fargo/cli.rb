require 'fargo/ext/irb'

module Fargo
  module CLI
    extend ActiveSupport::Autoload

    autoload :Helpers
    autoload :Completion
    autoload :Searches
    autoload :Info
    autoload :Downloads
    autoload :Stats

    def self.start
      Fargo.logger = ActiveSupport::BufferedLogger.new WrappingLogger.new
      Fargo.logger.level = ActiveSupport::BufferedLogger::INFO

      console = Console.new

      EventMachine.error_handler { |e|
        if e.message =~ /no acceptor/
          puts "Couldn't open sockets for listening"
          puts "  Ports in question:"
          [console.client.config.active_port, console.client.config.search_port,
              console.client.config.websocket_port].each do |p|
            puts "\t#{p}"
          end
          exit
        end
      }

      begin
        console.client.connected?
      rescue DRb::DRbConnError
        current = Thread.current # Wait for the reactor to start
        Thread.start{ EventMachine.run{
          console.client = Fargo::Client.new
          console.client.connect
          current.wakeup
        } }
        sleep
      end

      console.log_published_messages

      if !console.client.connected?
        puts "Client couldn't connect!"
        exit
      end

      IRB.start_session console.send(:binding) do
        console.setup_readline_completion
      end

      EventMachine.stop
    end

    class WrappingLogger
      def write str
        Readline.above_prompt{ puts str }
      end
    end

    class Console
      include Completion
      include Helpers
      include Searches
      include Info
      include Downloads
      include Stats
    end

  end
end
