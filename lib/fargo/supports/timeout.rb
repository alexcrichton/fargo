module Fargo
  module Supports
    module Timeout
      
      def timeout_response timeout, succeed_subscription
        thread = Thread.current
        subscribed_block = lambda do |*args|
          thread.wakeup if succeed_subscription.call(*args)
        end

        subscribe &subscribed_block
        yield
        sleep timeout
        unsubscribe &subscribed_block
      end

    end
  end
end
