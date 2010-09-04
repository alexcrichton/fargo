module Fargo
  module Connection
    class Search < Base

      # maybe do something special here at some point?
      # this is currently just receiving the search result packets over UDP
      # and fowarding them to the client who will handle them. This doesn't
      # explicitly disconnect because I'm not sure if multiple results
      # are sent. This connection will close itself because there will
      # be a read error I think...
      def receive data
        message = parse_message data
        
        @client.publish message[:type], message
      end
  
    end
  end
end