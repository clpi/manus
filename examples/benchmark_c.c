/* Reference C implementation mirroring examples/benchmark.lua source semantics. */
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

static double now(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
}

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
        avg *= 0.95
        avg += (double)(i % 100) * 0.05;
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

static int64_t matmul(int64_t reps) {
    int64_t size = 200;
    int64_t nn = size * size;
    int64_t *a = malloc((size_t)nn * sizeof(int64_t));
    int64_t *b = malloc((size_t)nn * sizeof(int64_t));
    int64_t *c = calloc((size_t)nn, sizeof(int64_t));
    for (int64_t i = 0; i < nn; i++) {
        a[i] = (i + 1) % 100;
        b[i] = ((i + 1) * 7) % 100;
    }
    for (int64_t rep = 0; rep < reps; rep++) {
        for (int64_t i = 0; i < size; i++)
            for (int64_t j = 0; j < size; j++) {
                int64_t sum = 0;
                for (int64_t k = 0; k < size; k++)
                    sum += a[i * size + k] * b[k * size + j];
                c[i * size + j] = sum;
            }
    }
    int64_t total = 0;
    for (int64_t i = 0; i < nn; i++) total += c[i];
    free(a); free(b); free(c);
    return total;
}

static int64_t prefix_sum(int64_t n) {
    int64_t *t = malloc((size_t)(n + 1) * sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = (i * 3) % 1000;
    for (int64_t i = 2; i <= n; i++) t[i] += t[i - 1];
    int64_t res = t[n];
    free(t);
    return res;
}

static int64_t gcd_reduce(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) {
        int64_t a = i, b = (i * 7 + 3) % 10000 + 1;
        while (b != 0) { int64_t tmp = b; b = a % b; a = tmp; }
        sum += a;
    }
    return sum;
}

static int64_t collatz_sum(int64_t n) {
    int64_t total = 0;
    for (int64_t i = 1; i <= n; i++) {
        int64_t x = i, steps = 0;
        while (x != 1) {
            if (x % 2 == 0) x /= 2;
            else x = 3 * x + 1;
            steps++;
        }
        total += steps;
    }
    return total;
}

static int64_t xor_fold(int64_t n) {
    int64_t acc = 0;
    for (int64_t i = 1; i <= n; i++)
        acc ^= i * (int64_t)2654435761LL;
    return acc;
}

static int64_t ring_buffer(int64_t n) {
    int64_t size = 1024;
    int64_t *buf = calloc((size_t)size, sizeof(int64_t));
    int64_t sum = 0;
    for (int64_t i = 0; i < n; i++) {
        int64_t idx = i % size;
        buf[idx] = (i * 31) % 100000;
        sum += buf[((i + size - 7) % size)];
    }
    free(buf);
    return sum;
}

static int64_t cond_swap(int64_t n) {
    int64_t *t = malloc((size_t)(n + 1) * sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) t[i] = (i * 17) % 10007;
    int64_t passes = 5;
    for (int64_t p = 0; p < passes; p++)
        for (int64_t i = 1; i < n; i++)
            if (t[i] > t[i + 1]) { int64_t tmp = t[i]; t[i] = t[i + 1]; t[i + 1] = tmp; }
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) sum += t[i];
    free(t);
    return sum;
}

static int64_t ack(int64_t m, int64_t n) {
    if (m == 0) return n + 1;
    if (n == 0) return ack(m - 1, 1);
    return ack(m - 1, ack(m, n - 1));
}

static int64_t leven(int64_t reps) {
    int64_t sum = 0;
    for (int64_t rep = 0; rep < reps; rep++) {
        int64_t len_a = 12, len_b = 13;
        int64_t prev[14], curr[14];
        for (int64_t j = 0; j <= len_b; j++) prev[j] = j;
        for (int64_t i = 1; i <= len_a; i++) {
            curr[0] = i;
            for (int64_t j = 1; j <= len_b; j++) {
                int64_t a_char = (rep * 7 + i * 3) % 26;
                int64_t b_char = (rep * 13 + j * 5) % 26;
                int64_t cost = a_char != b_char ? 1 : 0;
                int64_t del = prev[j] + 1;
                int64_t ins = curr[j - 1] + 1;
                int64_t sub = prev[j - 1] + cost;
                int64_t mn = del;
                if (ins < mn) mn = ins;
                if (sub < mn) mn = sub;
                curr[j] = mn;
            }
            for (int64_t j = 0; j <= len_b; j++) prev[j] = curr[j];
        }
        sum += prev[len_b];
    }
    return sum;
}

static int64_t sieve(int64_t n) {
    bool *is_prime = malloc((size_t)(n + 1));
    memset(is_prime, 1, (size_t)(n + 1));
    is_prime[0] = is_prime[1] = false;
    for (int64_t i = 2; i * i <= n; i++)
        if (is_prime[i])
            for (int64_t j = i * i; j <= n; j += i)
                is_prime[j] = false;
    int64_t count = 0;
    for (int64_t i = 2; i <= n; i++)
        if (is_prime[i]) count++;
    free(is_prime);
    return count;
}

static int64_t fenwick(int64_t n) {
    int64_t *tree = calloc((size_t)(n + 1), sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) {
        int64_t val = (i * 3) % 1000;
        for (int64_t idx = i; idx <= n; idx += idx & (-idx))
            tree[idx] += val;
    }
    int64_t sum = 0;
    for (int64_t q = 1; q <= n; q++)
        for (int64_t idx = q; idx > 0; idx -= idx & (-idx))
            sum += tree[idx];
    free(tree);
    return sum;
}

static double interp(int64_t n) {
    int64_t tbl_size = 1024;
    double tbl[1024];
    for (int64_t i = 0; i < tbl_size; i++)
        tbl[i] = sin(i * 0.01);
    double sum = 0;
    for (int64_t i = 0; i < n; i++) {
        double x = fmod(i * 0.0073, tbl_size - 1);
        int64_t idx = (int64_t)x;
        double frac = x - idx;
        sum += tbl[idx] * (1.0 - frac) + tbl[idx + 1] * frac;
    }
    return sum;
}

static int64_t run_len(int64_t n) {
    char *s = str_rep("aaabbccddddeefffff", n);
    size_t last = strlen(s);
    int64_t count = 0;
    for (size_t i = 1; i < last; i++)
        if ((unsigned char)s[i] != (unsigned char)s[i - 1]) count++;
    free(s);
    return count + 1;
}

static int64_t bitcount(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) {
        int64_t x = i, c = 0;
        while (x) { c += x & 1; x >>= 1; }
        sum += c;
    }
    return sum;
}

static double cordic(int64_t n) {
    double sum = 0;
    for (int64_t i = 0; i < n; i++) {
        double angle = (i % 1000) * 0.001;
        double s = angle, term = angle;
        for (int64_t k = 1; k <= 5; k++) {
            term = -term * angle * angle / ((2 * k) * (2 * k + 1));
            s += term;
        }
        sum += s;
    }
    return sum;
}

static int64_t sparse_dot(int64_t n) {
    int64_t stride = 16;
    int64_t len = n * stride;
    int64_t *a = calloc((size_t)len + 1, sizeof(int64_t));
    int64_t *b = calloc((size_t)len + 1, sizeof(int64_t));
    for (int64_t i = 1; i <= n; i++) {
        int64_t idx = (i - 1) * stride + 1;
        a[idx] = i;
        b[idx] = n - i + 1;
    }
    int64_t sum = 0;
    for (int64_t i = 1; i <= n; i++) {
        int64_t idx = (i - 1) * stride + 1;
        sum += a[idx] * b[idx];
    }
    free(a); free(b);
    return sum;
}

static int64_t life(int64_t steps) {
    int64_t W = 128, H = 128;
    int8_t *grid = malloc((size_t)(W * H));
    int8_t *next_grid = malloc((size_t)(W * H));
    for (int64_t i = 0; i < W * H; i++) {
        grid[i] = (i * 31337) % 3 == 0 ? 1 : 0;
        next_grid[i] = 0;
    }
    for (int64_t s = 0; s < steps; s++) {
        for (int64_t y = 1; y < H - 1; y++)
            for (int64_t x = 1; x < W - 1; x++) {
                int nb = grid[(y-1)*W+(x-1)] + grid[(y-1)*W+x] + grid[(y-1)*W+(x+1)]
                       + grid[y*W+(x-1)] + grid[y*W+(x+1)]
                       + grid[(y+1)*W+(x-1)] + grid[(y+1)*W+x] + grid[(y+1)*W+(x+1)];
                if (grid[y*W+x]) next_grid[y*W+x] = (nb == 2 || nb == 3) ? 1 : 0;
                else next_grid[y*W+x] = nb == 3 ? 1 : 0;
            }
        int8_t *tmp = grid; grid = next_grid; next_grid = tmp;
    }
    int64_t sum = 0;
    for (int64_t i = 0; i < W * H; i++) sum += grid[i];
    free(grid); free(next_grid);
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
    /* gap[096] NO TIME LINE — removed from the speed table on BOTH sides,
       RESULT kept. Duo's codegen substitutes an O(n) iteration for the
       O(phi^n) recursion, so the row compared two ALGORITHMS. C still runs the
       kernel and is still timed here; only the published comparison is gone. */
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
    /* gap[096] NO TIME LINE — removed from the speed table on BOTH sides,
       RESULT kept. Duo's codegen substitutes n(n+1)/2 for the O(n) loop. */
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
    printf("----------------------------------------\n");

    t0 = now(); int64_t matmul_res = matmul(50); t1 = now();
    printf("MatMul Checksum     %lld\n", (long long)matmul_res);
    printf("RESULT matmul %lld\n", (long long)matmul_res);
    printf("MatMul Time         %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t prefix_res = prefix_sum(2000000); t1 = now();
    printf("Prefix Sum Result   %lld\n", (long long)prefix_res);
    printf("RESULT prefix %lld\n", (long long)prefix_res);
    printf("Prefix Sum Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t gcd_res = gcd_reduce(2000000); t1 = now();
    printf("GCD Reduce Sum      %lld\n", (long long)gcd_res);
    printf("RESULT gcd %lld\n", (long long)gcd_res);
    printf("GCD Reduce Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t collatz_res = collatz_sum(500000); t1 = now();
    printf("Collatz Sum         %lld\n", (long long)collatz_res);
    printf("RESULT collatz %lld\n", (long long)collatz_res);
    printf("Collatz Sum Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t xor_res = xor_fold(5000000); t1 = now();
    printf("XOR Fold Result     %lld\n", (long long)xor_res);
    printf("RESULT xorfold %lld\n", (long long)xor_res);
    printf("XOR Fold Time       %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t ring_res = ring_buffer(5000000); t1 = now();
    printf("Ring Buffer Sum     %lld\n", (long long)ring_res);
    printf("RESULT ringbuf %lld\n", (long long)ring_res);
    printf("Ring Buffer Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t swap_res = cond_swap(100000); t1 = now();
    printf("Cond Swap Sum       %lld\n", (long long)swap_res);
    printf("RESULT cond_swap %lld\n", (long long)swap_res);
    printf("Cond Swap Time      %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t ack_res = ack(3, 11); t1 = now();
    printf("Ackermann Result    %lld\n", (long long)ack_res);
    printf("RESULT ack %lld\n", (long long)ack_res);
    printf("Ackermann Time      %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t leven_res = leven(200000); t1 = now();
    printf("Levenshtein Sum     %lld\n", (long long)leven_res);
    printf("RESULT leven %lld\n", (long long)leven_res);
    printf("Levenshtein Time    %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t sieve_res = sieve(2000000); t1 = now();
    printf("Sieve Count         %lld\n", (long long)sieve_res);
    printf("RESULT sieve %lld\n", (long long)sieve_res);
    printf("Sieve Time          %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t fenwick_res = fenwick(500000); t1 = now();
    printf("Fenwick Sum         %lld\n", (long long)fenwick_res);
    printf("RESULT fenwick %lld\n", (long long)fenwick_res);
    printf("Fenwick Time        %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); double interp_res = interp(5000000); t1 = now();
    printf("Interp Sum          %f\n", interp_res);
    printf("RESULT interp %.17g\n", interp_res);
    printf("Interp Time         %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t rle_res = run_len(50000); t1 = now();
    printf("Run-Length Count    %lld\n", (long long)rle_res);
    printf("RESULT run_len %lld\n", (long long)rle_res);
    printf("Run-Length Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t bitcount_res = bitcount(5000000); t1 = now();
    printf("Bitcount Sum        %lld\n", (long long)bitcount_res);
    printf("RESULT bitcount %lld\n", (long long)bitcount_res);
    /* gap[096] NO TIME LINE — removed from the speed table on BOTH sides,
       RESULT kept. Duo's codegen substitutes an O(log n) per-bit duty-cycle
       identity for the O(n log n) loop. */
    printf("----------------------------------------\n");

    t0 = now(); double cordic_res = cordic(5000000); t1 = now();
    printf("CORDIC Sum          %f\n", cordic_res);
    printf("RESULT cordic %.17g\n", cordic_res);
    printf("CORDIC Time         %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t sparse_res = sparse_dot(200000); t1 = now();
    printf("Sparse Dot Sum      %lld\n", (long long)sparse_res);
    printf("RESULT sparse %lld\n", (long long)sparse_res);
    printf("Sparse Dot Time     %f seconds\n", t1 - t0);
    printf("----------------------------------------\n");

    t0 = now(); int64_t life_res = life(500); t1 = now();
    printf("Life Population     %lld\n", (long long)life_res);
    printf("RESULT life %lld\n", (long long)life_res);
    printf("Life Time           %f seconds\n", t1 - t0);
    printf("========================================\n");
    return 0;
}
