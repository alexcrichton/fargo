require 'socket'
require 'thread'
require 'logger'
require 'fileutils'
require 'zlib'

require File.dirname(__FILE__) + '/fargo/utils'
require File.dirname(__FILE__) + '/fargo/utils/publisher'
require File.dirname(__FILE__) + '/fargo/parser'
require File.dirname(__FILE__) + '/fargo/search'
require File.dirname(__FILE__) + '/fargo/search/result'

require File.dirname(__FILE__) + '/fargo/supports/chat'
require File.dirname(__FILE__) + '/fargo/supports/searches'
require File.dirname(__FILE__) + '/fargo/supports/nick_list'
require File.dirname(__FILE__) + '/fargo/supports/uploads'
require File.dirname(__FILE__) + '/fargo/supports/downloads'
require File.dirname(__FILE__) + '/fargo/supports/persistence'

require File.dirname(__FILE__) + '/fargo/connection/base'
require File.dirname(__FILE__) + '/fargo/connection/download'
require File.dirname(__FILE__) + '/fargo/connection/hub'
require File.dirname(__FILE__) + '/fargo/connection/search'
require File.dirname(__FILE__) + '/fargo/connection/upload'

require File.dirname(__FILE__) + '/fargo/server'
require File.dirname(__FILE__) + '/fargo/client'

Thread.abort_on_exception = true

module Fargo
  class ConnectionException < RuntimeError; end
  
  @@logger = Logger.new STDOUT
  
  def self.logger
    @@logger
  end
  
  def self.logger= logger
    @@logger = logger
  end
  
end