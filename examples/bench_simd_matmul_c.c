#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/time.h>

double get_time() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
}

// standard ikj matmul (cache friendly)
void matmul_f32(const float* a, const float* b, float* c, int n) {
    for (int i = 0; i < n; i++) {
        for (int k = 0; k < n; k++) {
            float a_ik = a[i * n + k];
            for (int j = 0; j < n; j++) {
                c[i * n + j] += a_ik * b[k * n + j];
            }
        }
    }
}

int main() {
    int N = 512;
    float* a = (float*)malloc(N * N * sizeof(float));
    float* b = (float*)malloc(N * N * sizeof(float));
    float* c = (float*)malloc(N * N * sizeof(float));
    
    uint64_t s = 12345;
    for(int i = 0; i < N * N; i++) {
        s = s ^ (s << 13); s = s ^ (s >> 7); s = s ^ (s << 17);
        a[i] = (float)(s % 1000) / 1000.0f;
        
        s = s ^ (s << 13); s = s ^ (s >> 7); s = s ^ (s << 17);
        b[i] = (float)(s % 1000) / 1000.0f;
        
        c[i] = 0.0f;
    }
    
    // Warmup
    matmul_f32(a, b, c, 128);

    double start = get_time();
    for (int i = 0; i < 10; i++) {
        matmul_f32(a, b, c, N);
    }
    double time_taken = get_time() - start;

    double checksum = 0.0;
    for(int i = 0; i < N * N; i++) {
        checksum += c[i];
    }
    
    printf("RESULT simd_matmul\n");
    printf("%f\n", time_taken);
    printf("Checksum: %f\n", checksum);

    free(a); free(b); free(c);
    return 0;
}
