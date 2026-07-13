# SIMD Support

Duo provides native SIMD (Single Instruction, Multiple Data) support through vector types that compile to hardware-accelerated instructions.

## Vector Types

SIMD types are named with `v{N}{type}` format:

| Type | Elements | Element Type |
|------|----------|--------------|
| `v4f64` | 4 | f64 (double) |
| `v4i64` | 4 | i64 (integer) |
| `v8f32` | 8 | f32 (float) |
| `v8i32` | 8 | i32 (integer) |

## Creating Vectors

Use the `simd` module to create vectors:

```duo
-- Create vectors
v1: v4f64 = simd.v4f64(1.0, 2.0, 3.0, 4.0)
v2: v4f64 = simd.v4f64(10.0, 20.0, 30.0, 40.0)

-- Integer vectors
vi: v4i64 = simd.v4i64(1, 2, 3, 4)
```

## Arithmetic Operations

Vectors support element-wise arithmetic:

```duo
-- Addition
v3: v4f64 = v1 + v2  -- {11.0, 22.0, 33.0, 44.0}

-- Subtraction, multiplication, division
v4: v4f64 = v2 - v1
v5: v4f64 = v1 * v2
v6: v4f64 = v2 / v1

-- Scalar operations
v7: v4f64 = v1 * 2.0  -- Scalar broadcasts to all lanes
```

## Comparison Operations

Vector comparisons produce mask vectors:

```duo
-- Comparison produces integer mask
mask: v4i64 = simd.le(v3, simd.v4f64(20.0, 20.0, 20.0, 50.0))

-- Use mask for conditional selection
result: v4f64 = simd.select(mask, v3, simd.v4f64(0.0, 0.0, 0.0, 0.0))
```

## Reduction Operations

Collapse vectors to scalar values:

```duo
-- Sum all elements
total: f64 = simd.sum(v1)

-- Check any/all elements
any_true: bool = simd.any(mask)
all_true: bool = simd.all(mask)
```

## Fused Multiply-Add

```duo
-- Element-wise a*b+c in one instruction
out: v4f64 = simd.fma(a, b, c)
```

## Buffer Kernels (raw pointers)

For contiguous numeric buffers, use SIMD dot/matmul kernels:

```duo
s: f64 = simd.dot_f64(ptr_a, ptr_b, n)
simd.matmul_f64(ptr_a, ptr_b, ptr_c, m, n, k)  -- C += A @ B
```

Or via `std.simd` module: `std.simd.dot_f64(...)`, `std.simd.matmul_f64(...)`.

ML workloads can also call native kernels directly: `ml.matmul_256()`, `ml.dot_1m()`.

## Element Access

Access individual elements with indexing (0-indexed, following C convention):

```duo
print(v1[0])  -- 1.0
print(v1[3])  -- 4.0
```

## Example: Mandelbrot Render

```duo
-- SIMD-accelerated Mandelbrot rendering
fun mandel_simd(cx: v4f64, cy: v4f64): v4i64
    x: v4f64 = v4f64(0.0)
    y: v4f64 = v4f64(0.0)
    i: v4i64 = v4i64(0)
    
    while simd.lt(i, v4i64(100))
        x2: v4f64 = x * x
        y2: v4f64 = y * y
        escaped: v4i64 = simd.gt(x2 + y2, v4f64(4.0))
        
        if simd.any(escaped) then
            -- Handle escaped values
        end
        
        y = 2.0 * x * y + cy
        x = x2 - y2 + cx
        i = i + 1
    end
    
    return i
end
```

## Performance

SIMD operations compile to native instructions:

```c
// Duo types compile to clang extended vector types:
typedef double v4f64 __attribute__((ext_vector_type(4)));
typedef int64_t v4i64 __attribute__((ext_vector_type(4)));

// v4f64 + v4f64 compiles to:
v4f64 a = (v4f64){1.0, 2.0, 3.0, 4.0};
v4f64 b = (v4f64){10.0, 20.0, 30.0, 40.0};
v4f64 c = a + b;  // Vectorized addition
```