# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{fargo}
  s.version = "0.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Alex Crichton"]
  s.date = %q{2010-09-04}
  s.description = %q{DC Client}
  s.email = ["alex@alexcrichton.com"]
  s.files = [
    "VERSION",
     "lib/fargo.rb",
     "lib/fargo/client.rb",
     "lib/fargo/connection/base.rb",
     "lib/fargo/connection/download.rb",
     "lib/fargo/connection/hub.rb",
     "lib/fargo/connection/search.rb",
     "lib/fargo/connection/upload.rb",
     "lib/fargo/parser.rb",
     "lib/fargo/publisher.rb",
     "lib/fargo/search.rb",
     "lib/fargo/search_result.rb",
     "lib/fargo/server.rb",
     "lib/fargo/supports/chat.rb",
     "lib/fargo/supports/downloads.rb",
     "lib/fargo/supports/file_list.rb",
     "lib/fargo/supports/nick_list.rb",
     "lib/fargo/supports/persistence.rb",
     "lib/fargo/supports/searches.rb",
     "lib/fargo/supports/timeout.rb",
     "lib/fargo/supports/uploads.rb",
     "lib/fargo/utils.rb",
     "lib/fargo/version.rb"
  ]
  s.homepage = %q{http://github.com/alexcrichton/fargo}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{A client for the DC protocol}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<activesupport>, [">= 3.0.0"])
      s.add_runtime_dependency(%q<libxml-ruby>, [">= 0"])
      s.add_runtime_dependency(%q<bzip2-ruby>, [">= 0"])
    else
      s.add_dependency(%q<activesupport>, [">= 3.0.0"])
      s.add_dependency(%q<libxml-ruby>, [">= 0"])
      s.add_dependency(%q<bzip2-ruby>, [">= 0"])
    end
  else
    s.add_dependency(%q<activesupport>, [">= 3.0.0"])
    s.add_dependency(%q<libxml-ruby>, [">= 0"])
    s.add_dependency(%q<bzip2-ruby>, [">= 0"])
  end
end

