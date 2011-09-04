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

      attr_reader :current_downloads, :finished_downloads, :queued_downloads,
                  :failed_downloads, :trying, :timed_out

      def has_download_slot?
        raise NotInReactor unless EM.reactor_thread?
        open_download_slots > 0
      end

      def open_download_slots
        raise NotInReactor unless EM.reactor_thread?
        config.download_slots - @trying.size - @current_downloads.size
      end

      def clear_failed_downloads
        failed_downloads.clear
      end

      def clear_finished_downloads
        finished_downloads.clear
      end

      # Begin downloading a file from a remote peer. The actual download
      # may not begin immediately, but it will be scheduled to occur in the
      # future
      #
      # @param [Fargo::Listing, Fargo::Download, String] object if this is
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
          dl     = nick
          nick   = dl.nick
          file   = dl.file
          tth    = dl.tth
          size   = dl.size || -1
          offset = dl.offset || 0
        elsif object.is_a?(Listing) # i.e. a listing
          listing = nick
          nick    = listing.nick
          file    = listing.name
          tth     = listing.tth
          size    = listing.size
        else
          nick = object
        end

        raise 'File must not be nil!' if file.nil?
        unless nicks.include? nick
          raise ConnectionException.new "User #{nick} does not exist!"
        end

        tth = tth.gsub /^TTH:/, '' if tth

        download         = Download.new nick, file, tth, size, offset
        download.percent = 0
        download.status  = 'idle'

        # Using the mutex can be expensive in start_download, defer this
        if @timed_out.include? download.nick
          download.status = 'timeout'
          @failed_downloads[download.nick] << download
          return nil
        else
          if (@queued_downloads[download.nick] &&
              @queued_downloads[download.nick].include?(download)) ||
             @current_downloads[download.nick] == download
            return nil
          else
            (@queued_downloads[download.nick] ||= []) << download
            # This might not actually start the download. We
            # could possibly already be downloading from this
            # peer in which case we will queue this for later.
            EventMachine.next_tick { start_download }
          end
        end

        download
      end

      def retry_download nick, file
        raise NotInReactor unless EM.reactor_thread?
        dl = @failed_downloads[nick].detect{ |h| h.file == file }

        return if dl.nil?

        @failed_downloads[nick].delete dl
        download dl
      end

      def remove_download nick, file
        raise NotInReactor unless EM.reactor_thread?
        return unless @queued_downloads.key?(nick)
        @queued_downloads[nick].delete_if{ |h| h.file == file }
        @queued_downloads.delete(nick) if @queued_downloads[nick].empty?
      end

      # This is meant to get the Fargo::Download struct representing the next
      # download for a nick. A download should not initiate based off of this
      # information. This function exists to peek into the queue and see if we
      # have a download for the nick to send them the correct Upload or
      # Download direction. The Fargo::Download instance must later be locked
      # via {#lock_download!} to actually download the file.
      #
      # @param [String] nick the nick to get a download for
      # @return [Fargo::Download] a struct representing the next file that
      #    should be downloaded from this peer. This download should not
      #    actually be downloaded, but rather just used for information purposes
      def next_download_for nick
        raise NotInReactor unless EM.reactor_thread?
        @queued_downloads.key?(nick) ? @queued_downloads[nick].first : nil
      end

      # This is intended to be used for when a download has been previously
      # fetched via {#next_download_for}. This function then locks the download
      # so it's listed internally as being downloaded.
      #
      # @param [Fargo::Download] download object returned from the previous call
      #     to {#next_download_for}
      def lock_download! download
        peer = download.nick
        connection = connection_for peer
        # Check to make sure we're in a sane environment.
        raise NotInReactor                        unless EM.reactor_thread?
        raise "Already downloading from #{peer}!" if @current_downloads[peer]
        raise "No downloads: #{peer}"        if !@queued_downloads.key?(peer)
        raise 'Should not have empty array!' if @queued_downloads[peer].empty?
        raise "We should be connected with: #{peer}" if connection.nil?

        @queued_downloads[peer].delete(download)
        @queued_downloads.delete(peer) if @queued_downloads[peer].empty?
        @current_downloads[peer] = download
        @trying.delete peer

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
              download_finished! peer, map[:failed]
            end
          end
        end

        download
      end

      # If a connection timed out, retry all queued downloads for that user.
      #
      # @param [String] nick the remote peer name which has been previously
      #   timed out
      # @return [Boolean] true if all downloads were retried, false if the
      #   specified nick was never timed out.
      def try_again nick
        raise NotInReactor unless EM.reactor_thread?
        return false unless @timed_out.include? nick

        @timed_out.delete nick
        downloads = @failed_downloads[nick].dup
        @failed_downloads[nick].clear
        # Reschedule all the failed downloads again
        EM.next_tick {
          downloads.each{ |d| download nick, d.file, d.tth, d.size }
        }

        true
      end

      protected

      # Generically start the next download from the remote hub. This method
      # will inspect all queues and figure out the first download which can
      # be retrieved from the remote.
      #
      # @return [Boolean] true if a download was started
      def start_download
        raise NotInReactor unless EM.reactor_thread?
        return false unless has_download_slot?

        # Find the first candidate for downloading
        nick, downloads = @queued_downloads.detect{ |nick, downloads|
          raise 'Should have at least one download!' if downloads.empty?

          # Only download one file at a time from a peer who has not timed out.
          # The remote nick also needs to either have a slot or we should have
          # a connection open with them.
          !@current_downloads.key?(nick) &&
            !@trying.include?(nick) &&
            !@timed_out.include?(nick) #&&
            # (connection_for(nick) || nick_has_slot?(nick))
        }

        return false if nick.nil? || downloads.nil?
        connection = connection_for nick

        # If we already have an open connection to this user, tell that
        # connection to download the file. Otherwise, request a connection
        # which will handle downloading when the connection is complete.
        if connection
          debug 'download', "Using previous connection with #{nick}"
          download = downloads.first
          lock_download! download
          connection.download = download
          connection.begin_download!
        else
          @trying << nick
          connect_with nick
        end
        true
      end

      def download_finished! user, failed
        raise NotInReactor unless EM.reactor_thread?
        download = @current_downloads.delete user

        if failed
          @failed_downloads[user] << download
        else
          @finished_downloads[user] << download
        end

        # Start another download if possible
        EventMachine.next_tick{ start_download }
      end

      def connection_failed_with! nick
        raise NotInReactor unless EM.reactor_thread?
        @trying.delete nick
        @timed_out << nick

        @queued_downloads[nick].each{ |d|
          d.status = 'timeout'
          channel << [:download_finished, {
            :download   => d,
            :failed     => true,
            :last_error => 'Client timed out.'
          }]
        }
        @failed_downloads[nick] |= @queued_downloads.delete(nick)

        # This one failed, try the next one
        EventMachine.next_tick{ start_download }
      end

      def initialize_download_lists
        FileUtils.mkdir_p config.download_dir, :mode => 0755

        @queued_downloads   = {}
        @current_downloads  = {}
        @failed_downloads   = Hash.new{ |h, k| h[k] = [] }
        @finished_downloads = Hash.new{ |h, k| h[k] = [] }
        @trying             = []
        @timed_out          = []

        channel.subscribe do |type, hash|
          if type == :connection_timeout
            # Time out this connection with the remote user and remember that
            # we have timed out with them
            connection_failed_with! hash[:nick] if @trying.include?(hash[:nick])

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
