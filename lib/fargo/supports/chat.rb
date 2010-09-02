module Fargo
  module Supports
    module Chat
      
      def self.included(base)
        base.after_setup :subscribe_to_chats
      end
      
      def messages
        @public_chats
      end
      
      def messages_with nick
        @chats[nick] if @chats
      end
      
      def subscribe_to_chats
        @public_chats = []
        @chats = Hash.new{ |h, k| h[k] = [] }

        subscribe do |type, map|
          if type == :chat
            @public_chats << map
          elsif type == :privmsg
            @chats[map[:from]] << map
          elsif type == :hub_disconnected
            @chats.clear
            @public_chats.clear
          end
        end
      end
    end
  end
end