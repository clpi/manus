#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

static int64_t sieve_new(int64_t limit) {
    if (limit < 2) return 0;
    int64_t __prime_odd_len = ((limit) >> 1) + 1;
    uint8_t* restrict __prime_alloc = (uint8_t*)malloc((size_t)__prime_odd_len);
    if (!__prime_alloc) return 0;
    uint8_t* restrict __prime = (uint8_t*)__builtin_assume_aligned(__prime_alloc, 16);
    memset(__prime, 1, (size_t)__prime_odd_len);
    __prime[0] = 0;
    for (int64_t __n = 3; __n <= limit / __n; __n += 2) {
        if (!__prime[__n >> 1]) continue;
        uint8_t* restrict p = __prime + ((__n * __n) >> 1);
        uint8_t* restrict end = __prime + (limit >> 1);
        int64_t stride = __n;
        for (; p <= end; p += stride) *p = 0;
    }
    int64_t __count = 1;
    int64_t __prime_count_idx = 0;
    int64_t __prime_count_end = ((limit - 1) >> 1) + 1;
    for (; __prime_count_idx + 8 <= __prime_count_end; __prime_count_idx += 8) {
        uint64_t __prime_chunk;
        memcpy(&__prime_chunk, __prime + __prime_count_idx, sizeof(__prime_chunk));
        __count += (__builtin_popcountll(__prime_chunk));
    }
    for (; __prime_count_idx < __prime_count_end; ++__prime_count_idx) __count += (int64_t)__prime[__prime_count_idx];
    free(__prime_alloc);
    return __count;
}

int main() {
    volatile int64_t s2 = 0;
    clock_t t;
    t = clock();
    for (int i=0; i<1000; i++) s2 += sieve_new(1000000);
    printf("Pointer: %f\n", (double)(clock()-t)/CLOCKS_PER_SEC);
    return 0;
}
