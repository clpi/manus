// ward head-to-head WASM runtime benchmark.
// Checksums are emitted via raw write(2) + a hand-rolled decimal conversion
// rather than printf: ward's printf integer path is currently broken, and a
// benchmark whose result cannot be verified is worthless. Every runtime must
// produce byte-identical stdout.
#include <unistd.h>
#include <stdint.h>

#ifndef SCALE
#define SCALE 1
#endif

static void emit(uint32_t v) {
    char buf[16];
    char *p = buf + 15;
    *p = '\n';
    uint32_t x = v;
    do { *--p = (char)('0' + (x % 10u)); x /= 10u; } while (x);
    (void)!write(1, p, (size_t)(buf + 16 - p));
}

#if defined(BENCH_LOOP_I32)
static uint32_t run(uint32_t seed) {
    uint32_t sum = seed, prod = 1u + seed;
    for (uint32_t i = 0; i < 200u * SCALE; i++)
        for (uint32_t j = 0; j < 200u; j++) {
            uint32_t t = i * j + sum;
            sum += t;
            prod = (prod * 3u + 1u) & 0x7FFFFFFFu;
        }
    return sum ^ prod;
}
#elif defined(BENCH_LOOP_F64)
static uint32_t run(uint32_t seed) {
    double acc = (double)seed;
    for (uint32_t i = 1; i <= 40000u * SCALE; i++) {
        double x = (double)i;
        acc += (x * 1.0000001) / (x + 1.5) - acc * 1e-9;
    }
    return (uint32_t)(int32_t)(acc * 1000.0);
}
#elif defined(BENCH_MEMORY)
static uint32_t buf_[1 << 16];
static uint32_t run(uint32_t seed) {
    uint32_t n = 1 << 16, h = 2166136261u ^ seed;
    for (uint32_t i = 0; i < n; i++) buf_[i] = i * 2654435761u;
    for (uint32_t pass = 0; pass < 4u * SCALE; pass++)
        for (uint32_t i = 0; i < n; i++) {
            uint32_t v = buf_[(i * 7919u) & (n - 1u)];
            h ^= v; h *= 16777619u;
            buf_[i] = h;
        }
    return h;
}
#elif defined(BENCH_CALLS)
static uint32_t leaf(uint32_t a, uint32_t b) { return a * 31u + b; }
static uint32_t mid(uint32_t a, uint32_t b) { return leaf(a, b) ^ leaf(b, a); }
static uint32_t run(uint32_t seed) {
    uint32_t h = seed;
    for (uint32_t i = 0; i < 200000u * SCALE; i++) h = mid(h, i);
    return h;
}
#elif defined(BENCH_FIB)
static uint32_t fib(uint32_t n) { return n < 2u ? n : fib(n - 1u) + fib(n - 2u); }
static uint32_t run(uint32_t seed) { return fib(24u + (seed & 1u)); }
#elif defined(BENCH_BRTABLE)
static uint32_t run(uint32_t seed) {
    uint32_t h = 12345u ^ seed, acc = 0;
    for (uint32_t i = 0; i < 300000u * SCALE; i++) {
        h = h * 1103515245u + 12345u;
        switch ((h >> 16) & 7u) {
            case 0: acc += 3u; break;
            case 1: acc ^= h; break;
            case 2: acc -= 7u; break;
            case 3: acc += h >> 3; break;
            case 4: acc ^= 0x5A5A5A5Au; break;
            case 5: acc += acc >> 5; break;
            case 6: acc *= 3u; break;
            default: acc ^= acc << 7; break;
        }
    }
    return acc;
}
#else
#error "define one BENCH_* workload"
#endif

// A volatile load the compiler must actually perform: this defeats constant
// folding of the whole workload without dragging in WASI args (whose argv
// write-out is currently broken in ward). Value is 0, so output stays
// deterministic and comparable across runtimes.
static volatile uint32_t seed_src = 0u;
int main(void) { emit(run(seed_src)); return 0; }
