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
| `Table` / `table` | `lua_Value` table | dynamic | Lua-compatible table value |
| `*T` | pointer | machine word | Pointer to a value of type `T` |

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

## Type Aliases

Give an existing type a new name with `type`:

```duo
type Id = i64
type Point = { x: f64, y: f64 }
type StringList = []str

local id: Id = 42
local p: Point = { x = 1.0, y = 2.0 }
```

`alias` is also accepted as legacy syntax, but `type` is preferred.

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

`Table` and `table` are aliases for the same dynamic Lua table representation
used by untyped table literals. Use them when a value should keep Lua table
semantics instead of becoming a native record.

### Lists and Arrays

```duo
-- Arrays are tables with integer keys
local numbers = {1, 2, 3, 4, 5}

-- Dynamic-size typed list
local scores: List[i64] = {}

-- Equivalent spellings
local names: list[str] = {}
local raw: []i64 = {}

-- Fixed-size typed array
local vec3: [3]f64 = { 1.0, 2.0, 3.0 }

-- List comprehension over array values
local doubled = {x * 2 for x in numbers if x > 2}

-- Fixed-size typed array
local vec3: [3]f64 = { 1.0, 2.0, 3.0 }

-- Pointer to a typed value
local p: *i64 = nil
```

`List[T]`, `list[T]`, and `[]T` resolve to the same dynamic list type. Fixed
arrays use `[N]T`. Pointer types use `*T`; their full ownership semantics are still evolving.

### Raw Memory And Pointers

Typed Duo code has a compiler-recognized `mem` namespace for C-style machine
access. These calls lower directly to C and are available as either `mem.*` or
`std.mem.*` when written with that qualified name.

```duo
function checksum(): i64
    local raw: *u8 = mem.alloc(64)
    mem.zero(raw, 64)

    local ints: *i64 = mem.cast("i64", raw)
    mem.store("i64", ints, 42)
    local second: *i64 = mem.add(ints, 1)
    mem.volatile_store("i64", second, 7)

    local addr: u64 = mem.addr(raw)
    local again: *u8 = mem.ptr_from_addr("u8", addr)
    local value: i64 = mem.load("i64", mem.cast("i64", again))

    mem.free(raw)
    return value
end
```

Available low-level operations:

| Operation | Lowers To | Result |
|-----------|-----------|--------|
| `mem.alloc(bytes)` | `malloc` | `*u8` |
| `mem.calloc(count, bytes)` | `calloc` | `*u8` |
| `mem.realloc(ptr, bytes)` | `realloc` | same pointer type |
| `mem.free(ptr)` | `free` | `void` |
| `mem.cast("T", ptr)` / `mem.ptr_cast("T", ptr)` | typed pointer cast | `*T` |
| `mem.ptr_from_addr("T", addr)` | `uintptr_t` to pointer | `*T` |
| `mem.addr(ptr)` | pointer to `uintptr_t` | `u64` |
| `mem.is_null(ptr)` | null pointer test | `bool` |
| `mem.add(ptr, n)` | typed pointer arithmetic | same pointer type |
| `mem.byte_add(ptr, n)` | byte pointer arithmetic | `*u8` |
| `mem.load("T", ptr)` / `mem.store("T", ptr, value)` | typed load/store | `T` / `void` |
| `mem.volatile_load("T", ptr)` / `mem.volatile_store("T", ptr, value)` | volatile access | `T` / `void` |
| `mem.copy(dst, src, bytes)` | `memcpy` | `void` |
| `mem.move(dst, src, bytes)` | `memmove` | `void` |
| `mem.set(dst, byte, bytes)` / `mem.zero(dst, bytes)` | `memset` | `void` |
| `mem.compare(a, b, bytes)` | `memcmp` | `i64` |
| `mem.sizeof("T")` / `mem.alignof("T")` | `sizeof` / compiler alignment query | `u64` |
| `mem.fence()` / `mem.compiler_fence()` | hardware/compiler memory barrier | `void` |

The type argument is a string literal naming a primitive Duo type such as
`"u8"`, `"i64"`, `"f64"`, `"bool"`, `"usize"`, `"ptr"`, or a pointer spelling
like `"*i64"`. Pointer indexing is native in typed code: `p[i]` emits C
pointer indexing and has the pointee type.

### Atomic Memory Operations

The compiler also recognizes `atomic.*` and `std.atomic.*` calls for typed
machine atomics over raw pointer storage. Atomic type names use the same string
spelling as `mem.*`, but are limited to integer, boolean, and pointer storage.
Calls lower to C `__atomic_*` builtins with sequential consistency by default.

```duo
function next_id(slot: *i64): i64
    return atomic.fetch_add("i64", slot, 1, "acq_rel")
end
```

Available atomic operations:

| Operation | Lowers To | Result |
|-----------|-----------|--------|
| `atomic.load("T", ptr[, order])` | `__atomic_load_n` | `T` |
| `atomic.store("T", ptr, value[, order])` | `__atomic_store_n` | `void` |
| `atomic.exchange("T", ptr, value[, order])` | `__atomic_exchange_n` | `T` |
| `atomic.compare_exchange("T", ptr, expected_ptr, desired[, success[, failure]])` | `__atomic_compare_exchange_n` | `bool` |
| `atomic.fetch_add("T", ptr, delta[, order])` | `__atomic_fetch_add` | old `T` |
| `atomic.fetch_sub("T", ptr, delta[, order])` | `__atomic_fetch_sub` | old `T` |
| `atomic.fetch_and("T", ptr, mask[, order])` | `__atomic_fetch_and` | old `T` |
| `atomic.fetch_or("T", ptr, mask[, order])` | `__atomic_fetch_or` | old `T` |
| `atomic.fetch_xor("T", ptr, mask[, order])` | `__atomic_fetch_xor` | old `T` |
| `atomic.fence([order])` | `__atomic_thread_fence` | `void` |
| `atomic.compiler_fence([order])` | `__atomic_signal_fence` | `void` |

Memory order strings are `"relaxed"`, `"consume"`, `"acquire"`, `"release"`,
`"acq_rel"`, and `"seq_cst"` (`"seqcst"` is accepted as an alias). Load and
compare-exchange failure orders cannot use release semantics; store orders
cannot use acquire semantics.

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

Duo supports `Option[T]` for nullable values:

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
