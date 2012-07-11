module Fargo
  module Supports
    module Chat
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_chats
        set_callback :connect, :after, :periodically_remove_chats
      end

      def messages
        @public_chats
      end

      def messages_with nick
        @chats[nick]
      end

      def send_chat text
        hub.send_data "<#{config.nick}> #{text}|"
      end

      protected

      def periodically_remove_chats
        EventMachine.add_periodic_timer 60 do
          @public_chats = @public_chats[0...100]

          @chats.each_pair do |k, v|
            @chats[k] = v[0...100]
          end
        end
      end

      def initialize_chats
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

    end
  end
end
