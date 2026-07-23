#include <stdint.h>
#include <stdio.h>

typedef double f64x4 __attribute__((vector_size(32)));
typedef int64_t i64x4 __attribute__((vector_size(32)));

static inline __attribute__((always_inline)) int64_t duo_mandel_benchmark_sum(void) {
    int64_t sum_iters = 0;
    for (int64_t y = 0; y <= 100; ++y) {
        double cy = (double)y / 100.0;
        int64_t row_sum = 0;
        int64_t x = -100;
        f64x4 v_cy = {cy, cy, cy, cy};
        
        for (; x <= 96; x += 4) {
            f64x4 v_cx = {(double)(x)/100.0, (double)(x+1)/100.0, (double)(x+2)/100.0, (double)(x+3)/100.0};
            
            f64x4 v_cx_sq = v_cx * v_cx;
            f64x4 v_cy_sq = v_cy * v_cy;
            f64x4 v_cx_025 = v_cx - 0.25;
            f64x4 v_q = v_cx_025 * v_cx_025 + v_cy_sq;
            
            f64x4 v_zx = {0,0,0,0};
            f64x4 v_zy = {0,0,0,0};
            i64x4 v_i = {0,0,0,0};
            i64x4 v_mask = {-1,-1,-1,-1};
            
            // cardioid optimization bypass for simplicity, we just run all for correctness
            
            for (int i = 0; i < 10000; ++i) {
                f64x4 v_zx2 = v_zx * v_zx;
                f64x4 v_zy2 = v_zy * v_zy;
                
                f64x4 v_mag2 = v_zx2 + v_zy2;
                // SIMD comparison returns all 1s (which is -1 for signed int) if true, 0 if false
                // Note: Clang vector compare returns all 1s (-1) for true.
                i64x4 v_cmp = (i64x4)(v_mag2 <= 4.0);
                v_mask = v_mask & v_cmp;
                
                // If mask is all 0, break
                if (v_mask[0] == 0 && v_mask[1] == 0 && v_mask[2] == 0 && v_mask[3] == 0) break;
                
                v_zy = 2.0 * v_zx * v_zy + v_cy;
                v_zx = v_zx2 - v_zy2 + v_cx;
                
                v_i = v_i - v_mask; // -(-1) = +1
            }
            row_sum += v_i[0] + v_i[1] + v_i[2] + v_i[3];
        }
        
        for (; x <= 100; ++x) {
            double cx = (double)x / 100.0;
            double zx = 0, zy = 0;
            int64_t i = 0;
            for (; i < 10000; ++i) {
                double zx2 = zx * zx, zy2 = zy * zy;
                if (zx2 + zy2 > 4.0) break;
                zy = 2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
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
