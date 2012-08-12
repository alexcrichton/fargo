#ifndef _TTH_H
#define _TTH_H

#include <stdint.h>
#include <stdlib.h>

#define tth_num_blocks(fs, bs) MAX(((fs)+(bs)-1)/(bs), 1)
#define tiger_block_size 64

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

typedef struct tiger_ctx {
  uint64_t hash[3]; /* algorithm 192-bit state */
  char message[tiger_block_size]; /* 512-bit buffer for leftovers */
  uint64_t length;  /* processed message length */
} tiger_ctx_t;

typedef struct tth_ctx {
  tiger_ctx_t tiger;
  int leafnum; // There can be 2^29 leafs. Fits in an integer.
  int gotfirst;
  // Stack used to calculate the hash.
  //  Max. size = 2^29 * 1024 = 512 GiB
  // When the stack starts with a leaf node, the position in the stack
  // determines the data size the hash represents:
  //   size = tth_base_block << pos
  // (pos being the index from 0)
  char stack[29][24];
} tth_ctx_t;

uint64_t tth_blocksize(uint64_t fs,int blocks);
void tth_root(char *blocks,int num,char *result);
void tth_final(tth_ctx_t *ctx,char *result);
void tth_update(tth_ctx_t *ctx,const char *msg,size_t len);
void tth_update_leaf(tth_ctx_t *ctx,const char *leaf);
void tth_init(tth_ctx_t *ctx);

#endif /* _TTH_H */
