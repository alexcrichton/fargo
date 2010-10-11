require 'fargo/ext/readline'

module Fargo
  module CLI
    module Completion

      def setup_console
        old_proc = Readline.completion_proc
        Readline.basic_word_break_characters = " \t\n\\'`><=;|&{("
        Readline.basic_quote_characters = ''

        Readline.completion_proc = lambda { |str|
          input = Readline.get_input

          candidates, data = [], nil
          regex, proc = @completions.detect{ |k, _|
            data = input.match(k)
          }
          if data
            data = data.to_a
            data.shift
            candidates = proc.call *data
          end

          if candidates.empty?
            old_proc.call str
          else
            str = str.gsub /^"/, ''
            candidates.select{ |n| n.start_with? str }.map{ |s| s.inspect }
          end
        }
      end

      def add_completion regex, &block
        @completions ||= {}
        @completions[regex] = block
      end

    end
  end
end
