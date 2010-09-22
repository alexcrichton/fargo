module Fargo
  module Publisher

    attr_reader :subscribers

    def subscribe &subscriber
      raise RuntimeError.new('Need a subscription block!') if subscriber.nil?

      Fargo.logger.debug "#{self}: subscribing #{subscriber}"
      (@subscribers ||= []) << subscriber
    end

    def subscribed_to?
      @subscribers && @subscribers.size > 0
    end

    def unsubscribe &subscriber
      raise RuntimeError.new('Need a subscription block!') if subscriber.nil?

      Fargo.logger.debug "#{self}: unsubscribing #{subscriber}"
      (@subscribers ||= []).delete subscriber
    end

    def publish message_type, hash = {}
      @subscribers ||= []

      to_remove = []

      @subscribers.each do |subscriber|
        begin
          subscriber.call message_type, hash
        rescue => e
          Fargo.logger.warn "#{self}: error publishing to: #{subscriber}! #{e}"
          to_remove << subscriber
        end
      end

      @subscribers -= to_remove
    end

  end
end
