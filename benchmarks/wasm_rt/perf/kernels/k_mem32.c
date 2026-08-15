/* Memory-traffic kernel without malloc.
 *
 * Exists because k_mem.c traps on the Idol engine (wasi-libc malloc needs
 * `memory.grow`).  Same idea -- bulk fill, strided write, strided read,
 * checksum feedback -- over a static arena, so it measures store/load
 * throughput and bounds-check cost rather than the guest allocator.
 */
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define ARENA (1u << 20)          /* 1 MiB static */

static unsigned char arena[ARENA];

volatile uint32_t cfg_rounds = 400u;
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
        uint32_t n = base + (uint32_t)(sum % spread);
        if (n > ARENA) n = ARENA;
        memset(arena, (int)(r & 0xFF), n);
        for (uint32_t i = 0; i < n; i += 61) arena[i] = (unsigned char)(i + r);
        for (uint32_t i = 0; i < n; i += 251) sum += arena[i];
        sum = sum * 1099511628211ull + n;
    }
    emit_u64(sum);
    return 0;
}
