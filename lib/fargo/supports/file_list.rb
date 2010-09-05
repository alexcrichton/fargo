require 'bzip2'
require 'libxml'

module Fargo
  module Supports
    module FileList
      
      class Listing < Struct.new(:tth, :size, :name); end

      # Lazily load the file list for the nick. Subscribe to the client for the
      # event :file_list to get notified.
      def file_list nick
        @file_list ||= {}
        return @file_list[nick] if @file_list.has_key?(nick)

        file_gotten = lambda{ |type, map| 
          case type
            when :download_finished, :download_failed, :connection_timeout
              if map[:nick] == nick
                @file_list[nick] = parse_file_list map[:file]
                unsubscribe &file_gotten
                publish :file_list, :nick => nick, :list => @file_list[nick]
              end
          end
        }

        subscribe &file_gotten

        download nick, 'files.xml.bz2'
      end
      
      # Wait for the results, don't get them just yet
      def file_list! nick
        @file_list ||= {}
        return @file_list[nick] if @file_list.has_key?(nick)

        file_list = nil
        list_gotten = lambda{ |type, map| 
          if type == :file_list && map[:nick] == nick
            file_list = map[:list]
            true
          else
            false
          end
        }

        timeout_response(10, list_gotten){ file_list nick }

        file_list
      end

      private
      
      def parse_file_list file
        if file && File.exists?(file)
          xml = Bzip2::Reader.open(file).read
          doc = LibXML::XML::Document.string xml

          construct_file_list doc.root
        else
          nil
        end
      end
      
      def construct_file_list node
        list = {}

        node.each_element do |element|
          if element.name =~ /directory/i
            list[element['Name']] = construct_file_list element
          else
            list[element['Name']] = Listing.new(
              element['TTH'],
              element['Size'],
              element['Name']
            )
          end
        end

        list
      end
    end
  end
end