# ward — AI-native WASM runtime in Duo

Reimplementation of `wart` (~1.3M lines of Zig) in **~1,500 lines of Duo**. AI/hardware-aware WASM runtime with native `@device` and `Tensor` types.

## Dependency

Requires the `duo` compiler from `~/x/duo`:
```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast
# Binary: ~/x/duo/zig-out/bin/duo
export PATH="$HOME/x/duo/zig-out/bin:$PATH"
```

## Commands

```bash
duo run src/main.duo -- run hello.wasm          # run a WASM module
duo run src/main.duo -- compile app.wasm -o app # AOT compile to native
duo run src/main.duo -- deploy --serverless app.wasm  # serverless edge
duo run src/main.duo -- shell                   # interactive WASM shell
duo run src/main.duo -- inspect app.wasm        # inspect module

# Build targets (via build.duo)
duo build                    # default native build
duo build --target wasm      # wasm32-wasi output
duo build --target lib       # shared library
duo build --target test      # run test suite
duo build --target bench     # run benchmarks
```

## Source layout

```
src/
  main.duo          CLI entry (58 lines)
  cli.duo           All CLI commands (166 lines)
  lib.duo           Embeddable API (90 lines)
  wasm/
    module.duo      Binary decoder (255 lines)
    runtime.duo     Interpreter (263 lines)
    op.duo          Opcode dispatch (310 lines)
    jit.duo         JIT stubs
    wit.duo         WIT component model
test/               Test suite
ward/               Ward app framework
build.duo           Build configuration
```

## WASM target

ward can itself compile to WASM via duo:
```bash
duo build --target wasm   # produces wasm32-wasi binary
```

## wart relationship

`wart` (`~/x/wart`) is the reference Zig implementation. ward must match wart's WASI P1/P2 behaviour. Use `zig-out/bin/wart` from the wart project to validate.
