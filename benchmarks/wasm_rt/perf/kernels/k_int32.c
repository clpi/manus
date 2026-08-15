/* Integer-heavy kernel, 32-bit only.
 *
 * Exists because k_int.c (64-bit xorshift) does not execute on the Idol
 * engine: it refuses at `i32.store8`, body offset 185, after the i64 chain.
 * This variant keeps the same serial-dependency shape in i32 so the two
 * runtimes can actually be compared on integer throughput.
 *
 * Anti-folding: trip count and seed are `volatile`; xorshift32 has no closed
 * form, so LLVM cannot strength-reduce it the way it collapses the affine
 * recurrence in benchmarks/wasm_rt/hot.c.
 */
#include <stdint.h>
#include <unistd.h>

volatile uint32_t cfg_iters = 40000000u;
volatile uint32_t cfg_seed = 0x9E3779B9u;

__attribute__((noinline))
static uint32_t mix32(uint32_t x, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        x *= 2654435761u;
        x += 0x85EBCA6Bu;
    }
    return x;
}

static void emit_u32(uint32_t v) {
    char b[16];
    char *p = b + 15;
    *p = '\n';
    do { *--p = (char)('0' + (v % 10u)); v /= 10u; } while (v);
    (void)!write(1, p, (size_t)(b + 16 - p));
}

int main(void) {
    emit_u32(mix32(cfg_seed, cfg_iters));
    return 0;
}
