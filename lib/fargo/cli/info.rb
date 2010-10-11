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
        print_nick = lambda{ |n, s| printf "%10s %s\n", humanize_bytes(s), n }

        if client.nicks.include? sort_by
          info = client.info(sort_by)
          key_len = info.keys.map{ |k| k.to_s.length }.max

          info.each_pair do |k, v|
            next if k == :type
            printf "%#{key_len}s: %s\n", k,
              v.is_a?(Numeric) ? humanize_bytes(v) : v
          end
        elsif sort_by.nil?
          client.nicks.each do |n|
            print_nick.call n, client.info(n)[:sharesize]
          end
        else
          pairs = client.nicks.map{ |n|
            [n, client.info(n)[:sharesize]]
          }

          if sort_by == 'name'
            pairs = pairs.sort_by{ |p| p[0] }
          elsif sort_by == 'size'
            pairs = pairs.sort_by{ |p| p[1] }
          else
            pairs = []
            puts "Unknown sorting by: #{sort_by.inspect}"
          end

          pairs.each &print_nick
        end

        true
      end

    end
  end
end
