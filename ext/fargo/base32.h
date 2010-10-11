#ifndef __BASE32_H
#define __BASE32_H

// user must call free() funtion on pointer returned from these functions

char* base32_encode(const unsigned char* in, int inlen);

#endif // ifndef __BASE32_H
