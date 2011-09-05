require 'bzip2'
require 'libxml'

module Fargo
  # A struct representing a listing of a file for either a remote nick or as
  # a local file. The metadata contains information about the file used by DC.
  class Listing < Struct.new(:tth, :size, :name, :nick, :mtime, :root); end

  module Supports

    # A remote file list is a listing of files for any remote user on a hub.
    # The format of this listing isn't specified by these methods, but rather
    # the known formats are supported and one is automatically chosen based on
    # what the peer supports.
    #
    # File listings of peers are considered cached for a minute, but afterwards
    # if requested they will be re-downloaded.
    #
    # The file list is represented as a Hash. The hash represents the root
    # share of a user, and keys are directory/file names. Values are either a
    # Fargo::Listing to represent that the key is a file name, or a nested hash
    # to represent a directory. This nested hash has the same format.
    #
    # Published events are:
    #   :file_list => Happens when the file list for a nick has finished
    #                 downloading and is available. Keys are :nick, and :list.
    #
    module RemoteFileList
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_file_lists
      end

      # Initiate downloading of the file list from a remote peer. File lists are
      # cached for 10 minutes by default. When the file list is finished
      # downloading, a :file_list event will be published. If the file list
      # is cached, this event is immediately published. Subscribe to this event
      # on the client's channel if you would like to work with the file list.
      #
      # @param [String] nick the nick to download a file list for
      def file_list nick
        raise NotInReactor unless EM.reactor_thread?
        if @file_list.key?(nick)
          channel << [:file_list, {:nick => nick}]
          return
        end

        download nick, 'files.xml.bz2'

        # Only cache file lists for 10 minutes
        EventMachine.add_timer(600) { @file_list.delete nick }
      end

      # Retrieve a parsed version of the file list. The parsed form is a ruby
      # Hash object where each key corresponds to a directory/file and then
      # each value is either a hash or a Fargo::Listing. A nested hash signifies
      # a directory, while a Fargo::Listing signifies a file.
      #
      # @param [String] nick the peer to parse a file list for.
      # @yield [Hash] the block supplied to this function will be invoked with
      #   the parsed file list as a Hash described above when it is available.
      #   Parsing takes a significant amount of time sometimes, so it's
      #   recommended that this object be cached.
      def parsed_file_list nick, &block
        raise NotInReactor unless EM.reactor_thread?
        raise "Don't have file list for: #{nick}" if !@file_list.key?(nick)

        # Parsing takes awhile, defer it. Come back into the reactor and
        # call the block with the result of the parsing.
        EventMachine.defer lambda {
          parse_file_list @file_list[nick], nick
        }, block
      end

      protected

      # Parses a file list that has just been download.
      #
      # @param [String] file the file the file list was downloaded into
      # @param [String] nick the nick of the peer that was downloaded from
      #
      # @return [Hash, nil] the constructed file list, or nil if the file wasn't
      #   found.
      def parse_file_list file, nick
        debug 'parsing', "Parsing file list for: '#{nick}' at '#{file}'"
        xml = Bzip2::Reader.open file
        doc = LibXML::XML::Document.io xml

        construct_file_list doc.root, nil, nick
      end

      # Recursive helper for constructing a file list from a node
      #
      # @param [LibXML::XML::Node] node the current node at which construction
      #   is occurring.
      # @param [String, nil] prefix the path prefix that leads down to this
      #   current node. If nil, then this node's children are roots.
      # @param [String] nick the nick that the file list is for.
      def construct_file_list node, prefix, nick
        list = {}

        node.each_element do |element|
          path = prefix ? prefix + "\\" + element['Name'] : element['Name']

          if element.name =~ /directory/i
            list[element['Name']] = construct_file_list element, path, nick
          else
            element = list[element['Name']] = Listing.new(element['TTH'],
              element['Size'].to_i, path, nick)
          end
        end

        list
      end

      def initialize_file_lists
        @file_list = {}
        @getting_file_list = {}

        channel.subscribe do |type, map|
          if type == :download_finished && !map[:failed] &&
             map[:download].file_list?
            @file_list[map[:nick]] = map[:file]
            channel << [:file_list, {:nick => map[:nick]}]
          end
        end

      end

    end
  end
end
