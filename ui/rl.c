#include <sys/select.h>
#include <unistd.h>

#include "_cgo_export.h"

void fargo_install_rl() {
  rl_catch_signals  = 0;
  rl_catch_sigwinch = 0;
  rl_readline_name  = "Fargo";
  rl_callback_handler_install("> ", receiveLine);
}

int fargo_select_stdin() {
  fd_set set;
  FD_ZERO(&set);
  FD_SET(STDIN_FILENO, &set);

  struct timeval tv;
  tv.tv_sec = 0;
  tv.tv_usec = 100000;

  return select(STDIN_FILENO + 1, &set, NULL, NULL, &tv);
}
