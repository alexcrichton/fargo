require 'socket'
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
      config.address        = IPSocket.getaddress(Socket.gethostname)
      config.passive        = false
      config.nick           = 'fargo'
      config.hub_address    = '127.0.0.1'
      config.hub_port       = 7314
      config.active_port    = 7315
      config.search_port    = 7316
      config.download_slots = 4
      config.upload_slots   = 4
      config.password       = ''
      config.speed          = 'DSL'
      config.email          = nil
    end

    attr_reader :hub, :channel

    def initialize
      run_callbacks :initialization do
        @channel             = EventMachine::Channel.new
        @connection_timeouts = {}

        @channel.subscribe do |type, hash|
          Fargo.logger.debug "Channel received: #{type} - #{hash.inspect}"
        end
      end
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

      unless config.passive
        EventMachine.start_server '0.0.0.0', config.active_port,
            Fargo::Protocol::Download do |conn|
          conn.client = self
        end

        EventMachine.open_datagram_socket '0.0.0.0', config.search_port,
            Fargo::Protocol::DC do |conn|
          conn.client = self
        end
      end
    end

    def connected?
      EventMachine.reactor_running?
    end

    def disconnect
      Fargo.logger.info 'Disconnecting from hub.'
      EventMachine.stop_event_loop
    end

    def description
      "<fargo V:#{Fargo::VERSION},M:#{config.passive ? 'P' : 'A'},H:1/0/0,S:#{open_slots},Dt:1.2.6/W>"
    end

  end
end
