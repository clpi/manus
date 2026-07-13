# Duo AI/ML-Native Language Design

## Shipping now (compiler + stdlib)

These syntax pieces are implemented today and exercised in `examples/ml_showcase.duo`:

| Syntax | Meaning |
|--------|---------|
| `nn { linear(…) relu … }` | Desugars to `(req "std.ml.nn").build(…)` |
| `a @ b` | Infix matmul → `duo_tensor_matmul(a, b)`; `Tensor[M,K] @ Tensor[K,N]` → `Tensor[M,N]`; K mismatch is a compile error when dims are known (numeric or symbolic names) |
| `a + b` (tensors) | Broadcast-compatible shapes infer result type; incompatible concrete shapes are compile errors; codegen uses `duo_tensor_add` |
| `Tensor[M, N, f32]` | Resolved as compile-time shape type (dims + dtype) |
| `fun f(): Tensor[…] … return …` | Return/tail expr checked against annotated tensor shape |
| `@grad(fn, wrt?)` | Desugars to `(req "std.ml.autodiff"):grad(…)` |
| `@device`, `@autodiff`, `@profile` | Directives on functions (see `src/directives.zig`) |
| `ml.matmul_256()` etc. | Native kernel intrinsics (see `src/ml_kernels.zig`) |

The sections below describe the full vision; not every item is implemented yet.

## The Thesis

Mojo tries to be "Python for ML but fast." Duo should be **"the language that makes hardware think in your terms."**

The key insight: ML workloads are fundamentally about **data flow through hardware** — tensors flowing through compute units, gradients flowing backward, batches flowing through pipelines. Most languages force you to think in terms of *code that manipulates data*. Duo should let you think in terms of *data that flows through transformations*, with the compiler mapping that flow onto hardware optimally.

## Aha Moments (Design Goals)

### Moment 1: "I wrote a neural network and it's faster than PyTorch"
```duo
model = nn {
  linear(784, 256)
  relu
  linear(256, 10)
  softmax
}

-- This single line compiles to fused CUDA/Metal/WASM kernels
output = model(input)
```

The `nn { }` block is a compile-time DSL that:
- Fuses adjacent operations (linear + relu → fused kernel)
- Selects hardware backend automatically
- Pre-allocates all memory
- Generates backward pass from forward definition
- Exports to ONNX/TensorRT/CoreML

### Moment 2: "I can see my data's shape at every step"
```duo
-- Types carry tensor dimensions at compile time
x: Tensor[batch, 784, f32]
w: Tensor[784, 256, f32]

-- Dimension mismatch is a COMPILE error, not a runtime crash
y = x @ w  -- y: Tensor[batch, 256, f32]

-- Broadcasting rules checked statically
bias: Tensor[256, f32]
z = y + bias  -- compiler verifies broadcast compatibility
```

### Moment 3: "I just wrote one function and it runs on GPU, TPU, and CPU"
```duo
@device(.auto)
fun matmul(a: Tensor[M,K,T], b: Tensor[K,N,T]): Tensor[M,N,T]
  -- This loop body is the SAME regardless of target
  for i, j in parallel(M, N)
    sum: T = 0
    @unroll(8)
    for k = 1, K
      sum += a[i,k] * b[k,j]
    end
    result[i,j] = sum
  end
end
```

Compiler generates:
- **CPU**: Tiled + vectorized (AVX-512/NEON)
- **CUDA**: Thread blocks + shared memory
- **Metal**: Threadgroup dispatch
- **WebGPU**: Compute shader
- **TPU**: XLA HLO

### Moment 4: "Training and inference are the same code"
```duo
@autodiff
fun loss(model, x, target)
  pred = model(x)
  cross_entropy(pred, target)
end

-- Forward pass
l = loss(model, batch_x, batch_y)

-- Backward pass is AUTOMATIC — generated at compile time
grads = @grad(loss, model)(model, batch_x, batch_y)

-- Update
model = optimizer.step(model, grads)
```

### Moment 5: "I can profile at the language level"
```duo
@profile
fun train_step(model, batch)
  -- After running, Duo reports:
  -- ┌─────────────────────────────────────────────┐
  -- │ train_step: 4.2ms                           │
  -- │   forward:  1.8ms  (GPU util: 94%)         │
  -- │   backward: 2.1ms  (memory: 2.1GB peak)    │
  -- │   update:   0.3ms  (bandwidth: 12GB/s)     │
  -- │   ⚠ linear_3: compute-bound (suggest fp16) │
  -- └─────────────────────────────────────────────┘
end
```

---

## Core Design: Hardware Abstraction Through Types

### The Device Type System

```duo
-- Devices are first-class compile-time values
cpu   = @device.cpu()
gpu0  = @device.gpu(0)
metal = @device.metal()
tpu   = @device.tpu()

-- Tensors carry their device
x: Tensor[1024, f32] @on(gpu0)

-- Transfer is explicit (no hidden copies)
x_cpu = x @to(cpu)

-- Operations inherit device from operands
y = x + 1.0  -- runs on gpu0 because x is there
```

### Memory Layout as Type Information

```duo
-- Layout is part of the type, not a runtime property
row_major: Tensor[M, N, f32, .row]     -- C-contiguous
col_major: Tensor[M, N, f32, .col]     -- Fortran-contiguous
blocked:   Tensor[M, N, f32, .block(32, 32)]  -- tiled for cache

-- The compiler refuses mismatched layouts in kernels that require specific patterns
@require_layout(.col)
fun cholesky(a: Tensor[N, N, f64])
```

### Precision as a Dial, Not a Rewrite

```duo
-- Same model, different precisions — zero code change
model_f32 = model @precision(f32)
model_f16 = model @precision(f16)
model_int8 = model @precision(i8, calibration=cal_data)
model_mixed = model @precision(.mixed, policy=amp_policy)

-- The compiler handles all casting, scaling, and loss-of-precision guards
```

---

## Innovative Features (Not in Any Other Language)

### 1. Compute Graphs as First-Class Values

```duo
-- A computation is data you can inspect, transform, optimize
graph = @trace(fun(x) model(x) end)

-- Fuse operations
graph = graph |> fuse_pointwise |> tile(32) |> vectorize

-- Lower to hardware
kernel = graph @compile(.cuda)

-- Execute
result = kernel(input)
```

This gives you PyTorch's eager mode ergonomics with TensorRT's optimization, at compile time.

### 2. Shape Polymorphism with Compile-Time Specialization

```duo
-- One definition, infinite specializations
fun attention(q: Tensor[B,H,S,D], k: Tensor[B,H,S,D], v: Tensor[B,H,S,D])
  scores = (q @ k.T) / @(math.sqrt(D))
  weights = softmax(scores, dim=-1)
  weights @ v
end

-- Compiler generates specialized versions for each shape it sees:
-- attention<1,8,128,64>  → flash attention (fits in SRAM)
-- attention<1,8,4096,64> → chunked attention (memory-efficient)
-- attention<32,8,128,64> → batched flash attention
```

### 3. Differentiable Everything (Beyond Gradients)

```duo
@differentiable
fun simulate(params, initial_state, steps)
  state = initial_state
  for t = 1, steps
    state = physics_step(state, params)
  end
  state
end

-- Differentiate THROUGH the simulation
d_params = @grad(simulate, .params)(params, state0, 1000)

-- This enables:
-- - Differentiable physics
-- - Differentiable rendering
-- - Neural ODEs
-- - Learned optimizers
-- - Differentiable programming (Jax-style)
```

### 4. Hardware Topology Awareness

```duo
-- The compiler KNOWS your hardware
topo = @hardware.topology()
-- Returns: { gpus = 4, gpu_memory = 80GB, nvlink = true, pcie_gen = 5 }

-- Automatic sharding based on topology
@distribute(topo)
fun train(model, data)
  -- Compiler automatically:
  -- - Shards model across GPUs (tensor parallel)
  -- - Pipelines batches (pipeline parallel)
  -- - Overlaps communication with compute
  -- - Selects NCCL vs direct memory based on NVLink presence
end
```

### 5. Streaming / Incremental Computation

```duo
-- ML inference often processes streams, not batches
stream = @stream(audio_input, chunk_size=1024)

-- The runtime automatically:
-- - Buffers input
-- - Maintains hidden state across chunks
-- - Pipelines decode → process → output
-- - Handles backpressure
for chunk in stream
  features = model.encode(chunk)
  text = model.decode(features)
  yield text
end
```

### 6. Quantization-Aware Type System

```duo
-- Types that carry quantization metadata
Q8: Quantized[i8, scale=0.01, zero_point=128]

-- Operations on quantized types generate efficient integer arithmetic
-- No floating point at inference time
fun quantized_linear(x: Q8[B,D], w: Q8[D,H]): Q8[B,H]
  -- Compiler generates: int32 accumulate → requantize → int8 output
  x @ w
end

-- Calibration is a compile-time operation
@quantize(calibration_data)
model_q8 = model
```

### 7. Memory Planning at Compile Time

```duo
-- The compiler sees ALL allocations and computes an optimal memory plan
@memory_plan
fun inference(model, x)
  -- Compiler analysis:
  -- t1 = linear_1(x)     [needs 4MB, live until t3]
  -- t2 = relu(t1)        [in-place, 0 extra]
  -- t3 = linear_2(t2)    [needs 2MB, live until t5]
  -- t4 = relu(t3)        [in-place, 0 extra]
  -- t5 = output(t4)      [needs 1MB, returned]
  --
  -- Memory plan: 4MB total (t1 and t3 share allocation)
  -- Zero runtime malloc calls during inference
end
```

### 8. Kernel Fusion as a Library (Not Compiler Magic)

```duo
-- Users can define fusion rules
fusion softmax_cross_entropy
  match
    cross_entropy(softmax(x, dim), target)
  emit
    fused_softmax_ce(x, target, dim)  -- numerically stable, one kernel
  end
end

-- Register fusions
@fuse(softmax_cross_entropy, relu_linear, gelu_approx)
fun train_step(model, batch)
  ...
end
```

### 9. Sparsity as a Type Dimension

```duo
-- Sparse tensors are types, not runtime checks
dense:   Tensor[1024, 1024, f32]
sparse:  Tensor[1024, 1024, f32, .csr]     -- compressed sparse row
block_sparse: Tensor[1024, 1024, f32, .block_sparse(64)]

-- Operations dispatch to optimal implementations based on sparsity
y = sparse @ dense  -- uses cusparse or equivalent

-- Sparsity propagates through computation
mask = (dense > threshold) @as(.csr)
pruned = dense * mask  -- result is sparse
```

### 10. Multi-Modal Pipeline Composition

```duo
-- Compose models like Unix pipes
pipeline = image_encoder >> projector >> llm >> text_decoder

-- Each stage can be on different hardware
pipeline @place {
  image_encoder = .gpu(0),
  projector = .gpu(0),
  llm = .gpu(0..3),         -- tensor parallel across 4 GPUs
  text_decoder = .gpu(0),
}

-- Execution automatically pipelines stages
output = pipeline(input_image, prompt)
```

---

## Implementation Plan (Prioritized)

### Phase 0: Native ML intrinsics (implemented)

Zero-syntax hot paths for dense linear algebra — call `ml.<kernel>()` and the compiler emits optimized C once per translation unit:

| Builtin | Workload |
|---------|----------|
| `ml.matmul_256()` | 256×256 GEMM (ikj + restrict + vectorize pragmas) |
| `ml.conv2d()` | 32×32 conv, 16 channels × 100 reps |
| `ml.softmax_1k()` | 1024-vector softmax × 10k iters |
| `ml.attention()` | 8-head scaled dot-product attention |
| `ml.mlp_forward()` | 784→256→128→10 MLP × 1000 samples |

Used by `examples/bench_ml.duo` (ML gate: `zig build ml-bench`). Stdlib: `std.ml.tensor`, `std.ml.nn`, `std.ml.ops`, `std.ml.device`, `std.ml.shape`, `std.ml.autodiff`, `std.ml.train`, `std.ml.quant`.

| Builtin | Workload |
|---------|----------|
| `ml.gelu_1k()` | GELU activation × 1024 × 5k iters |
| `ml.layernorm_1k()` | Layer norm × 1024 × 2k iters |
| `ml.dot_1m()` | 1M-element dot product × 8 reps |
| `ml.conv1d()` | 1D conv (audio/sequence) 4096×7, 8 ch × 50 reps |

### Phase 1: Foundation (partial — implemented 2026-07)

Compiler and stdlib hooks that close the gap with Mojo for common workflows:

| Feature | Status | Duo mechanism |
|---------|--------|---------------|
| `@device(.auto\|.metal\|.cuda\|…)` | **Parser + sema + codegen** | `ast.FuncBody.device_target`; C comment + backend registry |
| `@autodiff` / `@differentiable` | **Attribute + annotate** | `fb.autodiff`; `annotate("duo_autodiff")`; `std.ml.autodiff` tape |
| `@profile` | **Codegen timing** | `clock_gettime` + `fprintf` per function |
| `@unroll(N)` | **Loop pragmas** | `fb.unroll_count` → Clang/GCC unroll |
| `nn.build(...)` | **Stdlib** | Alias for `nn.sequential`; `mnist_classifier()` preset |
| `std.ml.device` | **Stdlib** | Runtime placement + pairs with `@device` |
| `std.ml.train` | **Stdlib** | `train_step`, `fit`, `sgd_step` |
| `std.ml.quant` | **Stdlib** | Symmetric int8 quant + AMP policy stub |
| `std.ml.shape` | **Stdlib** | Const dims + assert; transformer block template |
| `std.ml.transformer` | **Stdlib** | Transformer stack + `ml.attention` hot path |
| `std.ml.data` | **Stdlib** | Batching, shuffle, dataloader iterators |
| `std.ml.deploy` | **Stdlib** | WASM/static binary + quant edge pipeline |
| `std.ml.fusion` | **Stdlib** | Fusion rule registry + sequential merger |
| GPU Metal path | **Example** | `examples/bench_gpu_metal.duo` + FFI (wiring to `@device(.metal)` next) |

See `examples/ml_showcase.duo` for an end-to-end demo.

### Phase 1: Foundation (remaining)

| Feature | What It Enables | Duo Mechanism |
|---------|----------------|---------------|
| `Tensor[dims, dtype]` type | Shape checking, specialization | Compile-time generics (in progress; use `std.ml.shape` today) |
| `@autodiff` transform | Automatic gradients | Comptime AST transform (today: `std.ml.autodiff` tape + annotate) |
| `@trace` graph capture | Lazy evaluation, fusion | Return computation graph instead of value |
| Fusion rules | Kernel merging | Comptime rewrite rules (like macro but typed) |
| Memory planning | Zero-alloc inference | Comptime escape analysis on tensor lifetimes |
| `@device(.metal)` routing | GPU kernels from one source | Wire Metal FFI from `bench_gpu_metal.duo` into codegen |

### Phase 2: Differentiation & Optimization

| Feature | What It Enables | Duo Mechanism |
|---------|----------------|---------------|
| `@autodiff` transform | Automatic gradients | Comptime AST transform on function body |
| `@trace` graph capture | Lazy evaluation, fusion | Return computation graph instead of value |
| Fusion rules | Kernel merging | Comptime rewrite rules (like macro but typed) |
| Memory planning | Zero-alloc inference | Comptime escape analysis on tensor lifetimes |

### Phase 3: Hardware Backends

| Feature | What It Enables | Duo Mechanism |
|---------|----------------|---------------|
| CUDA codegen | NVIDIA GPUs | `@device(.cuda)` → emit PTX via `@c.emit` |
| Metal codegen | Apple Silicon | `@device(.metal)` → emit MSL via `@c.emit` |
| WebGPU/WGSL | Browser ML | `@device(.webgpu)` → emit WGSL |
| WASM SIMD | Edge inference | `--target wasm32-wasi` + simd128 |
| Vulkan compute | Cross-platform GPU | `@device(.vulkan)` → emit SPIR-V |

### Phase 4: Ecosystem

| Feature | What It Enables | Duo Mechanism |
|---------|----------------|---------------|
| ONNX import/export | Interop with PyTorch | Comptime ONNX parser → Duo graph |
| Safetensors format | Model loading | Binary reader via `@ffi` |
| HuggingFace integration | Pre-trained models | `req("std.ml.hub")` |
| Distributed training | Multi-node | Built on `@device` + message passing |

---

## Future Use Cases (Covered Today vs Mojo)

| Use case | Mojo today | Duo today | Duo path |
|----------|------------|-----------|----------|
| CNN / conv | ✅ MAX kernels | ✅ `ml.conv2d`, `ml.conv1d` | Native C kernels + `@hot` |
| Transformer / attention | ✅ | ✅ `ml.attention`, `std.ml.transformer` | Kernel + stdlib stack |
| Training loop | Python interop | ✅ `std.ml.train`, `std.ml.data` | `@profile` + dataloader |
| Autodiff | Planned | ✅ `@autodiff` + `std.ml.autodiff` tape | Comptime transform next |
| Multi-device | CUDA-focused | ✅ `@device(.auto\|metal\|cuda\|webgpu\|wasm)` | Metadata + `@c.emit` backends |
| Quantized edge | Limited | ✅ `std.ml.quant`, `std.ml.deploy` | int8 + WASM SIMD |
| Kernel fusion | Compiler | ✅ `std.ml.fusion` rules | `@trace` rewrite next |
| Static deploy | Heavy runtime | ✅ AOT → `<1MB` binary | `duo compile -O3` |
| LLM inference | Emerging | ✅ Transformer + attention bench | Phase 3 GPU routing |
| Fine-tune / SGD | Via Python | ✅ `sgd_step`, `fit` | Full `@grad` later |
| Shape safety | Partial | ✅ `std.ml.shape` asserts | `Tensor[M,N,T]` types |
| Profiling | External tools | ✅ `@profile` in codegen | Per-op GPU util later |

Run `examples/ml_showcase.duo` for a single-file tour of the stack.

---

## Why This Beats Mojo/Triton/JAX

| Dimension | Mojo | Triton | JAX | Duo |
|-----------|------|--------|-----|-----|
| Syntax | Python-like | Python DSL | Python | Lua-native (lighter, faster parse) |
| Compile time | Minutes (MLIR) | Seconds | JIT (slow first run) | Milliseconds (C codegen) |
| Hardware targets | NVIDIA only (today) | NVIDIA only | TPU/GPU | ALL (via C + __emit) |
| Binary size | 100MB+ runtime | Python dep | Python dep | <1MB static binary |
| Startup time | Seconds | Seconds | Seconds | Microseconds |
| Dynamic fallback | Limited | None | Full | Full Lua semantics |
| Metaprogramming | Limited decorators | None | Jit transforms | Full comptime + AST |
| Edge deploy | No | No | Limited | Native WASM target |
| Differentiable | No | No | Yes | Yes (comptime transform) |
| Custom hardware | Via MLIR (complex) | No | Via XLA (complex) | Via __emit (direct) |
| Learning curve | High (new language) | Medium | High | Low (it's just Lua+types) |

---

## The Ultimate Aha Moment

```duo
-- This is a complete, trainable neural network in Duo.
-- It runs on any hardware. It's differentiable. It's type-safe.
-- It's 20 lines.

Transformer: { heads: i64, dim: i64, layers: i64 }

@autodiff
@device(.auto)
fun forward(model: Transformer, x: Tensor[B, S, model.dim, f16])
  h = x
  for l = 1, model.layers
    h = h + attention(h, model.heads)
    h = h + ffn(h, model.dim * 4)
  end
  h
end

model: Transformer = { heads = 8, dim = 512, layers = 6 }
loss_fn = @grad(fun(m, x, y) cross_entropy(forward(m, x), y) end, .m)

-- Train
for batch in dataloader
  grads = loss_fn(model, batch.x, batch.y)
  model = adam.step(model, grads, lr=1e-4)
end

-- Deploy (compiles to <5MB static binary, runs on phone)
duo compile train.duo -o model_server --target aarch64 -O3
```

The realization: **you never left Lua**. You just added types and `@device`. The same language that scripts game logic also trains transformers and deploys them to edge devices.

That's the aha.
