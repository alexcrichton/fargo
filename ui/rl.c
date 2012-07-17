#include <sys/select.h>
#include <unistd.h>

#include "_cgo_export.h"

/* can't figure out how to pass function pointers in go */
char*(*fargo_completion_entry)(char*, int) = completeEach;

static int disable_filename_completion(char **arr) {
  for (; *arr != NULL; arr++) {
    free(*arr);
    *arr = NULL;
  }
  return 1;
}

void fargo_install_rl() {
  /* let go handle signals, not readline */
  rl_catch_signals  = 0;
  rl_catch_sigwinch = 0;

  /* install readline handler, don't let readline block */
  rl_readline_name  = "Fargo";
  rl_callback_handler_install("> ", receiveLine);

  /* completion */
  rl_attempted_completion_function = (CPPFunction*) rawComplete;
  rl_ignore_some_completions_function = disable_filename_completion;
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

/* screen.c - User interface management (Readline)
 *
 * Copyright (C) 2004, 2005 Oskar Liljeblad
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */
void fargo_clear_rl() {
    int old_end = rl_end;
    char *old_prompt = rl_display_prompt;

    rl_end = 0;
    rl_display_prompt = (char*) "";
    rl_expand_prompt(rl_display_prompt);
    rl_redisplay();

    rl_end = old_end;
    rl_display_prompt = old_prompt;
    if (rl_display_prompt == rl_prompt)
        rl_expand_prompt(rl_prompt);
}
