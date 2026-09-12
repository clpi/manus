// g_ptrchase.c — gated benchmark oracle: pointer chasing.
// Gate: heap allocation, pointers, struct field access in the Idol subset.
// Semantics frozen: walk a 4M-node shuffled linked list, sum payloads,
// exit = sum & 255. Latency-bound, prefetcher-hostile; idol cannot
// express this until pointers land.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#define N 4000000
struct node { struct node *next; uint64_t v; };
static struct node *pool;
int main(void){
    pool = malloc(N * sizeof *pool);
    if(!pool) return 1;
    for(size_t i=0;i<N;i++) pool[i].v = (uint64_t)(i * 2654435761ULL);
    unsigned char *used = calloc(N, 1);
    size_t cur = 0;
    for(size_t k=0;k<N;k++){
        size_t nxt = (cur * 97 + 13) % N;
        while(used[nxt]) nxt = (nxt + 1) % N;
        pool[cur].next = &pool[nxt]; used[cur] = 1; cur = nxt;
    }
    pool[cur].next = NULL; free(used);
    uint64_t s = 0; struct node *p = &pool[0]; size_t c = 0;
    while(p && c < N){ s += p->v; p = p->next; c++; }
    free(pool);
    return (int)(s & 255);
}
