require 'fileutils'
require 'eventmachine'
require 'active_support/dependencies/autoload'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/module/delegation'
require 'active_support/buffered_logger'
require 'active_support/concern'

module Fargo
  extend ActiveSupport::Autoload

  class ConnectionException < RuntimeError; end
  class NotInReactor < RuntimeError; end

  mattr_accessor :logger
  self.logger = ActiveSupport::BufferedLogger.new STDOUT

  autoload :BlockingCounter, 'fargo/ext/blocking_counter'
  autoload :CLI
  autoload :Client
  autoload :Download, 'fargo/supports/downloads'
  autoload :Listing, 'fargo/supports/local_file_list'
  autoload :Parser
  autoload :Search
  autoload :SearchResult
  autoload :Throttler
  autoload :TTH
  autoload :Utils
  autoload :VERSION

  module Supports
    extend ActiveSupport::Autoload

    autoload :Chat
    autoload :Searches
    autoload :NickList
    autoload :Uploads
    autoload :Downloads
    autoload :Persistence
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
