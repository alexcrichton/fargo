require 'fileutils'
require 'eventmachine'
require 'active_support/dependencies/autoload'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/module/delegation'
require 'active_support/buffered_logger'
require 'active_support/concern'
require 'active_support/configurable'

module Fargo
  extend ActiveSupport::Autoload

  class ConnectionException < RuntimeError; end

  mattr_accessor :logger
  self.logger = ActiveSupport::BufferedLogger.new STDOUT

  autoload :Utils
  autoload :Parser
  autoload :Client
  autoload :Search
  autoload :SearchResult
  autoload :VERSION
  autoload :TTH
  autoload :Listing, 'fargo/supports/remote_file_list'
  autoload :Download, 'fargo/supports/downloads'

  module Supports
    extend ActiveSupport::Autoload

    autoload :Chat
    autoload :Searches
    autoload :NickList
    autoload :Uploads
    autoload :Downloads
    autoload :Persistence
    autoload :Timeout
    autoload :RemoteFileList
    autoload :LocalFileList
  end

  module Protocol
    extend ActiveSupport::Autoload

    autoload :DC
    autoload :Peer
    autoload :PeerDownload
    autoload :PeerUpload
    autoload :Hub
  end

  class << self
    delegate :config, :configure, :to => Client
  end
end
