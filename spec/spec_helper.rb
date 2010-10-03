require 'rubygems'
require 'bundler/setup'

require 'rspec/core'
require 'fargo'

download_dir = File.expand_path '../tmp', __FILE__

Fargo.configure do |config|
  config.download_dir = download_dir
  config.config_dir   = download_dir + '/config'
end

Fargo.logger.level = ActiveSupport::BufferedLogger::INFO

RSpec.configure do |c|
  c.color_enabled = true

  c.around :each do |example|
    FileUtils.mkdir_p download_dir
    example.run
    FileUtils.rm_rf download_dir
  end

  c.around :each, :type => :em do |example|
    EventMachine.run {
      example.run

      EventMachine.stop_event_loop
    }
  end
end

Dir[File.dirname(__FILE__) + '/support/*.rb'].each { |f| load f }

def helper_object mod
  o = Object.new
  o.send(:class_eval) do
    include mod
  end
  o
end
