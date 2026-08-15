/* Memory / allocation-heavy kernel.
 *
 * Repeated malloc/free at runtime-chosen sizes, each block written and read
 * back.  This exercises the allocator inside the guest (wasi-libc's dlmalloc),
 * linear-memory growth, and -- for the host runtime -- whatever bounds-check
 * strategy it uses on every load and store.
 *
 * Anti-folding: sizes and round count come from `volatile` globals, and the
 * checksum feeds back into the next size, so no round can be eliminated.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

volatile uint32_t cfg_rounds = 1200u;
volatile uint32_t cfg_base = 48u * 1024u;
volatile uint32_t cfg_spread = 16u * 1024u;

static void emit_u64(uint64_t v) {
    char b[24];
    char *p = b + 23;
    *p = '\n';
    do { *--p = (char)('0' + (v % 10ull)); v /= 10ull; } while (v);
    (void)!write(1, p, (size_t)(b + 24 - p));
}

int main(void) {
    uint32_t rounds = cfg_rounds, base = cfg_base, spread = cfg_spread;
    uint64_t sum = 1;
    for (uint32_t r = 0; r < rounds; r++) {
        size_t n = (size_t)(base + (uint32_t)(sum % spread));
        unsigned char *p = (unsigned char *)malloc(n);
        if (!p) { emit_u64(0); return 1; }
        memset(p, (int)(r & 0xFF), n);
        /* touch with a stride that crosses pages so the write is not elided */
        for (size_t i = 0; i < n; i += 61) p[i] = (unsigned char)(i + r);
        for (size_t i = 0; i < n; i += 251) sum += p[i];
        sum = sum * 1099511628211ull + n;
        free(p);
    }
    emit_u64(sum);
    return 0;
}
