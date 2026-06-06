# Project Structure

```
duo/
├── build.zig              # Zig build system configuration
├── build.zig.zon          # Package manifest (name, version, dependencies)
├── README.md              # Project documentation and benchmark results
│
├── src/                   # Compiler source code
│   ├── main.zig           # CLI entry point, argument parsing, orchestration
│   ├── root.zig           # Library root — re-exports public API
│   ├── lexer.zig          # Tokenizer (Lua + Duo keyword/operator support)
│   ├── parser.zig         # Recursive-descent parser → AST
│   ├── ast.zig            # AST node definitions
│   ├── types.zig          # Type system definitions
│   ├── sema.zig           # Semantic analysis and type checking
│   ├── codegen.zig        # C code generation from typed AST
│   ├── tests.zig          # Test aggregator (imports all modules for unit-test)
│   └── runtime/           # (placeholder for future runtime support)
│
├── examples/              # Example programs and benchmarks
│   ├── *.lua              # Lua-syntax source files
│   ├── *.duo              # Duo-syntax source files (with type annotations)
│   ├── benchmark.lua      # Primary 40-workload benchmark driver
│   ├── benchmark_c.c      # Reference C implementation for benchmark comparison
│   └── compile_fail/      # Expected-error test cases
│
├── tests/                 # Additional test files
│   ├── test_ast.zig       # AST-specific tests
│   ├── test_hash.zig      # Hash function tests
│   ├── test_plugin.sh     # Plugin integration test
│   └── test.lua           # Lua source that should compile cleanly
│
├── scripts/               # Shell scripts for CI and benchmarking
│   ├── run_compile_fail_tests.sh   # Compile-fail test harness
│   ├── run_benchmark.sh            # Duo vs C benchmark runner
│   └── run_cross_benchmark.sh      # Cross-language benchmark runner
│
└── .github/workflows/ci.yml  # CI: build, test, WASM check, bench, release
```

## Compiler Pipeline

The compilation flow is: **Source → Lexer → Parser → AST → Sema → CodeGen → C file → Clang → Native binary**

1. `lexer.zig` — Tokenizes `.lua` or `.duo` input
2. `parser.zig` — Builds an AST from the token stream
3. `sema.zig` — Performs semantic analysis and type checking (Lua 5.5 mode or Duo mode)
4. `codegen.zig` — Emits C source code from the checked AST
5. `main.zig` — Invokes Clang to compile the C to a native binary

## Testing Strategy

- **Unit tests**: In-module `test` blocks aggregated via `src/tests.zig`; run with `zig build unit-test`
- **Compile-fail tests**: Files in `examples/compile_fail/` that must produce specific error messages; run via `scripts/run_compile_fail_tests.sh`
- **Correctness tests**: Benchmark suite verifies output matches reference C (`RESULT <id> <value>` lines)
- **Smoke tests**: CI checks WASM cross-compilation produces valid WebAssembly
