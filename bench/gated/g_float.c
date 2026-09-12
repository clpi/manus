// g_float.c — gated benchmark oracle: float-heavy reduction.
// Gate: float/double type plus float arithmetic in the Idol subset.
// Semantics frozen: dot product of two 4M-element double arrays plus a
// Horner polynomial evaluation per element, exit = (uint64_t)sum & 255.
// Vectorizer and FMA bait; idol cannot express this until floats land.
#include <stdint.h>
#include <stdlib.h>
#define N 4000000
static double a[N], b[N];
int main(void){
    for(size_t i=0;i<N;i++){ a[i] = (double)(i % 1000) * 0.001; b[i] = (double)(i % 777) * 0.002; }
    double s = 0.0;
    for(size_t i=0;i<N;i++){
        double x = a[i];
        double p = ((3.0 * x + 7.0) * x + 11.0) * x + 13.0;
        s += a[i] * b[i] + p * 0.000001;
    }
    return (int)(((uint64_t)s) & 255);
}
