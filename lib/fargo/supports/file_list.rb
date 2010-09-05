require 'bzip2'
require 'libxml'

module Fargo
  module Supports
    module FileList
      
      class Listing < Struct.new(:tth, :size, :name); end

      def file_list nick
        @file_list ||= {}

        @file_list[nick] ||= begin
          downloaded_file = nil

          file_gotten = lambda{ |type, map| 
            case type
              when :download_finished, :download_failed, :connection_timeout
                # TODO: better way to do this?
                if map[:nick] == nick
                  downloaded_file = map[:file]
                end
                map[:nick] == nick
              else
                false
            end
          }

          timeout_response(10, file_gotten){ download nick, 'files.xml.bz2' }

          if downloaded_file && File.exists?(downloaded_file)
            xml = Bzip2::Reader.open(downloaded_file).read
            doc = LibXML::XML::Document.string xml

            construct_file_list doc.root
          else
            nil
          end
        end
      end

      private
      
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