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
      
      attr_reader :current_downloads, :finished_downloads, :queued_downloads,
                  :failed_downloads, :open_download_slots, :trying, :timed_out,
                  :download_slots
      
      included do
        set_callback :setup, :after, :initialize_queues
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

        # Append it to the queue of things to download. This will be processed
        # elsewhere
        @to_download << download
        true
      end

      def retry_download nick, file
        dl = (@failed_downloads[nick] ||= []).detect{ |h| h.file == file }

        if dl.nil?
          Fargo.logger.warn "#{file} isn't a failed download for: #{nick}!"
          return
        end
        
        @failed_downloads[nick].delete dl
        download dl.nick, dl.file, dl.tth, dl.size
      end

      def remove_download nick, file
        # We need to synchronize this access, so append these arguments to a 
        # queue to be processed later
        @to_remove << [nick, file]
        true
      end

      def lock_next_download! user, connection
        @downloading_lock.synchronize {
          return get_next_download_with_lock! user, connection
        }
      end

      # If a connection timed out, retry all queued downloads for that user
      def try_again nick
        return false unless @timed_out.include? nick

        @timed_out.delete nick
        downloads = @failed_downloads[nick].dup
        @failed_downloads[nick].clear
        downloads.each{ |d| download nick, d.file, d.tth, d.size }

        true
      end

      private

      # Finds the next queued up download and begins downloading it.
      def start_download
        return false if open_download_slots == 0 || @current_downloads.size + @trying.size > download_slots

        arr = nil

        @downloading_lock.synchronize {
          # Find the first nick and download list
          arr = @queued_downloads.to_a.detect{ |nick, downloads|
            downloads.size > 0 && 
              !@current_downloads.has_key?(nick) && 
              !@trying.include?(nick) && 
              !@timed_out.include?(nick) && 
              has_slot?(nick)
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

        arr
      end

      # This method should only be called when synchronized by the mutex
      def get_next_download_with_lock! user, connection
        raise 'No open slots!'                    if @open_download_slots <= 0
        raise "Already downloading from #{user}!" if @current_downloads[user]

        if @queued_downloads[user].nil? || @queued_downloads[user].size == 0
          return nil
        end

        download                 = @queued_downloads[user].shift 
        @current_downloads[user] = download
        @trying.delete user

        Fargo.logger.debug "#{self}: Locking download: #{download}"

        block = Proc.new{ |type, map|
          Fargo.logger.debug "#{connection}: received: #{type.inspect} - #{map.inspect}"

          if type == :download_progress
            download.percent = map[:percent]
          elsif type == :download_started
            download.status = 'downloading'
          elsif type == :download_finished
            connection.unsubscribe &block
            download.percent = 1
            download.status = 'finished'
            download_finished! user, false
          elsif type == :download_failed || type == :download_disconnected
            connection.unsubscribe &block
            download.status = 'failed'
            download_finished! user, true
          end
        }

        connection.subscribe &block

        download
      end
      
      def download_finished! user, failed
        download = nil
        @downloading_lock.synchronize{ 
          download = @current_downloads.delete user
          @open_download_slots += 1
        }

        if failed
          (@failed_downloads[user] ||= []) << download
        else
          (@finished_downloads[user] ||= []) << download
        end

        start_download # Start another download if possible
      end
      
      def connection_failed_with! nick
        @trying.delete nick
        @timed_out << nick

        @downloading_lock.synchronize {
          @queued_downloads[nick].each{ |d| d.status = 'timeout' }
          @failed_downloads[nick] ||= []
          @failed_downloads[nick] = @failed_downloads[nick] | @queued_downloads[nick]
          @queued_downloads[nick].clear
        }

        start_download # This one failed, try the next one
      end

      def initialize_queues
        @download_slots ||= 4

        FileUtils.mkdir_p config.download_dir, :mode => 0755

        @downloading_lock = Mutex.new

        # Don't use Hash.new{} because this can't be dumped by Marshal
        @queued_downloads   = {}
        @current_downloads  = {}
        @failed_downloads   = {}
        @finished_downloads = {}
        @trying             = []
        @timed_out          = []

        @open_download_slots = download_slots

        subscribe { |type, hash|
          if type == :connection_timeout
            connection_failed_with! hash[:nick] if @trying.include?(hash[:nick])
          elsif type == :hub_disconnected
            exit_download_queue_threads
          elsif type == :hub_connection_opened
            start_download_queue_threads
          end
        }
      end

      def exit_download_queue_threads
        @download_starter_thread.exit
        @download_removal_thread.exit
      end

      # Both of these need access to the synchronization lock, so we use 
      # separate threads to do these processes.
      def start_download_queue_threads
        @to_download = Queue.new
        @download_starter_thread = Thread.start {
          loop {
            download = @to_download.pop

            if @timed_out.include? download.nick
              download.status = 'timeout'
              (@failed_downloads[download.nick] ||= []) << download
            else
              (@queued_downloads[download.nick] ||= []) << download
              start_download
            end
          }
        }

        @to_remove = Queue.new
        @download_removal_thread = Thread.start {
          loop {
            user, file = @to_remove.pop

            @downloading_lock.synchronize {
              @queued_downloads[user] ||= []
              download = @queued_downloads[user].detect{ |h| h.file == file }
              @queued_downloads[user].delete download unless download.nil?
            }
          }
        }
      end

    end # Downloads  
  end # Supports
end # Fargo
