require 'rubygems'
require 'bundler/setup'

require 'rspec/core'
require 'fargo'

download_dir = File.dirname(__FILE__) + '/../tmp'

Fargo::Client.configure do |config|
  config.download_dir = download_dir
end

Fargo.logger.level = ActiveSupport::BufferedLogger::INFO

RSpec.configure do |c|
  c.color_enabled = true

  c.after(:each) do
    FileUtils.rm_rf download_dir
  end

  c.around :each, :type => :em do |example|
    EventMachine.run {
      example.run

      EventMachine.stop_event_loop
    }
  end
end
