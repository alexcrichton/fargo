require 'bzip2'
require 'libxml'
require 'pathname'
require 'securerandom'

module Fargo
  # A struct representing a listing of a local file. The metadata contains
  # information about the file used by DC.
  class Listing < Struct.new(:tth, :size, :path); end

  module Supports
    module LocalFileList
      extend ActiveSupport::Concern
      include TTH

      # Array of all shared directories of this client. Each element is a
      # Pathname.
      attr_reader :shared_directories

      included do
        set_callback :initialization, :after, :initialize_upload_lists
        set_callback :connect, :after, :schedule_update
      end

      # Share a new directory of files. The local file list will be updated
      # in the future to include all files in this directory.
      #
      # @param [String] dir the path to the directory which should be shared.
      def share_directory dir
        path = Pathname.new(dir).expand_path
        @shared_directories << path unless @shared_directories.include? path

        # This takes awhile so don't block the reactor
        EventMachine.defer { run_update path }
      end

      alias :share :share_directory

      # Get the size in bytes of all files shared by this client.
      #
      # @return [Integer] the number of bytes shared by the client.
      def share_size
        return config.override_share_size if config.override_share_size
        @share_size ||= begin
          sizes = @local_file_list.find('//*[@Size]').map{ |n| n['Size'].to_i }
          sizes.inject(0) { |sum, i| sum + i }
        end
      end

      # Generates the path on the local file system at which the file list
      # is stored. The file list is always ready for being uploaded to other
      # clients.
      #
      # @return [String] path to the local file list.
      def local_file_list_path
        File.join config.config_dir, 'files.xml.bz2'
      end

      def search_local_listings search
        parts = search.query.downcase.split("'")
        query = if parts.size == 0
          '"\'"'
        elsif parts.size == 1
          "'#{parts.first}'"
        else
          "concat(#{parts.map{ |p| "'" + p + "'" }.join(', "\'", ')})"
        end
        alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        translate = "translate(@Name, '#{alpha.upcase}', '#{alpha.downcase}')"
        xpath = "//*[contains(#{translate}, #{query})]"
        @local_file_list.find(xpath).map { |node| listing_from_node(node) }
      end

      # Fetch a Fargo::Listing object for the specified query by looking up
      # the file in our local file list to see if we have it.
      #
      # @param [String] query a query for the file to find. This query can be a
      #   TTH in the form 'TTH/<tth>', or it can be a relative path to the file
      #   to find.
      def listing_for query
        if query =~ /^TTH\/(\w+)$/
          node = @local_file_list.find_first("//File[@TTH='#{$1}']")
        else
          node = @local_file_list.find_first('/FileListing')
          Pathname.new(query).each_filename { |part|
            node = node.find_first "./*[@Name='#{part}']"
            break if node.nil?
          }
        end

        return nil if node.nil? || node.name == 'Directory'
        listing_from_node node, true
      end

      protected

      # Convert a LibXML::XML::Node to a Fargo::Listing object
      #
      # @param [LibXML::XML::Node] node the node in the XML document to convert
      #   into a Fargo::Listing.
      # @param [Boolean] absolute if true, then the `path` attribute of the
      #   Fargo::Listing will be an absolute path to the file on the local
      #   filesystem. Otherwise, it will be a relative path from our shared
      #   directories
      # @return [Fargo::Listing] the listing for the node.
      def listing_from_node node, absolute = false
        listing = Fargo::Listing.new
        if node.name == 'File'
          listing.tth   = node['TTH']
          listing.size  = node['Size'].to_i
        end

        # We need to do a bit of work to figure out where the file is located
        # on the filesystem. Walk upwards from the node to get the relative
        # path, and then search the load path for where the file is at.
        path = node['Name']
        loop {
          node = node.parent
          break if node.name == 'FileListing'
          path = File.join node['Name'], path
        }

        if absolute
          @shared_directories.each { |shared_path|
            next unless path.start_with?(shared_path.basename.to_s)
            possible = shared_path.dirname.join(path)
            if possible.exist?
              listing.path = possible.to_s
              break
            end
          }
        else
          listing.path = path
        end

        raise 'Inconsistent state!' if listing.path.nil?

        listing
      end

      # This path is used to dump internal state of fargo such as shared
      # directories, calculated TTHs, mtimes, etc.
      #
      # @return [String] path to the cache of internal state.
      def cache_file_list_path
        File.join config.config_dir, 'file_cache'
      end

      # Updates the XML document of our local file list.
      #
      # @param [Pathname] path the path at which to begin updating the TTH for.
      #   this path will be updated recursively if it's a directory or just
      #   this file will be updated if it's a file. This path must exist.
      # @param [LibXML::XML::Node] node the node at which new children should be
      #   placed under.
      def update_tth path, node
        if EventMachine.reactor_thread? || !@update_lock.locked?
          raise 'Should not update tth hashes in reactor thread or without' \
                ' the local list lock!'
        end

        # Files might need to have a TTH updated, but only if they've been
        # modified since we last calculated a TTH
        if path.file?
          cached_info = @local_file_info[path]
          child = LibXML::XML::Node.new('File')
          child['Name'] = path.basename.to_s
          if cached_info && path.mtime <= cached_info[:mtime]
            child['TTH']  = cached_info[:tth]
            child['Size'] = cached_info[:size]
          else
            debug 'file-list', "Hashing: #{path.to_s}"
            child['TTH']  = file_tth path.to_s
            child['Size'] = path.size.to_s
          end
          @local_file_info[path] = {:mtime => path.mtime,
                                    :size  => child['Size'],
                                    :tth   => child['TTH']}
          node << child

        # Directories just need a node and then a recursive update
        elsif path.directory?
          child = LibXML::XML::Node.new('Directory')
          child['Name'] = path.basename.to_s
          path.each_child { |child_path| update_tth child_path, child }
          node << child

        # If we're not a file or directory, then we just have to ignore the
        # file for now...
        else
          debug 'file-list', "Ignoring: #{path}"
        end
      end

      # Write the file list to the filesystem, along with the cache of internal
      # state. This function must not be called from within the reactor
      # thread and requires that the @update_lock to be held.
      def write_file_list
        if EventMachine.reactor_thread? || !@update_lock.locked?
          raise 'Should not write file list in reactor thread or without' \
                ' the local list lock!'
        end

        FileUtils.mkdir_p config.config_dir
        @local_file_list.root['CID'] = SecureRandom.hex(12).upcase
        output = @local_file_list.to_s(:indent => true)
        Bzip2::Writer.open(local_file_list_path, 'wb') { |f| f << output }
        @share_size = nil

        output = Marshal.dump([@local_file_info, @shared_directories])
        File.open(cache_file_list_path, 'wb'){ |f| f << output }
      end

      def schedule_update
        EventMachine::Timer.new(config.update_interval) do
          EventMachine.defer proc {
            @shared_directories.each{ |dir| run_update dir }
          }, proc { |_| schedule_update }
        end
      end

      def run_update path
        @update_lock.synchronize {
          @local_file_info.keys.each{ |k|
            @local_file_info.delete(k) unless k.exist?
          }
          debug 'file-list', "Updating: #{path}"
          xpath = "/FileListing/Directory[@Name='#{path.basename.to_s}']"
          @local_file_list.find(xpath).each{ |n| n.remove! }
          update_tth path, @local_file_list.find_first('/FileListing')
          write_file_list
        }
      end

      def initialize_upload_lists
        @local_file_info, @shared_directories = begin
          Marshal.load File.open(cache_file_list_path, 'rb') { |f| f.read }
        rescue
          [{}, []]
        end
        @update_lock = Mutex.new

        LibXML::XML.indent_tree_output = true
        if File.exists?(local_file_list_path)
          bzip = Bzip2::Reader.open(local_file_list_path, 'r')
          @local_file_list = LibXML::XML::Document.io bzip,
              :options => LibXML::XML::Parser::Options::NOBLANKS
          bzip.close
        else
          @local_file_list = LibXML::XML::Document.new
          @local_file_list.root = LibXML::XML::Node.new('FileListing')
          EventMachine.defer { @update_lock.synchronize { write_file_list } }
        end

        root = @local_file_list.root
        root['Base'] = '/'
        root['Version'] = '1'
        root['Generator'] = "fargo V:#{VERSION}"

        dirs = config.shared_directories || []
        dirs.each{ |dir| share_directory dir }
      end

    end
  end
end
