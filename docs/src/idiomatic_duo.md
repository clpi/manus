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
-- Stdlib imports via std global (double quotes are conventional)
s = req("std.string")
m = req("std.math")

-- String-literal call sugar: omit parentheses when the sole argument is a string
io = req 'std.io'
print 'ready'

-- User module imports
util = req("utils")
util = req 'utils'   -- same as above
```

`print 'hello'` and `req 'io'` are equivalent to `print('hello')` and `req('io')`. The parser treats a string literal immediately after a callable as the argument list. Double-quoted strings work the same way.

## 3b. Indentation Does Not Matter

Duo blocks are delimited by keywords (`fun`/`if`/`while`/`for`/`match` + `end`), not by significant whitespace. Indentation is for human readability only; the formatter (`duo fmt`) may normalize it but the compiler ignores it.

```duo
fun demo(): i64
if true
print(1)
end
1
end
```

This parses the same as a neatly indented version. Python-style indentation rules do **not** apply.

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
        Some(val) then print(val)
        None then print("Nothing")
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
| `@test.should_panic` | Expect panic/`error(...)`; normal return fails |
| `@test.bench` / `@test.time` | Enable bench/timing in test runner |

CLI:

```bash
duo test examples/directives_test.duo
duo test                              # uses @build.test src from build.duo / src/main.duo
duo test my_tests.duo --filter integration
duo bench my_bench.duo
duo symbols src/main.duo              # glanceable @build / @test inventory
```

In `.lua` files, use `--- @build.*` / `--- @test.*` comment directives (same semantics as `@` in `.duo`).

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

Inline in any module — no separate `build.duo` required (discovery order: `build.duo` → `src/main.duo` → `main.duo`):

```duo
@build.project({ name = "myapp", version = "0.1.0", default = "app" })

@build.run({ name = "app", src = "src/main.duo", out = "zig-out/bin/myapp" })

@build.test({ name = "test", src = "src/main.duo", out = "zig-out/bin/myapp_test" })

@build.bench({ name = "bench", src = "bench/suite.duo" })

@build.check({ name = "check", src = "src/main.duo" })

@build.fmt({ name = "fmt" })

@build.clean({ name = "clean" })
```

| Directive | Purpose |
|-----------|---------|
| `build.project` | Project metadata; `default` names the default target |
| `build.exe` / `build.run` | Executable target |
| `build.lib` | Library target |
| `build.test` | Test runner target (`duo build test` or default for `duo test`) |
| `build.bench` | Bench target (`duo bench` without file) |
| `build.check` | Type-check without linking (`duo build check`) |
| `build.fmt` | Format project sources (`duo build fmt`) |
| `build.clean` | Remove `zig-out/` (`duo build clean`) |

Common target fields: `name`, `src`, `out`, `opt`, `cc`, `target`, `stage` (build order), `deps` (comma-separated target names), `link`.

```bash
duo build              # default target from @build.project
duo build app          # named target
duo build list         # show all targets (or: duo build --list)
duo build all          # build every compile target in stage order
duo build test         # compile + run test runner
duo build clean|fmt|check
```

Registry tables: `std.test.attrs`, `std.bench.attrs`.

### Terminal output (diagnostics, debug, build, test)

The `duo` CLI uses ANSI styling when stdout is a TTY and `NO_COLOR` is unset. Diagnostics support rich source context; pipeline tracing and debug channels are opt-in.

**Diagnostics & tracing**

| Flag / env | Effect |
|------------|--------|
| `--trace` / `DUO_TRACE=1` | Pipeline steps with timings (parse, mono, ARC, codegen, link) |
| `--trace-rich` / `DUO_TRACE_RICH=1` | Unicode pipeline tree + timing bars (implies `--trace`; pairs with `-v` or `--build-report verbose`) |
| `--build-report` | `pretty` (default), `compact`, `verbose`, `plain` — target cards and phase timing |
| `--info` / `DUO_INFO=1` | Informational sema notes |
| `--hints` / `DUO_HINTS=1` | Compiler hints |
| `--plain-diagnostics` / `DUO_PLAIN_DIAG=1` | One-line errors for CI/LSP |
| `--no-color` / `NO_COLOR` | Disable styling |

**Debug / trace channels**

Module or function attributes:

```duo
@debug.sema
@trace.codegen({ depth = 8 })
@debug({ channels = "parse,sema,types", scopes = "function,struct" })
```

CLI / environment:

```bash
duo check app.duo --debug                    # all channels
duo check app.duo --debug=sema,codegen       # subset
duo check app.duo --debug-depth 6
DUO_DEBUG=parse,sema duo build
```

Channels: `lex`, `parse`, `sema`, `types`, `mono`, `arc`, `async`, `codegen`, `build`, `test`, `link`, or `all`.

**Test & bench reporting**

`duo test` and `duo bench` emit a structured `DUO_EVT` protocol on stderr; the compiler captures it and renders a tree-style report (default **pretty**).
Use `--no-color` or `NO_COLOR=1` when logs must be escape-free; pretty, compact, and verbose reports keep their structure without ANSI styling. Use `DUO_COLOR=1` to force rich ANSI styling in captured output. JSON reports stay NDJSON and escape-free even when color is forced.

| Style | Behavior |
|-------|----------|
| `pretty` | Icons, run/pass/skip/bench lines, summary box |
| `compact` | Minimal lines; bench shows µs/iter |
| `verbose` | Extra legacy detail |
| `plain` | Raw stderr (no capture) |
| `json` | NDJSON events for agents/CI (`--test-report json`) |

```bash
duo test examples/directives_test.duo
duo test my.duo --test-report compact --filter unit
duo test my.duo --test-report json | jq .
DUO_TEST_REPORT=verbose duo bench suite.duo
zig build report-styling                   # guard no-color and forced-color output
```

Assert failures emit `DUO_EVT test fail name=… reason=…` (assertion message when available) and continue with remaining tests.

`@test.should_panic` expects the test body to call `error(...)` (or otherwise trigger `lua_error`); returning normally counts as failure (`expected_panic`).

**Build reporting**

`duo build` shows target cards and compile phase timing when `--build-report` is not `plain` (default **pretty**). Use `DUO_BUILD_REPORT=compact` in CI.

```bash
duo build list                    # project hero + target table
duo build all --trace-rich -v     # full pipeline tree for every target
duo build app --build-report verbose
```

Target fields `stage` (numeric order) and `deps` (comma-separated target names) control `duo build all` ordering via topological sort.
