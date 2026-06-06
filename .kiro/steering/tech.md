# Tech Stack

## Language & Build System

- **Implementation language**: Zig (0.17.0-dev)
- **Build system**: Zig build system (`build.zig`)
- **No external dependencies** — the project uses only the Zig standard library
- **Target C compiler**: Clang (used at runtime to compile generated C)

## Common Commands

```bash
# Build the compiler
zig build

# Run the compiler directly
zig build run -- <command> <file> [options]

# Run all tests (unit + compile-fail)
zig build test

# Run unit tests only (lexer, parser, AST, types, sema)
zig build unit-test

# Run Duo vs C benchmark suite (correctness + timing)
zig build bench

# Run cross-language benchmark (Duo vs C vs Lua vs LuaJIT)
zig build cross-bench
```

## Zig Version

The project requires Zig `0.17.0-dev` (nightly). CI pins to a specific dev build. The minimum version is declared in `build.zig.zon`.

## Runtime Dependencies

- `clang` — required at runtime for compiling generated C to native binaries
- `zig cc` — used as the C compiler for WASM targets
- `lua` (≥5.4) and `luajit` — required only for cross-language benchmarks

## Code Style Conventions

- Snake_case for types (`TokenKind`, `Loc`) follows Zig stdlib conventions
- Functions use `snake_case` (e.g. `parse_module`, `emit_module`)
- Modules are single-file with public API via `pub` declarations
- Tests are co-located in the same `.zig` files using `test` blocks
- `src/tests.zig` aggregates all module tests for the unit-test build step
- Errors are handled with Zig's error union pattern; CLI exits with `std.process.exit(1)` on failure
