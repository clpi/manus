// g_callchain.c — gated benchmark oracle: deep call chains.
// Gate: function definitions and calls in the Idol subset.
// Semantics frozen: 12-deep chain of tiny functions, each doing one
// multiply-add, called 20M times from a loop; exit = result & 255.
// Inlining and inter-procedural optimization bait; idol cannot express
// this until calls land.
#include <stdint.h>
static uint64_t f12(uint64_t x){ return x * 3 + 1; }
static uint64_t f11(uint64_t x){ return f12(x * 5 + 2); }
static uint64_t f10(uint64_t x){ return f11(x * 7 + 3); }
static uint64_t f9(uint64_t x){ return f10(x * 11 + 4); }
static uint64_t f8(uint64_t x){ return f9(x * 13 + 5); }
static uint64_t f7(uint64_t x){ return f8(x * 17 + 6); }
static uint64_t f6(uint64_t x){ return f7(x * 19 + 7); }
static uint64_t f5(uint64_t x){ return f6(x * 23 + 8); }
static uint64_t f4(uint64_t x){ return f5(x * 29 + 9); }
static uint64_t f3(uint64_t x){ return f4(x * 31 + 10); }
static uint64_t f2(uint64_t x){ return f3(x * 37 + 11); }
static uint64_t f1(uint64_t x){ return f2(x * 41 + 12); }
int main(void){
    uint64_t t = 0;
    for(uint64_t i=0;i<20000000ULL;i++) t += f1(i);
    return (int)(t & 255);
}
