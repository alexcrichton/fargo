require 'logger'
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

    # Start a CLI session in the current process. STDOUT will be used as the
    # output. A local DRb server will be used as the Fargo client, but if it's
    # unavailable a local instance of a client will be started.
    #
    # Command line flags should be in ARGV
    #   -d : debug output
    def self.start
      if ARGV.any?{ |s| s == '--verbose' }
        Fargo.logger = Logger.new WrappingLogger.new
      else
        log = File.open(Fargo.config.config_dir + '/log', 'w')
        Fargo.logger = Logger.new log
      end
      Fargo.logger.datetime_format = ''

      console = Console.new

      # Provide some nice debug output when we hit an error
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

      # Try to use a client over DRb, fall back to a local EM reactor
      begin
        console.client_uri = 'druby://127.0.0.1:8082'
        console.client.connected?
        Fargo.logger.info "Using DRb server at: #{console.client_uri}"
        console.log_published_messages
      rescue DRb::DRbConnError
        console.client = Fargo::Client.new
        console.log_published_messages
        counter = Fargo::BlockingCounter.new 1
        Thread.start{ EventMachine.run{
          console.client.connect
          counter.decrement
        } }
        counter.wait 5
        Fargo.logger.info "Using local DC client"
      end

      if !console.client.connected?
        puts "Client couldn't connect to hub on: #{console.client.hub_url}"
        exit
      end

      # Run the actual IRB session, although before running the session, setup
      # the console when IRB is almost ready.
      IRB.start_session console.instance_eval{ binding } do
        console.setup_console
      end

      # Time to exit. Make sure EM is dead.
      EventMachine.stop
    end

    # Wrapper class for logging messages to Readline.above_prompt
    class WrappingLogger
      def write str
        Readline.above_prompt{ puts str }
      end
      def close
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
