/* Integer-heavy kernel: a serial mixing chain.
 *
 * Anti-folding: the trip count and the seed both come from `volatile` globals,
 * so neither LLVM (producing the wasm) nor a consuming JIT can close-form the
 * loop or hoist it.  The chain is serial -- each step depends on the previous
 * -- so it cannot be vectorised into something that measures SIMD width
 * instead of scalar integer throughput.
 *
 * docs note: benchmarks/wasm_rt/hot.c gets unrolled 248x and strength-reduced
 * by LLVM because its recurrence is affine; `acc = acc*31 + i` has a closed
 * form.  xorshift + multiply does not.
 */
#include <stdint.h>
#include <unistd.h>

volatile uint32_t cfg_iters = 40000000u;
volatile uint64_t cfg_seed = 0x9E3779B97F4A7C15ull;

__attribute__((noinline))
static uint64_t mix(uint64_t x, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x *= 0xD1342543DE82EF95ull;
        x += 0x2545F4914F6CDD1Dull;
    }
    return x;
}

static void emit_u64(uint64_t v) {
    char b[24];
    char *p = b + 23;
    *p = '\n';
    do { *--p = (char)('0' + (v % 10ull)); v /= 10ull; } while (v);
    (void)!write(1, p, (size_t)(b + 24 - p));
}

int main(void) {
    emit_u64(mix(cfg_seed, cfg_iters));
    return 0;
}
