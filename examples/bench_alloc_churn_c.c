#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <stdint.h>

double get_time() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
}

int bench_alloc_churn(int n) {
    volatile int64_t* t = (volatile int64_t*)malloc((n + 1) * sizeof(int64_t));
    if (!t) return 0;
    
    for (int i = 1; i <= n; i++) {
        t[i] = i;
    }
    
    // Simulate setting to nil
    for (int i = 1; i <= n; i++) {
        t[i] = 0;
    }
    
    free((void*)t);
    return 1;
}

int main() {
    int n = 10000000;
    
    // Warm up
    bench_alloc_churn(1000);

    double start = get_time();
    bench_alloc_churn(n);
    double time_taken = get_time() - start;

    printf("RESULT alloc_churn\n");
    printf("%f\n", time_taken);
    
    return 0;
}
