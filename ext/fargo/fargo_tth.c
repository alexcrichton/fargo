#include <ruby.h>
#include <string.h>
#include "tth.h"

#ifndef RUBY_19
# define RSTRING_LEN(s) (RSTRING(s)->len)
# define RSTRING_PTR(s) (RSTRING(s)->ptr)
# define RARRAY_LEN(s) (RARRAY(s)->len)
# define RARRAY_PTR(s) (RARRAY(s)->ptr)
#endif

VALUE rb_tth_file(VALUE self, VALUE filename) {
  char *file = RSTRING_PTR(filename);

  char* tthl = NULL;
  size_t tthl_size;
  char* hash = tth(file, &tthl, &tthl_size);
  if (tthl != NULL) {
    free(tthl);
  }

  if (hash != NULL) {
    return rb_str_new(hash, strlen(hash));
  } else {
    return Qnil;
  }
}

Init_tth() {
  VALUE cFargo = rb_define_module("Fargo");
  VALUE cTTH = rb_define_module_under(cFargo, "TTH");

  rb_define_method(cTTH, "file_tth", rb_tth_file, 1);
}