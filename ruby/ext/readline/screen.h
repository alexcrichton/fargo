#ifndef _FARGO_READLINE_SCREEN_H
#define _FARGO_READLINE_SCREEN_H

#if defined(HAVE_READLINE_READLINE_H)
# include <readline/readline.h>
#elif defined(HAVE_READLINE_H)
# include <readline.h>
#endif

void clear_rl();
void restore_rl();

#endif /* _FARGO_READLINE_SCREEN_H */
