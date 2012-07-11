require 'thread'

module Fargo
  # A BlockingCounter is a synchronization tool in which one thread calls wait
  # until other threads have called decrement +@cnt+ times.
  #
  # Once the counter has been used, it cannot be used again.
  class BlockingCounter

    # Creates a new counter with initial count of +cnt+.
    #
    # @param [Integer] cnt the number of times {#decrement} will be called
    #   before {#wait} will return
    def initialize cnt
      @cnt      = cnt
      @mutex    = Mutex.new
      @cond_var = ConditionVariable.new
    end

    # Decrement the current value on this counter. If the counter has reached
    # 0, then the waiting thread will be woken up.
    def decrement
      @mutex.synchronize {
        raise 'Counter already at 0' if @cnt == 0
        @cnt -= 1
        @cond_var.broadcast if @cnt == 0
      }
    end

    # Wait for the count to reach 0 on this counter. If the counter has already
    # reached 0, then this will return immediately.
    #
    # @param [Integer] timeout if provided, wait at most this many seconds.
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
