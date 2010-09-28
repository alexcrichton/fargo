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

  s.files         = `git ls-files lib ext`.split("\n")
  s.extensions    = ['ext/fargo/extconf.rb']
  s.require_paths = ['lib', 'ext']
  s.rdoc_options  = ['--charset=UTF-8']

  s.add_dependency 'eventmachine'
  s.add_dependency 'activesupport', '>= 3.0.0'
  s.add_dependency 'libxml-ruby'
  s.add_dependency 'bzip2-ruby'
end
