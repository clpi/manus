// g_megamorph.c — gated benchmark oracle: megamorphic dispatch.
// Gate: function definitions, indirect calls through a table, and
// arrays in the Idol subset.
// Semantics frozen: 16-entry table of tiny arithmetic kernels called
// through a data-dependent index 10M times; exit = accumulator & 255.
// Indirect-branch predictor bait; idol cannot express this until
// indirect calls land.
#include <stdint.h>
typedef uint64_t (*kern)(uint64_t);
static uint64_t k0(uint64_t x){ return x + 1; }
static uint64_t k1(uint64_t x){ return x * 3; }
static uint64_t k2(uint64_t x){ return x ^ 0x9e3779b97f4a7c15ULL; }
static uint64_t k3(uint64_t x){ return x - 7; }
static uint64_t k4(uint64_t x){ return x * x; }
static uint64_t k5(uint64_t x){ return x + 0x12345; }
static uint64_t k6(uint64_t x){ return (x << 13) | (x >> 51); }
static uint64_t k7(uint64_t x){ return x * 5 + 1; }
static uint64_t k8(uint64_t x){ return x ^ (x >> 29); }
static uint64_t k9(uint64_t x){ return x + x / 3; }
static uint64_t k10(uint64_t x){ return x * 11 - 3; }
static uint64_t k11(uint64_t x){ return (x << 7) ^ x; }
static uint64_t k12(uint64_t x){ return x + 999983; }
static uint64_t k13(uint64_t x){ return x * 13 + 17; }
static uint64_t k14(uint64_t x){ return x ^ 0xdeadbeef; }
static uint64_t k15(uint64_t x){ return x - x / 7; }
static kern tab[16] = {k0,k1,k2,k3,k4,k5,k6,k7,k8,k9,k10,k11,k12,k13,k14,k15};
int main(void){
    uint64_t x = 12345, t = 0, s = 987654321;
    for(uint64_t i=0;i<10000000ULL;i++){
        s = s * 1103515245ULL + 12345ULL;
        x = tab[(s >> 33) & 15](x);
        t += x;
    }
    return (int)(t & 255);
}
