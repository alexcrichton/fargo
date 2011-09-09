#include <ruby.h>
#include <string.h>
#include "tth.h"

#ifndef RSTRING_PTR
#  define RSTRING_PTR(s) (RSTRING(s)->ptr)
#endif

typedef struct {
  char *filename;
  char *tthl;
  size_t tthl_size;
} TTHArguments;

static VALUE tth_wrapper(void *_args) {
  TTHArguments *args = _args;
  return (VALUE) tth(args->filename, &args->tthl, &args->tthl_size);
}

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

  TTHArguments args;
  args.tthl = NULL;
  args.filename = RSTRING_PTR(filename);
  args.tthl_size = 0;

  #ifdef HAVE_TBR
  char* hash = (char*) rb_thread_blocking_region(tth_wrapper, &args, RUBY_UBF_IO, NULL);
  #else
  char* hash = tth_wrapper(&args)
  #endif
  if (args.tthl != NULL) {
    free(args.tthl);
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
