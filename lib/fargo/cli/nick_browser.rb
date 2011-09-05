require 'pathname'

module Fargo
  module CLI
    module NickBrowser
      extend ActiveSupport::Concern

      included do
        alias :get :download
      end

      module InstanceMethods
        def setup_console
          super

          @fixed_completions = {}

          add_completion(/^browse\s+[^\s]*$/) { client.nicks }

          file_regex = /(?:\s+(?:[^\s,]*))+/
          add_completion(/^(?:get|download)#{file_regex}$/) { completion true }
          add_completion(/^(?:ls|cd)#{file_regex}$/) { completion }

          add_logger(:file_list) do |message|
            client.parsed_file_list message[:nick] do |list|
              begin_browsing list
            end
          end
        end

        def download file, other = nil
          return super unless file.is_a?(String)

          resolved = resolve(file).to_s
          listing = drilldown resolved, @file_list

          if listing.nil?
            puts "No file to download!: #{file}"
          elsif listing.is_a? Hash
            # Recursively download the entire directory
            listing.keys.each do |k|
              download File.join(resolved, k)
            end
          else
            puts "Downloading: [#{@browsing}] - #{listing.name}"
            EventMachine.schedule { client.download listing }
          end
        end
      end

      def browse nick
        @browsing  = nick
        @file_list = nil
        EventMachine.schedule { client.file_list nick }
      end

      def cd dir = '/'
        cwd = resolve(dir)
        if drilldown(cwd, @file_list).nil?
          puts "#{dir.inspect} doesn't exist!"
        else
          @cwd = cwd
          pwd
        end
      end

      def pwd
        puts @cwd.to_s
      end

      alias :cwd :pwd

      def ls dir = ''
        if @cwd.nil? || @file_list.nil?
          puts "Not browsing any nick!"
          return
        end

        hash = drilldown(resolve(dir), @file_list)

        hash.keys.sort_by(&:downcase).
            sort_by{ |k| hash[k].is_a?(Hash) ? 0 : 1 }.each do |key|
          if hash[key].is_a?(Hash)
            puts "#{key}/"
          else
            printf "%10s -- %s\n", humanize_bytes(hash[key].size), key
          end
        end

        true
      end

      protected

      def begin_browsing list
        @cwd = Pathname.new '/'
        @file_list = list
        Readline.above_prompt{ puts "#{@browsing} ready for browsing" }
      end

      def completion include_files = false
        if @browsing
          all_input = Readline.get_input
          dirs = []
          while tmp = all_input.slice!(/[^\s]+?\s+/)
            dirs << tmp.rstrip.gsub!(/"/, '')
          end
          dirs.shift # original command

          resolved = resolve dirs.join('/'), false
          hash     = drilldown resolved, @file_list

          keys = hash.keys rescue []
          keys = keys.select{ |k|
            include_files || k == '..' || hash[k].is_a?(Hash)
          }
          keys << '..' unless keys.empty? && dirs.size != 0

          keys.map{ |k|
            suffix = hash[k].is_a?(Hash) ? '/' : ''

            # Readline doesn't like completing words with spaces in the file
            # name, so just display them as periods when in actuality we'll
            # convert back to a space later
            (k.gsub(' ', '.') + suffix).tap do |str|
              key = @cwd.join(*dirs).join(str).expand_path.to_s
              @fixed_completions[key] = resolved.join k
            end
          }
        else
          []
        end
      end

      def resolve dir, clear_cache = true
        return '' if @cwd.nil?

        res = @fixed_completions[@cwd.join(dir).expand_path.to_s] ||
                @cwd.join(dir).expand_path
        @fixed_completions.clear if clear_cache
        res.expand_path
      end

      def drilldown path, list
        path.to_s.gsub(/^\//, '').split('/').inject(list) { |hash, part|
          hash ? hash[part] : nil
        }
      end

    end
  end
end
