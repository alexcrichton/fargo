module Fargo
  module Supports
    module Chat

      def initialize *args
        super

        @public_chats = []
        @chats        = Hash.new{ |h, k| h[k] = [] }

        channel.subscribe do |type, map|
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

      def messages
        @public_chats
      end

      def messages_with nick
        @chats[nick]
      end

    end
  end
end
