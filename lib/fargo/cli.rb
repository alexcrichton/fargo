require 'fargo/ext/irb'

module Fargo
  module CLI
    extend ActiveSupport::Autoload

    autoload :Completion
    autoload :Downloads
    autoload :Help
    autoload :Info
    autoload :Logging
    autoload :NickBrowser
    autoload :Searches
    autoload :Stats

    def self.start
      Fargo.logger = ActiveSupport::BufferedLogger.new WrappingLogger.new

      unless ARGV.any?{ |s| s == '-d' }
        Fargo.logger.level = ActiveSupport::BufferedLogger::INFO
      end

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
        else
          Readline.above_prompt {
            puts "ERROR!!!", e.message, e.backtrace.join("\n")
          }
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

      IRB.start_session console.instance_eval{ binding } do
        console.setup_console
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
      include Logging
      include Searches
      include Info
      include Downloads
      include Stats
      include NickBrowser
      include Help

    end

  end
end
