require 'readline'
require 'readline/extra_utils'

module Readline
  def self.above_prompt
    Readline.clear_rl
    yield
  ensure
    Readline.restore
  end
end
