# Types and Type Annotations

Duo's type system combines static safety with zero runtime cost. When you annotate types, the compiler generates optimized C code with no boxing or dynamic dispatch overhead.

## Basic Types

### Primitive Types

| Duo Type | C Equivalent | Size | Description |
|----------|--------------|------|-------------|
| `i64` / `int` | `int64_t` | 64-bit | Signed integer |
| `f64` / `float` | `double` | 64-bit | Floating point |
| `str` / `string` | `const char*` | variable | Immutable string |
| `bool` | `bool` | 8-bit | Boolean value |
| `nil` | `NULL` | - | Null/none value |
| `any` | `lua_Value` | Tagged union | Dynamic value |

### Type Annotations

```duo
-- Basic type annotations
local count: i64 = 42
local ratio: f64 = 3.14159
local name: str = "Duo"
local flag: bool = true

-- Function parameter and return types
fun add(a: i64, b: i64): i64
    a + b
end

-- Multiple return types (C-style out params)
fun divmod(a: i64, b: i64): (i64, i64)
    local q: i64 = a / b
    local r: i64 = a % b
    return q, r
end
```

## Composite Types

### Tables

```duo
-- Untyped table (dynamic)
local t = { x = 10, y = 20 }

-- Typed table (anonymous record)
local point: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }

-- Table type for dynamic tables
local dynamic_table: Table = { a = 1, b = 2 }
```

### Arrays

```duo
-- Arrays are tables with integer keys
local numbers = {1, 2, 3, 4, 5}

-- Typed array (via table type)
local vec3: { 1: f64, 2: f64, 3: f64 } = { 1.0, 2.0, 3.0 }
```

## Type Inference

Duo can infer types for variables and expressions:

```duo
-- Inferred as i64
local x = 42

-- Inferred from function return
local name = get_name()  -- inferred from get_name's return type annotation

-- Inferred in function body
fun compute(n: i64): i64
    local doubled = n * 2  -- inferred as i64
    return doubled + 1
end
```

## Optional Types

Duo supports Rust-style `Option[T]` for nullable values:

```duo
-- Option type (no nil)
fun find_item(id: i64): Option[str]
    if id == 0 then
        return none  -- No value
    end
    return some("item_" .. tostring(id))
end

-- Using optional values
result = find_item(42)?
if result then
    print("Found: " .. result)
end
```

## Result Types

For error handling, use `Result[T, E]`:

```duo
-- Result type for operations that can fail
fun divide(a: f64, b: f64): Result[f64, str]
    if b == 0 then
        return err("division by zero")
    end
    return ok(a / b)
end

-- Propagate errors with ?
fun safe_div(a: f64, b: f64): Result[f64, str]
    quotient = divide(a, b)?  -- Propagates error if present
    return ok(quotient)
end
```

## SIMD Types

Duo supports SIMD vector types:

```duo
-- SIMD vector types
local v1: v4f64 = simd.v4f64(1.0, 2.0, 3.0, 4.0)
local v2: v4i64 = simd.v4i64(10, 20, 30, 40)

-- Operations compile to native SIMD
local v3: v4f64 = v1 + v2
local sum: f64 = simd.sum(v3)
```

Available SIMD types: `v4f64`, `v4i64`, `v8f32`, `v8i32`.