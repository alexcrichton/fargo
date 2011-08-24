require 'socket'
require 'active_support/core_ext/object/try'
require 'active_support/callbacks'
require 'active_support/configurable'

module Fargo
  class Client

    include ActiveSupport::Configurable
    include ActiveSupport::Callbacks

    define_callbacks :initialization, :connect

    include Supports::Chat
    include Supports::Uploads
    include Supports::NickList
    include Supports::Searches
    include Supports::Downloads
    include Supports::Persistence
    include Supports::Timeout
    include Supports::RemoteFileList
    include Supports::LocalFileList

    configure do |config|
      config.download_dir   = '/tmp/fargo/downloads'
      config.config_dir     = ENV['HOME'] + '/.fargo'
      config.address        =
        (IPSocket.getaddress(Socket.gethostname) rescue '0.0.0.0')
      config.passive        = false
      config.nick           = 'fargo'
      config.hub_address    = '127.0.0.1'
      config.hub_port       = 7314
      config.active_port    = 7315
      config.search_port    = 7316
      config.websocket_port = 9091
      config.websocket_host = '127.0.0.1'
      config.download_slots = 4
      config.upload_slots   = 4
      config.password       = ''
      config.speed          = 'DSL'
      config.email          = nil
      config.override_share_size = nil
    end

    attr_reader :hub, :channel

    def initialize
      run_callbacks :initialization do
        @channel             = EventMachine::Channel.new
        @connection_timeouts = {}

        @channel.subscribe do |type, hash|
          Fargo.logger.debug(
            "#{Time.now}: Channel received: #{type} - #{hash.inspect}")
        end

        config_file = config.config_dir + '/config'
        if File.exists? config_file
          eval File.read(config_file)
        end
      end
    end

    def hub_url
      "dc://#{config.hub_address}:#{config.hub_port}"
    end

    def active_server_url
      "dc://#{config.address}:#{config.active_port}"
    end

    def search_server_url
      "dc://#{config.address}:#{config.search_port}"
    end

    def websocket_url
      "ws://#{config.websocket_host}:#{config.websocket_port}"
    end

    def connect
      run_callbacks :connect do
        EventMachine.connect config.hub_address, config.hub_port,
            Protocol::Hub do |conn|
          @hub        = conn
          @hub.client = self
        end

        unless config.passive
          EventMachine.start_server '0.0.0.0', config.active_port,
              Protocol::Peer do |conn|
            conn.client = self
          end

          EventMachine.open_datagram_socket '0.0.0.0', config.search_port,
              Protocol::DC do |conn|
            conn.client = self
          end
        end
      end

      start_websocket_service if defined?(EventMachine::WebSocket)
    end

    def start_websocket_service
      require 'base64'
      EventMachine.start_server(config.websocket_host, config.websocket_port,
          EventMachine::WebSocket::Connection, {}) do |ws|
        ws.onopen {
          Fargo.logger.debug('ws connected')

          sid = channel.subscribe do |type, hash|
            if type != :peer_connected
              ws.send Base64.encode64(Marshal.dump([type, hash]))
            end
          end

          ws.onclose{ channel.unsubscribe sid }
        }
      end
    end

    def connected?
      EventMachine.reactor_running? && !hub.error?
    end

    def disconnect
      Fargo.logger.info 'Disconnecting from hub.'
      EventMachine.stop_event_loop
    end

    def description
      "<fargo V:#{VERSION},M:#{config.passive ? 'P' : 'A'},H:1/0/0,S:#{open_upload_slots},Dt:1.2.6/W>"
    end

  end
end
