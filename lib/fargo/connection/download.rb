module Fargo
  module Connection
    class Download < Base
      
      include Fargo::Utils
      include Fargo::Parser
        
      def pre_listen
        Fargo.logger.debug "Initiating connection on: #{self[:address]}:#{self[:port]}"
        
        self[:quit_on_disconnect] = false
        @lock, @pk = generate_lock
        @handshake_step = 0
        
        @buffer_size = (2 << 12).freeze
      end
      
      def post_listen
        write "$MyNick #{self[:nick]}|$Lock #{@lock} Pk=#{@pk}" if self[:first]
      end
      
      def read_data
        return super if @handshake_step != 6 # only download if we're at the correct time

        @exit_time = 20 # reset our timeout time
        
        data = @socket.readpartial @buffer_size
        
        if @zlib
          @zs = Zlib::Inflate.new if @zs.nil?
          data = @zs.inflate data
        end
        
        @file << data
        @recvd += data.length

        if @recvd == @length
          download_finished!
        elsif @recvd > @length
          Fargo.logger.warn "#{self} #{@recvd} > #{@length}!!!"
          download_finished!
        else
          publish :download_progress, :percent => @recvd.to_f / @length, 
                                      :file => download_path, 
                                      :nick => @other_nick, :download => self[:download],
                                      :size => @length, :compressed => @zlib
        end
      rescue IOError => e
        Fargo.logger.warn @last_error = "#{self}: IOError, disconnecting #{e}"
        disconnect
      end
  
      def receive data
        message = parse_message data
        
        case message[:type]
          when :mynick
            if @handshake_step == 0              
              @handshake_step = 1 
              @other_nick = message[:nick]

              self[:client].connected_with! @other_nick
              self[:client].lock_connection_with! @other_nick, self
              self[:download] = self[:client].lock_next_download! @other_nick, self

              if self[:download].nil? || self[:download].file.nil?
                Fargo.logger.warn @last_error = "Nothing to download from:#{@other_nick}!"
                disconnect
              end
            else
              Fargo.logger.warn @last_error = "Premature disconnect when mynick received"
              disconnect
            end
            
          when :lock
            if @handshake_step == 1
              @remote_lock = message[:lock]
              @handshake_step = 2
              out = ''
              out << "$MyNick #{self[:nick]}|" unless self[:first]
              out << "$Lock #{@lock} Pk=#{@pk}|" unless self[:first]
              out << "$Supports TTHF ADCGet ZLIG|"
              out << "$Direction Download #{@my_num = rand(10000)}|"
              out << "$Key #{generate_key @remote_lock}|"
              write out
            else
              Fargo.logger.warn @last_error = "Premature disconnect when lock received"
              disconnect
            end
            
          when :supports
            if @handshake_step == 2
              @client_extensions = message[:extensions]
              @handshake_step = 3
            else
              Fargo.logger.warn @last_error = "Premature disconnect when supports received"
              disconnect
            end
            
          when :direction
            if @handshake_step == 3 && message[:direction] == 'upload'
              @client_num = message[:number]
              @handshake_step = 4
            else
              Fargo.logger.warn @last_error = "Premature disconnect when direction received"
              disconnect
            end
            
          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]

              dir = File.dirname download_path
              FileUtils.mkdir_p dir, :mode => 0755

              begin_download!
              
            else
              Fargo.logger.warn @last_error = "Premature disconnect when key received"
              disconnect
            end
          when :file_length, :adcsnd
            if @handshake_step == 5
              @recvd = 0
              @handshake_step = 6
                            
              @zlib = message[:zlib]
              @length = message[:size]
              
              write "$Send" unless @client_extensions.include? 'ADCGet'
              
              publish :download_started, :file => download_path, 
                                         :download => self[:download], 
                                         :nick => @other_nick   
            else
              Fargo.logger.warn @last_error = "Premature disconnect when #{message[:type]} received"
              disconnect
            end
          when :noslots
            if self[:download]
              Fargo.logger.debug "#{self}: No Slots for #{self[:download]}"
              
              download_failed! "No Slots"
            end
          when :error
            Fargo.logger.error "#{self}: Error! #{message[:message]}"
            disconnect
          
          # This wasn't handled by us, proxy it on up to the client  
          else
            self[:client].publish message[:type], message
          
        end
      end
      
      def begin_download!
        @file = File.new(download_path, File::CREAT | File::WRONLY)

        self[:offset] = 0 if self[:offset].nil?

        @file.seek self[:offset]
        @file.sync = true
        @socket.sync = true
        @handshake_step = 5
        
        if @client_extensions.include? 'ADCGet'
          download_query = self[:download].file
          if !self[:download].file_list? && @client_extensions.include?('TTHF')
            download_query = self[:download].tth.gsub ':', '/'
          end
          zlig = ''
          if @client_extensions.include?("ZLIG") 
            zlig = "ZL1"
            Fargo.logger.debug "#{self} Enabling zlib compression on: #{self[:download].file}"
          end
          write "$ADCGET file #{download_query} #{self[:offset]} -1 #{zlig}"
        else
          write "$Get #{self[:download].file}$#{self[:offset] + 1}"
        end
        
        # This is the thread for the timeout of a connection. The @exit_time variable
        # is reset to 20 after every bit of information is received.
        @exit_time = 20
        @exit_thread = Thread.start { 
          while @exit_time > 0
            sleep 1
            @exit_time -= 1
            Fargo.logger.debug "#{self} time out in #{@exit_time} seconds"
          end
          download_failed! "Download timeout!" 
        }
        
        Fargo.logger.debug "#{self}: Beginning download of #{self[:download]}"
      end
      
      def download_failed! msg, opts = {}
        Fargo.logger.debug "#{self}: #{msg} #{self[:download]}"
        
        # cache because publishing must be at end of method and we're about to clear these
        path, download = download_path, self[:download]

        reset_download
        
        publish :download_failed, opts.merge(:nick => @other_nick, 
                                             :download => download, 
                                             :file => path, 
                                             :last_error => msg)
        @exit_thread = nil
      end
      
      def download_finished!
        Fargo.logger.debug "#{self}: Finished download of #{self[:download]}"
        
        # cache because publishing must be at end of method and we're about to clear these
        path, download = download_path, self[:download]
        
        reset_download
        
        publish :download_finished, :file => path, :download => download, 
                                    :nick => @other_nick
      end
      
      def disconnect
        Fargo.logger.debug "#{self} Disconnecting from: #{@other_nick}"
        
        super

        download_failed! @last_error, :recvd => @recvd, :length => @length if self[:download]
        
        reset_download
      end
     
      private
      def reset_download
        @file.close unless @file.nil? || @file.closed?
        File.delete(@file_path) if @file_path && File.exists?(@file_path) && File.size(@file_path) == 0
        
        if @socket
          @socket.sync = false
          @socket.flush
        end
        
        if @exit_thread != Thread.current # this was called from exit thread, don't kill it
          @exit_thread.exit if @exit_thread && @exit_thread.alive?
          @exit_thread = nil
        end
        
        # clear out these variables
        @zs = self[:offset] = @file_path = @zlib = self[:download] = @length = @recvd = nil        

        # Go back to the get step
        @handshake_step = 5
      end
  
      def download_path
        return nil if self[:download].nil? || self[:download].file.nil?
        return @file_path unless @file_path.nil?
        prefix = self[:client].download_dir
        filename = File.basename self[:download].file.gsub("\\", '/')
        
        @file_path = File.join(prefix, @other_nick, filename)
        return @file_path unless File.exists?(@file_path)
        
        # Generate a file name which won't overwrite some previous one
        i = 0
        while File.exists?(@file_path = File.join(prefix, @other_nick, "#{i}-#{filename}"))
          i += 1
        end
        @file_path
      end
  
    end
  end
end