module Fargo
  module Supports
    module Timeout

      def timeout_response timeout, succeed_subscription
        counter = Fargo::BlockingCounter.new 1

        id = channel.subscribe do |args|
          counter.decrement if succeed_subscription.call(*args)
        end

        yield if block_given?
        counter.wait timeout

        channel.unsubscribe id
      end

    end
  end
end
