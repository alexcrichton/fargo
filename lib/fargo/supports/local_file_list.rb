require 'bzip2'
require 'libxml'

module Fargo
  module Supports
    module LocalFileList
      extend ActiveSupport::Concern
      include Fargo::TTH

      module Watcher
        attr_accessor :client

        def file_modified
          client.update_tth path if client
        end
      end

      included do
        set_callback :initialization, :after, :initialize_upload_lists
      end

      def share_directory dir
        @shared_directories << dir

        EventMachine.defer{
          update_tth dir

          EventMachine.watch_file dir, Watcher do |watcher|
            watcher.client = self
          end
        }
      end

      def share_size
        config.override_share_size || @share_size
      end

      def my_file_listing
        @file_list
      end

      def write_file_list
        doc      = LibXML::XML::Document.new
        doc.root = LibXML::XML::Node.new 'FileListing'
        doc.root['Version']   = '1'
        doc.root['Base']      = '/'
        doc.root['Generator'] = "fargo #{Fargo::VERSION}"

        create_entities @file_list, doc.root

        FileUtils.mkdir_p config.config_dir
        Bzip2::Writer.open(config.config_dir + '/files.xml.bz2', 'w') do |f|
          f << doc.to_s(:indent => false)
        end
      end

      def update_tth directory, hash = @file_list
        Pathname.glob(directory + '/*').each do |path|
          if path.directory?
            update_tth path.to_s, hash[path.basename.to_s] ||= {}
          elsif hash[path.basename.to_s].nil? ||
              path.mtime > hash[path.basename.to_s].mtime
            hash[path.basename.to_s] = Listing.new(
                file_tth(path.to_s),
                path.size,
                path.to_s,
                config.nick,
                path.mtime
              )
          end
        end
      end

      protected

      def create_entities entity, node
        entity.each_pair do |k, v|
          if v.is_a? Hash
            dir = LibXML::XML::Node.new 'Directory'
            dir['Name'] = k
            create_entities v, dir
            node << dir
          else
            file = LibXML::XML::Node.new 'File'
            file['Name'] = v.name
            file['Size'] = v.size.to_s
            file['TTH']  = v.tth

            node << file
          end
        end
      end

      def initialize_upload_lists
        @shared_directories = []
        @file_list          = {}
        @share_size         = 0

        # file watching requires kqueue on OSX
        EventMachine.kqueue = true if EventMachine.kqueue?
      end

    end
  end
end
