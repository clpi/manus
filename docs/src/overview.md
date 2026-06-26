# Language Overview

Duo is a Lua-like language that compiles to native C via clang. It extends Lua 5.5 with static typing, generics, pattern matching, and other modern features while maintaining Lua's simplicity and expressiveness.

## Philosophy

Duo follows Lua's philosophy of minimalism and flexibility. Unlike languages that introduce new syntax for every feature, Duo builds on Lua's foundations:

- All composite data is a table (no `struct` or `class` keywords)
- Type annotations provide compile-time guarantees with zero runtime cost
- Typed code compiles to pure C with no boxing or dynamic dispatch
- Untyped code falls back to Lua-compatible behavior

## File Extensions

| Extension | Mode | Scoping | Use Case |
|-----------|------|---------|----------|
| `.duo` | Duo mode | Local-by-default | Modern Duo with typed features |
| `.lua` | Lua 5.5 mode | Global-by-default | Lua 5.5 compatibility |

## Basic Syntax

### Variables and Constants

```duo
-- Local variable (typed, local-by-default in .duo files)
local x: i64 = 42

-- Constant (immutable)
const PI: f64 = 3.14159

-- Untyped variable (inferred)
y = 100  -- inferred as i64
```

### Functions

```duo
-- Typed function (implicit return is preferred)
fun add(a: i64, b: i64): i64
    a + b
end

-- Untyped function (Lua-compatible)
function greet(name)
    return "Hello, " .. name
end

-- Explicit return is fine for early exits
fun clamp(x: i64, lo: i64, hi: i64): i64
    if x < lo then return lo end
    if x > hi then return hi end
    x
end

-- Short form
fun square(x: f64): f64
    x * x
end
```

### Control Flow

```duo
-- If/else
if x > 0 then
    print("positive")
elseif x < 0 then
    print("negative")
else
    print("zero")
end

-- While loop
while x < 100
    x = x * 2
end

-- Numeric for
for i = 1, 10, 2
    print(i)  -- 1, 3, 5, 7, 9
end

-- Generic for (iterators)
for key, value in pairs(my_table)
    print(key, value)
end
```

### Tables and Arrays

```duo
-- Array-like table
arr = {1, 2, 3, 4, 5}
first = arr[1]  -- 1-indexed

-- Dictionary-like table
point = { x = 10, y = 20 }
print(point.x)  -- 10

-- Typed table (anonymous record)
local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }

-- Dynamic Lua table annotation
local dynamic: Table = { name = "duo" }

-- Dynamic-size typed list
local nums: List[i64] = {}
```

### Imports

```duo
-- Require a module
local mymod = require("mymod")

-- Shorthand syntax
req = require  -- req is an alias for require
mymod = req("mymod")
```

## Typing Modes

### Typed Mode (Recommended)

When all parameters and return types are annotated, Duo generates pure C code:

```duo
fun distance(x1: f64, y1: f64, x2: f64, y2: f64): f64
    dx = x2 - x1
    dy = y2 - y1
    math.sqrt(dx * dx + dy * dy)
end
```

This compiles to:
```c
double duo_distance(double x1, double y1, double x2, double y2) {
    double dx = x1 - x2;
    double dy = y2 - y1;
    return sqrt(dx * dx + dy * dy);
}
```

### Untyped Mode (Lua-compatible)

Without type annotations, Duo uses Lua's dynamic semantics:

```duo
-- This works with any type
function identity(x)
    x
end

identity(42)      -- works
identity("hi")    -- also works
```

## Built-in Types

| Type | C Type | Description |
|------|--------|-------------|
| `i64` / `int` | `int64_t` | 64-bit signed integer |
| `f64` / `float` | `double` | 64-bit floating point |
| `str` / `string` | `const char*` | Immutable string |
| `bool` | `bool` | Boolean (true/false) |
| `any` | `lua_Value` | Dynamic value (tagged union) |
| `nil` | `void*` | Null value |
| `Table` / `table` | `lua_Value` table | Dynamic Lua-compatible table |
| `List[T]` / `list[T]` / `[]T` | `T*` | Dynamic typed list |

## Compilation Pipeline

Duo follows a multi-pass compilation pipeline:

```mermaid
graph LR
    A[Duo Source] --> B[Lexer]
    B --> C[Parser]
    C --> D[AST]
    D --> E[Semantic Analysis]
    E --> F[Monomorphizer]
    F --> G[ARC Pass]
    G --> H[Async Lowering]
    H --> I[Code Generator]
    I --> J[C11 Source]
    J --> K[Native Binary / WASM]
```

## Compiler Commands

```bash
duo                        # Start the interactive shell
duo shell                  # Start the interactive shell
duo script.duo             # Compile and run a script
duo compile <file>        # Compile to native binary or object
duo run <file>            # Compile and run
duo check <file>          # Type-check only
duo dump-c <file>         # Print generated C code
duo init [name]           # Create a new Duo project
duo build [target]        # Build from build.duo
duo completion <shell>    # Shell completions (bash, zsh, fish, nushell)
```

See [Language Status and Roadmap](./roadmap.md) for the current feature set, partially implemented features, and future plans.
