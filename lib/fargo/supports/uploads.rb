require 'active_support/core_ext/module/synchronization'

module Fargo
  module Supports
    module Uploads
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_upload_locks
      end

      def open_upload_slots
        [config.upload_slots - @taken_slots, 0].max
      end

      def take_slot!
        @taken_slots -= 1
      end

      def release_slot!
        @taken_slots += 1
      end

      synchronize :take_slot!, :release_slot!, :with => :@upload_slot_lock

      protected

      def initialize_upload_locks
        @upload_slot_lock = Mutex.new
        @taken_slots      = 0
      end

    end
  end
end
