# Idiomatic Duo (The Zen of Duo)

Duo is designed to be a pragmatic, high-performance language that blends the flexibility of Lua with the speed and safety of native C. To get the most out of Duo, follow these idiomatic guidelines:

## 1. File-as-M: Implicit Module Scope

Every `.duo` file IS its own `M`. Functions and values declared at file scope are module exports. No boilerplate needed.

**Idiomatic:**
```duo
-- lib/std/my_mod.duo
fun greet(name: str): str
    "hello " .. name
end

fun farewell(name: str): str
    "bye " .. name
end
```

**Less idiomatic (unnecessary):**
```duo
local M = {}
fun M.greet(name: str): str
    "hello " .. name
end
return M
```

Use `M = {}` only when you need to rename exports or expose a subset:
```duo
internal_helper = fun() ... end
M = {}
M.greet = greet  -- only export greet, not internal_helper
M
```

## 2. Prefer `fun` Over `function`

Always use `fun` for function declarations — it's shorter and Duo-native.

```duo
add = fun(a: i64, b: i64): i64
    a + b
end
```

## 3. Use `req` for Imports

Use `req` for all module imports. When importing from stdlib, use the `std` global:

```duo
-- Stdlib imports via std global
local s = req("std.string")
local m = req("std.math")

-- User module imports
local util = req("utils")
```

## 4. Omit `do` Where Possible

Duo allows omitting `do` after `while`, `if`, and `for` conditions:

**Idiomatic:**
```duo
while i < n
    i = i + 1
end

if x > 0
    print(x)
end

for i = 1, 10
    print(i)
end
```

**Less idiomatic:**
```duo
while i < n do
    i = i + 1
end
```

## 5. Implicit Returns Over Explicit `return`

When the last thing a function does is produce a value, let the block tail expression be the return. This is cleaner, faster to read, and generates the same code as an explicit `return`.

**Idiomatic:**
```duo
fun add(a: i64, b: i64): i64
    a + b
end

fun max(a: i64, b: i64): i64
    if a > b then a else b end
end
```

Use explicit `return` only when you need to exit early:

```duo
fun find_index(list: any, target: any): i64
    local i: i64 = 1
    while i <= #list
        if list[i] == target then
            return i
        end
        i = i + 1
    end
    -1
end
```

## 6. Type Annotations for Performance

Adding static type annotations (`x: i64`, `s: str`) allows the compiler to generate highly optimized C code (often 4-100x faster than untyped code).

**Idiomatic (when performance matters):**
```duo
fun calculate_sum(n: i64): i64
    local sum: i64 = 0
    local i: i64 = 1
    while i <= n
        sum = sum + i
        i = i + 1
    end
    sum
end
```

**Codegen limitation:** Typed params work reliably for external API calls (through `__lua` wrappers). For same-module calls where the compiler can't track argument types, use `any` instead.

## 7. Default to `local`

Always declare variables with `local`. Global variables are discouraged unless absolutely necessary, as they can inhibit optimizations and cause unintended side-effects across your program.

## 8. Leverage Pattern Matching

Duo's pattern matching (`match`) is more expressive and safer than complex `if/elseif/else` chains. Use it to handle enums, variants, and structured data clearly.

```duo
enum Option
    Some(val: any)
    None
end

fun process(opt: Option)
    match opt
        case Some(val) then print(val)
        case None then print("Nothing")
    end
end
```

## 10. Favor Fewer Characters

Where possible without sacrificing clarity, favor shorter names and less boilerplate:

```duo
-- Good: short, clear
for k, v in pairs(t)
    print(k, v)
end

-- Less ideal: unnecessary verbosity
for key, value in pairs(table) do
    print(key, value)
end
```

## 11. Hierarchical Module Organization

Group related modules under parent namespaces:

```duo
-- In lib/std.duo
std.net = req "std.net"         -- networking core
std.net.retry = req "std.net.retry"  -- network retry (child of net)
std.collections = req "std.collections"  -- data structures
std.collections.cache = req "std.collections.cache"  -- caches (child of collections)
std.time = req "std.time"       -- time utilities
std.time.timer = req "std.timer"  -- benchmarks (child of time)
```

## 12. Take Advantage of Constant Folding

When values are known at compile time, the Duo compiler will aggressively constant-fold. You can rely on this for zero-cost abstractions, meaning that clear, descriptive code often compiles down to nothing!

```duo
fun circle_area(r: f64): f64
    math.pi * r * r
end
```

## 13. Compiler Directives (`@test.*`, `@build.*`, `@bench`, `@time`)

Duo supports attribute-style directives on functions and module-level `@build.*` declarations. The compiler collects `@test` / `@bench` functions and emits a native test runner when you use `duo test` or `duo bench`.

### Testing (`@test.*`)

Mark void functions with no parameters:

```duo
@test.unit
fun test_add(): void
    local t = req("std.test")
    t.assert_eq(1 + 1, 2, "addition")
end

@test.skip
fun skipped(): void
end

@test.only
fun focus_me(): void
end

@test({ tag = "integration", timeout_ms = 5000 })
fun slow_check(): void
end
```

| Attribute | Meaning |
|-----------|---------|
| `@test` | Run under `duo test` |
| `@test.unit` / `@test.integration` / `@test.e2e` | Category tag (filter via `--filter`) |
| `@test.skip` | Skip |
| `@test.only` | Run only these when any `@test.only` exists |
| `@test.flaky` | Mark flaky (logged, still runs) |
| `@test.should_panic` | Collected; runner enforcement pending |
| `@test.bench` / `@test.time` | Enable bench/timing in test runner |

CLI:

```bash
duo test examples/directives_test.duo
duo test my_tests.duo --filter integration
duo bench my_bench.duo
```

### Benchmarking (`@bench`, `@time`)

```duo
@bench({ iterations = 1000, warmup = 50 })
fun bench_hash(): void
    -- hot loop
end

@time
fun timed_setup(): void
end
```

`duo bench <file>` runs only `@bench` (or `@test.bench`) functions. Defaults: `iterations=1000`, warmup optional.

### Build (`@build.*`)

Module-level directives in `build.duo` (also supported as `build.exe({...})` calls):

```duo
@build.project({ name = "myapp", version = "0.1.0", default = "app" })

@build.exe({ name = "app", src = "src/main.duo", out = "zig-out/bin/myapp" })

@build.test({ name = "tests", src = "tests/all.duo" })

@build.bench({ name = "bench", src = "bench/suite.duo" })
```

| Directive | Purpose |
|-----------|---------|
| `build.project` | Project metadata; `default` names the default target |
| `build.exe` | Executable target |
| `build.lib` | Library target |
| `build.test` | Test runner target (`duo build tests`) |
| `build.bench` | Bench target |
| `build.run` / `build.check` / `build.fmt` / `build.clean` | Reserved for future `duo build` subcommands |

Registry tables: `std.test.attrs`, `std.bench.attrs`.