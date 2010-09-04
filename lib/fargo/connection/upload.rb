# TODO: actually get this class to work in some fashion
module Fargo
  module Connection
    class Upload < Base
      
      include Fargo::Utils
      include Fargo::Parser
  
      def post_listen
        @lock, @pk = generate_lock
        write "$MyNick #{self[:nick]}|$Lock #{@lock} Pk=#{@pk}"
        @handshake_step = 0
      end
  
      def supports
        "$Supports BZList TTHL TTHF" # ???
      end
      
      def receive data
        message = parse_message data
        publish message[:type], message
        case message[:type]
          when :mynick
            if @handshake_step == 0
              @remote_nick = message[:nick]
              @handshake_step = 1
            else
              disconnect
            end
          when :lock
            if @handshake_step == 1
              @remote_lock = message[:lock]
              @handshake_step = 2
            else
              disconnect
            end
          when :supports
            if @handshake_step == 2
              @remote_extensions = message[:extensions]
              @handshake_step = 3
            else
              disconnect
            end
          when :direction
            if @handshake_step == 3 && message[:direction] == 'download'
              @handshake_step = 4
              @client_num = message[:number]
            else
              disconnect
            end
          when :key
            if @handshake_step == 4 && generate_key(@lock) == message[:key]
              write supports
              write "$Direction Download #{@my_num = rand 10000}"
              write "$Key #{generate_key @remote_lock}"
              @handshake_step = 5
            else
              disconnect
            end
          when :get
            if @handshake_step == 5
              @filepath = message[:path]
              @offset = message[:offset]
              write "$FileLength #{file_length}"
              @handshake_step = 5
            else
              disconnect
            end
          when :send
            write_chunk if @handshake_step == 5
        
          else
            # Fargo.logger.warn "Ignoring `#{data}'\n"
        end
      end
  
      def write_chunk
      end
  
      def file_length
      end
  
    end
  end
end