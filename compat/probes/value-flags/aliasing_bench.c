// Per-iteration cost of the aliasing mechanisms, for `for (@a) { $sum += $_ }` over N ints.
// (a) packed i64 page, direct                         -- lower bound
// (b) 16-byte tagged words, direct
// (c) registry + ElemProxy: per iteration store (array,idx) into the registry entry, then
//     every $_ read resolves proxy -> array -> slot -> tag check
// (d) promote-on-bind (alternative): per iteration pop a 32-byte cell from a freelist, copy the
//     value in, insert (idx -> cell) into an open-addressing side table, read $_ through the cell;
//     at n/8 promotions convert the page to 8-byte tagged words (copy) and thereafter write the
//     cell pointer into the word array instead of the side table.  Cells are never freed (identity
//     is permanent).
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#define N 1000000
typedef struct { uint64_t payload; uint8_t aux[7]; uint8_t tag; } word;      // 16 bytes
typedef struct { uint32_t rc, flags; word v; void *meta; } cell;               // 32 bytes
typedef struct { uint32_t idx; cell *c; } entry;
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
static int64_t *page; static word *words; static cell *cells; static entry *table; static uint64_t *tagged;
int main(void){
  page = malloc(N*8); words = malloc(N*16); cells = aligned_alloc(64, N*32);
  size_t tcap = 1<<21; table = calloc(tcap, sizeof(entry)); tagged = malloc(N*8);
  for (int i=0;i<N;i++){ page[i]=i; words[i].payload=i; words[i].tag=1; }
  volatile int64_t sink; double t0,t1; int64_t sum;
  // (a)
  t0=now(); sum=0; for(int i=0;i<N;i++) sum+=page[i]; t1=now(); sink=sum; printf("(a) packed direct         %6.2f ns/iter\n",(t1-t0)/N*1e9);
  // (b)
  t0=now(); sum=0; for(int i=0;i<N;i++){ if(words[i].tag!=1) abort(); sum+=(int64_t)words[i].payload; } t1=now(); sink=sum; printf("(b) 16B words direct      %6.2f ns/iter\n",(t1-t0)/N*1e9);
  // (c) registry entry {container, idx}, proxy resolve per read (array ptr + len + slots ptr, then slot)
  struct { void *holder; word *arr; uint32_t len; uint32_t idx; } reg; volatile word *arrp = words; volatile uint32_t len = N;
  t0=now(); sum=0; for(int i=0;i<N;i++){ reg.arr=(word*)arrp; reg.idx=i; reg.len=len;             /* bind $_ */
     word *slot = &reg.arr[reg.idx]; if (reg.idx>=reg.len) abort(); if(slot->tag!=1) abort(); sum+=(int64_t)slot->payload; }
  t1=now(); sink=sum; printf("(c) registry+proxy        %6.2f ns/iter\n",(t1-t0)/N*1e9);
  // (d) promote-on-bind with side table, conversion at n/8
  cell *freelist = cells; for(int i=0;i<N-1;i++) *(cell**)&cells[i] = &cells[i+1]; *(cell**)&cells[N-1]=NULL;
  size_t promoted=0; int converted=0;
  t0=now(); sum=0;
  for(int i=0;i<N;i++){
     cell *c = freelist; freelist = *(cell**)c;                       /* alloc */
     c->rc=2; c->flags=0; c->v.payload=page[i]; c->v.tag=1; c->meta=NULL; /* init from packed */
     if(!converted){
        size_t h = (i*0x9E3779B97F4A7C15ull)>>43; while(table[h].c) h=(h+1)&(tcap-1);  /* side table insert */
        table[h].idx=i; table[h].c=c;
        if(++promoted > N/8){ converted=1; for(int j=0;j<N;j++) tagged[j]=(uint64_t)page[j]<<1|1;   /* widen to tagged words */
           for(size_t k=0;k<tcap;k++) if(table[k].c) tagged[table[k].idx]=(uint64_t)table[k].c; }
     } else tagged[i]=(uint64_t)c;                                   /* handle in-band */
     if(c->v.tag!=1) abort(); sum+=(int64_t)c->v.payload;            /* $_ read via the cell */
  }
  t1=now(); sink=sum; printf("(d) promote-on-bind       %6.2f ns/iter  (end state: %zu MB words+cells)\n",(t1-t0)/N*1e9,(size_t)(N*8+N*32)>>20);
  return 0;
}
