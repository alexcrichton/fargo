#include <ruby.h>
#include <string.h>
#include "tth.h"

#ifndef RSTRING_PTR
#  define RSTRING_PTR(s) (RSTRING(s)->ptr)
#endif

/*
 * Calculates the TTH value for the specified file.
 *
 * @param [String] filename the file
 * @return [String] the tth value for the specified file, or +nil+ if the file
 *    didn't exist or couldn't be read
 */
VALUE rb_tth_file(VALUE self, VALUE filename) {
  if (TYPE(filename) != T_STRING) {
    rb_raise(rb_eArgError, "argument must be a string");
  }
  char *file = RSTRING_PTR(filename);

  char* tthl = NULL;
  size_t tthl_size;
  char* hash = tth(file, &tthl, &tthl_size);
  if (tthl != NULL) {
    free(tthl);
  }

  VALUE ret = Qnil;
  if (hash != NULL) {
    ret = rb_str_new(hash, strlen(hash));
    free(hash);
  }
  return ret;
}

void Init_tth() {
  VALUE cFargo = rb_define_module("Fargo");
  VALUE cTTH = rb_define_module_under(cFargo, "TTH");

  rb_define_method(cTTH, "file_tth", rb_tth_file, 1);
}
