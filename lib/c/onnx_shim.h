/*
 * onnx_shim.h — C wrapper for ONNX Runtime API, simplified for duo @ffi.
 *
 * The ONNX Runtime C API uses a function-pointer-table pattern
 * (OrtGetApiBase() -> OrtApi* with ~200 function pointers).  Duo's @ffi
 * cannot dereference C structs, so this shim exposes a small set of
 * plain C functions that hide the OrtApi/OrtEnv/OrtSession bookkeeping.
 *
 * Each duo_onnx_* function is a thin wrapper returning simple types:
 *   - int      return codes (0 = success, negative = error)
 *   - void*    opaque session handles
 *   - char*    name buffers (caller-allocated)
 *   - int64_t* dimension buffers (caller-allocated)
 *
 * Compile:
 *   cc -c onnx_shim.c -o onnx_shim.o
 * Link with:
 *   -lonnxruntime  (and the shim object)
 *
 * Build in duo:
 *   duo compile myapp.id --link onnxruntime --link onnx_shim.c
 */

#ifndef ONNX_SHIM_H
#define ONNX_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * duo_onnx_init: create an OrtEnv + OrtSession from a model file.
 *
 * Returns: opaque session handle (void*), or NULL on error.
 *          The caller must release it with duo_onnx_close().
 */
void* duo_onnx_init(const char* model_path);

/*
 * duo_onnx_run: run inference on a single input/output pair.
 *
 *   session      — handle from duo_onnx_init
 *   input_name   — NUL-terminated input tensor name
 *   input_data   — float array (row-major, flattened)
 *   input_len    — number of float elements in input_data
 *   output_name  — NUL-terminated output tensor name
 *   output_data  — caller-allocated float buffer for results
 *   output_len   — [in] capacity of output_data in floats;
 *                  [out] actual number of floats written
 *
 * Returns: 0 on success, negative on error.
 */
int duo_onnx_run(void* session,
                 const char* input_name,
                 const float* input_data,
                 size_t input_len,
                 const char* output_name,
                 float* output_data,
                 size_t* output_len);

/*
 * duo_onnx_close: release a session handle and associated resources.
 * Passing NULL is safe.
 */
void duo_onnx_close(void* session);

/*
 * duo_onnx_input_count: number of input tensors in the model.
 * Returns: count, or -1 on error.
 */
int duo_onnx_input_count(void* session);

/*
 * duo_onnx_output_count: number of output tensors in the model.
 * Returns: count, or -1 on error.
 */
int duo_onnx_output_count(void* session);

/*
 * duo_onnx_input_name: write the name of input #idx into buf.
 *   buf     — caller-allocated character buffer
 *   buf_len — size of buf in bytes
 * Returns: number of bytes written (excluding NUL), or negative on error.
 *          If buf_len is too small, returns -1.
 */
int duo_onnx_input_name(void* session, int idx, char* buf, int buf_len);

/*
 * duo_onnx_output_name: write the name of output #idx into buf.
 *   buf     — caller-allocated character buffer
 *   buf_len — size of buf in bytes
 * Returns: number of bytes written (excluding NUL), or negative on error.
 *          If buf_len is too small, returns -1.
 */
int duo_onnx_output_name(void* session, int idx, char* buf, int buf_len);

/*
 * duo_onnx_input_shape: write dimension sizes of input #idx into dims.
 *   dims     — caller-allocated int64_t array
 *   max_dims — capacity of dims (number of int64_t slots)
 * Returns: number of dimensions written, or negative on error.
 *          If max_dims is too small, returns -1.
 */
int duo_onnx_input_shape(void* session, int idx, int64_t* dims, int max_dims);

/*
 * duo_onnx_output_shape: write dimension sizes of output #idx into dims.
 *   dims     — caller-allocated int64_t array
 *   max_dims — capacity of dims (number of int64_t slots)
 * Returns: number of dimensions written, or negative on error.
 *          If max_dims is too small, returns -1.
 */
int duo_onnx_output_shape(void* session, int idx, int64_t* dims, int max_dims);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ONNX_SHIM_H */