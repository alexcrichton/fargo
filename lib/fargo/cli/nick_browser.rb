module Fargo
  module CLI
    module NickBrowser

      def setup_console
        super

        add_completion(/^browse\s+[^\s]*$/){ client.nicks }

        add_completion(/^ls\s+([^\s]*)$/) do |match|
          if @browsing
            partial = match.split '/'
            question = partial.pop

            rel = File.join(@cwd, partial.join('/'))
            hash = drilldown(rel, @file_list)
            hash.try(:keys) || []
          else
            []
          end
        end

        add_logger(:download_finished) do |message|
          if message[:file].end_with? 'files.xml.bz2'
            begin_browsing message[:nick]
          end
        end
      end

      def browse nick
        @browsing = nick
        @file_list = nil
        list = client.file_list nick
        if list.is_a?(Hash)
          begin_browsing nick
        end
      end

      def ls dir = ''
        hash = drilldown(File.join(@cwd, dir), @file_list)

        hash.keys.sort.each do |key|
          if hash[key].is_a?(Hash)
            puts "#{key}/"
          else
            printf "%10s -- %s\n", humanize_bytes(hash[key].size), key
          end
        end

        true
      end

      def begin_browsing nick
        @cwd = '/'
        @file_list = client.file_list(@browsing)
        nil
      end

      protected

      def drilldown path, list
        path.gsub(/^\//, '').split('/').inject(list) { |hash, part|
          hash ? hash[part] : nil
        }
      end

    end
  end
end
