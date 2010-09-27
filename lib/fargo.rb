require 'fileutils'
require 'active_support/dependencies/autoload'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/buffered_logger'
require 'active_support/concern'

module Fargo
  extend ActiveSupport::Autoload

  class ConnectionException < RuntimeError; end

  mattr_accessor:logger
  self.logger = ActiveSupport::BufferedLogger.new STDOUT

  autoload :Utils
  autoload :Publisher
  autoload :Parser
  autoload :Server
  autoload :Client
  autoload :Search
  autoload :SearchResult
  autoload :VERSION

  module Supports
    extend ActiveSupport::Autoload

    autoload :Chat
    autoload :Searches
    autoload :NickList
    autoload :Uploads
    autoload :Downloads
    autoload :Persistence
    autoload :Timeout
    autoload :FileList
  end

  module Connection
    extend ActiveSupport::Autoload

    autoload :Base
    autoload :Download
    autoload :Hub
    autoload :Search
    autoload :Upload
  end

end
