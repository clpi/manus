#include <unistd.h>
#include <stdint.h>
static volatile uint32_t seed_src = 0u;
// Hot kernel: only locals + i32 arithmetic/compare + a loop, so the tier-1
// JIT's opcode set covers it. noinline keeps it a separate wasm function.
__attribute__((noinline))
static uint32_t kernel(uint32_t n, uint32_t seed) {
    uint32_t acc = 1u + seed, i = 0u;
    while (i < n) { acc = acc * 31u + i; i = i + 1u; }
    return acc;
}
static void emit(uint32_t v) {
    char b[16]; char *p = b + 15; *p='\n'; uint32_t x=v;
    do { *--p = (char)('0' + (x % 10u)); x /= 10u; } while (x);
    (void)!write(1, p, (size_t)(b + 16 - p));
}
int main(void) { emit(kernel(60000000u, seed_src)); return 0; }
