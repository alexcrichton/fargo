require 'readline/clear_rl'

module Readline
  def above_prompt
    Readline.clear_rl
    yield
    Readline.restore
  end
end