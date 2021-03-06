require 'socket'
require 'active_support/core_ext/object/try'
require 'active_support/callbacks'
require 'active_support/configurable'

module Fargo
  RESET = "\e[0m"
  BOLD  = "\e[1m"
  RED   = "\e[31m"
  GREEN = "\e[32m"
  BLUE  = "\e[34m"

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
    include Supports::RemoteFileList
    include Supports::LocalFileList

    configure do |config|
      config.download_dir   = '/tmp/fargo/downloads'
      config.config_dir     = ENV['HOME'] + '/.fargo'
      config.address        = '0.0.0.0'
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
      config.update_interval     = 60
      config.override_share_size = nil
      config.color = false
    end

    attr_reader :hub, :channel

    def initialize
      run_callbacks :initialization do
        @channel             = EventMachine::Channel.new
        @connection_timeouts = {}

        @channel.subscribe do |type, hash|
          debug 'event', "#{type} - #{hash.inspect}", BOLD
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
      config.passive_search = config.passive
      run_callbacks :connect do
        EventMachine.connect config.hub_address, config.hub_port,
            Protocol::Hub do |conn|
          if conn.error?
            channel << [:hub_disconnected, {}]
          else
            @hub        = conn
            @hub.client = self
          end
        end

        unless config.passive
          EventMachine.start_server '0.0.0.0', config.active_port,
              Protocol::Peer do |conn|
            if conn.error?
              config.passive = true
            else
              conn.client = self
            end
          end

          EventMachine.open_datagram_socket '0.0.0.0', config.search_port,
              Protocol::DC do |conn|
            if conn.error?
              config.passive_search = true
            else
              conn.client = self
            end
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
      EventMachine.reactor_running?
    end

    def disconnect
      Fargo.logger.info 'Disconnecting from hub.'
      EventMachine.stop_event_loop
    end

    def description
      "<fargo V:#{VERSION},M:#{config.passive ? 'P' : 'A'},H:1/0/0,S:#{open_upload_slots},Dt:1.2.6/W>"
    end

    def debug type, message, color = nil
      log = ''
      log << Time.now.to_s
      log << ": ["
      log << BOLD  if config.color && color
      log << type.rjust(8)
      log << RESET if config.color
      log << "] "
      log << color if config.color && color
      log << message
      log << RESET if config.color
      Fargo.logger.debug log
    end

  end
end
