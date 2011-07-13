require 'bzip2'
require 'nokogiri'

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

      # Lazily load the file list for the nick. Subscribe to the client for the
      # event :file_list to get notified.
      #
      # @param [String] nick the nick to download a file list for
      # @return [Hash, true] either the file list (if one is available), or true
      #   if the file list is currently being downloaded.
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
                channel << [:file_list,
                    {:nick => nick, :list => @file_list[nick]}]

                @getting_file_list.delete nick
              end
          end
        end

        @getting_file_list[nick] = true
        download nick, 'files.xml.bz2'

        EventMachine.add_timer 60 do
          @file_list.delete nick
          @getting_file_list.delete nick
        end
        true
      end

      # Synchronously load the file list with a specified timeout.
      #
      # @param [String] nick the nick to download the file list for
      # @param [Integer] timeout the number of seconds to timeout for this
      #   download
      # @return [Hash, nil] the parsed file list of the user (if downloaded), or
      #   nil if the download timed out. The downloaded file list is cached for
      #   a minute.
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

      protected

      # Parses a file list that has just been download.
      #
      # @param [String] file the file the file list was downloaded into
      # @param [String] nick the nick of the peer that was downloaded from
      #
      # @return [Hash, nil] the constructed file list, or nil if the file wasn't
      #   found.
      def parse_file_list file, nick
        if file && File.exists?(file)
          Fargo.logger.debug "Parsing file list for: '#{nick}' at '#{file}'"
          xml = Bzip2::Reader.open(file).read
          doc = Nokogiri::XML::Document.parse xml

          construct_file_list doc.root, nil, nick
        else
          nil
        end
      end

      # Recursive helper for constructing a file list from a node
      #
      # @param [Nokogiri::XML::Node] node the current node at which construction
      #   is occurring.
      # @param [String, nil] prefix the path prefix that leads down to this
      #   current node. If nil, then this node's children are roots.
      # @param [String] nick the nick that the file list is for.
      def construct_file_list node, prefix, nick
        list = {}

        node.element_children.each do |element|
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
      end

    end
  end
end
