require 'active_support/core_ext/numeric/time'

module Fargo
  module Supports
    module NickList
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_nick_lists
      end

      attr_accessor :nicks

      def get_info nick
        hub.send_message 'GetINFO', "#{nick} #{config.nick}"
      end

      def get_ip *nicks
        hub.send_message 'UserIP', nicks.flatten.join('$$')
      end

      # Send a $GetINFO request to the hub for the specified peer.
      #
      # @param [String] nick the peer to get information about
      # @param [Integer] timeout the maximum amount of time (in seconds) to wait
      #   before the supplied block will be called.
      # @param [Proc] block once information is retrieved, then this callback
      #   will be invoked with the info retrieved from the nick. If the timeout
      #   expires before we have information, the block will be invoked with
      #   nil.
      def info nick, timeout = 5, &block
        deferrable = EventMachine::DefaultDeferrable.new
        @info_deferrables[nick] = deferrable
        deferrable.timeout timeout
        deferrable.callback &block
        deferrable.errback {
          @info_deferrable.delete nick
          block.call nil
        }

        get_info nick
      end

      # Test whether the remote peer has a slot for downloading a file. This
      # information might be cached, so the supplied block might be invoked
      # immediately.
      #
      # @param [String] nick the remote peer to inspect
      # @param [Proc] block the callback which will be invoked with one
      #   boolean parameter whether the nick had a slot or not.
      def nick_has_slot? nick, &block
        raise ArgumentError.new 'Need a block!' if block.nil?
        if @search_result_slots.key?(nick) &&
           Time.now < @search_result_slots[nick][:updated_at] + 1.minute
          block.call @search_result_slots[nick][:slots] > 0
        end

        info nick do |map|
          if map.nil?
            # Timed out? No slots...
            block.call false
          elsif map[:interest].nil?
            # No interest given, assume has a slot
            block.call true
          elsif match = info[:interest].match(/.*?<.*S:(\d+).*>/)
            debug 'slots', "User: #{nick} has #{match[1]} open slots"
            block.call match[1].to_i > 0
          else
            # Couldn't parse, assume has a slot
            block.call true
          end
        end

      end

      protected

      def initialize_nick_lists
        @nicks     = []
        @info_deferrables = {}
        @search_result_slots = {}

        channel.subscribe do |type, map|
          case type
            when :hello
              @nicks << map[:nick] unless @nicks.include? map[:nick]
            when :myinfo
              deferrable = @info_deferrables.delete map[:nick]
              deferrable.succeed map if deferrable
            when :nick_list
              @nicks = map[:nicks]
            when :quit
              deferrable = @info_deferrables.delete map[:nick]
              deferrable.fail if deferrable
              @nicks.delete map[:nick]
            when :hub_disconnected
              @nicks.clear
              @info_deferrables.each_value { |v| v.fail }
              @info_deferrables.clear
            when :userip
              map[:users].each_pair{ |nick, ip| @nick_info[nick][:ip] = ip }
            when :search_result
              @search_result_slots[map[:nick]] = {
                :slots      => map[:open_slots],
                :updated_at => Time.now
              }
          end
        end
      end

    end
  end
end
