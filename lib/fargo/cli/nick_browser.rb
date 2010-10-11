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

          add_logger(:download_finished) do |message|
            if message[:file].end_with? 'files.xml.bz2'
              begin_browsing message[:nick]
            end
          end
        end

        def download file, other = nil
          if file.is_a?(String)
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
              client.download listing
            end
          else
            super
          end
        end
      end

      def browse nick
        @browsing  = nick
        @file_list = nil
        list       = client.file_list nick
        begin_browsing nick, false if list.is_a?(Hash)
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
          puts "Note browsing any nick!"
          return
        end

        hash = drilldown(resolve(dir), @file_list)

        hash.keys.sort_by{ |k| hash[k].is_a?(Hash) ? 0 : 1 }.each do |key|
          if hash[key].is_a?(Hash)
            puts "#{key}/"
          else
            printf "%10s -- %s\n", humanize_bytes(hash[key].size), key
          end
        end

        true
      end

      def begin_browsing nick, above_prompt = true
        @cwd = Pathname.new '/'
        @file_list = client.file_list(@browsing)

        if above_prompt
          Readline.above_prompt{ puts "#{@browsing} ready for browsing" }
        else
          puts "#{@browsing} ready for browsing"
        end
      end

      protected

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
