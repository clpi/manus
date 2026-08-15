/* Hot loop over runtime-sized data, without malloc.
 *
 * Exists because k_data.c traps on the Idol engine: wasi-libc's malloc calls
 * `memory.grow`, which the engine does not satisfy, and the allocation-failure
 * path aborts.  Here the buffer is a static array (so it lives in the module's
 * declared linear memory and needs no growth) and only the *portion used* is
 * runtime-chosen, which is what keeps the loop from being folded.
 *
 * The walk is a dependent chase -- each load's address is the previous load's
 * value -- so no bounds check can be hoisted out of the loop.  That is the
 * property that makes a runtime's bounds-check strategy visible.
 */
#include <stdint.h>
#include <unistd.h>

#define CAP (1u << 19)            /* 512 Ki u32 = 2 MiB, static */

static uint32_t a[CAP];

volatile uint32_t cfg_elems = CAP;
volatile uint32_t cfg_passes = 24u;
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
    if (n > CAP) n = CAP;
    for (uint32_t i = 0; i < n; i++)
        a[i] = (uint32_t)(((uint64_t)i * mul + 12345u) % n);
    uint64_t sum = 0;
    uint32_t idx = 0;
    for (uint32_t p = 0; p < passes; p++) {
        for (uint32_t i = 0; i < n; i++) {
            idx = a[idx];
            sum += idx;
        }
    }
    emit_u64(sum);
    return 0;
}
