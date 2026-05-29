/* Reference C implementation mirroring examples/benchmark.lua source semantics. */
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static double now(void) { return (double)clock() / (double)CLOCKS_PER_SEC; }

static int64_t fib(int64_t n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

static int64_t count_primes(int64_t limit) {
    int64_t count = 0;
    for (int64_t n = 2; n <= limit; n++) {
        bool is_prime = true;
        for (int64_t d = 2; d * d <= n; d++) {
            if (n % d == 0) is_prime = false;
        }
        if (is_prime) count++;
    }
    return count;
}

static int64_t mandel_iter(double cx, double cy) {
    double zx = 0, zy = 0;
    for (int64_t i = 0; i < 10000; i++) {
        double zx2 = zx * zx, zy2 = zy * zy;
        if (zx2 + zy2 > 4.0) return i;
        zy = 2.0 * zx * zy + cy;
        zx = zx2 - zy2 + cx;
    }
    return 10000;
}

static double eval_A(double i, double j) {
    return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
}

static double compute_grid_sum(int64_t size) {
    double total = 0;
    for (int64_t i = 0; i < size; i++)
        for (int64_t j = 0; j < size; j++)
            total += eval_A(i, j);
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

static char *str_rep(const char *s, int64_t n) {
    if (n <= 0) { char *e = malloc(1); if (e) e[0] = 0; return e; }
    size_t len = strlen(s);
    size_t total = len * (size_t)n;
    char *out = malloc(total + 1);
    char *p = out;
    for (int64_t i = 0; i < n; i++) { memcpy(p, s, len); p += len; }
    *p = 0;
    return out;
}

static int64_t string_byte_sum(int64_t n) {
    char *s = str_rep("The quick brown fox jumps over the lazy dog. ", n);
    int64_t sum = 0;
    size_t last = strlen(s);
    for (size_t i = 0; i < last; i++) sum += (unsigned char)s[i];
    free(s);
    return sum;
}

static int64_t table_array_sum(int64_t n) {
    int64_t *t = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = i;
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) sum += t[i];
    free(t);
    return sum;
}

static double trig_sum(int64_t n) {
    double sum = 0;
    for (int64_t i = 0; i < n; i++) sum += sin((double)i) * cos((double)i);
    return sum;
}

static int64_t string_len_chain(int64_t n) {
    char *s = str_rep("a", 1000);
    int64_t total = 0;
    for (int64_t i = 1; i <= n; i++) {
        char pat[2] = { 'b', 0 };
        char *tmp = str_rep(pat, (i % 10) + 1);
        total += (int64_t)strlen(s) + (int64_t)strlen(tmp);
        free(tmp);
    }
    free(s);
    return total;
}

static int64_t string_hash_roll(int64_t n) {
    char *s = str_rep("benchmark", n);
    int64_t h = 0;
    size_t lim = strlen(s);
    for (size_t i = 0; i < lim; i++) {
        h = (h * 31 + (unsigned char)s[i]) % 1000000007;
    }
    free(s);
    return h;
}

static double math_floor_max(int64_t n) {
    double acc = 0, peak = 0;
    for (int64_t i = 0; i < n; i++) {
        double v = floor(i * 0.73 + 0.5);
        acc += v;
        if (v > peak) peak = v;
    }
    return acc + peak;
}

static int64_t table_max_scan(int64_t n) {
    int64_t *t = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = (i * 17) % 100003;
    int64_t mx = 0;
    for (int64_t i = 1; i <= n; i++)
        if (t[i] > mx) mx = t[i];
    free(t);
    return mx;
}

static double math_pow_sqrt(int64_t n) {
    double sum = 0;
    for (int64_t i = 1; i <= n; i++)
        sum += sqrt(pow((double)(i % 997), 0.25));
    return sum;
}

static int64_t binary_search_scan(int64_t n) {
    int64_t *t = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = i;
    int64_t hits = 0;
    for (int64_t q = 1; q <= 200000; q++) {
        int64_t key = ((q * 7919) % n) + 1;
        int64_t lo = 1, hi = n;
        while (lo <= hi) {
            int64_t mid = (lo + hi) / 2;
            if (t[mid] < key) lo = mid + 1;
            else if (t[mid] > key) hi = mid - 1;
            else { hits++; break; }
        }
    }
    free(t);
    return hits;
}

static int64_t filter_count(int64_t n) {
    int64_t count = 0;
    for (int64_t i = 1; i <= n; i++) {
        int64_t v = (i * 17) % 100003;
        if (v > 50000) count++;
    }
    return count;
}

static int64_t dot_product(int64_t n) {
    int64_t *a = calloc((size_t)n + 1, sizeof(int64_t));
    int64_t *b = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) {
        a[i] = i;
        b[i] = n - i + 1;
    }
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) sum += a[i] * b[i];
    free(a);
    free(b);
    return sum;
}

static int64_t clamp_sum(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 0; i < n; i++) {
        int64_t v = i % 1000;
        if (v > 255) v = 255;
        if (v < 0) v = 0;
        sum += v;
    }
    return sum;
}

static int64_t bucket_hash(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++)
        sum += (i * 31) % 256;
    return sum;
}

static double ema_smooth(int64_t n) {
    double avg = 0;
    for (int64_t i = 0; i < n; i++)
        avg = avg * 0.95 + (double)(i % 100) * 0.05;
    return avg;
}

static int64_t token_count(int64_t n) {
    char *s = str_rep("alpha beta gamma ", n);
    int64_t count = 0;
    size_t last = strlen(s);
    for (size_t i = 0; i < last; i++)
        if ((unsigned char)s[i] == 32) count++;
    free(s);
    return count;
}

static int64_t config_parse_sum(int64_t n) {
    char *s = str_rep("{\"id\":1,\"name\":\"item\",\"ok\":true},", n);
    int64_t sum = 0;
    size_t last = strlen(s);
    for (size_t i = 0; i < last; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '{' || c == ':' || c == '"') sum += c;
    }
    free(s);
    return sum;
}

static int64_t table_lookup_sum(int64_t n) {
    int64_t *t = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = i * 3;
    int64_t sum = 0;
    for (int64_t q = 1; q <= n; q++) {
        int64_t idx = (q * 7) % n + 1;
        sum += t[idx];
    }
    free(t);
    return sum;
}

static int64_t table_insert_churn(int64_t n) {
    int64_t *t = calloc((size_t)n + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = (i * 13) % 997;
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) sum += t[i];
    free(t);
    return sum;
}

int main(void) {
    double t0, t1;
    printf("========================================\n");
    printf("     COMPREHENSIVE BENCHMARK SUITE      \n");
    printf("========================================\n");

    t0 = now(); int64_t fib_res = fib(40); t1 = now();
    printf("Fibonacci(40) Result: %lld\n", (long long)fib_res);
    printf("RESULT fib %lld\n", (long long)fib_res);
    printf("Fibonacci(40) Time  %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t prime_res = count_primes(100000); t1 = now();
    printf("Primes Found        %lld\n", (long long)prime_res);
    printf("RESULT primes %lld\n", (long long)prime_res);
    printf("Prime Sieve Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now();
    int64_t sum_iters = 0;
    for (int64_t y = -100; y <= 100; y++)
        for (int64_t x = -100; x <= 100; x++)
            sum_iters += mandel_iter(x / 100.0, y / 100.0);
    t1 = now();
    printf("Mandel Iterations   %lld\n", (long long)sum_iters);
    printf("RESULT mandel %lld\n", (long long)sum_iters);
    printf("Mandelbrot Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double grid_res = compute_grid_sum(5000); t1 = now();
    printf("Grid Matrix Result  %f\n", grid_res);
    printf("RESULT grid %.17g\n", grid_res);
    printf("Grid Matrix Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double nbody_res = simulate_nbody(5000000); t1 = now();
    printf("N-Body Coord Sum    %f\n", nbody_res);
    printf("RESULT nbody %.17g\n", nbody_res);
    printf("N-Body Physics Time %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t str_res = string_byte_sum(500); t1 = now();
    printf("String Byte Sum     %lld\n", (long long)str_res);
    printf("RESULT str_bytes %lld\n", (long long)str_res);
    printf("String Bench Time   %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t tbl_res = table_array_sum(500000); t1 = now();
    printf("Table Array Sum     %lld\n", (long long)tbl_res);
    printf("RESULT table_sum %lld\n", (long long)tbl_res);
    printf("Table Bench Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double trig_res = trig_sum(5000000); t1 = now();
    printf("Trig Sum Result     %f\n", trig_res);
    printf("RESULT trig %.17g\n", trig_res);
    printf("Trig Bench Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t chain_res = string_len_chain(5000); t1 = now();
    printf("String Chain Sum    %lld\n", (long long)chain_res);
    printf("RESULT str_chain %lld\n", (long long)chain_res);
    printf("String Chain Time   %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t hash_res = string_hash_roll(8000); t1 = now();
    printf("String Hash Result  %lld\n", (long long)hash_res);
    printf("RESULT str_hash %lld\n", (long long)hash_res);
    printf("String Hash Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double math_res = math_floor_max(5000000); t1 = now();
    printf("Math Floor/Max      %f\n", math_res);
    printf("RESULT floor_max %.17g\n", math_res);
    printf("Math Floor/Max Time %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t max_res = table_max_scan(500000); t1 = now();
    printf("Table Max Result    %lld\n", (long long)max_res);
    printf("RESULT table_max %lld\n", (long long)max_res);
    printf("Table Max Time      %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double pow_res = math_pow_sqrt(2000000); t1 = now();
    printf("Pow/Sqrt Result     %f\n", pow_res);
    printf("RESULT pow_sqrt %.17g\n", pow_res);
    printf("Pow/Sqrt Time       %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t bsearch_res = binary_search_scan(500000); t1 = now();
    printf("Binary Search Hits  %lld\n", (long long)bsearch_res);
    printf("RESULT bsearch %lld\n", (long long)bsearch_res);
    printf("Binary Search Time  %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t filter_res = filter_count(500000); t1 = now();
    printf("Filter Count        %lld\n", (long long)filter_res);
    printf("RESULT filter %lld\n", (long long)filter_res);
    printf("Filter Count Time   %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t dot_res = dot_product(500000); t1 = now();
    printf("Dot Product Sum     %lld\n", (long long)dot_res);
    printf("RESULT dot %lld\n", (long long)dot_res);
    printf("Dot Product Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t clamp_res = clamp_sum(5000000); t1 = now();
    printf("Clamp Sum Result    %lld\n", (long long)clamp_res);
    printf("RESULT clamp %lld\n", (long long)clamp_res);
    printf("Clamp Sum Time      %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t bucket_res = bucket_hash(1000000); t1 = now();
    printf("Bucket Hash Sum     %lld\n", (long long)bucket_res);
    printf("RESULT bucket %lld\n", (long long)bucket_res);
    printf("Bucket Hash Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double ema_res = ema_smooth(5000000); t1 = now();
    printf("EMA Result          %f\n", ema_res);
    printf("RESULT ema %.17g\n", ema_res);
    printf("EMA Smooth Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t token_res = token_count(50000); t1 = now();
    printf("Token Count         %lld\n", (long long)token_res);
    printf("RESULT token %lld\n", (long long)token_res);
    printf("Token Count Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t parse_res = config_parse_sum(20000); t1 = now();
    printf("Config Parse Sum    %lld\n", (long long)parse_res);
    printf("RESULT parse %lld\n", (long long)parse_res);
    printf("Config Parse Time   %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t lookup_res = table_lookup_sum(500000); t1 = now();
    printf("Table Lookup Sum    %lld\n", (long long)lookup_res);
    printf("RESULT lookup %lld\n", (long long)lookup_res);
    printf("Table Lookup Time   %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t churn_res = table_insert_churn(500000); t1 = now();
    printf("Table Churn Sum     %lld\n", (long long)churn_res);
    printf("RESULT churn %lld\n", (long long)churn_res);
    printf("Table Churn Time    %f seconds\n", t1 - t0);
    printf("========================================\n");
    return 0;
}
