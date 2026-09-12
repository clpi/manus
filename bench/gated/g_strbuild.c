// g_strbuild.c — gated benchmark oracle: string building.
// Gate: byte-addressable memory, byte stores, and a strlen-like scan
// in the Idol subset.
// Semantics frozen: append 1M formatted integers into a 16MB byte
// buffer (hand-rolled itoa), then scan it back summing bytes,
// exit = sum & 255. Store-heavy with data-dependent lengths; idol
// cannot express this until byte memory lands.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define NAPPEND 1000000
static char buf[16*1024*1024];
int main(void){
    char *p = buf;
    for(int i=0;i<NAPPEND;i++){
        int v = (i * 1103515245 + 12345) & 0x7fffffff;
        char tmp[12]; int n = 0;
        if(v==0) tmp[n++]='0';
        while(v>0){ tmp[n++] = (char)('0' + v % 10); v /= 10; }
        while(n>0) *p++ = tmp[--n];
        *p++ = ',';
    }
    uint64_t s = 0;
    for(char *q = buf; q < p; q++) s += (unsigned char)*q;
    return (int)(s & 255);
}
