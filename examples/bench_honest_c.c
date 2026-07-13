/* bench_honest_c.c — Reference C for honest benchmarks.
 * Algorithms match bench_honest.duo (@c.emit blocks): tiled matmul, Mo3 qsort,
 * unrolled hashtable, branchless bsearch, 4-way FNV. Same -O3 -flto flags as Duo.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <time.h>

static inline int64_t xorshift(int64_t s) {
    s ^= (s << 13);
    s ^= (s >> 7);
    s ^= (s << 17);
    return s < 0 ? -s : s;
}

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* 1. Dense matmul 128x128 — tiled i-k-j, 4x4 micro-kernel */
static double bench_matmul(int64_t n, int64_t s) {
    (void)n;
    double A[128 * 128], B[128 * 128], C[128 * 128];
    for (int i = 0; i < 128 * 128; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        A[i] = (double)(s % 1000) / 1000.0;
    }
    for (int i = 0; i < 128 * 128; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        B[i] = (double)(s % 1000) / 1000.0;
    }
    memset(C, 0, sizeof(C));

    enum { TILE = 32 };
    for (int ii = 0; ii < 128; ii += TILE) {
        for (int kk = 0; kk < 128; kk += TILE) {
            for (int jj = 0; jj < 128; jj += TILE) {
                for (int i = ii; i < ii + TILE && i < 128; i += 4) {
                    for (int j = jj; j < jj + TILE && j < 128; j += 4) {
                        double c00 = C[(i + 0) * 128 + (j + 0)], c01 = C[(i + 0) * 128 + (j + 1)],
                               c02 = C[(i + 0) * 128 + (j + 2)], c03 = C[(i + 0) * 128 + (j + 3)];
                        double c10 = C[(i + 1) * 128 + (j + 0)], c11 = C[(i + 1) * 128 + (j + 1)],
                               c12 = C[(i + 1) * 128 + (j + 2)], c13 = C[(i + 1) * 128 + (j + 3)];
                        double c20 = C[(i + 2) * 128 + (j + 0)], c21 = C[(i + 2) * 128 + (j + 1)],
                               c22 = C[(i + 2) * 128 + (j + 2)], c23 = C[(i + 2) * 128 + (j + 3)];
                        double c30 = C[(i + 3) * 128 + (j + 0)], c31 = C[(i + 3) * 128 + (j + 1)],
                               c32 = C[(i + 3) * 128 + (j + 2)], c33 = C[(i + 3) * 128 + (j + 3)];
                        for (int k = kk; k < kk + TILE && k < 128; k++) {
                            double a0 = A[(i + 0) * 128 + k], a1 = A[(i + 1) * 128 + k],
                                   a2 = A[(i + 2) * 128 + k], a3 = A[(i + 3) * 128 + k];
                            double b0 = B[k * 128 + (j + 0)], b1 = B[k * 128 + (j + 1)],
                                   b2 = B[k * 128 + (j + 2)], b3 = B[k * 128 + (j + 3)];
                            c00 += a0 * b0;
                            c01 += a0 * b1;
                            c02 += a0 * b2;
                            c03 += a0 * b3;
                            c10 += a1 * b0;
                            c11 += a1 * b1;
                            c12 += a1 * b2;
                            c13 += a1 * b3;
                            c20 += a2 * b0;
                            c21 += a2 * b1;
                            c22 += a2 * b2;
                            c23 += a2 * b3;
                            c30 += a3 * b0;
                            c31 += a3 * b1;
                            c32 += a3 * b2;
                            c33 += a3 * b3;
                        }
                        C[(i + 0) * 128 + (j + 0)] = c00;
                        C[(i + 0) * 128 + (j + 1)] = c01;
                        C[(i + 0) * 128 + (j + 2)] = c02;
                        C[(i + 0) * 128 + (j + 3)] = c03;
                        C[(i + 1) * 128 + (j + 0)] = c10;
                        C[(i + 1) * 128 + (j + 1)] = c11;
                        C[(i + 1) * 128 + (j + 2)] = c12;
                        C[(i + 1) * 128 + (j + 3)] = c13;
                        C[(i + 2) * 128 + (j + 0)] = c20;
                        C[(i + 2) * 128 + (j + 1)] = c21;
                        C[(i + 2) * 128 + (j + 2)] = c22;
                        C[(i + 2) * 128 + (j + 3)] = c23;
                        C[(i + 3) * 128 + (j + 0)] = c30;
                        C[(i + 3) * 128 + (j + 1)] = c31;
                        C[(i + 3) * 128 + (j + 2)] = c32;
                        C[(i + 3) * 128 + (j + 3)] = c33;
                    }
                }
            }
        }
    }
    double cksum = 0;
    for (int i = 0; i < 128 * 128; i++) cksum += C[i];
    return cksum;
}

/* 2. Quicksort — median-of-three + insertion sort for small partitions */
static int64_t bench_qsort(int64_t n, int64_t s) {
    int64_t *arr = (int64_t *)malloc((size_t)n * sizeof(int64_t));
    if (!arr) return 0;
    for (int64_t i = 0; i < n; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        arr[i] = s;
    }

    int64_t stack[128];
    int top = -1;
    stack[++top] = 0;
    stack[++top] = n - 1;
    while (top >= 0) {
        int64_t hi = stack[top--], lo = stack[top--];
        if (hi - lo < 16) {
            for (int64_t i = lo + 1; i <= hi; i++) {
                int64_t key = arr[i];
                int64_t j = i - 1;
                while (j >= lo && arr[j] > key) {
                    arr[j + 1] = arr[j];
                    j--;
                }
                arr[j + 1] = key;
            }
            continue;
        }
        int64_t mid = lo + (hi - lo) / 2;
        if (arr[mid] < arr[lo]) {
            int64_t t = arr[lo];
            arr[lo] = arr[mid];
            arr[mid] = t;
        }
        if (arr[hi] < arr[lo]) {
            int64_t t = arr[lo];
            arr[lo] = arr[hi];
            arr[hi] = t;
        }
        if (arr[hi] < arr[mid]) {
            int64_t t = arr[mid];
            arr[mid] = arr[hi];
            arr[hi] = t;
        }
        int64_t t = arr[mid];
        arr[mid] = arr[hi - 1];
        arr[hi - 1] = t;
        int64_t pivot = arr[hi - 1];
        int64_t i = lo;
        int64_t j = hi - 1;
        for (;;) {
            while (arr[++i] < pivot) {}
            while (arr[--j] > pivot) {}
            if (i >= j) break;
            t = arr[i];
            arr[i] = arr[j];
            arr[j] = t;
        }
        t = arr[i];
        arr[i] = arr[hi - 1];
        arr[hi - 1] = t;
        if (i - 1 > lo) {
            stack[++top] = lo;
            stack[++top] = i - 1;
        }
        if (i + 1 < hi) {
            stack[++top] = i + 1;
            stack[++top] = hi;
        }
    }
    int64_t cksum = 0;
    for (int64_t i = 0; i < n; i++) cksum += arr[i];
    int64_t sorted = 1;
    for (int64_t i = 1; i < n; i++)
        if (arr[i] < arr[i - 1]) sorted = 0;
    free(arr);
    return cksum ^ sorted;
}

/* 3. Hash table — 4-way unrolled probes */
static int64_t bench_hashtable(int64_t n, int64_t s) {
#define HT_SIZE 65536
#define HT_MASK (HT_SIZE - 1)
    int64_t *ht = (int64_t *)calloc(HT_SIZE, sizeof(int64_t));
    if (!ht) return 0;
    for (int64_t i = 0; i < 32768; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        ht[s & HT_MASK] = s;
    }
    int64_t hits = 0;
    int64_t s0 = s, s1 = s ^ 1, s2 = s ^ 2, s3 = s ^ 3;
    int64_t i = 0;
    for (; i + 3 < n; i += 4) {
        s0 = s0 ^ (s0 << 13);
        s0 = s0 ^ (s0 >> 7);
        s0 = s0 ^ (s0 << 17);
        s1 = s1 ^ (s1 << 13);
        s1 = s1 ^ (s1 >> 7);
        s1 = s1 ^ (s1 << 17);
        s2 = s2 ^ (s2 << 13);
        s2 = s2 ^ (s2 >> 7);
        s2 = s2 ^ (s2 << 17);
        s3 = s3 ^ (s3 << 13);
        s3 = s3 ^ (s3 >> 7);
        s3 = s3 ^ (s3 << 17);
        __builtin_prefetch(&ht[s0 & HT_MASK], 0, 0);
        hits += (ht[s0 & HT_MASK] != 0) + (ht[s1 & HT_MASK] != 0) + (ht[s2 & HT_MASK] != 0) +
                (ht[s3 & HT_MASK] != 0);
    }
    for (; i < n; i++) {
        s0 = s0 ^ (s0 << 13);
        s0 = s0 ^ (s0 >> 7);
        s0 = s0 ^ (s0 << 17);
        if (ht[s0 & HT_MASK] != 0) hits++;
    }
    free(ht);
#undef HT_SIZE
#undef HT_MASK
    return hits;
}

/* 4. Binary search — branchless lower-bound style */
static int64_t bench_bsearch(int64_t n, int64_t s) {
#define BS_SIZE 100000
    int64_t *sorted_arr = (int64_t *)malloc(BS_SIZE * sizeof(int64_t));
    if (!sorted_arr) return 0;
    for (int64_t i = 0; i < BS_SIZE; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        sorted_arr[i] = s;
    }
    for (int64_t i = 1; i < BS_SIZE; i++) {
        int64_t key = sorted_arr[i];
        int64_t j = i - 1;
        while (j >= 0 && sorted_arr[j] > key) {
            sorted_arr[j + 1] = sorted_arr[j];
            j--;
        }
        sorted_arr[j + 1] = key;
    }
    int64_t found = 0;
    for (int64_t q = 0; q < n; q++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        int64_t target = s;
        int64_t lo = 0, len = BS_SIZE;
        while (len > 1) {
            int64_t half = len / 2;
            lo += (sorted_arr[lo + half] < target) ? half : 0;
            len -= half;
        }
        found += (sorted_arr[lo] == target);
    }
    free(sorted_arr);
#undef BS_SIZE
    return found;
}

/* 5. N-body simulation (16 bodies, 100K steps) */
static double bench_nbody_real(int64_t steps, int64_t s) {
#define NB 16
    double px[NB], py[NB], vx[NB], vy[NB], mass[NB];
    for (int i = 0; i < NB; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        px[i] = (double)(s % 1000) * 0.1;
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        py[i] = (double)(s % 1000) * 0.1;
        vx[i] = 0;
        vy[i] = 0;
        mass[i] = 1.0 + (double)(i % 5);
    }
    double dt = 0.01;
    for (int64_t step = 0; step < steps; step++) {
        for (int i = 0; i < NB; i++) {
            double fx = 0, fy = 0;
            for (int j = 0; j < NB; j++) {
                if (i == j) continue;
                double dx = px[j] - px[i], dy = py[j] - py[i];
                double dist = sqrt(dx * dx + dy * dy + 0.01);
                double f = mass[j] / (dist * dist * dist);
                fx += f * dx;
                fy += f * dy;
            }
            vx[i] += fx * dt;
            vy[i] += fy * dt;
        }
        for (int i = 0; i < NB; i++) {
            px[i] += vx[i] * dt;
            py[i] += vy[i] * dt;
        }
    }
    double energy = 0;
    for (int i = 0; i < NB; i++) energy += 0.5 * mass[i] * (vx[i] * vx[i] + vy[i] * vy[i]);
#undef NB
    return energy;
}

/* 6. FNV-1a hash — 4-way interleaved */
static int64_t bench_fnv_hash(int64_t n, int64_t s) {
#define BUF_SZ (1024 * 1024)
    uint8_t *buf = (uint8_t *)malloc(BUF_SZ);
    if (!buf) return 0;
    for (int i = 0; i < BUF_SZ; i++) {
        s = s ^ (s << 13);
        s = s ^ (s >> 7);
        s = s ^ (s << 17);
        buf[i] = (uint8_t)(s & 0xFF);
    }
    int64_t hash_sum = 0;
    for (int64_t iter = 0; iter < n; iter++) {
        int64_t offset = (iter * 37) % (BUF_SZ - 256);
        uint64_t h0 = 14695981039346656037ULL;
        uint64_t h1 = 14695981039346656037ULL;
        uint64_t h2 = 14695981039346656037ULL;
        uint64_t h3 = 14695981039346656037ULL;
        for (int j = 0; j < 256; j += 4) {
            h0 ^= buf[offset + j + 0];
            h0 *= 1099511628211ULL;
            h1 ^= buf[offset + j + 1];
            h1 *= 1099511628211ULL;
            h2 ^= buf[offset + j + 2];
            h2 *= 1099511628211ULL;
            h3 ^= buf[offset + j + 3];
            h3 *= 1099511628211ULL;
        }
        hash_sum += (int64_t)(h0 ^ h1 ^ h2 ^ h3);
    }
    free(buf);
#undef BUF_SZ
    return hash_sum;
}

int main(void) {
    int64_t seed = (int64_t)(clock() ^ ((int64_t)clock() << 16));
    double t0, t1;

    printf("=== Honest Benchmarks (runtime-seeded, no precomputation) ===\n");
    printf("Seed: %lld\n", (long long)seed);

    t0 = now();
    double r1 = bench_matmul(128, seed);
    t1 = now();
    printf("RESULT matmul %.17g\n", r1);
    printf("Time matmul %f seconds\n", t1 - t0);

    t0 = now();
    int64_t r2 = bench_qsort(100000, seed);
    t1 = now();
    printf("RESULT qsort %lld\n", (long long)r2);
    printf("Time qsort %f seconds\n", t1 - t0);

    t0 = now();
    int64_t r3 = bench_hashtable(1000000, seed);
    t1 = now();
    printf("RESULT hashtable %lld\n", (long long)r3);
    printf("Time hashtable %f seconds\n", t1 - t0);

    t0 = now();
    int64_t r4 = bench_bsearch(1000000, seed);
    t1 = now();
    printf("RESULT bsearch %lld\n", (long long)r4);
    printf("Time bsearch %f seconds\n", t1 - t0);

    t0 = now();
    double r5 = bench_nbody_real(100000, seed);
    t1 = now();
    printf("RESULT nbody %.17g\n", r5);
    printf("Time nbody %f seconds\n", t1 - t0);

    t0 = now();
    int64_t r6 = bench_fnv_hash(1000000, seed);
    t1 = now();
    printf("RESULT fnv %lld\n", (long long)r6);
    printf("Time fnv %f seconds\n", t1 - t0);

    return 0;
}
