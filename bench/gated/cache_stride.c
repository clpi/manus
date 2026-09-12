// cache_stride.c — gated benchmark oracle: cache-HOSTILE walk.
// Pair with cache_seq.c (cache-FRIENDLY). Gate: memory (array indexing).
// Semantics frozen: same 64MB array, same elements summed exactly once,
// but visited with stride 64 (one 8-byte element per 512-byte step, i.e.
// one useful element per 8 cache lines), exit = sum & 255.
#include <stddef.h>
#include <stdint.h>
#define N 8388608
#define STRIDE 64
static uint64_t a[N];
int main(void){
    for(size_t i=0;i<N;i++){a[i]=(uint64_t)(i*6364136223846793005ULL+1442695040888963407ULL);}
    uint64_t s=0;
    for(size_t j=0;j<STRIDE;j++){
        for(size_t i=j;i<N;i+=STRIDE){s+=a[i];}
    }
    return (int)(s&255);
}
