module Fargo
  class Download < Struct.new(:nick, :file, :tth, :size, :offset)
    attr_accessor :percent, :status

    def file_list?
      file == 'files.xml.bz2'
    end
  end

  module Supports
    module Downloads
      extend ActiveSupport::Concern

      included do
        set_callback :initialization, :after, :initialize_download_lists
      end

      def open_download_slots
        raise NotInReactor unless EM.reactor_thread?
        config.download_slots - @current_downloads.size
      end

      # Begin downloading a file from a remote peer. The actual download
      # may not begin immediately, but it will be scheduled to occur in the
      # future
      #
      # @param [Fargo::Download, String] object if this is
      #   either a Listing or Download, then none of the other parameters are
      #   used. The others are inferred from the fields of the Listing or
      #   Download. Otherwise the string is the nick of the remote peer to
      #   download from
      # @param [String] file the file name to download. This should have been
      #   acquired from searching the hub beforehand. Required if the first
      #   parameter is the remote peer name.
      # @param [String] tth the TTH hash of the remote file, optional.
      # @param [Integer] size the number of bytes which should be requested for
      #   download. Optional, and -1 indicates the entire file should be
      #   downloaded.
      # @param [Integer] offset the offset in bytes from the start of the file
      #   to begin downloading.
      #
      # @return [Fargo::Download, nil] If nil is returned, then the queueing of
      #   the download failed because the peer has been timed out previously,
      #   or this download is already queued. Otherwise, the download object
      #   represents the state of the download. The download may start
      #   immediately, but it may also be deferred for later.
      #
      #   To track the status of the download, subscribe to the client's channel
      #   for the events listed in Fargo::Protocol::PeerDownload
      def download object, file = nil, tth = nil, size = -1, offset = 0
        raise ConnectionException.new 'Not connected yet!' unless hub
        raise NotInReactor unless EM.reactor_thread?

        if object.is_a?(Download)
          dl     = object
          nick   = dl.nick
          file   = dl.file
          tth    = dl.tth
          size   = dl.size || -1
          offset = dl.offset || 0
        else
          nick = object
        end

        raise 'File must not be nil!' if file.nil?

        tth = tth.gsub /^TTH:/, '' if tth
        download         = Download.new nick, file, tth, size, offset
        download.percent = 0
        download.status  = 'idle'

        (@queued_downloads[download.nick] ||= []) << download
        # This might not actually start the download. We could possibly already
        # be downloading from this peer in which case we will queue this for
        # later. Regardless, let the start_download logic handle this
        EventMachine.next_tick { start_download }

        download
      end

      # Test whether we have a download in the queue for the specified peer.
      # This is meant to be used in the client to client protocol when we must
      # send them our intended direction for upload/download.
      #
      # @param [String] peer the nick to get a download for
      # @return [Boolean] true if we have a download for this users
      def download_for? peer
        raise NotInReactor unless EM.reactor_thread?
        @current_downloads.key?(peer) && @current_downloads[peer] == nil
      end

      # When {#download_for?} returns true for a peer, then this method is used
      # to return the Fargo::Download object representing the download.
      #
      # @return [Fargo::Download] download object which contains the metadata
      #   about the download
      def download_for! peer
        # Check to make sure we're in a sane environment.
        raise NotInReactor                      unless EM.reactor_thread?
        raise "No downloads for: #{peer}"       unless download_for?(peer)
        raise "We should be connected: #{peer}" if connection_for(peer).nil?

        download = @queued_downloads[peer].shift
        @queued_downloads.delete peer if @queued_downloads[peer].empty?
        @current_downloads[peer] = download

        subscribed_id = channel.subscribe do |type, map|
          if map[:nick] == peer
            if type == :download_progress
              download.percent = map[:percent]
            elsif type == :download_started
              download.status = 'downloading'
            elsif type == :download_finished
              channel.unsubscribe subscribed_id
              download.percent = 1 unless map[:failed]
              download.status  = map[:failed] ? 'failed' : 'finished'

              @current_downloads.delete peer
              EventMachine.next_tick { start_download }
            end
          end
        end

        download
      end

      protected

      # Generically start the next download from the remote hub. This method
      # will inspect all queues and figure out the first download which can
      # be retrieved from the remote.
      #
      # @return [Boolean] true if a download was started
      def start_download
        raise NotInReactor unless EM.reactor_thread?
        return false unless open_download_slots > 0

        # Find the first candidate for downloading
        nick, downloads = @queued_downloads.detect{ |nick, downloads|
          raise 'Should have at least one download!' if downloads.empty?

          # Only download one file at a time from a peer.
          !@current_downloads.key?(nick)
        }

        return false if nick.nil? || downloads.nil?
        # Signify that we're trying to initiate a connection with this nick.
        @current_downloads[nick] = nil
        connection = connection_for nick

        # If we already have an open connection to this user, tell that
        # connection to download the file. Otherwise, request a connection
        # which will handle downloading when the connection is complete.
        if connection
          debug 'download', "Using previous connection with #{nick}"
          connection.download = download_for!(nick)
          connection.begin_download!
        else
          connect_with nick
        end
        true
      end

      def connection_failed_with! nick
        raise NotInReactor unless EM.reactor_thread?
        @current_downloads.delete nick

        @queued_downloads.delete(nick).each{ |d|
          d.status = 'timeout'
          channel << [:download_finished, {
            :download   => d,
            :failed     => true,
            :last_error => 'Client timed out.'
          }]
        }

        # This one failed, try the next one
        EventMachine.next_tick{ start_download }
      end

      def initialize_download_lists
        FileUtils.mkdir_p config.download_dir, :mode => 0755

        @queued_downloads  = {}
        @current_downloads = {}

        channel.subscribe do |type, hash|
          if type == :connection_timeout
            if @current_downloads.key?(hash[:nick])
              connection_failed_with! hash[:nick]
            end

          elsif type == :upload_finished
            # If we just finished uploading something, try downloading something
            # from the other user.
            EventMachine.next_tick { start_download }
          end
        end
      end

    end
  end
end
