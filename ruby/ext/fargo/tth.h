#ifndef __TTH_H
#define __TTH_H

#include "tiger.h"

// user must call free() funtion on pointer returned from these functions

char* tth(const char* filename, char **tthl, size_t *tthl_len);

#endif // ifndef __TTH_H
