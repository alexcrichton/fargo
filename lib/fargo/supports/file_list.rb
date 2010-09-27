require 'bzip2'
require 'libxml'

module Fargo
  module Supports
    module FileList
      class Listing < Struct.new(:tth, :size, :name, :nick); end

      def initialize *args
        @file_list = {}
        @getting_file_list ||= {}
      end

      # Lazily load the file list for the nick. Subscribe to the client for the
      # event :file_list to get notified.
      def file_list nick
        if @file_list.has_key?(nick)
          return parse_file_list(@file_list[nick], nick)
        elsif @getting_file_list[nick]
          return true
        end

        subscription_id = channel.subscribe do |type, map|
          case type
            when :download_finished, :download_failed, :connection_timeout
              if map[:nick] == nick
                @file_list[nick] = map[:file]

                channel.unsubscribe subscription_id
                channel.publish [:file_list,
                    {:nick => nick, :list => @file_list[nick]}]

                @getting_file_list.delete nick
              end
          end
        end

        @getting_file_list[nick] = true
        download nick, 'files.xml.bz2'
      end

      # Wait for the results to arrive, timed out after some time
      def file_list! nick, timeout = 10
        if @file_list.has_key?(nick)
          return parse_file_list(@file_list[nick], nick)
        end

        list = nil
        list_gotten = lambda{ |type, map|
          if type == :file_list && map[:nick] == nick
            list = map[:list]
            true
          else
            false
          end
        }

        timeout_response(timeout, list_gotten){ file_list nick }

        parse_file_list list, nick
      end

      private

      def parse_file_list file, nick
        if file && File.exists?(file)
          Fargo.logger.debug "Parsing file list for: '#{nick}' at '#{file}'"
          xml = Bzip2::Reader.open(file).read
          doc = LibXML::XML::Document.string xml

          construct_file_list doc.root, nil, nick
        else
          nil
        end
      end

      def construct_file_list node, prefix, nick
        list = {}

        node.each_element do |element|
          path = prefix ? prefix + "\\" + element['Name'] : element['Name']

          if element.name =~ /directory/i
            list[element['Name']] = construct_file_list element, path, nick
          else
            # Why does this consistently segfault ruby 1.8.7 when I convert
            # element['Size'] to an integer before the struct is created?!
            element = list[element['Name']] = Listing.new(element['TTH'],
              element['Size'], path, nick)
            element.size = element.size.to_i
          end
        end

        list
      end
    end
  end
end
