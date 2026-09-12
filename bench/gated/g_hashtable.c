// g_hashtable.c — gated benchmark oracle: hash table.
// Gate: arrays, pointers, and modular indexing in the Idol subset.
// Semantics frozen: insert 200k keys into an open-addressing table
// (FNV-1a, linear probing), then look up 200k keys, exit = hits & 255.
// Branchy, data-dependent, cache-unfriendly; idol cannot express this
// until arrays and pointers land.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define CAP 524288
#define NKEYS 200000
static uint64_t keys[CAP];
static uint64_t vals[CAP];
static unsigned char occ[CAP];
static uint64_t hash64(uint64_t x){
    x ^= x >> 30; x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27; x *= 0x94d049bb133111ebULL;
    x ^= x >> 31; return x;
}
int main(void){
    uint64_t hits = 0;
    for(uint64_t i=0;i<NKEYS;i++){
        uint64_t k = i * 2654435761ULL + 1;
        uint64_t h = hash64(k) & (CAP - 1);
        while(occ[h]){ if(keys[h]==k) break; h = (h + 1) & (CAP - 1); }
        if(!occ[h]){ occ[h]=1; keys[h]=k; vals[h]=k*3+7; }
    }
    for(uint64_t i=0;i<NKEYS;i++){
        uint64_t k = i * 2654435761ULL + 1;
        uint64_t h = hash64(k) & (CAP - 1);
        while(occ[h]){ if(keys[h]==k){ hits += vals[h]; break; } h = (h + 1) & (CAP - 1); }
    }
    return (int)(hits & 255);
}
