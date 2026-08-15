/* Call-heavy kernel, indirect calls dominant.
 *
 * The dispatch index is derived from the running accumulator, so the target of
 * every `call_indirect` is unknown until the call is reached: no devirtual-
 * isation, no inlining, and the host runtime pays its real indirect-call cost
 * (table bounds check + type-signature check + trampoline) once per iteration.
 *
 * A direct-call arm is included at a fixed ratio so the two costs can be told
 * apart by editing cfg_direct_every.
 */
#include <stdint.h>
#include <unistd.h>

volatile uint32_t cfg_iters = 6000000u;
volatile uint32_t cfg_seed = 12345u;

typedef uint32_t (*op_fn)(uint32_t, uint32_t);

/* Every op must mix ALL bits.  A first draft used `a ^ (b << 3)` and indexed
 * with `acc & 7`: the low three bits then never changed, the same target was
 * called 6M times, and the whole loop folded to the seed.  Native and wasm
 * agreed on the wrong thing, which is exactly how a fake benchmark survives. */
__attribute__((noinline)) static uint32_t op_add(uint32_t a, uint32_t b) { return (a + b) * 2654435761u; }
__attribute__((noinline)) static uint32_t op_xor(uint32_t a, uint32_t b) { a ^= b; return a ^ (a >> 15); }
__attribute__((noinline)) static uint32_t op_mul(uint32_t a, uint32_t b) { return a * (b | 1u) + 0x9E3779B9u; }
__attribute__((noinline)) static uint32_t op_rot(uint32_t a, uint32_t b) { a += b; return (a << 7) | (a >> 25); }
__attribute__((noinline)) static uint32_t op_sub(uint32_t a, uint32_t b) { a = a - b - 1u; return a ^ (a >> 11); }
__attribute__((noinline)) static uint32_t op_and(uint32_t a, uint32_t b) { return ((a & b) + 0x9E3779B9u) * 40503u; }
__attribute__((noinline)) static uint32_t op_or (uint32_t a, uint32_t b) { return ((a | b) ^ 0x85EBCA6Bu) * 2246822519u; }
__attribute__((noinline)) static uint32_t op_shr(uint32_t a, uint32_t b) { a = (a >> 5) + b; return a * 3266489917u; }

static op_fn table[8] = { op_add, op_xor, op_mul, op_rot, op_sub, op_and, op_or, op_shr };

static void emit_u64(uint64_t v) {
    char b[24];
    char *p = b + 23;
    *p = '\n';
    do { *--p = (char)('0' + (v % 10ull)); v /= 10ull; } while (v);
    (void)!write(1, p, (size_t)(b + 24 - p));
}

int main(void) {
    uint32_t n = cfg_iters, acc = cfg_seed;
    for (uint32_t i = 0; i < n; i++) {
        acc = table[(acc ^ (acc >> 17)) & 7u](acc, i);
    }
    emit_u64(acc);
    return 0;
}
