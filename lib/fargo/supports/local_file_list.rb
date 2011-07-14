require 'bzip2'
require 'libxml'
require 'active_support/core_ext/module/synchronization'

module Fargo
  module Supports
    module LocalFileList
      extend ActiveSupport::Concern
      include TTH

      attr_reader :local_file_list, :shared_directories

      included do
        set_callback :initialization, :after, :initialize_upload_lists
        set_callback :connect, :after, :schedule_update
      end

      def share_directory dir
        shared_directories << dir unless shared_directories.include? dir

        EventMachine.schedule { # Make sure we run in the reactor
          EventMachine.defer {  # This takes awhile so don't block the reactor
            update_tth dir
            write_file_list
          }
        }
      end

      def share_size
        config.override_share_size || @share_size
      end

      def local_file_list_path
        File.join config.config_dir, 'files.xml.bz2'
      end

      def local_listings
        collect_local_listings local_file_list, [], nil
      end

      def search_local_listings search
        collect_local_listings local_file_list, [], search
      end

      def listing_for query
        if query =~ /^TTH\/(\w+)$/
          tth = $1
          local_listings.detect{ |l| l.tth = tth }
        else
          local_listings.detect{ |l| l.name == query }
        end
      end

      protected

      def cache_file_list_path
        File.join config.config_dir, 'file_cache'
      end

      def collect_local_listings hash, arr, search
        hash.each_pair do |k, v|
          if v.is_a?(Listing)
            arr << v if search.nil? || search.matches?(v)
          else
            collect_local_listings v, arr, search
          end
        end

        arr
      end

      def update_tth root, directory = nil, hash = nil
        if directory.nil?
          directory = root
          root      = File.dirname(root)
        end

        hash ||= (local_file_list[File.basename(directory)] ||= {})

        Pathname.glob(directory + '/*').each do |path|
          if path.directory?
            update_tth_without_synchronization root, path.to_s,
              hash[path.basename.to_s] ||= {}

          elsif hash[path.basename.to_s].nil? ||
              path.mtime > hash[path.basename.to_s].mtime

            hash[path.basename.to_s] = Listing.new(
                file_tth(path.to_s),
                path.size,
                path.to_s.gsub(root + '/', ''),
                config.nick,
                path.mtime,
                root
            )

            @share_size += path.size
          end
        end

        to_remove = []

        hash.each_pair do |k, v|
          file = directory + '/' + k
          unless File.exists?(file)
            to_remove << k
            @share_size -= v.size
          end
        end

        to_remove.each{ |k| hash.delete k }
      end

      synchronize :update_tth, :with => :@update_lock

      def write_file_list
        document = LibXML::XML::Document.new
        document.root = node 'FileListing', :Base => '/', :Version => '1',
          :Generator => "fargo #{VERSION}"

        create_entities local_file_list, document.root

        FileUtils.mkdir_p config.config_dir
        Bzip2::Writer.open(local_file_list_path, 'w') do |f|
          f << document.to_s
        end

        File.open(cache_file_list_path, 'w'){ |f|
          f << Marshal.dump([local_file_list, shared_directories, share_size])
        }
      end

      def create_entities entity, node
        entity.each_pair do |k, v|
          if v.is_a? Hash
            dir = node 'Directory', :Name => k
            create_entities v, dir
            node << dir
          else
            node << node('File', :Name => k, :Size => v.size.to_s,
                :TTH => v.tth)
          end
        end
      end

      def node name, attrs
        LibXML::XML::Node.new(name).tap { |n|
          attrs.each{ |k, v| n[k.to_s] = v }
        }
      end

      def schedule_update
        EventMachine::Timer.new(60) do
          shared_directories.each{ |d| update_tth d }

          write_file_list
          schedule_update
        end
      end

      def initialize_upload_lists
        @local_file_list, @shared_directories, @share_size = begin
          Marshal.load File.read(cache_file_list_path)
        rescue
          [{}, [], 0]
        end
        @update_lock = Mutex.new
      end

    end
  end
end
