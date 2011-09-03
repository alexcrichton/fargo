require 'active_support/core_ext/module/delegation'

module Fargo
  module CLI
    module Info

      delegate :send_chat, :to => :client
      alias :say :send_chat

      def setup_console
        super

        add_completion(/^who\s+[^\s]*$/) { client.nicks + ['size', 'name'] }
      end

      def who sort_by = nil
        print_nick = lambda{ |p|
          printf "%10s %s\n", humanize_bytes(p[1]), p[0]
        }

        if client.nicks.include? sort_by
          client.info(sort_by) do |info|
            key_len = info.keys.map{ |k| k.to_s.length }.max
            Readline.above_prompt {
              info.each_pair do |k, v|
                next if k == :type

                printf "%#{key_len}s: %s\n", k,
                  v.is_a?(Numeric) ? humanize_bytes(v) : v
              end
            }
          end

        elsif sort_by.nil?
          client.nicks.each do |n|
            client.sharesize(n) do |size|
              Readline.above_prompt { print_nick.call [n, size] }
            end
          end

        else
          if sort_by != 'name' && sort_by != 'size'
            puts "Unknown sorting by: #{sort_by.inspect}"
            return false
          end

          nicks_left = client.nicks.dup
          pairs = []
          defer = EventMachine::DefaultDeferrable.new
          print_all = proc {
            if sort_by == 'name'
              pairs = pairs.sort_by{ |p| p[0] }
            elsif sort_by == 'size'
              pairs = pairs.sort_by{ |p| p[1] }
            end
            Readline.above_prompt {
              puts "Unknown: #{nicks_left.inspect}" if nicks_left.any?
              pairs.each &print_nick
            }
          }
          defer.callback &print_all
          defer.errback &print_all
          defer.timeout 5

          client.nicks.each do |n|
            client.sharesize(n) do |size|
              nicks_left.delete n
              pairs << [n, size]
              defer.succeed if nicks_left.empty?
            end
          end

        end

        true
      end

    end
  end
end
