# -*- encoding: utf-8 -*-

$LOAD_PATH << File.expand_path('../lib', __FILE__)
require 'fargo/version'

Gem::Specification.new do |s|
  s.name     = 'fargo'
  s.version  = Fargo::VERSION
  s.platform = Gem::Platform::RUBY

  s.author      = 'Alex Crichton'
  s.email       = 'alex@alexcrichton.com'
  s.homepage    = 'http://github.com/alexcrichton/fargo'
  s.summary     = 'A client for the DC protocol'
  s.description = 'Direct Connect (DC) Client implemented in pure Ruby'

  s.files        = `git ls-files lib/*`.split("\n")
  s.require_path = 'lib'
  s.rdoc_options = ['--charset=UTF-8']

  s.add_runtime_dependency 'activesupport', '>= 3.0.0'
  s.add_runtime_dependency 'libxml-ruby'
  s.add_runtime_dependency 'bzip2-ruby'
end
