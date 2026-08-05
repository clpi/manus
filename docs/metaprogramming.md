# Duo Metaprogramming Framework

> **Architecture plan:** [`semantic_universe.md`](semantic_universe.md) — all `@comp.*`
> combinators migrate to a unified transform engine with contracts, staging, and
> agent-safe graph transactions. User-facing syntax here is unchanged; semantics
> become predictable and testable across evaluation sites.

Comprehensive reference for Duo's exponential metaprogramming system.

## Philosophy

Duo's metaprogramming breaks the asymptotic linear ceiling on code output. Traditional languages offer linear expansion: one macro invocation produces a fixed amount of code. Duo's `@comp.*` framework provides **exponential scaling** — a single line of Duo metaprogramming can produce combinatorial native output that folds entirely at compile time.

The goal: agents and developers using Duo achieve **exponential productivity gains** through minimal syntax that expands into maximal native code. One author line → multiplicative (or exponential) native output.

## Core Rules

1. `@` is the **SINGLE prefix** for ALL compile-time operations in `.duo` files.
2. NO underscores in directive names: `@comp.foo.bar`, NEVER `@comp.foo_bar`.
3. **BANNED directives**: `@const`, `@comptime` — these do NOT exist in Duo.
4. All metaprogramming folds at compile time — **zero runtime cost**.
5. Output is ALWAYS native C/asm/machine code — **NEVER `lua_Value` boxing**.

## @-Directive Hierarchy (Canonical)

```
@                           ← single prefix for all compile-time ops
├── @(expr)                 ← inline compile-time evaluation
├── @comp.*                 ← PRIMARY meta-module (canonical shortest form)
├── @meta.*                 ← alias of @comp.*
└── @compiler.*             ← alias of @comp.*
```

`@comp.*` is always preferred. `@meta.*` and `@compiler.*` resolve to the same functionality and exist for readability in contexts where the longer name is clearer.

## Full Hierarchy Tree

### @comp.compile.* — Compile-Time Control Flow

| Directive | Purpose |
|-----------|---------|
| `@comp.compile.when` | Conditional compilation |
| `@comp.compile.loop` | Compile-time loop expansion |
| `@comp.compile.fold` | Compile-time reduction |
| `@comp.compile.log` | Emit compiler log message |
| `@comp.compile.warn` | Emit compiler warning |
| `@comp.compile.error` | Emit compiler error (abort) |
| `@comp.compile.assert` | Compile-time assertion |
| `@comp.compile.cached` | Memoize compile-time result |
| `@comp.compile.thread` | Thread-parallel codegen hint |
| `@comp.compile.device` | Target device selection |
| `@comp.compile.autodiff` | Automatic differentiation transform |
| `@comp.compile.unroll` | Loop unroll directive |
| `@comp.compile.modify` | AST modification hook |
| `@comp.compile.profile` | Profile-guided hint injection |
| `@comp.compile.native` | Force native codegen path |
| `@comp.compile.only` | Include only for specified target |
| `@comp.compile.differentiable` | Mark function as differentiable |

### @comp.embed.* — Compile-Time Embedding

| Directive | Purpose |
|-----------|---------|
| `@comp.embed.str` | Embed string literal |
| `@comp.embed.file` | Embed file contents as bytes |
| `@comp.embed.json` | Parse and embed JSON at compile time |
| `@comp.embed.wasm` | Embed WASM module |

### @comp.bit.* — Bit Manipulation Intrinsics

| Directive | Purpose |
|-----------|---------|
| `@comp.bit.popcount` | Population count (Hamming weight) |
| `@comp.bit.ctz` | Count trailing zeros |
| `@comp.bit.clz` | Count leading zeros |
| `@comp.bit.bswap` | Byte swap |
| `@comp.bit.rotl` | Rotate left |
| `@comp.bit.rotr` | Rotate right |
| `@comp.bit.bitcast` | Reinterpret bits as different type |

### @comp.hint.* — Compiler Hints and Optimization

| Directive | Purpose |
|-----------|---------|
| `@comp.hint.likely` | Branch prediction: likely path |
| `@comp.hint.unlikely` | Branch prediction: unlikely path |
| `@comp.hint.prefetch` | Memory prefetch |
| `@comp.hint.assume` | Assert condition for optimizer |
| `@comp.hint.unreachable` | Mark unreachable code |
| `@comp.hint.trap` | Insert trap instruction |
| `@comp.hint.fence` | Memory fence |
| `@comp.hint.hot` | Mark hot path |
| `@comp.hint.volatile` | Prevent reordering/elimination |

### @comp.type.* — Type Introspection

| Directive | Purpose |
|-----------|---------|
| `@comp.type.name` | Get type name as string |
| `@comp.type.id` | Get unique type identifier |
| `@comp.type.info` | Full type metadata |
| `@comp.type.is` | Type predicate check |
| `@comp.type.as` | Compile-time type cast |
| `@comp.type.names` | List field/variant names |
| `@comp.type.of` | Infer type of expression |

### @comp.c.* — C Interop

| Directive | Purpose |
|-----------|---------|
| `@comp.c.emit` | Inject raw C code |
| `@comp.c.include` | Include C header |
| `@comp.c.import` | Parse and import C declarations |
| `@comp.c.export` | Export function with C ABI |
| `@comp.c.call` | Call C function directly |
| `@comp.c.type` | Reference C type |
| `@comp.c.link` | Link external library |
| `@comp.c.emit.file` | Emit to separate C file |

### @comp.agent.* — Agent Integration

| Directive | Purpose |
|-----------|---------|
| `@comp.agent.catalog` | Discover all available constructs |
| `@comp.agent.ladder` | Query scaling tier of a construct |
| `@comp.agent.hooks` | Hook into build/test/bench pipeline |
| `@comp.agent.dedupe` | Prevent duplicate code generation |
| `@comp.agent.gaps` | Find optimization opportunities |

### @comp.str.* — Compile-Time String Operations

| Directive | Purpose |
|-----------|---------|
| `@comp.str.countlines` | Count lines in string |
| `@comp.str.splitcount` | Count splits by delimiter |
| `@comp.str.len` | String length |
| `@comp.str.eq` | String equality |
| `@comp.str.join` | Join strings |
| `@comp.str.contains` | Substring check |

### @comp.emit.* — Code Emission

| Directive | Purpose |
|-----------|---------|
| `@comp.emit` | Emit generated code inline |
| `@comp.emit.derive` | Emit derived implementations |
| `@comp.emit.omni` | Emit for all targets simultaneously |
| `@comp.emit.file` | Emit to separate output file |

### @comp.rewrite.* — Rewrite Rules

| Directive | Purpose |
|-----------|---------|
| `@comp.register.rewrite` | Register a new rewrite rule |
| `@comp.rewrite.describe` | Describe an active rewrite |
| `@comp.rewrite.rulecount` | Count active rewrite rules |

### Standalone @comp.* Directives

| Directive | Purpose |
|-----------|---------|
| `@comp.pipeline` | Multi-stage compile-time pipeline |
| `@comp.derive` | Derive implementations for a type |
| `@comp.define.derive` | Define a new derivation strategy |
| `@comp.foreign` | Foreign function interface declaration |
| `@comp.sql` | Compile-time SQL query validation |
| `@comp.wasm` | WASM-specific compilation |
| `@comp.lua` | Lua compatibility layer |
| `@comp.schema` | Schema validation/generation |
| `@comp.ffi` | FFI binding generation |
| `@comp.codegen` | Custom codegen hook |
| `@comp.as` | Compile-time type coercion |
| `@comp.make.type` | Construct a new type at compile time |
| `@comp.bitfield` | Packed bitfield layout |
| `@comp.union` | Tagged or untagged union |
| `@comp.select` | Compile-time conditional select |
| `@comp.run` | Execute compile-time code block |
| `@comp.constexpr` | Mark expression as constant |
| `@comp.catalog` | List available meta-constructs |
| `@comp.ladder` | Query scaling tier |
| `@comp.asm` | Inline assembly |

## Exponential Scaling Ladder

The key differentiator. Each tier multiplies the ratio of author input to native output.

| Tier | Constructs | Scaling | Description |
|------|-----------|---------|-------------|
| **Linear** | `@comp.map`, `@comp.template`, `@comp.generate`, `@comp.scheme`, `@comp.match`, `@comp.tabulate`, `@comp.interpolate` | O(n) | One input spec → n outputs |
| **Quadratic** | `@comp.product`, `@comp.zip` | O(n²) | Cartesian product of two specs |
| **Cubic+** | `@comp.tensor`, `@comp.burst`, `@comp.transcend` | O(n³)+ | 3-way product |
| **Polynomial** | `@comp.nfold`, `@comp.tower` | O(n^k) | k-way sweep, dynamic k up to 16 |
| **Exponential** | `@comp.power`, `@comp.powerset` | O(2^n) | All subsets of input |
| **Combinatorial** | `@comp.choose` | O(n choose k) | Fixed-size subsets |
| **Factorial** | `@comp.permute` | O(n!) | All orderings |
| **Grammar** | `@comp.grammar` | O(b^d) | Grammar-based branching (b branches, d depth) |

### Scaling Examples

```duo
-- Linear: 5 types → 5 serializers
@comp.map({"i64", "f64", "str", "bool", "vec3"}, fun(T)
  @comp.derive("Serialize", T)
end)

-- Quadratic: 4 types × 3 formats = 12 converters
@comp.product(
  {"i64", "f64", "str", "bool"},
  {"json", "msgpack", "csv"},
  fun(T, fmt)
    @comp.emit.derive("Convert", T, fmt)
  end
)

-- Exponential: 2^5 = 32 feature flag combinations
@comp.powerset({"logging", "metrics", "tracing", "auth", "cache"}, fun(subset)
  @comp.emit.derive("Config", subset)
end)

-- Factorial: all orderings of a pipeline
@comp.permute({"parse", "validate", "transform", "emit"}, fun(order)
  @comp.emit("pipeline", order)
end)
```

### Scaling Ceiling Comparison

| Language | Max Scaling | Mechanism |
|----------|-------------|-----------|
| C preprocessor | O(1) per macro | Token pasting |
| C++ templates | O(n) | Template instantiation |
| Rust proc macros | O(n) | TokenStream → TokenStream |
| Zig comptime | O(n) | Inline execution |
| Jai #run | O(n) | Arbitrary compile-time code |
| **Duo @comp.*** | **O(n!)** | **Exponential scaling ladder** |

## Bare-Name Aliases

Common intrinsics available without the `@comp.*` prefix for ergonomics:

### Compile-Time Evaluation
- `@(expr)` — evaluate expression at compile time

### Bit Intrinsics
- `@popcount` → `@comp.bit.popcount`
- `@clz` → `@comp.bit.clz`
- `@ctz` → `@comp.bit.ctz`

### Branch Hints
- `@likely` → `@comp.hint.likely`
- `@unlikely` → `@comp.hint.unlikely`

### Function Attributes
- `@hot` → `@comp.hint.hot`
- `@cold` — mark cold path
- `@inline` — force inline
- `@noinline` — prevent inlining
- `@pure` — mark as pure (no side effects)
- `@flatten` — inline all callees
- `@noreturn` — function does not return
- `@restrict` — pointer restrict qualifier
- `@deprecated` — mark deprecated

### Type/Layout Attributes
- `@raw` — raw memory access (no bounds check)
- `@packed` — packed struct layout
- `@align` — alignment specification

### Linkage
- `@export` → `@comp.c.export`
- `@ffi` → `@comp.foreign`
- `@native` → `@comp.compile.native`

### Optimization
- `@cached` → `@comp.compile.cached`

## Design Principles

1. **MINIMUM syntax for MAXIMUM expressiveness** — Duo adds as few tokens as possible over Lua while providing more metaprogramming power than any existing systems language.

2. **One author line → multiplicative native output** — The scaling ladder means a single `@comp.powerset` call with 10 inputs generates 1024 native specializations.

3. **All metaprogramming folds at compile time** — Zero runtime cost. The binary contains only the fully-expanded native code. No interpreter, no JIT, no reflection overhead.

4. **Output is ALWAYS native** — C, assembly, machine code, GPU kernels, SIMD intrinsics, or WASM. Never `lua_Value` boxing on typed paths.

5. **Language-agnostic surface** — Any language can inject Duo metaprogramming via triple-dash comments (`.lua` files), dedicated `.duo` metaprogramming files, or MCP tool integration.

6. **Composable** — Scaling constructs compose. `@comp.product` inside `@comp.map` inside `@comp.powerset` produces the multiplicative product of their scaling factors.

## Cross-Language Integration

### In .lua files

Triple-dash comments inject Duo directives without breaking Lua syntax:

```lua
--- @inline
--- @hot
function hot_loop(n)
  local sum = 0
  --- @comp.compile.unroll(4)
  for i = 1, n do
    sum = sum + i
  end
  return sum
end
```

### In other languages

Create a dedicated `.duo` metaprogramming file that generates code for the target language:

```duo
-- generate_bindings.duo
-- Generates Python bindings for all exported types
@comp.map(@comp.type.names("exported"), fun(T)
  @comp.emit.file("bindings/" .. T .. ".py", @comp.foreign("python", T))
end)
```

### MCP Integration

The `duo_cross_lang_meta` MCP tool injects exponential gains into any host language:

```json
{
  "tool": "duo_cross_lang_meta",
  "params": {
    "target": "python",
    "construct": "@comp.product",
    "inputs": [["int", "float", "str"], ["json", "csv"]],
    "template": "converter"
  }
}
```

## Agent Integration

Agents (AI coding assistants, CI bots, orchestration tools) have first-class access to the metaprogramming framework.

### Discovery

```duo
-- List all available constructs and their scaling tiers
constructs = @comp.agent.catalog()

-- Query the scaling tier of a specific construct
tier = @comp.agent.ladder("@comp.powerset")  -- returns "exponential"
```

### Build Pipeline Hooks

```duo
-- Hook into build events
@comp.agent.hooks({
  before.build = fun() @comp.compile.log("Agent: starting build") end,
  after.bench  = fun(results) @comp.agent.gaps(results) end,
})
```

### Deduplication

```duo
-- Prevent multiple agents from generating the same code
@comp.agent.dedupe("serializers.i64.json", fun()
  @comp.derive("Serialize", "i64", {format = "json"})
end)
```

### Gap Analysis

```duo
-- Find optimization opportunities in the current codebase
gaps = @comp.agent.gaps()
-- Returns: list of {location, current.scaling, possible.scaling, suggestion}
```

### Runtime Coordination (std.agent)

```duo
agent = req "std.agent"

-- Register agent presence
agent.register("kiro", {capabilities = {"codegen", "bench", "test"}})

-- Claim a work item
agent.claim("optimize.sieve")

-- Signal completion
agent.done("optimize.sieve", {ratio = 1.05, files = {"src/codegen.zig"}})
```

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│  COMPILE-TIME EVAL    @(expr)                               │
│  META-MODULE          @comp.*  (@meta.* / @compiler.*)      │
│  C INTEROP            @comp.c.emit / include / import / ... │
│  TYPE INSPECT         @comp.type.name / id / info / is / ...│
│  BIT OPS              @popcount / @clz / @ctz               │
│  HINTS                @likely / @unlikely / @hot / @cold    │
│  FUNCTION ATTRS       @inline / @noinline / @pure / @export │
│  LAYOUT               @packed / @align / @raw               │
│  SCALING              @comp.map (O(n)) → @comp.permute (n!) │
│  AGENT                @comp.agent.catalog / ladder / gaps    │
├─────────────────────────────────────────────────────────────┤
│  BANNED: @const, @comptime, underscores in directives       │
│  RULE: @comp.foo.bar ✓   @comp.foo_bar ✗                   │
└─────────────────────────────────────────────────────────────┘
```

## Version

This document describes the Duo metaprogramming framework as of 2026-08-03. The `@comp.*` hierarchy is canonical and stable. New directives may be added under existing namespaces; the namespace structure itself is frozen.
