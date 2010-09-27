module Fargo
  class SearchResult

    # Needs :file, :filesize, :client, :target (if passive)
    def initialize file, filesize, client, target = nil
      @file, @filesize, @client, @target = file, filesize, client, target
    end

    def to_s
      file = @file.gusb '/', "\\"
      if File.directory? @file
        s = file
      else
        s = "#{file}\005#{@filesize}"
      end

      s << sprintf(" %d/%d\005%s (%s:%d)", @client.open_slots,
                                           @client.config.upload_slots,
                                           @client.hub.hubname,
                                           @client.config.hub_address,
                                           @client.config.hub_port)
      s << "\005#{@target}" if @client.config.passive
    end

    def active_send nick, ip, port
      socket = EventMachine.open_datagram_socket '0.0.0.0', 0
      socket.send_datagram "$SR #{nick} #{to_s}", ip, port
      socket.close_connection_after_writing
    end
  end
end
