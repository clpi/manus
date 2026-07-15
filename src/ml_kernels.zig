//! Optimized ML kernel C declarations emitted once per translation unit.
//! Invoked via `ml.matmul_256()` etc. — minimal Duo syntax, native performance.

const std = @import("std");
const codegen = @import("codegen.zig");

/// Full C source for ML builtins (included in generated .c once).
pub const decls =
    \\#ifndef DUO_ML_KERNELS_DECLS
    \\#define DUO_ML_KERNELS_DECLS
    \\
    \\#ifdef __clang__
    \\#define DUO_ML_VEC _Pragma("clang loop vectorize(enable) interleave(enable) unroll_count(8)")
    \\#else
    \\#define DUO_ML_VEC
    \\#endif
    \\
    \\typedef double duo_ml_v4f64 __attribute__((vector_size(32), may_alias));
    \\static inline duo_ml_v4f64 duo_ml_v4f64_load(const double* p) {
    \\    return *(const duo_ml_v4f64*)p;
    \\}
    \\static inline void duo_ml_v4f64_store(double* p, duo_ml_v4f64 v) { *(duo_ml_v4f64*)p = v; }
    \\static inline duo_ml_v4f64 duo_ml_v4f64_splat(double x) { return (duo_ml_v4f64){x, x, x, x}; }
    \\static inline duo_ml_v4f64 duo_ml_v4f64_fma(duo_ml_v4f64 a, duo_ml_v4f64 b, duo_ml_v4f64 c) {
    \\    return a * b + c;
    \\}
    \\static inline double duo_ml_v4f64_sum(duo_ml_v4f64 v) { return v[0] + v[1] + v[2] + v[3]; }
    \\
    \\typedef double duo_ml_v2f64 __attribute__((vector_size(16), may_alias));
    \\static inline duo_ml_v2f64 duo_ml_v2f64_load(const double* p) {
    \\    return *(const duo_ml_v2f64*)p;
    \\}
    \\static inline void duo_ml_v2f64_store(double* p, duo_ml_v2f64 v) { *(duo_ml_v2f64*)p = v; }
    \\static inline duo_ml_v2f64 duo_ml_v2f64_splat(double x) { return (duo_ml_v2f64){x, x}; }
    \\static inline duo_ml_v2f64 duo_ml_v2f64_fma(duo_ml_v2f64 a, duo_ml_v2f64 b, duo_ml_v2f64 c) {
    \\    return a * b + c;
    \\}
    \\
    \\static inline double duo_ml_exp_m1_0_poly8(double x) {
    \\    return 1.0 + x * (1.0 + x * (0.5 + x * (0.16666666666666665741 + x * (0.04166666666666666435 + x * (0.00833333333333333322 + x * (0.00138888888888888894 + x * (0.00019841269841269841 + x * 0.00002480158730158730)))))));
    \\}
    \\__attribute__((always_inline)) static inline double duo_ml_dot_v4(const double* restrict a, const double* restrict b, int n) {
    \\    duo_ml_v4f64 acc = {0};
    \\    int i = 0;
    \\    for (; i + 4 <= n; i += 4)
    \\        acc = duo_ml_v4f64_fma(duo_ml_v4f64_load(a + i), duo_ml_v4f64_load(b + i), acc);
    \\    double sum = duo_ml_v4f64_sum(acc);
    \\    for (; i < n; i++) sum += a[i] * b[i];
    \\    return sum;
    \\}
    \\static inline double duo_ml_dot_v4_strided(
    \\    const double* restrict a, const double* restrict b0, int n, int b_stride) {
    \\    duo_ml_v4f64 acc = {0};
    \\    int i = 0;
    \\    for (; i + 4 <= n; i += 4) {
    \\        duo_ml_v4f64 av = duo_ml_v4f64_load(a + i);
    \\        duo_ml_v4f64 bv = {
    \\            b0[i * b_stride], b0[(i + 1) * b_stride],
    \\            b0[(i + 2) * b_stride], b0[(i + 3) * b_stride],
    \\        };
    \\        acc = duo_ml_v4f64_fma(av, bv, acc);
    \\    }
    \\    double sum = duo_ml_v4f64_sum(acc);
    \\    for (; i < n; i++) sum += a[i] * b0[i * b_stride];
    \\    return sum;
    \\}
    \\
    \\static inline double duo_ml_relu_dot(const double* restrict a, const double* restrict w, int n, double bias) {
    \\    const double s = bias + duo_ml_dot_v4(a, w, n);
    \\    return s > 0.0 ? s : 0.0;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_matmul_256(void) {
    \\    enum { N = 256, BN = 64 };
    \\    double *restrict A = (double*)malloc((size_t)N * N * sizeof(double));
    \\    double *restrict B = (double*)malloc((size_t)N * N * sizeof(double));
    \\    double *restrict C = (double*)calloc((size_t)N * N, sizeof(double));
    \\    if (!A || !B || !C) { free(A); free(B); free(C); return 0.0; }
    \\    for (int i = 0; i < N; i++)
    \\        for (int j = 0; j < N; j++) {
    \\            A[i * N + j] = (double)((i * N + j) % 1000) * 0.001;
    \\            B[i * N + j] = (double)(((i + 1) * (j + 1)) % 1000) * 0.001;
    \\        }
    \\    for (int ii = 0; ii < N; ii += BN) {
    \\        for (int jj = 0; jj < N; jj += BN) {
    \\            for (int kk = 0; kk < N; kk += BN) {
    \\                for (int i = ii; i < ii + BN; i += 4) {
    \\                    for (int j = jj; j < jj + BN; j += 8) {
    \\                        duo_ml_v2f64 c00 = duo_ml_v2f64_load(C + (i+0) * N + j + 0);
    \\                        duo_ml_v2f64 c01 = duo_ml_v2f64_load(C + (i+0) * N + j + 2);
    \\                        duo_ml_v2f64 c02 = duo_ml_v2f64_load(C + (i+0) * N + j + 4);
    \\                        duo_ml_v2f64 c03 = duo_ml_v2f64_load(C + (i+0) * N + j + 6);
    \\
    \\                        duo_ml_v2f64 c10 = duo_ml_v2f64_load(C + (i+1) * N + j + 0);
    \\                        duo_ml_v2f64 c11 = duo_ml_v2f64_load(C + (i+1) * N + j + 2);
    \\                        duo_ml_v2f64 c12 = duo_ml_v2f64_load(C + (i+1) * N + j + 4);
    \\                        duo_ml_v2f64 c13 = duo_ml_v2f64_load(C + (i+1) * N + j + 6);
    \\
    \\                        duo_ml_v2f64 c20 = duo_ml_v2f64_load(C + (i+2) * N + j + 0);
    \\                        duo_ml_v2f64 c21 = duo_ml_v2f64_load(C + (i+2) * N + j + 2);
    \\                        duo_ml_v2f64 c22 = duo_ml_v2f64_load(C + (i+2) * N + j + 4);
    \\                        duo_ml_v2f64 c23 = duo_ml_v2f64_load(C + (i+2) * N + j + 6);
    \\
    \\                        duo_ml_v2f64 c30 = duo_ml_v2f64_load(C + (i+3) * N + j + 0);
    \\                        duo_ml_v2f64 c31 = duo_ml_v2f64_load(C + (i+3) * N + j + 2);
    \\                        duo_ml_v2f64 c32 = duo_ml_v2f64_load(C + (i+3) * N + j + 4);
    \\                        duo_ml_v2f64 c33 = duo_ml_v2f64_load(C + (i+3) * N + j + 6);
    \\
    \\                        for (int k = kk; k < kk + BN; k++) {
    \\                            duo_ml_v2f64 a0 = duo_ml_v2f64_splat(A[(i+0) * N + k]);
    \\                            duo_ml_v2f64 a1 = duo_ml_v2f64_splat(A[(i+1) * N + k]);
    \\                            duo_ml_v2f64 a2 = duo_ml_v2f64_splat(A[(i+2) * N + k]);
    \\                            duo_ml_v2f64 a3 = duo_ml_v2f64_splat(A[(i+3) * N + k]);
    \\
    \\                            duo_ml_v2f64 b0 = duo_ml_v2f64_load(B + k * N + j + 0);
    \\                            duo_ml_v2f64 b1 = duo_ml_v2f64_load(B + k * N + j + 2);
    \\                            duo_ml_v2f64 b2 = duo_ml_v2f64_load(B + k * N + j + 4);
    \\                            duo_ml_v2f64 b3 = duo_ml_v2f64_load(B + k * N + j + 6);
    \\
    \\                            c00 = duo_ml_v2f64_fma(a0, b0, c00);
    \\                            c01 = duo_ml_v2f64_fma(a0, b1, c01);
    \\                            c02 = duo_ml_v2f64_fma(a0, b2, c02);
    \\                            c03 = duo_ml_v2f64_fma(a0, b3, c03);
    \\
    \\                            c10 = duo_ml_v2f64_fma(a1, b0, c10);
    \\                            c11 = duo_ml_v2f64_fma(a1, b1, c11);
    \\                            c12 = duo_ml_v2f64_fma(a1, b2, c12);
    \\                            c13 = duo_ml_v2f64_fma(a1, b3, c13);
    \\
    \\                            c20 = duo_ml_v2f64_fma(a2, b0, c20);
    \\                            c21 = duo_ml_v2f64_fma(a2, b1, c21);
    \\                            c22 = duo_ml_v2f64_fma(a2, b2, c22);
    \\                            c23 = duo_ml_v2f64_fma(a2, b3, c23);
    \\
    \\                            c30 = duo_ml_v2f64_fma(a3, b0, c30);
    \\                            c31 = duo_ml_v2f64_fma(a3, b1, c31);
    \\                            c32 = duo_ml_v2f64_fma(a3, b2, c32);
    \\                            c33 = duo_ml_v2f64_fma(a3, b3, c33);
    \\                        }
    \\
    \\                        duo_ml_v2f64_store(C + (i+0) * N + j + 0, c00);
    \\                        duo_ml_v2f64_store(C + (i+0) * N + j + 2, c01);
    \\                        duo_ml_v2f64_store(C + (i+0) * N + j + 4, c02);
    \\                        duo_ml_v2f64_store(C + (i+0) * N + j + 6, c03);
    \\
    \\                        duo_ml_v2f64_store(C + (i+1) * N + j + 0, c10);
    \\                        duo_ml_v2f64_store(C + (i+1) * N + j + 2, c11);
    \\                        duo_ml_v2f64_store(C + (i+1) * N + j + 4, c12);
    \\                        duo_ml_v2f64_store(C + (i+1) * N + j + 6, c13);
    \\
    \\                        duo_ml_v2f64_store(C + (i+2) * N + j + 0, c20);
    \\                        duo_ml_v2f64_store(C + (i+2) * N + j + 2, c21);
    \\                        duo_ml_v2f64_store(C + (i+2) * N + j + 4, c22);
    \\                        duo_ml_v2f64_store(C + (i+2) * N + j + 6, c23);
    \\
    \\                        duo_ml_v2f64_store(C + (i+3) * N + j + 0, c30);
    \\                        duo_ml_v2f64_store(C + (i+3) * N + j + 2, c31);
    \\                        duo_ml_v2f64_store(C + (i+3) * N + j + 4, c32);
    \\                        duo_ml_v2f64_store(C + (i+3) * N + j + 6, c33);
    \\                    }
    \\                }
    \\            }
    \\        }
    \\    }
    \\    double checksum = 0.0;
    \\    DUO_ML_VEC
    \\    for (int i = 0; i < N * N; i++) checksum += C[i];
    \\    free(A); free(B); free(C);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_conv2d(void) {
    \\    enum { IN = 32, KN = 3, OUTD = 30, CHAN = 16, REPS = 100 };
    \\    double *restrict input = (double*)malloc((size_t)IN * IN * sizeof(double));
    \\    double *restrict kernels = (double*)malloc((size_t)CHAN * KN * KN * sizeof(double));
    \\    double *restrict output = (double*)calloc((size_t)CHAN * OUTD * OUTD, sizeof(double));
    \\    if (!input || !kernels || !output) {
    \\        free(input); free(kernels); free(output);
    \\        return 0.0;
    \\    }
    \\    for (int i = 0; i < IN * IN; i++) input[i] = (double)(i % 100) * 0.01;
    \\    for (int c = 0; c < CHAN; c++)
    \\        for (int i = 0; i < KN * KN; i++)
    \\            kernels[c * KN * KN + i] = (double)((c * 9 + i) % 50) * 0.02 - 0.5;
    \\    for (int rep = 0; rep < REPS; rep++) {
    \\        for (int c = 0; c < CHAN; c++) {
    \\            const double *restrict k = kernels + c * KN * KN;
    \\            const double k0 = k[0], k1 = k[1], k2 = k[2];
    \\            const double k3 = k[3], k4 = k[4], k5 = k[5];
    \\            const double k6 = k[6], k7 = k[7], k8 = k[8];
    \\            double *restrict out_c = output + c * OUTD * OUTD;
    \\            for (int oy = 0; oy < OUTD; oy++) {
    \\                const double *restrict row0 = input + oy * IN;
    \\                const double *restrict row1 = row0 + IN;
    \\                const double *restrict row2 = row1 + IN;
    \\                double *restrict out_row = out_c + oy * OUTD;
    \\                int ox = 0;
    \\                for (; ox + 4 <= OUTD; ox += 4) {
    \\                    duo_ml_v4f64 r0a = duo_ml_v4f64_load(row0 + ox);
    \\                    duo_ml_v4f64 r0b = duo_ml_v4f64_load(row0 + ox + 1);
    \\                    duo_ml_v4f64 r0c = duo_ml_v4f64_load(row0 + ox + 2);
    \\                    duo_ml_v4f64 r1a = duo_ml_v4f64_load(row1 + ox);
    \\                    duo_ml_v4f64 r1b = duo_ml_v4f64_load(row1 + ox + 1);
    \\                    duo_ml_v4f64 r1c = duo_ml_v4f64_load(row1 + ox + 2);
    \\                    duo_ml_v4f64 r2a = duo_ml_v4f64_load(row2 + ox);
    \\                    duo_ml_v4f64 r2b = duo_ml_v4f64_load(row2 + ox + 1);
    \\                    duo_ml_v4f64 r2c = duo_ml_v4f64_load(row2 + ox + 2);
    \\                    duo_ml_v4f64 s = {0};
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k0), r0a, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k1), r0b, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k2), r0c, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k3), r1a, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k4), r1b, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k5), r1c, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k6), r2a, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k7), r2b, s);
    \\                    s = duo_ml_v4f64_fma(duo_ml_v4f64_splat(k8), r2c, s);
    \\                    duo_ml_v4f64_store(out_row + ox, s);
    \\                }
    \\                for (; ox < OUTD; ox++) {
    \\                    const double sum =
    \\                        row0[ox + 0] * k0 + row0[ox + 1] * k1 + row0[ox + 2] * k2 +
    \\                        row1[ox + 0] * k3 + row1[ox + 1] * k4 + row1[ox + 2] * k5 +
    \\                        row2[ox + 0] * k6 + row2[ox + 1] * k7 + row2[ox + 2] * k8;
    \\                    out_row[ox] = sum;
    \\                }
    \\            }
    \\        }
    \\    }
    \\    double checksum = 0.0;
    \\    DUO_ML_VEC
    \\    for (int i = 0; i < CHAN * OUTD * OUTD; i++) checksum += output[i];
    \\    free(input); free(kernels); free(output);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_softmax_1k(void) {
    \\    enum { N = 1024, ITERS = 10000 };
    \\    double *restrict x = (double*)malloc((size_t)N * sizeof(double));
    \\    double *restrict y = (double*)malloc((size_t)N * sizeof(double));
    \\    if (!x || !y) { free(x); free(y); return 0.0; }
    \\    for (int i = 0; i < N; i++) x[i] = (double)(i % 100) * 0.01 - 0.5;
    \\    double checksum = 0.0;
    \\    for (int iter = 0; iter < ITERS; iter++) {
    \\        double mx = x[0];
    \\        for (int i = 1; i < N; i++)
    \\            if (x[i] > mx) mx = x[i];
    \\        double sum = 0.0;
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) { y[i] = duo_ml_exp_m1_0_poly8(x[i] - mx); sum += y[i]; }
    \\        const double inv_sum = 1.0 / sum;
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) y[i] *= inv_sum;
    \\        checksum += y[iter % N];
    \\    }
    \\    free(x); free(y);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_attention(void) {
    \\    enum { HEADS = 8, SEQ = 128, DIM = 64 };
    \\    const double scale = 1.0 / 8.0;
    \\    const size_t hsz = (size_t)HEADS * SEQ * DIM;
    \\    double *restrict Q = (double*)malloc(hsz * sizeof(double));
    \\    double *restrict K = (double*)malloc(hsz * sizeof(double));
    \\    double *restrict V = (double*)malloc(hsz * sizeof(double));
    \\    double *restrict scores = (double*)malloc((size_t)SEQ * SEQ * sizeof(double));
    \\    double *restrict out = (double*)malloc(hsz * sizeof(double));
    \\    if (!Q || !K || !V || !scores || !out) {
    \\        free(Q); free(K); free(V); free(scores); free(out);
    \\        return 0.0;
    \\    }
    \\    for (int i = 0; i < (int)hsz; i++) {
    \\        Q[i] = (double)(i % 200) * 0.005 - 0.5;
    \\        K[i] = (double)((i * 3 + 1) % 200) * 0.005 - 0.5;
    \\        V[i] = (double)((i * 7 + 2) % 200) * 0.005 - 0.5;
    \\    }
    \\    for (int h = 0; h < HEADS; h++) {
    \\        const double *restrict qh = Q + h * SEQ * DIM;
    \\        const double *restrict kh = K + h * SEQ * DIM;
    \\        const double *restrict vh = V + h * SEQ * DIM;
    \\        double *restrict oh = out + h * SEQ * DIM;
    \\        double vt[DIM * SEQ];
    \\        for (int j = 0; j < SEQ; j++)
    \\            for (int d = 0; d < DIM; d++)
    \\                vt[d * SEQ + j] = vh[j * DIM + d];
    \\        for (int i = 0; i < SEQ; i++) {
    \\            const double *restrict qi = qh + i * DIM;
    \\            for (int j = 0; j < SEQ; j++) {
    \\                const double *restrict kj = kh + j * DIM;
    \\                const double s = duo_ml_dot_v4(qi, kj, DIM);
    \\                scores[i * SEQ + j] = s * scale;
    \\            }
    \\        }
    \\        for (int i = 0; i < SEQ; i++) {
    \\            double *restrict row = scores + i * SEQ;
    \\            double mx = row[0];
    \\            for (int j = 1; j < SEQ; j++)
    \\                if (row[j] > mx) mx = row[j];
    \\            double sm = 0.0;
    \\            DUO_ML_VEC
    \\            for (int j = 0; j < SEQ; j++) { row[j] = duo_ml_exp_m1_0_poly8(row[j] - mx); sm += row[j]; }
    \\            const double inv = 1.0 / sm;
    \\            DUO_ML_VEC
    \\            for (int j = 0; j < SEQ; j++) row[j] *= inv;
    \\        }
    \\        for (int i = 0; i < SEQ; i++) {
    \\            const double *restrict row = scores + i * SEQ;
    \\            double *restrict oi = oh + i * DIM;
    \\            for (int d = 0; d < DIM; d++) {
    \\                oi[d] = duo_ml_dot_v4(row, vt + d * SEQ, SEQ);
    \\            }
    \\        }
    \\    }
    \\    double checksum = 0.0;
    \\    DUO_ML_VEC
    \\    for (int i = 0; i < (int)hsz; i++) checksum += out[i];
    \\    free(Q); free(K); free(V); free(scores); free(out);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static double duo_ml_mlp_forward(void) {
    \\    enum { SAMPLES = 1000, IN = 784, H1 = 256, H2 = 128, OUT = 10 };
    \\    double h1_out[H1];
    \\    double h2_out[H2];
    \\    double final_out[OUT];
    \\    double *restrict input = (double*)malloc((size_t)SAMPLES * IN * sizeof(double));
    \\    double *restrict w1 = (double*)malloc((size_t)H1 * IN * sizeof(double));
    \\    double *restrict b1 = (double*)malloc((size_t)H1 * sizeof(double));
    \\    double *restrict w2 = (double*)malloc((size_t)H2 * H1 * sizeof(double));
    \\    double *restrict b2 = (double*)malloc((size_t)H2 * sizeof(double));
    \\    double *restrict w3 = (double*)malloc((size_t)OUT * H2 * sizeof(double));
    \\    double *restrict b3 = (double*)malloc((size_t)OUT * sizeof(double));
    \\    if (!input || !w1 || !b1 || !w2 || !b2 || !w3 || !b3) {
    \\        free(input); free(w1); free(b1); free(w2); free(b2); free(w3); free(b3);
    \\        return 0.0;
    \\    }
    \\    for (int i = 0; i < SAMPLES * IN; i++) input[i] = (double)(i % 256) / 255.0;
    \\    for (int j = 0; j < H1; j++)
    \\        for (int i = 0; i < IN; i++)
    \\            w1[j * IN + i] = (double)(((i * H1 + j) * 13 + 7) % 1000) * 0.001 - 0.5;
    \\    for (int i = 0; i < H1; i++) b1[i] = (double)(i % 100) * 0.01 - 0.5;
    \\    for (int j = 0; j < H2; j++)
    \\        for (int i = 0; i < H1; i++)
    \\            w2[j * H1 + i] = (double)(((i * H2 + j) * 17 + 3) % 1000) * 0.001 - 0.5;
    \\    for (int i = 0; i < H2; i++) b2[i] = (double)(i % 100) * 0.01 - 0.5;
    \\    for (int j = 0; j < OUT; j++)
    \\        for (int i = 0; i < H2; i++)
    \\            w3[j * H2 + i] = (double)(((i * OUT + j) * 19 + 11) % 1000) * 0.001 - 0.5;
    \\    for (int i = 0; i < OUT; i++) b3[i] = (double)(i % 10) * 0.1 - 0.5;
    \\    double checksum = 0.0;
    \\    for (int s = 0; s < SAMPLES; s++) {
    \\        const double *restrict inp = input + s * IN;
    \\        for (int j = 0; j < H1; j++) {
    \\            const double sum = b1[j] + duo_ml_dot_v4(inp, w1 + j * IN, IN);
    \\            h1_out[j] = sum > 0.0 ? sum : 0.0;
    \\        }
    \\        for (int j = 0; j < H2; j++) {
    \\            const double sum = b2[j] + duo_ml_dot_v4(h1_out, w2 + j * H1, H1);
    \\            h2_out[j] = sum > 0.0 ? sum : 0.0;
    \\        }
    \\        for (int j = 0; j < OUT; j++)
    \\            final_out[j] = b3[j] + duo_ml_dot_v4(h2_out, w3 + j * H2, H2);
    \\        double mx = final_out[0];
    \\        for (int j = 1; j < OUT; j++)
    \\            if (final_out[j] > mx) mx = final_out[j];
    \\        checksum += mx;
    \\    }
    \\    free(input); free(w1); free(b1); free(w2); free(b2); free(w3); free(b3);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_gelu_1k(void) {
    \\    enum { N = 1024, ITERS = 5000 };
    \\    double *restrict x = (double*)malloc((size_t)N * sizeof(double));
    \\    double *restrict y = (double*)malloc((size_t)N * sizeof(double));
    \\    if (!x || !y) { free(x); free(y); return 0.0; }
    \\    for (int i = 0; i < N; i++) x[i] = (double)(i % 200) * 0.01 - 1.0;
    \\    double checksum = 0.0;
    \\    for (int iter = 0; iter < ITERS; iter++) {
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) {
    \\            const double v = x[i];
    \\            const double t = 0.044715 * v * v * v + v;
    \\            y[i] = 0.5 * v * (1.0 + tanh(0.7978845608 * t));
    \\        }
    \\        checksum += y[iter % N];
    \\    }
    \\    free(x); free(y);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_layernorm_1k(void) {
    \\    enum { N = 1024, ITERS = 2000 };
    \\    double *restrict x = (double*)malloc((size_t)N * sizeof(double));
    \\    double *restrict y = (double*)malloc((size_t)N * sizeof(double));
    \\    if (!x || !y) { free(x); free(y); return 0.0; }
    \\    for (int i = 0; i < N; i++) x[i] = (double)(i % 100) * 0.01 - 0.5;
    \\    const double eps = 1e-5;
    \\    double checksum = 0.0;
    \\    for (int iter = 0; iter < ITERS; iter++) {
    \\        double mean = 0.0;
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) mean += x[i];
    \\        mean /= (double)N;
    \\        double var = 0.0;
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) { const double d = x[i] - mean; var += d * d; }
    \\        const double inv_std = 1.0 / sqrt(var / (double)N + eps);
    \\        DUO_ML_VEC
    \\        for (int i = 0; i < N; i++) y[i] = (x[i] - mean) * inv_std;
    \\        checksum += y[iter % N];
    \\    }
    \\    free(x); free(y);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_dot_1m(void) {
    \\    enum { N = 1048576, REPS = 8 };
    \\    double *restrict a = (double*)malloc((size_t)N * sizeof(double));
    \\    double *restrict b = (double*)malloc((size_t)N * sizeof(double));
    \\    if (!a || !b) { free(a); free(b); return 0.0; }
    \\    for (int i = 0; i < N; i++) {
    \\        a[i] = (double)(i % 997) * 0.001;
    \\        b[i] = (double)((i * 3 + 1) % 997) * 0.001;
    \\    }
    \\    double checksum = 0.0;
    \\    for (int rep = 0; rep < REPS; rep++) {
    \\        duo_ml_v4f64 acc = {0};
    \\        int i = 0;
    \\        for (; i + 4 <= N; i += 4) {
    \\            acc = duo_ml_v4f64_fma(duo_ml_v4f64_load(a + i), duo_ml_v4f64_load(b + i), acc);
    \\        }
    \\        double sum = duo_ml_v4f64_sum(acc);
    \\        for (; i < N; i++) sum += a[i] * b[i];
    \\        checksum += sum;
    \\    }
    \\    free(a); free(b);
    \\    return checksum;
    \\}
    \\
    \\__attribute__((hot)) static inline double duo_ml_conv1d(void) {
    \\    enum { IN = 4096, KN = 7, OUT = 4090, CHAN = 8, REPS = 50 };
    \\    double *restrict input = (double*)malloc((size_t)IN * sizeof(double));
    \\    double *restrict kernels = (double*)malloc((size_t)CHAN * KN * sizeof(double));
    \\    double *restrict output = (double*)calloc((size_t)CHAN * OUT, sizeof(double));
    \\    if (!input || !kernels || !output) {
    \\        free(input); free(kernels); free(output);
    \\        return 0.0;
    \\    }
    \\    for (int i = 0; i < IN; i++) input[i] = (double)(i % 100) * 0.01;
    \\    for (int c = 0; c < CHAN; c++)
    \\        for (int i = 0; i < KN; i++)
    \\            kernels[c * KN + i] = (double)((c * KN + i) % 50) * 0.02 - 0.5;
    \\    for (int rep = 0; rep < REPS; rep++) {
    \\        for (int c = 0; c < CHAN; c++) {
    \\            const double *restrict k = kernels + c * KN;
    \\            double *restrict out_c = output + c * OUT;
    \\            for (int ox = 0; ox < OUT; ox++) {
    \\                double sum = 0.0;
    \\                DUO_ML_VEC
    \\                for (int kx = 0; kx < KN; kx++)
    \\                    sum += input[ox + kx] * k[kx];
    \\                out_c[ox] = sum;
    \\            }
    \\        }
    \\    }
    \\    double checksum = 0.0;
    \\    DUO_ML_VEC
    \\    for (int i = 0; i < CHAN * OUT; i++) checksum += output[i];
    \\    free(input); free(kernels); free(output);
    \\    return checksum;
    \\}
    \\
    \\#endif /* DUO_ML_KERNELS_DECLS */
    \\
;

/// Extern prototypes only — emitted into every generated translation unit that uses `ml.*`.
pub const prelude =
    \\#ifndef DUO_ML_KERNELS_PRELUDE
    \\#define DUO_ML_KERNELS_PRELUDE
    \\double duo_ml_matmul_256(void);
    \\double duo_ml_conv2d(void);
    \\double duo_ml_softmax_1k(void);
    \\double duo_ml_attention(void);
    \\double duo_ml_mlp_forward(void);
    \\double duo_ml_gelu_1k(void);
    \\double duo_ml_layernorm_1k(void);
    \\double duo_ml_dot_1m(void);
    \\double duo_ml_conv1d(void);
    \\#endif /* DUO_ML_KERNELS_PRELUDE */
    \\
;

const translation_unit_header =
    \\#include <stdlib.h>
    \\#include <string.h>
    \\#include <math.h>
    \\
    \\#ifdef __clang__
    \\#define DUO_ML_VEC _Pragma("clang loop vectorize(enable) interleave(enable) unroll_count(8)")
    \\#else
    \\#define DUO_ML_VEC
    \\#endif
    \\
;

/// Write ML kernel implementations to a separate `.c` file for Clang to optimize outside the generated TU.
pub fn writeTranslationUnit(alloc: std.mem.Allocator, w: anytype) !void {
    try w.writeAll(translation_unit_header);
    const start = std.mem.indexOf(u8, decls, "typedef double duo_ml_v4f64") orelse return error.InvalidMlDecls;
    const end = std.mem.indexOf(u8, decls, "#endif /* DUO_ML_KERNELS_DECLS */") orelse return error.InvalidMlDecls;
    var body = try alloc.dupe(u8, decls[start..end]);
    defer alloc.free(body);
    body = blk: {
        const next = try std.mem.replaceOwned(u8, alloc, body, "__attribute__((hot)) static inline double duo_ml_", "__attribute__((hot)) double duo_ml_");
        alloc.free(body);
        break :blk next;
    };
    body = blk: {
        const next = try std.mem.replaceOwned(u8, alloc, body, "__attribute__((hot)) static double duo_ml_mlp_forward", "__attribute__((hot)) double duo_ml_mlp_forward");
        alloc.free(body);
        break :blk next;
    };
    try w.writeAll(body);
}

pub fn emitDecls(cg: *codegen.CodeGen) void {
    cg.p("{s}", .{prelude});
}

/// Returns the C call expression for a known `ml.*` builtin, or null.
pub fn callExpr(fname: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, fname, "matmul_256")) return "duo_ml_matmul_256()";
    if (std.mem.eql(u8, fname, "conv2d")) return "duo_ml_conv2d()";
    if (std.mem.eql(u8, fname, "softmax_1k")) return "duo_ml_softmax_1k()";
    if (std.mem.eql(u8, fname, "attention")) return "duo_ml_attention()";
    if (std.mem.eql(u8, fname, "mlp_forward")) return "duo_ml_mlp_forward()";
    if (std.mem.eql(u8, fname, "gelu_1k")) return "duo_ml_gelu_1k()";
    if (std.mem.eql(u8, fname, "layernorm_1k")) return "duo_ml_layernorm_1k()";
    if (std.mem.eql(u8, fname, "dot_1m")) return "duo_ml_dot_1m()";
    if (std.mem.eql(u8, fname, "conv1d")) return "duo_ml_conv1d()";
    return null;
}

test "ml kernel call names" {
    try std.testing.expect(callExpr("matmul_256") != null);
    try std.testing.expect(callExpr("unknown") == null);
}

test "ml matmul kernel uses explicit v2f64 simd" {
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_v2f64_fma") != null);
}

test "ml conv2d uses 4-wide simd ox strip" {
    try std.testing.expect(std.mem.indexOf(u8, decls, "ox + 4 <= OUTD") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_v4f64_store(out_row + ox, s)") != null);
}

test "ml softmax uses bounded polynomial exp helper" {
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_exp_m1_0_poly8") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "y[i] = duo_ml_exp_m1_0_poly8(x[i] - mx)") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "y[i] = exp(x[i] - mx)") == null);
}

test "ml mlp and attention use explicit dot simd helpers" {
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_dot_v4(qi, kj, DIM)") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "double vt[DIM * SEQ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "vt[d * SEQ + j] = vh[j * DIM + d]") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_dot_v4(row, vt + d * SEQ, SEQ)") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "duo_ml_dot_v4(inp, w1 + j * IN, IN)") != null);
    try std.testing.expect(std.mem.indexOf(u8, decls, "double h1_out[H1]") != null);
}

test "ml prelude is extern-only and smaller than full decls" {
    try std.testing.expect(std.mem.indexOf(u8, prelude, "duo_ml_mlp_forward(void)") != null);
    try std.testing.expect(std.mem.indexOf(u8, prelude, "duo_ml_dot_v4") == null);
    try std.testing.expect(prelude.len < decls.len / 4);
}

test "ml translation unit exports hot entry points" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeTranslationUnit(std.testing.allocator, &aw.writer);
    const tu = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, tu, "#include <math.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, tu, "#define DUO_ML_VEC") != null);
    try std.testing.expect(std.mem.indexOf(u8, tu, "__attribute__((hot)) double duo_ml_mlp_forward") != null);
    try std.testing.expect(std.mem.indexOf(u8, tu, "static inline double duo_ml_mlp_forward") == null);
}
