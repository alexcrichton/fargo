module Fargo
  module Supports
    module Timeout

      def timeout_response timeout, succeed_subscription
        thread = Thread.current

        subscribed_block = lambda do |args|
          thread.wakeup if succeed_subscription.call(*args)
        end

        id = channel.subscribe subscribed_block

        yield if block_given?
        sleep timeout

        channel.unsubscribe id
      end

    end
  end
end
