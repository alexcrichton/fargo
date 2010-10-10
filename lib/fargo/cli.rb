require 'drb'
require 'irb'
require 'em-http-request'
require 'fargo/ext/readline'
require 'fargo/ext/irb'

module Fargo
  module CLI

    def self.start
      Fargo.logger = ActiveSupport::BufferedLogger.new WrappingLogger.new
      Fargo.logger.level = ActiveSupport::BufferedLogger::INFO

      begin
        client.connected?
      rescue DRb::DRbConnError
        Thread.start{ EventMachine.run{
          self.client = Fargo::Client.new
          client.connect
        } }
      end

      streamer = proc {
        host = "ws://#{client.config.websocket_host}" +
                  ":#{client.config.websocket_port}/"
        ws = EventMachine::HttpRequest.new(host).get(:timeout => 0)

        ws.stream { |msg|
          to_log = nil
          type, message = Marshal.load(msg)

          case type
            when :chat
              to_log = "<#{message[:from]}>: #{message[:text]}"
            when :search_result
              obj = client.search_objects.detect{ |s| s.matches? message }
              if obj
                to_log = "New search result for: #{obj.query.inspect}"
              else
                to_log = "New search result"
              end
          end

          Readline.above_prompt{ puts to_log } unless to_log.nil?
        }
      }

      if EventMachine.reactor_running?
        EventMachine.schedule streamer
      else
        Thread.start{ EventMachine.run streamer }
      end

      IRB.start_session binding do
        old_proc = Readline.completion_proc
        Readline.basic_word_break_characters = " \t\n\\'`><=;|&{("
        Readline.basic_quote_characters = ''

        Readline.completion_proc = lambda { |str|
          input = Readline.get_input

          candidates = []
          if input =~  /^who /
            candidates = client.nicks + ['name', 'size']
          elsif input =~ /^results /
            candidates = client.searches
          end

          if candidates.empty?
            old_proc.call str
          else
            str = str.gsub /^"/, ''
            candidates.select{ |n| n.start_with? str }.map{ |s| s.inspect }
          end
        }
      end

      EventMachine.stop
    end

    class WrappingLogger
      def write str
        Readline.above_prompt{ puts str }
      end
    end

    module Helpers
      def client
        @fargo_client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
      end

      def client= client
        @fargo_client = client
      end

      def results str = nil, opts = {}
        str ||= client.searches.last
        results = client.search_results(str).dup

        if results.nil?
          puts "No search results for: #{str.inspect}!"
          return
        end

        results.each_with_index{ |r, i|
          r[:file]  = File.basename(r[:file].gsub("\\", '/'))
          r[:index] = i
        }

        max_nick_size = results.map{ |r| r[:nick].size }.max

        if opts[:sort] == 'size'
          results = results.sort_by{ |r| r[:size] }
        elsif !opts[:sort].nil?
          puts "Unknown sort value: #{opts[:sort]}"
          results = []
        end

        if opts[:grep]
          results = results.select{ |r| r[:file].match opts[:grep] }
        end

        results.each do |r|
          printf "%3d: %#{max_nick_size}s %9s -- %s\n", r[:index],
            r[:nick], humanize_bytes(r[:size]), r[:file]
        end

        true
      end

      def search str
        client.search str
      end

      def download index, search = nil
        search ||= client.searches[0]

        item = client.search_results(search)[index]

        if item.nil?
          puts 'That is not something to download!'
        else
          client.download item[:nick], item[:file], item[:tth]
        end
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

      protected

      def humanize_bytes bytes
        suffix = 'B'
        while bytes > 1024
          suffix = case suffix
            when 'B' then 'K'
            when 'K' then 'M'
            when 'M' then 'G'
            when 'G' then 'T'
            when 'T' then break
          end

          bytes /= 1024.0
        end

        '%.2f %s' % [bytes, suffix]
      end
    end

    extend Helpers
  end
end
