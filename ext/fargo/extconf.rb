# This uses mkmf
require 'mkmf'

if RUBY_VERSION =~ /1\.9/
  $CFLAGS << ' -DRUBY_19'
end

create_makefile('tth')
