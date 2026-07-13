// metal_compute.m — Metal compute helper for Duo GPU benchmark
// Compile: clang -c metal_compute.m -o metal_compute.o -framework Metal -framework Foundation -O2
//
// Exports C-linkage functions for Duo FFI:
//   metal_init()        — create device, command queue, compile kernel
//   metal_matmul(...)   — dispatch matmul on GPU
//   metal_sync()        — wait for GPU completion
//   metal_cleanup()     — release resources

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

// --- Metal state ---
static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_pipeline = nil;

// --- Embedded Metal shader source ---
static const char* kMatmulShader =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "\n"
    "kernel void matmul(device const float* A [[buffer(0)]],\n"
    "                   device const float* B [[buffer(1)]],\n"
    "                   device float* C [[buffer(2)]],\n"
    "                   constant int& M [[buffer(3)]],\n"
    "                   constant int& N [[buffer(4)]],\n"
    "                   constant int& K [[buffer(5)]],\n"
    "                   uint2 gid [[thread_position_in_grid]]) {\n"
    "    int row = gid.y;\n"
    "    int col = gid.x;\n"
    "    if (row < M && col < N) {\n"
    "        float sum = 0.0f;\n"
    "        for (int i = 0; i < K; i++)\n"
    "            sum += A[row * K + i] * B[i * N + col];\n"
    "        C[row * N + col] = sum;\n"
    "    }\n"
    "}\n";

// --- C-linkage API ---

int metal_init(void) {
    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (!g_device) {
            fprintf(stderr, "[metal] ERROR: No Metal device found\n");
            return -1;
        }

        g_queue = [g_device newCommandQueue];
        if (!g_queue) {
            fprintf(stderr, "[metal] ERROR: Failed to create command queue\n");
            return -1;
        }

        // Compile shader from source
        NSString *source = [NSString stringWithUTF8String:kMatmulShader];
        NSError *error = nil;
        id<MTLLibrary> library = [g_device newLibraryWithSource:source
                                                        options:nil
                                                          error:&error];
        if (!library) {
            fprintf(stderr, "[metal] ERROR: Shader compile failed: %s\n",
                    [[error localizedDescription] UTF8String]);
            return -1;
        }

        id<MTLFunction> func = [library newFunctionWithName:@"matmul"];
        if (!func) {
            fprintf(stderr, "[metal] ERROR: Function 'matmul' not found\n");
            return -1;
        }

        g_pipeline = [g_device newComputePipelineStateWithFunction:func error:&error];
        if (!g_pipeline) {
            fprintf(stderr, "[metal] ERROR: Pipeline creation failed: %s\n",
                    [[error localizedDescription] UTF8String]);
            return -1;
        }

        printf("[metal] Initialized: %s\n", [[g_device name] UTF8String]);
        return 0;
    }
}

int metal_matmul(const float* a, const float* b, float* c, int M, int N, int K) {
    @autoreleasepool {
        if (!g_device || !g_pipeline || !g_queue) {
            fprintf(stderr, "[metal] ERROR: Not initialized\n");
            return -1;
        }

        size_t sizeA = (size_t)M * K * sizeof(float);
        size_t sizeB = (size_t)K * N * sizeof(float);
        size_t sizeC = (size_t)M * N * sizeof(float);

        // Create buffers
        id<MTLBuffer> bufA = [g_device newBufferWithBytes:a length:sizeA options:MTLResourceStorageModeShared];
        id<MTLBuffer> bufB = [g_device newBufferWithBytes:b length:sizeB options:MTLResourceStorageModeShared];
        id<MTLBuffer> bufC = [g_device newBufferWithLength:sizeC options:MTLResourceStorageModeShared];

        // Dimension constants
        id<MTLBuffer> bufM = [g_device newBufferWithBytes:&M length:sizeof(int) options:MTLResourceStorageModeShared];
        id<MTLBuffer> bufN = [g_device newBufferWithBytes:&N length:sizeof(int) options:MTLResourceStorageModeShared];
        id<MTLBuffer> bufK = [g_device newBufferWithBytes:&K length:sizeof(int) options:MTLResourceStorageModeShared];

        // Encode compute command
        id<MTLCommandBuffer> cmdBuf = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];

        [encoder setComputePipelineState:g_pipeline];
        [encoder setBuffer:bufA offset:0 atIndex:0];
        [encoder setBuffer:bufB offset:0 atIndex:1];
        [encoder setBuffer:bufC offset:0 atIndex:2];
        [encoder setBuffer:bufM offset:0 atIndex:3];
        [encoder setBuffer:bufN offset:0 atIndex:4];
        [encoder setBuffer:bufK offset:0 atIndex:5];

        // Dispatch threads: N columns x M rows
        MTLSize gridSize = MTLSizeMake(N, M, 1);
        NSUInteger w = g_pipeline.threadExecutionWidth;
        NSUInteger h = g_pipeline.maxTotalThreadsPerThreadgroup / w;
        MTLSize threadgroupSize = MTLSizeMake(w, h, 1);

        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [encoder endEncoding];

        // Submit and wait
        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        // Copy result back
        memcpy(c, [bufC contents], sizeC);

        return 0;
    }
}

void metal_sync(void) {
    // Already synchronous in metal_matmul (waitUntilCompleted)
    // Provided for API completeness / future async dispatch
}

void metal_cleanup(void) {
    @autoreleasepool {
        g_pipeline = nil;
        g_queue = nil;
        g_device = nil;
        printf("[metal] Cleaned up\n");
    }
}
