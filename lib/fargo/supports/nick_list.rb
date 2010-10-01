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

      def info nick
        if @nick_info.has_key?(nick) || !connected? || !@nicks.include?(nick)
          return @nick_info[nick]
        end

        # If we're connected and we don't already have this user's info, ask the
        # server. We'll wait for 5 second to respond, otherwise we'll just
        # return nil and be done with it
        info_gotten = lambda{ |type, map|
          type == :myinfo && map[:nick].to_s == nick.to_s
        }
        timeout_response(5, info_gotten){ get_info nick }

        @nick_info[nick]
      end

      # This query must be up to date so remove any cached information we have
      # about the nick so we can get a fresh copy
      def nick_has_slot? nick
        if @search_result_slots[nick] &&
            @search_result_slots[nick][:updated_at] + 10.minutes > Time.now
          return @search_result_slots[nick][:slots] > 0
        end

        @nick_info.try :delete, nick
        info = info nick

        return false if info.nil?
        return true  if info[:interest].nil?

        match = info[:interest].match /.*?<.*S:(\d+).*>/
        return true if match.nil?

        Fargo.logger.debug "#{self} User: #{nick} has #{match[1]} open slots"
        match[1].to_i > 0
      end

      protected

      def initialize_nick_lists
        @nicks     = []
        @nick_info = Hash.new{ |h, k| h[k] = {} }
        @search_result_slots = {}

        channel.subscribe do |type, map|
          case type
            when :hello
              @nicks << map[:nick] unless @nicks.include? map[:nick]
            when :myinfo
              @nick_info[map[:nick]] = map
            when :nick_list
              @nicks = map[:nicks]
            when :quit
              @nicks.delete map[:nick]
              @nick_info.delete map[:nick]
            when :hub_disconnected
              @nicks.clear
              @nick_info.clear
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
