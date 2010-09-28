# This uses mkmf
require 'mkmf'

if RUBY_VERSION =~ /1.9/
  $CFLAGS << ' -DRUBY_19'
end

# Ensure we have the fuse lib.
create_makefile('tth')
