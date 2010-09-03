module Fargo
  module Supports
    module Downloads
      extend ActiveSupport::Concern

      class Download < Struct.new(:nick, :file, :tth, :size)
        attr_accessor :percent, :status

        def file_list?
          file == 'files.xml.bz2'
        end
      end
      
      attr_reader :current_downloads, :finished_downloads, :queued_downloads, :failed_downloads,
                  :open_download_slots, :trying, :timed_out
      
      included do
        set_callback :setup, :after, :initialize_queues
      end
      
      def clear_failed_downloads
        failed_downloads.clear
      end
      
      def clear_finished_downloads
        finished_downloads.clear
      end

      def download nick, file, tth, size
        raise ConnectionException.new "Not connected yet!" unless options[:hub]
        raise ConnectionException.new "User #{nick} does not exist!" unless nicks.include? nick
        
        raise "TTH or size or file are nil!" if tth.nil? || size.nil? || file.nil?
        download = Download.new nick, file, tth, size
        download.percent = 0
        download.status = 'idle'
        @to_download << download
        true
      end
      
      def retry_download nick, file
        download = (@failed_downloads[nick] ||= []).detect{ |h| h.file == file }
        if download.nil?
          Fargo.logger.warn "#{self}: #{file} isn't a failed download for: #{nick}!"
          return
        end
        
        @failed_downloads[nick].delete download
        download download.nick, download.file, download.tth, download.size
      end
      
      def remove_download nick, file
        @to_remove << [nick, file]
        true
      end
      
      def lock_next_download! user, connection
        @downloading_lock.synchronize {
          return get_next_download_with_lock! user, connection
        }
      end
      
      def try_again nick
        return false unless @timed_out.include? nick
        @timed_out.delete nick
        downloads = @failed_downloads[nick].dup
        @failed_downloads[nick].clear
        downloads.each { |d| download nick, d.file, d.tth, d.size }
        true
      end
      
      def start_download
        return false if open_download_slots == 0 || @current_downloads.size + @trying.size > download_slots
        arr = nil

        @downloading_lock.synchronize {
          arr = @queued_downloads.to_a.detect{ |arr|
            nick, downloads = arr
            downloads.size > 0 && !@current_downloads.has_key?(nick) && !@trying.include?(nick) && !@timed_out.include?(nick) && has_slot?(nick)
          }
          return false if arr.nil? || arr.size == 0

          if connection_for arr[0]
            Fargo.logger.debug "Requesting previous connection downloads: #{arr[1].first}"
            download = get_next_download_with_lock! arr[0], connection_for(arr[0])
            connection_for(arr[0])[:download] = download
            connection_for(arr[0]).begin_download!
          else
            Fargo.logger.debug "Requesting connection with: #{arr[0]} for downloading"
            @trying << arr[0]
            connect_with arr[0]
          end
        }
        arr
      end
      
      private
      def get_next_download_with_lock! user, connection
        raise "No open slots!" if @open_download_slots <= 0
        
        raise "Already downloading from #{user}!" if @current_downloads[user]
        
        return nil if @queued_downloads[user].nil? || @queued_downloads[user].size == 0
        
        download = @queued_downloads[user].shift 
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

        start_download
      end 
      
      def connection_failed_with! nick
        @trying.delete nick
        @timed_out << nick
        @downloading_lock.synchronize {
          @queued_downloads[nick].each{ |d| d.status = 'timeout' }
          @failed_downloads[nick] = (@failed_downloads[nick] || []) | @queued_downloads[nick]
          @queued_downloads[nick].clear
        }
        start_download
      end
      
      def initialize_queues
        self.download_slots = 4 if options[:download_slots].nil?
        
        FileUtils.mkdir_p download_dir, :mode => 0755
        
        @downloading_lock = Mutex.new
        
        # Don't use Hash.new{} because this can't be dumped by Marshal
        @queued_downloads = {}
        @current_downloads = {}
        @failed_downloads = {}
        @finished_downloads = {}
        @trying = []
        @timed_out = []
        
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
