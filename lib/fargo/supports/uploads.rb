require 'active_support/core_ext/module/synchronization'

module Fargo
  module Supports
    module Uploads
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_upload_locks
      end

      def open_upload_slots
        raise NotInReactor unless EM.reactor_thread?
        [config.upload_slots - @taken_slots, 0].max
      end

      def take_slot!
        raise NotInReactor unless EM.reactor_thread?

        if config.upload_slots <= @taken_slots
          false
        else
          @taken_slots += 1
          true
        end
      end

      def release_slot!
        raise NotInReactor unless EM.reactor_thread?
        @taken_slots -= 1
      end

      protected

      def initialize_upload_locks
        @taken_slots = 0
      end

    end
  end
end
