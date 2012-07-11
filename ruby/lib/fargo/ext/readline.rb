require 'readline'

if Readline::VERSION =~ /editline/i
  $stderr.puts "Sorry, fargo CLI requires a ruby compiled against the actual"
  $stderr.puts "Readline library. Your version is: '#{Readline::VERSION}'"
  exit 1
end

require 'readline/extra_utils'

# Extend the Readline module to allow some extra special wizardry when printing
# information to the console. There aren't existing ruby APIs for this, so there
# is a small C extension with thie project to add the functionality needed.
module Readline

  # Create a state where information printed will appear above the current
  # readline prompt in a terminal.
  #
  # @yield any information printed inside the given block will appear above the
  #   current readline.
  def self.above_prompt
    Readline.clear_rl
    yield
  ensure
    Readline.restore
  end
end
