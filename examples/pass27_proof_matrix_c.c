/* Pass 27 P0 — ten-benchmark correctness reference for 3-profile proof matrix. */
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int64_t fib(int64_t n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

static int64_t count_primes(int64_t limit) {
    int64_t count = 0;
    for (int64_t n = 2; n <= limit; n++) {
        int64_t is_prime = 1;
        for (int64_t d = 2; d * d <= n; d++) {
            if (n % d == 0) is_prime = 0;
        }
        if (is_prime) count++;
    }
    return count;
}

static int64_t mandel_iter(double cx, double cy) {
    double zx = 0, zy = 0;
    for (int64_t i = 0; i < 1000; i++) {
        double zx2 = zx * zx, zy2 = zy * zy;
        if (zx2 + zy2 > 4.0) return i;
        zy = 2.0 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
    }
    return 1000;
}

static double eval_A(double i, double j) {
    return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
}

static double compute_grid_sum(int64_t size) {
    double total = 0;
    for (int64_t i = 0; i < size; i++)
        for (int64_t j = 0; j < size; j++)
            total += eval_A((double)i, (double)j);
    return total;
}

static double simulate_nbody(int64_t steps) {
    double x1 = 0, y1 = 0, vx1 = 0, vy1 = 0, m1 = 1000;
    double x2 = 10, y2 = 0, vx2 = 0, vy2 = 10, m2 = 1;
    double x3 = 0, y3 = -10, vx3 = -10, vy3 = 0, m3 = 1;
    double dt = 0.001;
    for (int64_t i = 0; i < steps; i++) {
        double dx12 = x2 - x1, dy12 = y2 - y1;
        double dist12_sq = dx12 * dx12 + dy12 * dy12 + 0.001;
        double dist12 = sqrt(dist12_sq);
        double f12 = (m1 * m2) / dist12_sq;
        vx1 += (f12 * dx12 / dist12) * dt / m1;
        vy1 += (f12 * dy12 / dist12) * dt / m1;
        vx2 -= (f12 * dx12 / dist12) * dt / m2;
        vy2 -= (f12 * dy12 / dist12) * dt / m2;
        double dx13 = x3 - x1, dy13 = y3 - y1;
        double dist13_sq = dx13 * dx13 + dy13 * dy13 + 0.001;
        double dist13 = sqrt(dist13_sq);
        double f13 = (m1 * m3) / dist13_sq;
        vx1 += (f13 * dx13 / dist13) * dt / m1;
        vy1 += (f13 * dy13 / dist13) * dt / m1;
        vx3 -= (f13 * dx13 / dist13) * dt / m3;
        vy3 -= (f13 * dy13 / dist13) * dt / m3;
        x1 += vx1 * dt; y1 += vy1 * dt;
        x2 += vx2 * dt; y2 += vy2 * dt;
        x3 += vx3 * dt; y3 += vy3 * dt;
    }
    return x1 + y1 + x2 + y2 + x3 + y3;
}

static int64_t table_array_sum(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) sum += i;
    return sum;
}

static double trig_sum(int64_t n) {
    double sum = 0;
    for (int64_t i = 0; i < n; i++) sum += sin((double)i) * cos((double)i);
    return sum;
}

static int64_t rolling_hash(int64_t n) {
    int64_t h = 0;
    for (int64_t i = 0; i < n; i++) h = (h * 31 + (i % 256)) % 1000000007;
    return h;
}

static double dot2d(int64_t n) {
    double sum = 0;
    for (int64_t i = 0; i < n; i++) sum += (double)i * (double)(n - i);
    return sum;
}

static int64_t reduce_xor(int64_t n) {
    int64_t x = 0;
    for (int64_t i = 1; i <= n; i++) x ^= i;
    return x;
}

int main(void) {
    printf("RESULT fib %lld\n", (long long)fib(32));
    printf("RESULT primes %lld\n", (long long)count_primes(10000));
    int64_t mandel = 0;
    for (int64_t y = -20; y <= 20; y++)
        for (int64_t x = -20; x <= 20; x++)
            mandel += mandel_iter(x / 20.0, y / 20.0);
    printf("RESULT mandel %lld\n", (long long)mandel);
    printf("RESULT grid %.17g\n", compute_grid_sum(200));
    printf("RESULT nbody %.17g\n", simulate_nbody(50000));
    printf("RESULT table_sum %lld\n", (long long)table_array_sum(50000));
    printf("RESULT trig %.17g\n", trig_sum(500000));
    printf("RESULT hash %lld\n", (long long)rolling_hash(80000));
    printf("RESULT dot %.17g\n", dot2d(50000));
    printf("RESULT xor %lld\n", (long long)reduce_xor(65535));
    return 0;
}
