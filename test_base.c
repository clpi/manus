#include <stdint.h>
#include <stdio.h>

static inline __attribute__((always_inline)) int64_t duo_mandel_benchmark_sum(void) {
    int64_t sum_iters = 0;
    for (int64_t y = 0; y <= 100; ++y) {
        double cy = (double)y / 100.0;
        int64_t row_sum = 0;
        for (int64_t x = -100; x <= 100; ++x) {
            double cx = (double)x / 100.0;
            double cx_sq = cx * cx;
            double cy_sq = cy * cy;
            double q = (cx - 0.25) * (cx - 0.25) + cy_sq;
            if (q * (q + (cx - 0.25)) < 0.25 * cy_sq) { row_sum += 10000; continue; }
            if ((cx + 1.0) * (cx + 1.0) + cy_sq < 0.0625) { row_sum += 10000; continue; }
            double zx = 0, zy = 0;
            int64_t i = 0;
            #pragma GCC unroll 4
            while (i < 10000) {
                double zx2 = zx * zx, zy2 = zy * zy;
                if (zx2 + zy2 > 4) break;
                zy = ((2 * zx) * zy) + cy;
                zx = (zx2 - zy2) + cx;
                i = i + 1;
            }
            row_sum += i;
        }
        if (y == 0) sum_iters += row_sum; else sum_iters += 2 * row_sum;
    }
    return sum_iters;
}

int main() {
    printf("%lld\n", duo_mandel_benchmark_sum());
    return 0;
}
