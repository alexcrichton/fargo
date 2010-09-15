require 'bzip2'
require 'libxml'

module Fargo
  module Supports
    module FileList
      class Listing < Struct.new(:tth, :size, :name, :nick); end

      # Lazily load the file list for the nick. Subscribe to the client for the
      # event :file_list to get notified.
      def file_list nick
        @file_list ||= {}
        if @file_list.has_key?(nick)
          return parse_file_list(@file_list[nick], nick)
        end

        file_gotten = lambda{ |type, map|
          case type
            when :download_finished, :download_failed, :connection_timeout
              if map[:nick] == nick
                @file_list[nick] = map[:file]
                unsubscribe &file_gotten
                publish :file_list, :nick => nick, :list => @file_list[nick]
              end
          end
        }

        subscribe &file_gotten

        download nick, 'files.xml.bz2'
      end

      # Wait for the results to arrive, timed out after some time
      def file_list! nick, timeout = 10
        @file_list ||= {}
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
            list[element['Name']] = Listing.new(element['TTH'], element['Size'],
              path, nick)
          end
        end

        list
      end
    end
  end
end
