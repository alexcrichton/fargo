#include <ruby.h>
#include "screen.h"

/*
 * Clears the current readline prompt. All input text will disappear from the
 * terminal. Invoke the {restore} method to bring this information back.
 *
 * @return [Boolean] true
 */
VALUE rb_readline_clear_rl(VALUE self) {
  clear_rl();

  return Qtrue;
}

/*
 * Restores the readline prompt since the last call to {clear_rl}. The line
 * will be restored at the bottom of the terminal and normal readline
 * functionality will be restored.
 *
 * @return [Boolean] true
 */
VALUE rb_readline_restore(VALUE self) {
  restore_rl();

  return Qtrue;
}

/*
 * Read the current value on the readline prompt, without causing anything to
 * happen at the readline prompt. This is useful with completion options, for
 * example.
 *
 * @return [String] the current typed string at the readline prompt
 */
VALUE rb_readline_input(VALUE self) {
  const char *empty = "";
  struct readline_state state;
  if (rl_save_state(&state) == 0 && state.buffer != NULL) {
    return rb_str_new(state.buffer, strlen(state.buffer));
  }
  return rb_str_new(empty, 0);
}

void Init_extra_utils() {
  VALUE cReadline = rb_define_module("Readline");

  rb_define_singleton_method(cReadline, "clear_rl", rb_readline_clear_rl, 0);
  rb_define_singleton_method(cReadline, "restore", rb_readline_restore, 0);
  rb_define_singleton_method(cReadline, "get_input", rb_readline_input, 0);
}
