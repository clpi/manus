// traverse.c — gated benchmark oracle: data-structure traversal.
// Gate: memory + pointers in the Idol subset.
// Semantics frozen: walk a 1M-node list (shuffled order), sum payloads,
// exit = sum & 255. Pointer-chasing: latency-bound, prefetcher-hostile.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#define N 1000000
struct node { struct node *next; uint64_t v; };
static struct node pool[N];
int main(void){
    for(size_t i=0;i<N;i++){pool[i].v=(uint64_t)(i*2654435761ULL);}
    // deterministic shuffle: link i -> (i*97+13) % N
    char *used = calloc(N,1);
    size_t cur = 0;
    for(size_t k=0;k<N;k++){
        size_t nxt = (cur*97+13)%N;
        while(used[nxt]){nxt=(nxt+1)%N;}
        pool[cur].next=&pool[nxt]; used[cur]=1; cur=nxt;
    }
    pool[cur].next=NULL; free(used);
    uint64_t s=0; struct node *p=&pool[0]; size_t c=0;
    while(p && c<N){s+=p->v;p=p->next;c++;}
    return (int)(s&255);
}
