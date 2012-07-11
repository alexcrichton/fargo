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
/* This piece of code was snatched from lftp, and modified somewhat by me.
 * I suggest a function called rl_clear() be added to readline. The
 * function clears the prompt and everything the user has written so far on
 * the line. The cursor is positioned at the beginning of the line that
 * contained the prompt. Note: This function doesn't modify the screen_state
 * variable.
 */

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

#include "screen.h"

void clear_rl() {

    extern char *rl_display_prompt;
#if HAVE__RL_MARK_MODIFIED_LINES
    extern int _rl_mark_modified_lines;
    int old_mark = _rl_mark_modified_lines;
#endif
    int old_end = rl_end;
    char *old_prompt = rl_display_prompt;

    rl_end = 0;
    rl_display_prompt = (char*) "";
    rl_expand_prompt(rl_display_prompt);
#if HAVE__RL_MARK_MODIFIED_LINES
    _rl_mark_modified_lines = 0;
#endif

    rl_redisplay();

    rl_end = old_end;
    rl_display_prompt = old_prompt;
#if HAVE__RL_MARK_MODIFIED_LINES
    _rl_mark_modified_lines = old_mark;
#endif
    if (rl_display_prompt == rl_prompt)
        rl_expand_prompt(rl_prompt);
}

void restore_rl() {
  rl_forced_update_display();
}
