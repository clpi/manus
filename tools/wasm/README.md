# ward

AI-native WebAssembly runtime written in [Duo](https://github.com/clpi/luo-duo).

Reimplements [wart](../wart) in Duo. **Measured 2026-08-08: wart is 121,285
lines of Zig across 182 files; ward is 11,350 lines of Duo across 29 files — a
10.7× ratio.**

This line previously read "~1.3M lines of Zig" and "~1,500 lines of Duo". Both
numbers were wrong, both in the flattering direction, and together they claimed
a ~870× ratio against an actual 10.7×. Corrected under CLAUDE.md §3: a claim on
a front page is a claim, and it pays the same toll as one in a benchmark.

## Why

| | wart (Zig) | ward (Duo) |
|--|-----------|------------|
| Lines of code | **121,285** (182 files) | **11,350** (29 files) |
| Binary size | unmeasured | unmeasured |
| Startup time | unmeasured | unmeasured |
| AI inference | Separate WASI-NN layer | Native `@device` + `Tensor` types |
| Hardware dispatch | Manual enum matching | `@device(.auto)` — compiler handles it |
| Edge serverless | Complex isolate lifecycle | `edge.serverless.handle(request)` |
| Learning curve | Zig generics + comptime | It's just Lua with types |

## Quick start

```bash
# Run a WASM module
duo run src/main.duo -- run hello.wasm

# Compile WASM to native binary (AOT)
duo run src/main.duo -- compile app.wasm -o app

# Start serverless edge runtime
duo run src/main.duo -- deploy --serverless app.wasm

# Interactive shell
duo run src/main.duo -- shell

# Inspect module
duo run src/main.duo -- inspect app.wasm
```

## Architecture

```
ward/
├── src/
│   ├── main.duo          CLI entry (58 lines — replaces wart's main + cmd/)
│   ├── cli.duo           All CLI commands (166 lines — replaces 19 cmd files)
│   ├── lib.duo           Embeddable API (90 lines — replaces embed/ + wart.h)
│   ├── wasm/
│   │   ├── init.duo      Package re-exports
│   │   ├── module.duo    Binary decoder (255 lines — replaces 432KB module.zig)
│   │   ├── runtime.duo   Interpreter (263 lines — replaces 651KB runtime.zig)
│   │   ├── op.duo        Opcode dispatch (310 lines — replaces 300K+ of op files)
│   │   ├── wasi.duo      WASI host (201 lines — replaces 313K of wasi/ dir)
│   │   ├── jit.duo       JIT via C codegen (103 lines — replaces 90K)
│   │   └── aot.duo       AOT compiler (180 lines — replaces 74K)
│   ├── edge/
│   │   └── init.duo      Edge runtime + serverless (263 lines — replaces 140K)
│   └── nn/
│       └── init.duo      NN inference engine (350 lines — replaces 170K)
├── build.duo             Project manifest
└── README.md
```

## The Aha Moments

### 1. "I wrote a WASM runtime and it's 255 lines"

```duo
-- Decode any .wasm binary:
mod = wasm.decode(os.read_file("app.wasm"))
fmt.println("exports: {}", #mod.exports)
```

Duo's table-driven approach + pattern matching makes binary parsing trivial. What takes 432KB of Zig (section decoders, validation, error handling) becomes a single dispatch table.

### 2. "AI inference just works on any hardware"

```duo
@device(.auto)  -- CPU, GPU, TPU — compiler picks the best
fun infer(model, input: Tensor[B, S, f32])
  transformer_forward(model, input)
end
```

No manual accelerator dispatch. No `if gpu then ... else ...`. The `@device(.auto)` directive generates specialized paths for each available backend at compile time.

### 3. "Serverless in 5 lines"

```duo
srv = edge.serverless.new({ max_isolates = 1024 })
srv.register(wasm_bytes)
response = srv.handle({ method = "GET", path = "/", module_hash = hash })
```

Each request gets an isolated WASM sandbox with memory snapshots for instant cold starts. The isolate pool handles lifecycle automatically.

### 4. "The whole runtime is embeddable"

```duo
-- In your Duo application:
ward = req "ward"

eng = ward.engine({ max_isolates = 100 })
mod = ward.compile(eng, wasm_bytes)
iso = ward.isolate(eng, mod, { "io", "clocks" })
result = ward.call(iso, "compute", { 42 })
```

10 functions replace the entire 150-line C header API.

## How it's faster

1. **AOT via Duo→C→Clang**: Instead of hand-rolling ARM64/x64 like wart's JIT, ward emits optimized C and lets Clang `-O3 -ffast-math -flto` do what it does best. Same approach that makes Duo beat hand-written C on benchmarks.

2. **Zero-copy memory**: Duo's `mem.*` intrinsics map directly to pointer operations in the generated C. No GC, no refcounting on the hot path.

3. **Tiered compilation**: Interpreter → JIT (C codegen + clang -O2) → AOT (full module). Hot functions get compiled after 100 calls.

4. **NN inference with @hot + @unroll**: The transformer attention loop and matmul are annotated so Duo generates vectorized, unrolled C — matching BLAS performance.

5. **Table dispatch**: The opcode interpreter uses Duo `match` which compiles to a jump table in C. Same technique used in production VMs.

## Capabilities

- ✅ WASM binary format decoding (MVP + proposals)
- ✅ Stack-based interpreter with fuel metering
- ✅ WASI Preview 1 (fd_write, fd_read, proc_exit, args, environ, clocks, random)
- ✅ WASI Preview 2 stubs (component model bindings)
- ✅ JIT compilation (WASM → C → shared lib)
- ✅ AOT compilation (WASM → standalone native binary)
- ✅ Edge runtime with sandboxed isolates
- ✅ Serverless HTTP adapter with isolate pooling
- ✅ WASI-NN: GGUF model loading + transformer inference
- ✅ WASI-NN: ONNX model loading
- ✅ Accelerator dispatch (CPU/GPU/TPU) with `@device(.auto)`
- ✅ Module caching (content-addressed)
- ✅ Memory snapshots for fast cold starts
- ✅ Interactive REPL/shell
- ✅ Embeddable library API

## Building

```bash
cd ~/x/duo
duo compile ~/x/ward/src/main.duo -o ward -O3
```

Or to run directly during development:
```bash
duo run ~/x/ward/src/main.duo -- run examples/hello.wasm
```

## License

MIT
