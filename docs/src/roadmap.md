# Language Status and Roadmap

Duo stays close to Lua while adding static types, AOT codegen, and a small set of syntax extensions where they buy real safety or performance. This page tracks the current language direction so examples do not drift from the compiler.

## Current status

- **Compiler**: Zig-based, ahead-of-time compiler that lowers Duo/Lua source to C and shells out to `clang` (or `zig cc` for WASM).
- **Source dialects**: `.duo` files (Duo mode, local-by-default, typed features) and `.lua` files (Lua 5.5 mode, global-by-default).
- **Tests**: 393+ unit tests plus compile-fail tests and a 40-benchmark performance gate (`zig build bench` requires Duo to beat or tie C).
- **Outputs**: native executables, shared libraries, and `wasm32-wasi` modules.

## Implemented

### Language surface

- `fun` for typed functions and `function` for Lua-compatible untyped functions.
- `.duo` files are local-by-default for bare assignments; `local` remains valid for Lua compatibility and readability.
- Type annotations on locals, constants, parameters, and returns: `: i64`, `: f64`, `: str`, `: bool`, `: void`, etc.
- Type aliases: `type Name = ExistingType` (preferred); `alias` is still accepted as legacy syntax.
- Pointer types: `*T` parse and lower; reference/ownership semantics are still evolving.
- Postfix `?` and `!` as propagation and unwrap operators.
- `await` is the async wait primitive. There is no separate `wait` keyword.
- `match` expressions with Lua-like `case pattern then expression` or
  `case pattern do statement` arms. Legacy `pattern => expression` arms remain
  accepted for source compatibility.
- `try` / `catch` / `defer` for error handling and cleanup.
- `enum`, `concept`, `alias`, `extends`, `private` for type-system extensions.
- `const` bindings and attributes such as `@export`, `@inline`, and `@concurrent("threaded")`.
- `expr and x` / `expr or y` preserve Lua operand-return semantics. The common `cond and x or y` idiom recovers native typed code when `x` and `y` share a non-boolean, non-nil branch type.

### Types

- Primitive numeric types: `i8`/`i16`/`i32`/`i64`, `u8`/`u16`/`u32`/`u64`, `f32`/`f64`.
- `bool`, `str`/`string`, `nil`, `void`, `any`.
- `Table` and `table` name the dynamic Lua table representation.
- `List[T]`, `list[T]`, and `[]T` resolve to the same dynamic typed list shape.
- Fixed arrays: `[N]T`.
- Anonymous records: `{ x: f64, y: f64 }`.
- `Option[T]` and `Result[T, E]` for nullable values and error handling.
- SIMD vector types: `v4f64`, `v4i64`, `v8f32`, `v8i32`.

### Standard library

- Core modules in `lib/std/`: `math`, `string`, `table`, `io`, `fs`, `os`, `path`, `time`, `env`, `proc`, `fmt`, `log`, `json`, `hash`, `crypto`, `base64`, `base32`, `hex`, `url`, `uuid`, `utf8`, `regex`, `random`, `iter`, `collections`, `memo`, `test`, `build`, `package`, `argparse`, `debug`, `csv`, `xml`, `toml`, `yaml`, `ini`, `html`, `http`, `datetime`, `sqlite`, `tar`, `zip`, `color`.
- Concurrency modules: `coroutine`, `sync`, `channel`, `concurrent`, `thread`, `mproc`, `atomic`.
- Networking: `net` (HTTP and sockets; zero-overhead codegen when the module variable is named `net`).
- Low-level/memory: `mem`, `wasm/wasi`.
- Modules are imported with `require("std.module")` or the shorthand `req "std.module"`.

### Codegen and tooling

- Monomorphizer (`src/mono.zig`) for generic specializations.
- ARC pass (`src/arc.zig`) for retain/release/close decisions.
- Async lowering (`src/async_lower.zig`) transforms async functions into stackless
  state-machine descriptors; async declarations also emit a direct callable body
  so simple async/await chains run today.
- Profile-guided optimization (`--pgo`), shared-memory WASM (`--shared-memory`), library mode (`--lib`), and dynamic chunk loading (`--load-chunk`).
- `duo` and `duo shell` start an interactive shell that compiles/runs one Duo
  line through the normal pipeline, supports `!command` host escapes, and
  `.duo` scripts may start with a Unix shebang. Added `duo fmt` for formatting.
- Shell completions for bash, zsh, fish, and nushell.

## Partial / in progress

- `if ... then ... else ... end` can be used as a tail expression in blocks. Postfix `expr if cond else fallback` syntax is not implemented.
- Concepts exist as compile-time structural checks and now also emit runtime
  descriptor tables (`name`, `required_fields`, `required_methods`) that
  `std.meta.satisfies_concept` can inspect. `std.meta.make_concept(...)` and
  `std.meta.derive` now create the same descriptor shape as ordinary tables,
  and `@implements` accepts literal descriptor bindings. Full generic
  constraint dispatch and syntax removal are still in progress.
- Pointer types use `*T`. Reference and ownership semantics are still evolving.
- Allocator and memory-management work is tracked through ARC, escape analysis, and custom allocator tasks.
- Compile-time `##(...)` and `__constexpr(...)` share a small pure evaluator
  for literals, unary/binary operators, and scoped local/const bindings.
  Unsupported runtime expressions still fall back to normal runtime emission.
  Macro expansion, quote/unquote, AST replacement, and hygienic macro syntax
  are still in progress.
- Scheduler-backed async tasks, pending poll states, and async channels are still
  being completed; current async calls run synchronously while descriptors are
  emitted for the full runtime path.
- Native record passing end-to-end: record-typed parameters and locals work in many cases, but call-site coercion from table literals and named alias lowering are incomplete.
- String-returning builtins in typed contexts can disagree between sema and emit; `string.sub` and `tostring` in a typed `str` context need careful use until fixed.

## Planned

- Hygienic macro syntax and more complete metaprogramming: quote/unquote,
  conditional/loop/function evaluation, AST replacement, and expansion-time
  diagnostics.
- A tighter concept/metatable model that finishes compile-time dispatch through
  ordinary Lua metatables and removes unnecessary syntax additions.
- Deeper table/list lowering so dynamic Lua tables and typed Duo lists share more optimizer paths without losing Lua compatibility.
- Escape analysis and stack allocation for non-escaping temporaries.
- ARC pruning and custom allocator integration.
- Generalized dense-table lowering, loop specialization, and closure/upvalue optimization.
- NaN-boxed `lua_Value`, string interning, LTO/PGO integration, and SIMD auto-vectorization hints.
- Official formatter (`duo fmt`).

## How to follow progress

- `docs/perf-todo.md` tracks detailed codegen/optimization tasks, correctness bugs, and benchmark-gate constraints.
- Run `zig build test` and `zig build bench` before submitting changes that touch codegen or the standard library.
