module Fargo
  module Supports
    module Downloads
      extend ActiveSupport::Concern

      class Download < Struct.new(:nick, :file, :tth, :size, :offset)
        attr_accessor :percent, :status

        def file_list?
          file == 'files.xml.bz2'
        end
      end

      included do
        set_callback :initialization, :after, :initialize_download_lists
      end

      attr_reader :current_downloads, :finished_downloads, :queued_downloads,
                  :failed_downloads, :trying, :timed_out

      def has_download_slot?
        @current_downloads.size + @trying.size < config.download_slots
      end

      def clear_failed_downloads
        failed_downloads.clear
      end

      def clear_finished_downloads
        finished_downloads.clear
      end

      def download nick, file=nil, tth=nil, size=-1, offset=0
        raise ConnectionException.new 'Not connected yet!' unless hub

        if nick.is_a?(Supports::FileList::Listing)
          listing = nick
          nick    = listing.nick
          file    = listing.name
          tth     = listing.tth
          size    = listing.size
        elsif nick.is_a?(Download)
          dl     = nick
          nick   = dl.nick
          file   = dl.file
          tth    = dl.tth
          size   = dl.size || -1
          offset = dl.offset || 0
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
        else
          unless @queued_downloads[download.nick].include?(download) ||
              @current_downloads[download.nick] == download
            @queued_downloads[download.nick] << download

            # This uses the lock and could be expensive, defer this for later
            EventMachine.defer{ start_download }
          end
        end

        true
      end

      def retry_download nick, file
        dl = @failed_downloads[nick].detect{ |h| h.file == file }

        return if dl.nil?

        @failed_downloads[nick].delete dl
        download dl
      end

      def remove_download nick, file
        # We need to synchronize this access, so append these arguments to a
        # queue to be processed later
        EventMachine.defer do
          @downloading_lock.synchronize {
            @queued_downloads[nick].delete_if{ |h| h.file == file }
          }
        end
      end

      def lock_next_download! user, connection
        @downloading_lock.synchronize {
          get_next_download_with_lock! user, connection
        }
      end

      # If a connection timed out, retry all queued downloads for that user
      def try_again nick
        return false unless @timed_out.include? nick

        @timed_out.delete nick
        downloads = @failed_downloads[nick].dup
        @failed_downloads[nick].clear
        # Reschedule all the failed downloads again
        downloads.each{ |d| download nick, d.file, d.tth, d.size }

        true
      end

      protected

      # Finds the next queued up download and begins downloading it.
      def start_download
        return false unless has_download_slot?

        arr = nil

        @downloading_lock.synchronize {
          # Find the first nick and download list
          arr = @queued_downloads.to_a.detect{ |nick, downloads|
            downloads.size > 0 &&
              !@current_downloads.has_key?(nick) &&
              !@trying.include?(nick) &&
              !@timed_out.include?(nick) &&
              (connection_for(nick) || nick_has_slot?(nick))
          }

          return false if arr.nil? || arr.size == 0
          dl_nick    = arr[0]
          connection = connection_for dl_nick

          # If we already have an open connection to this user, tell that
          # connection to download the file. Otherwise, request a connection
          # which will handle downloading when the connection is complete.
          if connection
            Fargo.logger.debug "Requesting previous connection downloads: #{arr[1].first}"
            download = get_next_download_with_lock! dl_nick, connection

            connection.download = download
            connection.begin_download!
          else
            Fargo.logger.debug "Requesting connection with: #{dl_nick} for downloading"
            @trying << dl_nick
            connect_with dl_nick
          end
        }
      end

      # This method should only be called when synchronized by the mutex
      def get_next_download_with_lock! user, connection
        raise 'No open slots!'                    unless has_download_slot?
        raise "Already downloading from #{user}!" if @current_downloads[user]

        return nil if @queued_downloads[user].size == 0

        download                 = @queued_downloads[user].shift
        @current_downloads[user] = download
        @trying.delete user

        Fargo.logger.debug "#{self}: Locking download: #{download}"

        subscribed_id = channel.subscribe do |type, map|
          if map[:nick] == user
            Fargo.logger.debug "#{connection}: received: #{type.inspect} - #{map.inspect}"

            if type == :download_progress
              download.percent = map[:percent]
            elsif type == :download_started
              download.status = 'downloading'
            elsif type == :download_finished
              channel.unsubscribe subscribed_id
              download.percent = 1
              download.status  = 'finished'
              download_finished! user, false
            elsif type == :download_failed || type == :download_disconnected
              channel.unsubscribe subscribed_id
              download.status = 'failed'
              download_finished! user, true
            end
          end
        end

        download
      end

      def download_finished! user, failed
        download = nil
        @downloading_lock.synchronize{
          download = @current_downloads.delete user
        }

        if failed
          @failed_downloads[user] << download
        else
          @finished_downloads[user] << download
        end

        # Start another download if possible
        EventMachine.defer{ start_download }
      end

      def connection_failed_with! nick
        @downloading_lock.synchronize {
          @trying.delete nick
          @timed_out << nick

          @queued_downloads[nick].each{ |d| d.status = 'timeout' }
          @failed_downloads[nick] |= @queued_downloads.delete(nick)
        }

        # This one failed, try the next one
        EventMachine.defer{ start_download }
      end

      def initialize_download_lists
        FileUtils.mkdir_p config.download_dir, :mode => 0755

        @downloading_lock = Mutex.new

        @queued_downloads   = Hash.new{ |h, k| h[k] = [] }
        @current_downloads  = {}
        @failed_downloads   = Hash.new{ |h, k| h[k] = [] }
        @finished_downloads = Hash.new{ |h, k| h[k] = [] }
        @trying             = []
        @timed_out          = []

        channel.subscribe do |type, hash|
          if type == :connection_timeout
            connection_failed_with! hash[:nick] if @trying.include?(hash[:nick])
          end
        end
      end

    end
  end
end
