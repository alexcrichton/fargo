require 'rubygems'
require 'bundler/setup'

require 'rspec/core'
require 'fargo'

download_dir = File.dirname(__FILE__) + '/../tmp'

Fargo::Client.configure do |config|
  config.download_dir = download_dir
end

RSpec.configure do |c|
  c.color_enabled = true

  c.after(:each) do
    FileUtils.rm_rf download_dir
  end
end
