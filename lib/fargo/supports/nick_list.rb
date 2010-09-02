module Fargo
  module Supports
    module NickList
      
      def self.included(base)
        base.after_setup :subscribe_to_nicks
      end
      
      def nicks
        @nicks
      end
      
      def info nick
        return nil unless @nick_info
        return @nick_info[nick] if @nick_info.has_key?(nick) || !connected? || !@nicks.include?(nick)
        
        # If we're connected and we don't already have this user's info, ask the server. 
        # We'll wait for 5 second to respond, otherwise we'll just return nil and be done with it
        thread = Thread.current
        block = lambda { |type, map|
          thread.wakeup if map[:type] == :myinfo && map[:nick].to_s == nick.to_s
        }
        hub.subscribe &block
        get_info nick
        sleep 5
        hub.unsubscribe &block
        @nick_info[nick]
      end
      
      def has_slot? nick
        return false if @nick_info.nil?
        @nick_info.delete nick
        info = info nick
        return false if info.nil?
        return true if info[:interest].nil?
        match = info[:interest].match /.*?<.*S:(\d+).*>/
        return true if match.nil?
        Fargo.logger.debug "#{self} User: #{nick} has #{match[1]} open slots"
        return match[1].to_i > 0
      end
      
      def subscribe_to_nicks
        @nicks = []
        @nick_info = {}

        subscribe do |type, map|
          case type
            when :hello
              @nicks << map[:who] unless @nicks.include?(map[:who])
            when :myinfo
              @nick_info[map[:nick]] = map
            when :nick_list
              @nicks = map[:nicks]
            when :quit
              @nicks.delete map[:who]
              @nick_info.delete map[:who]
            when :hub_disconnected
              @nicks.clear
              @nick_info.clear
            when :userip
              map[:users].each_pair{ |nick, ip| @nick_info[nick][:ip] = ip}
          end
        end
      end
    
    end
  end
end