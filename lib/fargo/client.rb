require 'active_support/core_ext/object/try'
require 'active_support/callbacks'

module Fargo
  class Client

    include ActiveSupport::Configurable
    include ActiveSupport::Callbacks

    define_callbacks :initialization

    include Fargo::Supports::Chat
    include Fargo::Supports::Uploads
    include Fargo::Supports::NickList
    include Fargo::Supports::Searches
    include Fargo::Supports::Downloads
    include Fargo::Supports::Persistence
    include Fargo::Supports::Timeout
    include Fargo::Supports::FileList

    configure do |config|
      config.download_dir   = '/tmp/fargo/downloads'
      config.version        = '0.75'
      config.address        = IPSocket.getaddress(Socket.gethostname)
      config.passive        = true
      config.nick           = 'fargo'
      config.hub_address    = '127.0.0.1'
      config.hub_port       = 7314
      config.download_slots = 4
      config.password       = ''
      config.speed          = 'DSL'
      config.email          = nil
    end

    attr_reader :hub, :channel

    def initialize
      run_callbacks :initialization do
        @channel             = EventMachine::Channel.new
        @connection_timeouts = {}
      end
    end

    def get_info nick
      hub.send_message 'GetINFO', "#{nick} #{config.nick}"
    end

    def get_ip *nicks
      hub.send_message 'UserIP', nicks.flatten.join('$$')
    end

    def connect_with nick
      @connection_timeouts[nick] = EventMachine::Timer.new(10) do
        connection_timeout! nick
      end

      if config.passive
        hub.send_message 'RevConnectToMe', "#{self.config.nick} #{nick}"
      else
        hub.send_message 'ConnectToMe',
          "#{nick} #{config.address}:#{config.active_port}"
      end
    end

    def connected_with! nick
      @connection_timeouts.delete(nick).try(:cancel)
    end

    def connect
      EventMachine.error_handler{ |e|
        Fargo.logger.debug "Error raised during event loop: #{e.message}"
        Fargo.logger.debug e.backtrace.join("\n")
      }

      EventMachine.connect config.hub_address, config.hub_port,
          Fargo::Protocol::Hub do |conn|
        @hub        = conn
        @hub.client = self
      end
    end

    def connected?
      EventMachine.reactor_running?
    end

    def disconnect
      Fargo.logger.info 'Disconnecting from hub.'
      EventMachine.stop_event_loop
    end

    def search_hub query
      raise ConnectionError.new('Not connected Yet!') unless connected?

      if config.passive
        location = "Hub:#{config.nick}"
      else
        location = "#{config.address}:#{config.search_port}"
      end

      hub.send_message 'Search', "#{location} #{query.to_s}"
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
      @connection_timeouts.delete(nick)
      channel.push [:connection_timeout, {:nick => nick}]
    end

  end
end
