require 'rubygems'
require 'bundler/setup'

require 'rspec/core'
require 'fargo'

download_dir = File.expand_path '../tmp', __FILE__

Fargo.logger.level = ActiveSupport::BufferedLogger::FATAL

RSpec.configure do |c|
  c.before :each do
    Fargo.configure do |config|
      config.download_dir        = download_dir
      config.config_dir          = download_dir + '/config'
      config.nick                = 'fargo'
      config.override_share_size = nil
      config.upload_slots        = 4
    end
  end

  c.around :each do |example|
    FileUtils.mkdir_p download_dir
    begin
      example.run
    ensure
      FileUtils.rm_rf download_dir
    end
  end

  c.around :each, :type => :em_different_thread do |example|
    t = Thread.start{ EventMachine.run }
    begin
      example.run
    ensure
      t.kill
    end
  end

  c.around :each, :type => :em do |example|
    EventMachine.run_block{ example.run }
  end

  c.before :each, :type => :emsync do
    EM.stub(:reactor_thread?).and_return true
    EM.stub(:schedule).and_yield
    EM.stub(:next_tick).and_yield
    EM.stub(:defer) { |block1, block2|
      EM.stub(:reactor_thread?).and_return false
      result = block1.call
      block2.call result if block2
      EM.stub(:reactor_thread?).and_return true
    }
  end
end

Dir[File.dirname(__FILE__) + '/support/*.rb'].each { |f| load f }

def helper_object mod
  Object.new.tap{ |o| o.class_eval{ include mod } }
end
