#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static inline int64_t duo_gcd_i64(int64_t a, int64_t b) {
    while (b != 0) { int64_t t = a % b; a = b; b = t; }
    return a < 0 ? -a : a;
}

static inline int64_t duo_mod_inverse_i64(int64_t a, int64_t mod) {
    int64_t t = 0, new_t = 1, r = mod, new_r = a;
    while (new_r != 0) {
        int64_t q = r / new_r;
        int64_t next_t = t - q * new_t; t = new_t; new_t = next_t;
        int64_t next_r = r - q * new_r; r = new_r; new_r = next_r;
    }
    if (t < 0) t += mod;
    return t;
}

static inline int64_t duo_count_linear_congruence_precomputed_i64(int64_t start, int64_t terms, int64_t g, int64_t mod, int64_t inv_a) {
    if ((start % g) != 0) return 0;
    if (mod == 1) return terms;
    int64_t b = (-(start / g)) % mod;
    if (b < 0) b += mod;
    int64_t first = (b * inv_a) % mod;
    return first < terms ? 1 + (terms - 1 - first) / mod : 0;
}
