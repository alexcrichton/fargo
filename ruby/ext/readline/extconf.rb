require 'mkmf'

if RUBY_VERSION =~ /1\.9/
  $CFLAGS << ' -DRUBY_19'
end

$CFLAGS << ' -pedantic -Wall -Wextra -Wno-unused'

if have_header('readline/readline.h') || have_header('readline.h')
  create_makefile('extra_utils')
end
