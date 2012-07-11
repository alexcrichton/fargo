module Fargo
  # A class to throttle the number of events per second. The #throttle method
  # takes a block which is conditionally yielded to depending on whether the
  # qps rate is being exceeded.
  class Throttler

    # Creates a new throttler with the specified maximum queries per second
    # allowed through.
    #
    # @param [Integer] qps the number of queries that should be allowed every
    #   second through the #throttle method
    def initialize qps
      @qps = qps
    end

    # Starts the throttling, should be called before #throttle is invoked.
    def start_throttling
      @processed = false
      @timer = EventMachine::PeriodicTimer.new(1.0 / @qps) do
        @processed = false
      end
    end

    # Throttle a block of code. Only the specified QPS of times will the block
    # be invoked every second
    #
    # @yield only if the throttling rate allows the block to be invoked.
    def throttle
      if !@processed
        yield
        @processed = true
      end
    end

    # Stops throttling, cleans up after ourselves.
    def stop_throttling
      @timer.cancel
      @timer = nil
    end

  end
end
