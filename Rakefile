require 'bundler'
Bundler.setup
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

if RUBY_VERSION < '1.9'
  desc "Run all examples using rcov"
  RSpec::Core::RakeTask.new :rcov => :cleanup_coverage_files do |t|
    t.rcov = true
    t.rcov_opts =  %[-Ilib -Ispec --exclude "gems/*,spec/support,spec/fargo,spec/spec_helper.rb,/Library/Ruby/*"]
  end
else
  desc 'Run all tests using cover_me'
  task :coverage => :cleanup_coverage_files do
    require 'simplecov'

    SimpleCov.start do
      add_filter '/spec/'

      require 'rspec/core'
      spec_dir = File.expand_path('../spec', __FILE__)
      RSpec::Core::Runner.disable_autorun!
      RSpec::Core::Runner.run [spec_dir], STDERR, STDOUT
    end

  end
end

task :cleanup_coverage_files do
  rm_rf 'coverage'
end

task :clobber => :cleanup_coverage_files do
  rm_rf 'pkg'
  rm_rf 'tmp'
end

desc "Build the C extensions"
task :build_extensions do
  ['fargo', 'readline'].each do |ext|
    if File.exists? "ext/#{ext}/Makefile"
      sh "cd ext/#{ext} && make distclean"
    end

    sh "cd ext/#{ext} && ruby extconf.rb && make"
  end
end
