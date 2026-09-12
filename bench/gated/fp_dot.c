// fp_dot.c — gated benchmark oracle: floating-point dot product.
// Gate: float type + float arithmetic in the Idol compiled subset.
// Semantics frozen: sum_{i=0}^{999999} a[i]*b[i], exit = (long long)sum & 255.
#include <stddef.h>
#define N 1000000
static float a[N], b[N];
int main(void){
    for(size_t i=0;i<N;i++){a[i]=(float)(i%97)*0.5f;b[i]=(float)(i%53)*0.25f;}
    double s=0.0;
    for(size_t i=0;i<N;i++){s+=(double)a[i]*(double)b[i];}
    return (int)(((long long)s)&255);
}
