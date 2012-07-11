# This uses mkmf
require 'mkmf'

$defs.push("-DHAVE_TBR") if have_func('rb_thread_blocking_region')

create_makefile('tth')
