module Fargo
  class Search
    class Result

      attr_accessor :options

      # Needs :file, :filesize, :client, :target (if passive)
      def initialize opts = {}
        self.options = opts
      end

      def to_s
        file = options[:file].gusb '/', "\\"
        if File.directory? options[:file]
          s = file
        else
          s = "#{file}\005#{options[:filesize]}"
        end
        s << sprintf(" %d/%d\005%s (%s:%d)", options[:client].open_slots,
                                             options[:client].slots,
                                             options[:client].hub[:hubname],
                                             options[:client].hub[:ip],
                                             options[:client].hub[:port])
        s << "\005#{options[:target]}" if options[:passive]
      end

      def active_send nick, ip, port
        socket = UDPSocket.new
        socket.send "$SR #{nick} #{self}", 0, ip, port
        socket.close
      end
    end
  end
end