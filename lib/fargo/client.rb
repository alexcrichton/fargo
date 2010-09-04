require 'active_support/callbacks'
require 'active_support/configurable'
require 'active_support/core_ext/object/try'

module Fargo
  class Client

    include ActiveSupport::Callbacks
    include ActiveSupport::Configurable

    define_callbacks :setup

    include Fargo::Publisher
    include Fargo::Supports::Chat
    include Fargo::Supports::Uploads
    include Fargo::Supports::NickList
    include Fargo::Supports::Searches
    include Fargo::Supports::Downloads
    include Fargo::Supports::Persistence

    # Options
    #   :hub_port
    #   :hub_address
    #   :search_port
    #   :active_port
    #   :nick
    #   :password
    #   :email
    #   :speed
    #   :passive
    #   :download_slots
    #   :download_dir
    #   :slots    
    configure do |config|
      config.download_dir = '/tmp/fargo/downloads'
      config.version      = '0.75'
      # default the address to the address of this machine
      config.address      = IPSocket.getaddress(Socket.gethostname)
      config.passive      = true
      config.nick         = 'fargo'
    end

    attr_reader :hub, :searcher, :active_server
    
    def initialize
      @connection_timeout_threads = {}
    end
    
    # Don't do this in initialization so we have time to set all the options
    def setup
      @hub = Fargo::Connection::Hub.new self
      @hub.config.port    = config.hub_port if config.hub_port
      @hub.config.address = config.hub_address if config.hub_address

      unless config.passive
        # TODO: get this working again
        # Always create a search connection for this.
        # searcher_options = new_options.merge :port => search_port, 
        #                                      :connection => Fargo::Connection::Search
        # @searcher    = Fargo::Server.new searcher_options
        # 
        # # For now, being active means that you can only download things. Always make a 
        # # connection which downloads things.
        # active_options     = new_options.merge :port => active_port, 
        #                                        :connection => Fargo::Connection::Download
        # @active_server = Fargo::Server.new active_options
      end

      run_callbacks :setup
    end

    def get_info nick
      hub.write "$GetINFO #{nick} #{config.nick}"
    end

    def get_ip *nicks
      hub.write "$UserIP #{nicks.flatten.join '$$'}"
    end

    def connect_with nick
      @connection_timeout_threads[nick] = Thread.start do
        sleep 10
        connection_timeout! nick
      end

      if config.passive
        hub.write "$RevConnectToMe #{self.nick} #{nick}"
      else
        hub.write "$ConnectToMe #{nick} #{address}:#{active_port}"
      end
    end
    
    def connected_with! nick
      return unless @connection_timeout_threads.has_key?(nick)
      @connection_timeout_threads.delete(nick).exit
    end

    def connect
      setup if hub.nil?

      # connect all our associated servers
      hub.connect

      unless config.passive
        searcher.connect
        active_server.connect
      end

      true
    end
    
    def connected?
      hub.try :connected?
    end

    def disconnect
      return if hub.nil?

      Fargo.logger.info "Disconnecting from hub."
      hub.disconnect
      unless config.passive
        searcher.disconnect
        active_server.disconnect
      end
    end

    def search_hub query
      raise ConnectionError.new('Not connected Yet!') if hub.nil?

      if config.passive
        location = "Hub:#{config.nick}"
      else
        location = "#{config.address}:#{config.search_port}"
      end

      hub.write "$Search #{location} #{query.to_s}"
    end

    # see hub/parser#@@search for what's passed in
    # searches this client's files based on those options and returns an array
    # of SearchResult(s)
    def search_files options
      # TODO: implement me
      []
    end

    def description
      "<++ V:#{config.version},M:#{config.passive ? 'P' : 'A'},H:1/0/0,S:#{open_slots},Dt:1.2.0/W>"
    end

    private

    def connection_timeout! nick
      @connection_timeout_threads.delete(nick).disconnect
      publish :connection_timeout, :nick => nick
    end
    
  end
end
