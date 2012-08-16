/* ncdc - NCurses Direct Connect client

  Copyright (c) 2011-2012 Yoran Heling

  Permission is hereby granted, free of charge, to any person obtaining
  a copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be included
  in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

#include "tth.h"

#define TTH_BUFSIZE 4096
#define MAX_GRANULARITY (64 * 1024)

char *fargo_tth(int fd, uint64_t size, uint64_t *progress) {
  tth_ctx_t tth;
  char buf[TTH_BUFSIZE];
  char *real = NULL;

  // Initialize some stuff
  uint64_t blocksize = tth_blocksize(size, 1<<(8-1)); /* TODO: #define 10? */
  if (blocksize < MAX_GRANULARITY) {
    blocksize = MAX_GRANULARITY;
  }
  int blocks_num = tth_num_blocks(size, blocksize);
  char blocks[24 * blocks_num];
  tth_init(&tth);

  int r;
  uint64_t rd = 0;
  int block_cur = 0;
  uint64_t block_len = 0;

  while ((r = read(fd, buf, TTH_BUFSIZE)) > 0) {
    rd += r;
    if (progress) {
      (*progress) += r;
    }
    // file has been modified. time to back out
    if (rd > size) {
      return NULL;
    }
    // and hash
    char *b = buf;
    while (r > 0) {
      int w = MIN(r, blocksize-block_len);
      tth_update(&tth, b, w);
      block_len += w;
      b += w;
      r -= w;
      if (block_len >= blocksize) {
        tth_final(&tth, blocks+(block_cur*24));
        tth_init(&tth);
        block_cur++;
        block_len = 0;
      }
    }
  }
  if (r < 0) {
    return NULL;
  }
  if (rd != size) {
    return NULL;
  }
  // Calculate last block
  if (!size || block_len) {
    tth_final(&tth, blocks+(block_cur*24));
    block_cur++;
  }
  if (block_cur != blocks_num) {
    return NULL;
  }
  // Calculate root hash
  char *str = malloc(25);
  if (str == NULL) {
    return NULL;
  }
  tth_root(blocks, blocks_num, str);
  str[24] = 0;
  return str;
}
