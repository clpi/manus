#include <stdint.h>
#include <stdio.h>
#include <time.h>

typedef double v4f64 __attribute__((ext_vector_type(4)));
typedef int64_t v4i64 __attribute__((ext_vector_type(4)));

static inline __attribute__((always_inline)) int64_t duo_mandel_benchmark_sum_simd_no_cardioid(void) {
    int64_t sum_iters = 0;
    for (int64_t y = 0; y <= 100; ++y) {
        double cy = (double)y / 100.0;
        v4f64 cy4 = (v4f64){cy, cy, cy, cy};
        int64_t row_sum = 0;
        int64_t x = -100;
        for (; x <= 100 - 3; x += 4) {
            v4f64 cx4 = (v4f64){(double)x/100.0, (double)(x+1)/100.0, (double)(x+2)/100.0, (double)(x+3)/100.0};
            v4i64 iters = (v4i64){0, 0, 0, 0};
            v4i64 active = (v4i64){-1,-1,-1,-1};
            v4f64 zx = (v4f64){0,0,0,0}, zy = (v4f64){0,0,0,0};
            int i = 0;
            while (i < 10000 && (active[0] | active[1] | active[2] | active[3])) {
                v4f64 zx2 = zx * zx, zy2 = zy * zy;
                active &= (v4i64)(zx2 + zy2 <= (v4f64){4.0, 4.0, 4.0, 4.0});
                if (!(active[0] | active[1] | active[2] | active[3])) break;
                zy = ((v4f64){2.0, 2.0, 2.0, 2.0} * zx) * zy + cy4;
                zx = (zx2 - zy2) + cx4;
                iters -= active;
                i++;
            }
            row_sum += iters[0] + iters[1] + iters[2] + iters[3];
        }
        for (; x <= 100; ++x) {
            double cx = (double)x / 100.0;
            double zx = 0, zy = 0;
            int64_t i = 0;
            while (i < 10000) {
                double zx2 = zx * zx, zy2 = zy * zy;
                if (zx2 + zy2 > 4.0) break;
                zy = 2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                i = i + 1;
            }
            row_sum += i;
        }
        if (y > 0) sum_iters += row_sum * 2;
        else sum_iters += row_sum;
    }
    return sum_iters;
}

int main() {
    volatile int64_t sum = 0;
    clock_t start = clock();
    for (int i = 0; i < 10; i++) sum += duo_mandel_benchmark_sum_simd_no_cardioid();
    clock_t end = clock();
    printf("SIMD no cardioid: %f seconds\n", (double)(end - start) / CLOCKS_PER_SEC);
    printf("Result: %lld\n", duo_mandel_benchmark_sum_simd_no_cardioid());
    return 0;
}
