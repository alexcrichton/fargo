require 'bzip2'
require 'libxml'
require 'active_support/core_ext/module/synchronization'

module Fargo
  module Supports
    module LocalFileList
      extend ActiveSupport::Concern
      include Fargo::TTH

      included do
        set_callback :initialization, :after, :initialize_upload_lists
        set_callback :connect, :after, :schedule_update
      end

      def share_directory dir
        @shared_directories << dir

        EventMachine.defer {
          update_tth dir
          write_file_list
        }
      end

      def share_size
        config.override_share_size || @share_size
      end

      def my_file_listing
        @file_list.dup
      end

      protected

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

      def update_tth directory, hash = nil
        hash ||= (@file_list[File.basename(directory)] ||= {})

        Pathname.glob(directory + '/*').each do |path|
          if path.directory?
            update_tth_without_synchronization path.to_s,
              hash[path.basename.to_s] ||= {}
          elsif hash[path.basename.to_s].nil? ||
              path.mtime > hash[path.basename.to_s].mtime
            hash[path.basename.to_s] = Listing.new(
                file_tth(path.to_s),
                path.size,
                path.to_s,
                config.nick,
                path.mtime
            )

            @share_size += path.size
          end
        end

        to_remove = []

        hash.each_pair do |k, v|
          file = directory + '/' + k
          unless File.exists?(file)
            to_remove << k
            @share_size -= File.size file if File.file?(file)
          end
        end

        to_remove.each{ |k| hash.delete k }
      end

      synchronize :update_tth, :with => :@update_lock

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

      def schedule_update
        EventMachine::Timer.new(60) do
          @shared_directories.each{ |d| update_tth d }

          write_file_list
          schedule_update
        end
      end

      def initialize_upload_lists
        @shared_directories = []
        @file_list          = {}
        @share_size         = 0
        @update_lock        = Mutex.new
      end

    end
  end
end
