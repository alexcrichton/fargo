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

      begin
        console.client.connected?
      rescue DRb::DRbConnError
        Thread.start{ EventMachine.run{
          console.client = Fargo::Client.new
          console.client.connect
        } }
      end

      console.log_published_messages

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
