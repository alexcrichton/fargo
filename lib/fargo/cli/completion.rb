require 'fargo/ext/readline'

module Fargo
  module CLI
    module Completion
      extend ActiveSupport::Concern

      def setup_readline_completion
        old_proc = Readline.completion_proc
        Readline.basic_word_break_characters = " \t\n\\'`><=;|&{("
        Readline.basic_quote_characters = ''

        Readline.completion_proc = lambda { |str|
          input = Readline.get_input

          candidates  = []
          regex, proc = self.class.completions.detect{ |k, _| input.match k }
          candidates  = proc.call client if proc

          if candidates.empty?
            old_proc.call str
          else
            str = str.gsub /^"/, ''
            candidates.select{ |n| n.start_with? str }.map{ |s| s.inspect }
          end
        }
      end

      module ClassMethods
        def add_completion regex, &block
          @completions ||= {}
          @completions[regex] = block
        end

        def completions
          @completions
        end
      end

    end
  end
end
