/*
 * onnx_shim.c — C implementation wrapping the ONNX Runtime C API.
 *
 * The ONNX Runtime C API (onnxruntime_c_api.h) exposes everything via a
 * single OrtApi* struct returned by OrtGetApiBase().  That struct contains
 * ~200 function pointers (CreateEnv, CreateSession, Run, etc.).  Duo's
 * @ffi cannot dereference C struct fields, so this file translates those
 * calls into a handful of flat C functions.
 *
 * Build:
 *   cc -c onnx_shim.c -o onnx_shim.o -I<onnxruntime include dir>
 * Link:
 *   -lonnxruntime
 *
 * Or (if your build system supports it):
 *   duo compile myapp.id --link onnxruntime --link onnx_shim.c \
 *     --cflags -I<onnxruntime include dir>
 */

#include "onnx_shim.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── ONNX Runtime C API header ──────────────────────────────────────── */

#ifdef ONNXRUNTIME_INCLUDE_DIR
#  include ONNXRUNTIME_INCLUDE_DIR "/onnxruntime_c_api.h"
#else
/*
 * If onnxruntime_c_api.h is in the default include path, this works.
 * Otherwise define ONNXRUNTIME_INCLUDE_DIR via -D when compiling the
 * shim, e.g. -DONNXRUNTIME_INCLUDE_DIR=\"/usr/local/include/onnxruntime\".
 */
#  include "onnxruntime_c_api.h"
#endif

/* ── Internal session context ──────────────────────────────────────── */

/*
 * Each duo_onnx_init() call produces one of these.  The void* returned
 * to the caller points to a heap-allocated DuoOnnxSession.
 */
typedef struct {
    OrtEnv*         env;
    OrtSession*     session;
    OrtAllocator*   allocator;
    const OrtApi*   api;
} DuoOnnxSession;

/* ── Helper: get the OrtApi pointer once ───────────────────────────── */

static const OrtApi* duo_get_ort_api(void) {
    OrtGetApiBaseFn* base_fn = OrtGetApiBase;
    if (base_fn == NULL) return NULL;
    const OrtApiBase* base = base_fn();
    if (base == NULL) return NULL;
    return base->GetApi(base);
}

/* ── duo_onnx_init ─────────────────────────────────────────────────── */

void* duo_onnx_init(const char* model_path) {
    if (model_path == NULL) return NULL;

    const OrtApi* api = duo_get_ort_api();
    if (api == NULL) return NULL;

    DuoOnnxSession* ctx = (DuoOnnxSession*)calloc(1, sizeof(DuoOnnxSession));
    if (ctx == NULL) return NULL;
    ctx->api = api;

    /* Create the environment.  We use a fixed name "duo_onnx_env".
     * Threading level ORT_LOGGING_LEVEL_WARNING = 2.
     */
    OrtStatus* status = api->CreateEnv(2, "duo_onnx_env", &ctx->env);
    if (status != NULL) {
        api->ReleaseStatus(status);
        free(ctx);
        return NULL;
    }

    /* Create the session options, then the session.
     * We use default options (single-threaded, no providers specified
     * beyond the default CPU provider).
     */
    OrtSessionOptions* session_options = NULL;
    status = api->CreateSessionOptions(&session_options);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseEnv(ctx->env);
        free(ctx);
        return NULL;
    }

    status = api->CreateSession(ctx->env, model_path, session_options, &ctx->session);
    api->ReleaseSessionOptions(session_options);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseEnv(ctx->env);
        free(ctx);
        return NULL;
    }

    /* Get the default allocator (used for querying input/output names
     * and shapes).
     */
    status = api->GetAllocatorWithDefaultOptions(&ctx->allocator);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseSession(ctx->session);
        api->ReleaseEnv(ctx->env);
        free(ctx);
        return NULL;
    }

    return (void*)ctx;
}

/* ── duo_onnx_close ────────────────────────────────────────────────── */

void duo_onnx_close(void* session) {
    if (session == NULL) return;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;

    if (ctx->api != NULL) {
        if (ctx->session != NULL) {
            ctx->api->ReleaseSession(ctx->session);
        }
        if (ctx->env != NULL) {
            ctx->api->ReleaseEnv(ctx->env);
        }
    }
    free(ctx);
}

/* ── duo_onnx_run ──────────────────────────────────────────────────── */

int duo_onnx_run(void* session,
                 const char* input_name,
                 const float* input_data,
                 size_t input_len,
                 const char* output_name,
                 float* output_data,
                 size_t* output_len) {
    if (session == NULL || input_name == NULL || input_data == NULL ||
        output_name == NULL || output_data == NULL || output_len == NULL) {
        return -1;
    }

    DuoOnnxSession* ctx = (DuoOnnxSession*)session;
    const OrtApi* api = ctx->api;
    if (api == NULL) return -2;

    /* Query the input tensor info to build the input tensor. */
    OrtTypeInfo* input_type_info = NULL;
    OrtTensorTypeAndShapeInfo* input_tensor_info = NULL;
    size_t input_dim_count = 0;
    int64_t input_dims[8]; /* most models have ≤ 8 dimensions */

    OrtStatus* status = api->SessionGetInputTypeInfo(ctx->session, 0, &input_type_info);
    if (status != NULL) { api->ReleaseStatus(status); return -3; }

    status = api->CastTypeInfoToTensorInfo(input_type_info, &input_tensor_info);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTypeInfo(input_type_info);
        return -4;
    }

    status = api->GetDimensionsCount(input_tensor_info, &input_dim_count, 8);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTensorTypeAndShapeInfo(input_tensor_info);
        api->ReleaseTypeInfo(input_type_info);
        return -5;
    }

    status = api->GetDimensions(input_tensor_info, input_dims, input_dim_count);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTensorTypeAndShapeInfo(input_tensor_info);
        api->ReleaseTypeInfo(input_type_info);
        return -6;
    }

    api->ReleaseTensorTypeAndShapeInfo(input_tensor_info);
    api->ReleaseTypeInfo(input_type_info);

    /* Determine the input element count from the dimensions.  Dynamic
     * dimensions (value -1) are replaced by 1, since the caller passes
     * the actual flattened length.
     */
    size_t computed_input_len = 1;
    for (size_t i = 0; i < input_dim_count; i++) {
        if (input_dims[i] > 0) {
            computed_input_len *= (size_t)input_dims[i];
        }
    }
    /* If we can't determine it from dims, trust the caller's input_len. */
    if (computed_input_len == 0 || computed_input_len != input_len) {
        computed_input_len = input_len;
    }

    /* Create the input tensor. */
    OrtValue* input_tensor = NULL;
    OrtMemoryInfo* memory_info = NULL;

    status = api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != NULL) { api->ReleaseStatus(status); return -7; }

    status = api->CreateTensorWithDataAsOrtValue(
        memory_info,
        (void*)input_data,
        computed_input_len * sizeof(float),
        input_dims,
        input_dim_count,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &input_tensor);
    api->ReleaseMemoryInfo(memory_info);
    if (status != NULL) { api->ReleaseStatus(status); return -8; }

    /* Query the output tensor info to determine the output size. */
    OrtTypeInfo* output_type_info = NULL;
    OrtTensorTypeAndShapeInfo* output_tensor_info = NULL;
    size_t output_dim_count = 0;
    int64_t output_dims[8];
    size_t output_element_count = 1;

    status = api->SessionGetOutputTypeInfo(ctx->session, 0, &output_type_info);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseValue(input_tensor);
        return -9;
    }

    status = api->CastTypeInfoToTensorInfo(output_type_info, &output_tensor_info);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTypeInfo(output_type_info);
        api->ReleaseValue(input_tensor);
        return -10;
    }

    status = api->GetDimensionsCount(output_tensor_info, &output_dim_count, 8);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTensorTypeAndShapeInfo(output_tensor_info);
        api->ReleaseTypeInfo(output_type_info);
        api->ReleaseValue(input_tensor);
        return -11;
    }

    status = api->GetDimensions(output_tensor_info, output_dims, output_dim_count);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseTensorTypeAndShapeInfo(output_tensor_info);
        api->ReleaseTypeInfo(output_type_info);
        api->ReleaseValue(input_tensor);
        return -12;
    }

    for (size_t i = 0; i < output_dim_count; i++) {
        if (output_dims[i] > 0) {
            output_element_count *= (size_t)output_dims[i];
        }
    }

    api->ReleaseTensorTypeAndShapeInfo(output_tensor_info);
    api->ReleaseTypeInfo(output_type_info);

    /* Check output buffer capacity. */
    if (*output_len < output_element_count) {
        api->ReleaseValue(input_tensor);
        *output_len = output_element_count; /* report needed size */
        return -13;
    }

    /* Run the model. */
    const char* input_names[1] = { input_name };
    const char* output_names[1] = { output_name };
    OrtValue* output_tensor = NULL;

    status = api->Run(
        ctx->session,
        NULL, /* run options (default) */
        input_names,
        &input_tensor,
        1,
        output_names,
        1,
        &output_tensor);

    api->ReleaseValue(input_tensor);
    if (status != NULL) {
        api->ReleaseStatus(status);
        return -14;
    }

    /* Copy output tensor data to caller's buffer. */
    float* output_tensor_data = NULL;
    status = api->GetTensorMutableData(output_tensor, (void**)&output_tensor_data);
    if (status != NULL) {
        api->ReleaseStatus(status);
        api->ReleaseValue(output_tensor);
        return -15;
    }

    memcpy(output_data, output_tensor_data, output_element_count * sizeof(float));
    *output_len = output_element_count;

    api->ReleaseValue(output_tensor);
    return 0;
}

/* ── duo_onnx_input_count ──────────────────────────────────────────── */

int duo_onnx_input_count(void* session) {
    if (session == NULL) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;
    size_t count = 0;
    OrtStatus* status = ctx->api->SessionGetInputCount(ctx->session, &count);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }
    return (int)count;
}

/* ── duo_onnx_output_count ─────────────────────────────────────────── */

int duo_onnx_output_count(void* session) {
    if (session == NULL) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;
    size_t count = 0;
    OrtStatus* status = ctx->api->SessionGetOutputCount(ctx->session, &count);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }
    return (int)count;
}

/* ── duo_onnx_input_name ───────────────────────────────────────────── */

int duo_onnx_input_name(void* session, int idx, char* buf, int buf_len) {
    if (session == NULL || buf == NULL || buf_len <= 0) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;

    char* name = NULL;
    OrtStatus* status = ctx->api->SessionGetInputName(
        ctx->session, (size_t)idx, ctx->allocator, &name);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }

    size_t len = strlen(name);
    if ((int)len >= buf_len) {
        ctx->api->AllocatorFree(ctx->allocator, name);
        return -3;
    }

    memcpy(buf, name, len);
    buf[len] = '\0';
    ctx->api->AllocatorFree(ctx->allocator, name);
    return (int)len;
}

/* ── duo_onnx_output_name ──────────────────────────────────────────── */

int duo_onnx_output_name(void* session, int idx, char* buf, int buf_len) {
    if (session == NULL || buf == NULL || buf_len <= 0) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;

    char* name = NULL;
    OrtStatus* status = ctx->api->SessionGetOutputName(
        ctx->session, (size_t)idx, ctx->allocator, &name);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }

    size_t len = strlen(name);
    if ((int)len >= buf_len) {
        ctx->api->AllocatorFree(ctx->allocator, name);
        return -3;
    }

    memcpy(buf, name, len);
    buf[len] = '\0';
    ctx->api->AllocatorFree(ctx->allocator, name);
    return (int)len;
}

/* ── duo_onnx_input_shape ──────────────────────────────────────────── */

int duo_onnx_input_shape(void* session, int idx, int64_t* dims, int max_dims) {
    if (session == NULL || dims == NULL || max_dims <= 0) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;

    OrtTypeInfo* type_info = NULL;
    OrtTensorTypeAndShapeInfo* tensor_info = NULL;
    size_t dim_count = 0;

    OrtStatus* status = ctx->api->SessionGetInputTypeInfo(
        ctx->session, (size_t)idx, &type_info);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }

    status = ctx->api->CastTypeInfoToTensorInfo(type_info, &tensor_info);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTypeInfo(type_info);
        return -3;
    }

    status = ctx->api->GetDimensionsCount(tensor_info, &dim_count, (size_t)max_dims);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -4;
    }

    if ((int)dim_count > max_dims) {
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -5;
    }

    status = ctx->api->GetDimensions(tensor_info, dims, dim_count);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -6;
    }

    ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
    ctx->api->ReleaseTypeInfo(type_info);
    return (int)dim_count;
}

/* ── duo_onnx_output_shape ─────────────────────────────────────────── */

int duo_onnx_output_shape(void* session, int idx, int64_t* dims, int max_dims) {
    if (session == NULL || dims == NULL || max_dims <= 0) return -1;
    DuoOnnxSession* ctx = (DuoOnnxSession*)session;

    OrtTypeInfo* type_info = NULL;
    OrtTensorTypeAndShapeInfo* tensor_info = NULL;
    size_t dim_count = 0;

    OrtStatus* status = ctx->api->SessionGetOutputTypeInfo(
        ctx->session, (size_t)idx, &type_info);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        return -2;
    }

    status = ctx->api->CastTypeInfoToTensorInfo(type_info, &tensor_info);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTypeInfo(type_info);
        return -3;
    }

    status = ctx->api->GetDimensionsCount(tensor_info, &dim_count, (size_t)max_dims);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -4;
    }

    if ((int)dim_count > max_dims) {
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -5;
    }

    status = ctx->api->GetDimensions(tensor_info, dims, dim_count);
    if (status != NULL) {
        ctx->api->ReleaseStatus(status);
        ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
        ctx->api->ReleaseTypeInfo(type_info);
        return -6;
    }

    ctx->api->ReleaseTensorTypeAndShapeInfo(tensor_info);
    ctx->api->ReleaseTypeInfo(type_info);
    return (int)dim_count;
}