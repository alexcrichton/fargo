#include <ruby.h>
#include "screen.h"

VALUE rb_readline_clear_rl(VALUE self) {
  clear_rl();

  return Qtrue;
}

VALUE rb_readline_restore(VALUE self) {
  restore_rl();

  return Qtrue;
}

Init_clear_rl() {
  VALUE cReadline = rb_define_module("Readline");

  rb_define_singleton_method(cReadline, "clear_rl", rb_readline_clear_rl, 0);
  rb_define_singleton_method(cReadline, "restore", rb_readline_restore, 0);
}
