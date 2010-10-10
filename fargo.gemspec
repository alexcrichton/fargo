# -*- encoding: utf-8 -*-

require File.expand_path('../lib/fargo/version', __FILE__)

Gem::Specification.new do |s|
  s.name     = 'fargo'
  s.version  = Fargo::VERSION
  s.platform = Gem::Platform::RUBY

  s.author      = 'Alex Crichton'
  s.email       = 'alex@alexcrichton.com'
  s.homepage    = 'http://github.com/alexcrichton/fargo'
  s.summary     = 'A client for the DC protocol'
  s.description = 'Direct Connect (DC) Client implemented in pure Ruby'

  s.files         = `git ls-files lib ext bin`.split("\n") + ['README.md']
  s.test_files    = `git ls-files spec`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.extensions    = ['ext/fargo/extconf.rb', 'ext/readline/extconf.rb']
  s.require_paths = ['lib', 'ext']

  s.add_dependency 'eventmachine'
  s.add_dependency 'em-websocket'
  s.add_dependency 'em-http-request'
  s.add_dependency 'activesupport', '>= 3.0.0'
  s.add_dependency 'libxml-ruby'
  s.add_dependency 'bzip2-ruby'
  s.add_dependency 'hirb'
end
