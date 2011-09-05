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

          file_regex = /(?:\s+(?:[^\s,]+))+/
          add_completion(/^(?:get|download)#{file_regex}$/) { completion true }
          add_completion(/^(?:ls|cd)#{file_regex}$/) { completion }

          add_logger(:file_list) do |message|
            client.parsed_file_list message[:nick] do |document|
              @browsing  = message[:nick]
              begin_browsing document
            end
          end
        end

        def download file, other = nil
          return super unless file.is_a?(String)

          node, path = resolve(file)

          if node.nil?
            puts "No file to download!: #{file}"
          elsif node.name == 'Directory'
            # Recursively download the entire directory
            node.each_element do |element|
              download path.join(element['Name'])
            end
          else
            puts "Downloading: [#{@browsing}] - #{node['Name']}"
            EventMachine.schedule {
              client.download @browsing, path.to_s.gsub(/^\//, ''),
                              node['TTH'], node['Size'].to_i
            }
          end
        end
      end

      def browse nick
        EventMachine.schedule { client.file_list nick }
      end

      def cd dir = '/'
        node, path = resolve(dir)
        if node.nil?
          puts "#{path.to_s} doesn't exist!"
        else
          @node = node
          @cwd  = path
          pwd
        end
      end

      def pwd
        puts @cwd.to_s
      end

      alias :cwd :pwd

      def ls dir = ''
        if @file_list.nil?
          puts "Not browsing any nick!"
          return
        end

        node, path = resolve dir
        if node.nil?
          puts "No such path: #{dir}"
          return
        end

        node.each_element do |e|
          if e.name == 'Directory'
            puts e['Name'] + '/'
          else
            printf "%10s -- %s\n", humanize_bytes(e['Size'].to_i), e['Name']
          end
        end
      end

      protected

      def begin_browsing document
        @cwd  = Pathname.new '/'
        @node = document.find_first '/FileListing'
        raise 'Invalid file list!' if @node.nil?
        @file_list = document
        Readline.above_prompt{ puts "#{@browsing} ready for browsing" }
      end

      def completion include_files = false
        return [] unless @browsing
        str = Readline.get_input
        dirs = []
        while tmp = str.slice!(/[^\s]+\s*/)
          dirs << tmp.rstrip.gsub('"', '')
        end
        dirs.pop   # Ignore what we're completing
        dirs.shift # Ignore the original command

        node, path = resolve dirs.join('/'), false
        return [] if node.nil?

        files = []
        node.each_element do |element|
          next if !include_files && element.name == 'File'
          name = element['Name']
          suffix = element.name == 'Directory' ? '/' : ''

          # Readline doesn't like completing words with spaces in the file
          # name, so just display them as periods when in actuality we'll
          # convert back to a space later
          comp = name.gsub(' ', '.') + suffix
          files << comp

          key = @cwd.join(*dirs).join(comp).expand_path.to_s
          @fixed_completions[key] = path.join name
        end

        files << '..' if files.empty? || dirs.size == 0
        files
      end

      def resolve dir, clear_cache = true
        return '' if @node.nil?

        res = @fixed_completions[@cwd.join(dir).expand_path.to_s] ||
                @cwd.join(dir).expand_path
        @fixed_completions.clear if clear_cache

        path = res.expand_path
        xpath = '/FileListing'
        path.each_filename do |component|
          xpath += "/*[@Name='#{component}']"
        end
        [@file_list.find_first(xpath), path]
      end

    end
  end
end
