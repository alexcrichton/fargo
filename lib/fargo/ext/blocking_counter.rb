require 'thread'

module Fargo
  class BlockingCounter

    def initialize cnt
      @cnt      = cnt
      @mutex    = Mutex.new
      @cond_var = ConditionVariable.new
    end

    def decrement
      @mutex.synchronize {
        raise 'Counter already at 0' if @cnt == 0
        @cnt -= 1
        @cond_var.broadcast if @cnt == 0
      }
    end

    def wait timeout = nil
      @mutex.synchronize {
        if @cnt != 0
          if timeout
            @cond_var.wait @mutex, timeout
          else
            @cond_var.wait @mutex
          end
        end
      }
    end

  end
end
