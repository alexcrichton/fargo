require 'readline'

if Readline::VERSION =~ /editline/i
  $stderr.puts "Sorry, fargo CLI requires a ruby compiled against the actual"
  $stderr.puts "Readline library. Your version is: '#{Readline::VERSION}'"
  exit 1
end

require 'readline/extra_utils'

module Readline
  def self.above_prompt
    Readline.clear_rl
    yield
  ensure
    Readline.restore
  end
end
