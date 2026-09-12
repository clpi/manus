// strops.c — gated benchmark oracle: string ops (strlen + strcpy idiom).
// Gate: byte-addressable memory (load/store) in the Idol subset.
// Semantics frozen: fill 1MB, strlen it, copy it, exit = checksum & 255.
#include <string.h>
#define N 1048576
static char src[N], dst[N];
int main(void){
    for(size_t i=0;i<N-1;i++){src[i]=(char)('a'+(i%26));}
    src[N-1]='\0';
    size_t n=strlen(src);
    for(size_t i=0;i<=n;i++){dst[i]=src[i];}
    unsigned long long c=0;
    for(size_t i=0;i<n;i++){c+= (unsigned char)dst[i];}
    return (int)(c&255);
}
