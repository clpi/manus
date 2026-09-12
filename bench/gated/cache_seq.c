// cache_seq.c — gated benchmark oracle: cache-FRIENDLY walk.
// Pair with cache_stride.c (cache-HOSTILE). Gate: memory (array indexing).
// Semantics frozen: 8M x 8-byte elements (64MB), sum with stride 1,
// exit = sum & 255.
#include <stddef.h>
#include <stdint.h>
#define N 8388608
static uint64_t a[N];
int main(void){
    for(size_t i=0;i<N;i++){a[i]=(uint64_t)(i*6364136223846793005ULL+1442695040888963407ULL);}
    uint64_t s=0;
    for(size_t i=0;i<N;i++){s+=a[i];}
    return (int)(s&255);
}
