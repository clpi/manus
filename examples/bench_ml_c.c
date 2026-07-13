/* Reference C implementation for ML benchmark suite.
 * Compile: clang -O3 -ffast-math -march=native -flto -lm -o bench_ml_c bench_ml_c.c
 * Must produce identical RESULT lines as bench_ml.duo.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* ============================================================
 * 1. matmul_256 — Dense 256x256 matrix multiply
 * ============================================================ */
static double matmul_256(void) {
    double *A = (double*)malloc(256*256*sizeof(double));
    double *B = (double*)malloc(256*256*sizeof(double));
    double *C = (double*)calloc(256*256, sizeof(double));
    for (int i = 0; i < 256; i++)
        for (int j = 0; j < 256; j++) {
            A[i*256+j] = (double)((i*256+j) % 1000) * 0.001;
            B[i*256+j] = (double)(((i+1)*(j+1)) % 1000) * 0.001;
        }
    /* ikj order for cache efficiency */
    for (int i = 0; i < 256; i++)
        for (int k = 0; k < 256; k++) {
            double a_ik = A[i*256+k];
            for (int j = 0; j < 256; j++)
                C[i*256+j] += a_ik * B[k*256+j];
        }
    double checksum = 0.0;
    for (int i = 0; i < 256*256; i++) checksum += C[i];
    free(A); free(B); free(C);
    return checksum;
}

/* ============================================================
 * 2. conv2d — 2D convolution: 32x32 input, 3x3 kernel, 16 channels
 *    Repeated 100 times for measurable timing
 * ============================================================ */
static double conv2d(void) {
    int IN = 32, KN = 3, OUTD = 30, CHAN = 16, REPS = 100;
    double *input = (double*)malloc(IN*IN*sizeof(double));
    double *kernels = (double*)malloc(CHAN*KN*KN*sizeof(double));
    double *output = (double*)calloc(CHAN*OUTD*OUTD, sizeof(double));
    for (int i = 0; i < IN*IN; i++) input[i] = (double)(i % 100) * 0.01;
    for (int c = 0; c < CHAN; c++)
        for (int i = 0; i < KN*KN; i++)
            kernels[c*KN*KN+i] = (double)((c*9+i) % 50) * 0.02 - 0.5;
    for (int rep = 0; rep < REPS; rep++) {
        for (int c = 0; c < CHAN; c++) {
            for (int oy = 0; oy < OUTD; oy++) {
                for (int ox = 0; ox < OUTD; ox++) {
                    double sum = 0.0;
                    for (int ky = 0; ky < KN; ky++)
                        for (int kx = 0; kx < KN; kx++)
                            sum += input[(oy+ky)*IN + (ox+kx)] * kernels[c*KN*KN + ky*KN + kx];
                    output[c*OUTD*OUTD + oy*OUTD + ox] = sum;
                }
            }
        }
    }
    double checksum = 0.0;
    for (int i = 0; i < CHAN*OUTD*OUTD; i++) checksum += output[i];
    free(input); free(kernels); free(output);
    return checksum;
}

/* ============================================================
 * 3. softmax_1k — Softmax over 1024-element vectors, 10000 iterations
 * ============================================================ */
static double softmax_1k(void) {
    int N = 1024, ITERS = 10000;
    double *x = (double*)malloc(N*sizeof(double));
    double *y = (double*)malloc(N*sizeof(double));
    for (int i = 0; i < N; i++) x[i] = (double)(i % 100) * 0.01 - 0.5;
    double checksum = 0.0;
    for (int iter = 0; iter < ITERS; iter++) {
        double mx = x[0];
        for (int i = 1; i < N; i++) if (x[i] > mx) mx = x[i];
        double sum = 0.0;
        for (int i = 0; i < N; i++) { y[i] = exp(x[i] - mx); sum += y[i]; }
        double inv_sum = 1.0 / sum;
        for (int i = 0; i < N; i++) y[i] *= inv_sum;
        checksum += y[iter % N];
    }
    free(x); free(y);
    return checksum;
}

/* ============================================================
 * 4. attention — Scaled dot-product attention
 *    batch=1, heads=8, seq=128, dim=64
 * ============================================================ */
static double attention(void) {
    int HEADS = 8, SEQ = 128, DIM = 64;
    double scale = 1.0 / 8.0;  /* 1/sqrt(64) */
    double *Q = (double*)malloc(HEADS*SEQ*DIM*sizeof(double));
    double *K = (double*)malloc(HEADS*SEQ*DIM*sizeof(double));
    double *V = (double*)malloc(HEADS*SEQ*DIM*sizeof(double));
    double *scores = (double*)malloc(SEQ*SEQ*sizeof(double));
    double *out = (double*)malloc(HEADS*SEQ*DIM*sizeof(double));
    for (int i = 0; i < HEADS*SEQ*DIM; i++) {
        Q[i] = (double)(i % 200) * 0.005 - 0.5;
        K[i] = (double)((i*3+1) % 200) * 0.005 - 0.5;
        V[i] = (double)((i*7+2) % 200) * 0.005 - 0.5;
    }
    for (int h = 0; h < HEADS; h++) {
        double *qh = Q + h*SEQ*DIM, *kh = K + h*SEQ*DIM, *vh = V + h*SEQ*DIM, *oh = out + h*SEQ*DIM;
        /* scores = Q @ K^T, scaled */
        for (int i = 0; i < SEQ; i++) {
            for (int j = 0; j < SEQ; j++) {
                double s = 0;
                for (int d = 0; d < DIM; d++) s += qh[i*DIM+d] * kh[j*DIM+d];
                scores[i*SEQ+j] = s * scale;
            }
        }
        /* row-wise softmax */
        for (int i = 0; i < SEQ; i++) {
            double mx = scores[i*SEQ];
            for (int j = 1; j < SEQ; j++) if (scores[i*SEQ+j] > mx) mx = scores[i*SEQ+j];
            double sm = 0;
            for (int j = 0; j < SEQ; j++) { scores[i*SEQ+j] = exp(scores[i*SEQ+j] - mx); sm += scores[i*SEQ+j]; }
            double inv = 1.0 / sm;
            for (int j = 0; j < SEQ; j++) scores[i*SEQ+j] *= inv;
        }
        /* out = scores @ V */
        for (int i = 0; i < SEQ; i++) {
            for (int d = 0; d < DIM; d++) {
                double s = 0;
                for (int j = 0; j < SEQ; j++) s += scores[i*SEQ+j] * vh[j*DIM+d];
                oh[i*DIM+d] = s;
            }
        }
    }
    double checksum = 0.0;
    for (int i = 0; i < HEADS*SEQ*DIM; i++) checksum += out[i];
    free(Q); free(K); free(V); free(scores); free(out);
    return checksum;
}

/* ============================================================
 * 5. mlp_forward — Forward pass: 784→256→128→10, 1000 samples
 * ============================================================ */
static double mlp_forward(void) {
    int SAMPLES = 1000, IN = 784, H1 = 256, H2 = 128, OUT = 10;
    double *input = (double*)malloc(SAMPLES*IN*sizeof(double));
    double *w1 = (double*)malloc(IN*H1*sizeof(double));
    double *b1 = (double*)malloc(H1*sizeof(double));
    double *w2 = (double*)malloc(H1*H2*sizeof(double));
    double *b2 = (double*)malloc(H2*sizeof(double));
    double *w3 = (double*)malloc(H2*OUT*sizeof(double));
    double *b3 = (double*)malloc(OUT*sizeof(double));
    double *h1_out = (double*)malloc(H1*sizeof(double));
    double *h2_out = (double*)malloc(H2*sizeof(double));
    double *final_out = (double*)malloc(OUT*sizeof(double));

    for (int i = 0; i < SAMPLES*IN; i++) input[i] = (double)(i % 256) / 255.0;
    for (int i = 0; i < IN*H1; i++) w1[i] = (double)((i*13+7) % 1000) * 0.001 - 0.5;
    for (int i = 0; i < H1; i++) b1[i] = (double)(i % 100) * 0.01 - 0.5;
    for (int i = 0; i < H1*H2; i++) w2[i] = (double)((i*17+3) % 1000) * 0.001 - 0.5;
    for (int i = 0; i < H2; i++) b2[i] = (double)(i % 100) * 0.01 - 0.5;
    for (int i = 0; i < H2*OUT; i++) w3[i] = (double)((i*19+11) % 1000) * 0.001 - 0.5;
    for (int i = 0; i < OUT; i++) b3[i] = (double)(i % 10) * 0.1 - 0.5;

    double checksum = 0.0;
    for (int s = 0; s < SAMPLES; s++) {
        double *inp = input + s*IN;
        /* Layer 1: inp @ w1 + b1, ReLU */
        for (int j = 0; j < H1; j++) {
            double sum = b1[j];
            for (int i = 0; i < IN; i++) sum += inp[i] * w1[i*H1+j];
            h1_out[j] = sum > 0 ? sum : 0;
        }
        /* Layer 2: h1 @ w2 + b2, ReLU */
        for (int j = 0; j < H2; j++) {
            double sum = b2[j];
            for (int i = 0; i < H1; i++) sum += h1_out[i] * w2[i*H2+j];
            h2_out[j] = sum > 0 ? sum : 0;
        }
        /* Layer 3: h2 @ w3 + b3 (logits) */
        for (int j = 0; j < OUT; j++) {
            double sum = b3[j];
            for (int i = 0; i < H2; i++) sum += h2_out[i] * w3[i*OUT+j];
            final_out[j] = sum;
        }
        /* Max logit as checksum */
        double mx = final_out[0];
        for (int j = 1; j < OUT; j++) if (final_out[j] > mx) mx = final_out[j];
        checksum += mx;
    }
    free(input); free(w1); free(b1); free(w2); free(b2); free(w3); free(b3);
    free(h1_out); free(h2_out); free(final_out);
    return checksum;
}

/* ============================================================ */
int main(void) {
    double t0, t1, r;

    printf("========================================\n");
    printf("       ML BENCHMARK SUITE (C ref)       \n");
    printf("========================================\n");

    /* matmul_256 */
    printf("Running matmul_256...\n");
    t0 = now(); r = matmul_256(); t1 = now();
    printf("Time: %.6f seconds\n", t1 - t0);
    printf("RESULT matmul_256 %.6f\n", r);
    printf("----------------------------------------\n");

    /* conv2d */
    printf("Running conv2d...\n");
    t0 = now(); r = conv2d(); t1 = now();
    printf("Time: %.6f seconds\n", t1 - t0);
    printf("RESULT conv2d %.6f\n", r);
    printf("----------------------------------------\n");

    /* softmax_1k */
    printf("Running softmax_1k...\n");
    t0 = now(); r = softmax_1k(); t1 = now();
    printf("Time: %.6f seconds\n", t1 - t0);
    printf("RESULT softmax_1k %.6f\n", r);
    printf("----------------------------------------\n");

    /* attention */
    printf("Running attention...\n");
    t0 = now(); r = attention(); t1 = now();
    printf("Time: %.6f seconds\n", t1 - t0);
    printf("RESULT attention %.6f\n", r);
    printf("----------------------------------------\n");

    /* mlp_forward */
    printf("Running mlp_forward...\n");
    t0 = now(); r = mlp_forward(); t1 = now();
    printf("Time: %.6f seconds\n", t1 - t0);
    printf("RESULT mlp_forward %.6f\n", r);
    printf("----------------------------------------\n");

    printf("========================================\n");
    printf("       ML BENCHMARK SUITE COMPLETE       \n");
    printf("========================================\n");
    return 0;
}
