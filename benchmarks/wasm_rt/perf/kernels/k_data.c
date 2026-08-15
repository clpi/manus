/* Hot loop over runtime-sized data.
 *
 * A buffer whose size is only known at run time is filled, then walked by a
 * dependent pointer chase (each load's address comes from the previous load's
 * value).  That is the shape that makes a WASM runtime's bounds-check strategy
 * visible: the address is not affine, so no check can be hoisted out of the
 * loop, and every access pays whatever the runtime charges for one.
 *
 * Anti-folding: element count, pass count and stride all come from `volatile`
 * globals; the chase is serial.
 */
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

volatile uint32_t cfg_elems = 1u << 21;   /* 2 Mi u32 = 8 MiB, exceeds L2 */
volatile uint32_t cfg_passes = 12u;
volatile uint32_t cfg_stride = 1103515245u;

static void emit_u64(uint64_t v) {
    char b[24];
    char *p = b + 23;
    *p = '\n';
    do { *--p = (char)('0' + (v % 10ull)); v /= 10ull; } while (v);
    (void)!write(1, p, (size_t)(b + 24 - p));
}

int main(void) {
    uint32_t n = cfg_elems, passes = cfg_passes, mul = cfg_stride;
    uint32_t *a = (uint32_t *)malloc((size_t)n * sizeof(uint32_t));
    if (!a) { emit_u64(0); return 1; }
    /* Build a permutation-ish chain: a[i] holds the next index to visit. */
    for (uint32_t i = 0; i < n; i++) a[i] = (uint32_t)(((uint64_t)i * mul + 12345u) % n);
    uint64_t sum = 0;
    uint32_t idx = 0;
    for (uint32_t p = 0; p < passes; p++) {
        for (uint32_t i = 0; i < n; i++) {
            idx = a[idx];          /* dependent load: address = previous value */
            sum += idx;
        }
    }
    free(a);
    emit_u64(sum);
    return 0;
}
