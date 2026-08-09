# duon wasm

duon's WebAssembly engine. Decodes a module, runs it, and JITs it to ARM64 —
written in Duo, no `@c.emit`, no C intermediary, no LLVM.

It used to be a separate product called **ward**, living at `~/x/ward` and then
`ext/ward/`. It is not a separate product any more: it is the wasm part of the
toolchain, the same way `tools/lsp` is the language-server part.
`docs/wasm-integration.md` records the move and why it landed in `tools/` rather
than `lib/std/wasm/`.

## Status — measured 2026-08-08, nothing here is a projection

| | |
|---|---|
| Conformance | **126 PASS / 130 rows, 0 DIFF** — every fixture, both engines, both entry shapes, differenced against wasmtime **by value** (`zig build wasm-test`) |
| JIT coverage | 49 of 65 bodies compiled; the rest fall back to the interpreter, which is a speed difference and never an answer difference |
| JIT worth | **29×** over this engine's own interpreter (43.04 s → 1.32 s on a 1e9 i32 kernel) |
| Size | 11,350 lines of Duo across 28 files, of which `src/engine.duo` is 6,312 |

Against the other runtimes on that kernel — all five return `3725993217`:

| runtime | best wall | vs wasmtime |
|---|---|---|
| wasmtime | **1.05 s** | 1.00× |
| wasmer | 1.21 s | 1.15× |
| **duon wasm** (`engine=jit-arm64`) | **1.32 s** | 1.26× |
| wart (Zig, JIT) | 1.36 s | 1.30× |

**Read that honestly: it is 3% ahead of wart and 26% behind wasmtime — last of
the four JIT-class runtimes.** One kernel, one shape. It is not a dominance
claim and must not be quoted as one. `docs/wart-integration.md` §1 has the
method, the positive control, and what the number cannot say.

wart is 121,285 lines of Zig across 182 files, so the ratio is **10.7×**. This
page previously said "~1.3M lines of Zig" and "~1,500 lines of Duo" — both wrong,
both flattering, together claiming ~870× against an actual 10.7×. Corrected in
`0e4eb29` under CLAUDE.md §3: a claim on a front page pays the same toll as one
in a benchmark.

## Running it

```bash
zig build wasm-test        # build the engine + run the full differential
```

The engine reads **environment, not argv** — duon-compiled binaries do not
populate Lua's `arg`, and passing a module as an argument measures nothing.
This has faked two whole benchmark sweeps.

```bash
duo compile src/engine.duo --backend=c --emit exe -o /tmp/duowasm
DUO_WASM_MODULE=$PWD/bench/fib.wasm DUO_WASM_INVOKE=run /tmp/duowasm
# engine=jit-arm64
# result=2178309
```

| variable | meaning |
|---|---|
| `DUO_WASM_MODULE` | the module to run. **Required** — there is no default, because a default made every mis-invocation print a plausible answer for a different module |
| `DUO_WASM_INVOKE` | export to enter, default `run` |
| `DUO_WASM_ENGINE` | `interp` forces the architecture-independent path; used to check JIT/interpreter parity |
| `DUO_WASM_JIT_TRACE` | name the reason the JIT declined a body. It declines **silently** otherwise |
| `DUO_WASM_PHASES` | read / walk / alloc / compile timings |
| `DUO_WASM_DUMP` | write the emitted ARM64 words as hex for disassembly |

A `duon wasm run x.wasm` subcommand is the intended surface and does not exist
yet; it needs `src/main.zig`. See `docs/wasm-integration.md` §3.

## What it does

- WASM binary decoding — section walk, exports, memory, globals, data, elements
- A stack interpreter covering 184 opcodes, architecture-independent
- An **ARM64 JIT written in Duo** (`std.jit` mmap/seal/call), falling back to the
  interpreter on any opcode it cannot emit, so adding opcodes changes speed and
  never changes an answer
- WASI Preview 1, partially: enough `fd_write` for the fixtures that use it
- SIMD (0xFD) on the interpreter path

## What it does NOT do

Named explicitly because the previous version of this file listed fifteen
capabilities with green checkmarks and roughly four of them were real.

- **No AOT.** `src/wasm/aot.duo` is ten lines and `compile()` returns `""`.
- **No x86-64 JIT.** ARM64 only.
- **No component model, no WIT, no WASI Preview 2 or 3.**
- **No threads, atomics, exceptions, GC, multi-memory, memory64, tail-call, or
  relaxed-SIMD.** Zero grep hits for each in `src/engine.duo`.
- **No edge runtime, no serverless adapter, no isolate pool, no REPL, no module
  cache, no memory snapshots, no WASI-NN, no GGUF or ONNX loading, no
  accelerator dispatch.** Every one of those was claimed here. None exists.
- **No embeddable library API.** `src/lib.duo` does not exist.

`src/nn/init.duo` is a 368-line tensor/transformer module that nothing requires
and that has nothing to do with WebAssembly; it is a leftover of the
"AI-native" framing. `docs/wasm-integration.md` §5 proposes moving it to
`lib/std/ml/` or deleting it.

## Layout

```
src/engine.duo      the whole runtime — decoder, interpreter, ARM64 JIT
src/wasm/           a parallel modular tree that NOTHING requires (dead)
  jit_arm64.duo       dead as a module, live as the source of truth for
                      lib/std/compiler/arm64{,check}.duo; a donor for SH-11
  jit.duo             a C-emitting JIT stub — the foreign waist Pass 103 §0b
                      bans by name, sitting in dead code. Should be deleted.
  aot.duo             10-line stub returning ""
src/nn/             tensors and a transformer; not wasm
bench/              6 harnesses + 47 .wasm fixtures (inputs, not source)
test/conform.duo    the differential suite; refuses to score until 5 controls pass
tools/opcodes.duo   the opcode descriptor. Opcode numbers are PROJECTED into
                    src/engine.duo — never type one
```

`src/engine.duo` is one 6,312-line file on purpose. Two codegen constraints
force it: pointer locals must not cross a function boundary, and a bare module
tail makes the native-scalar precheck reject the whole file, at which point
every value transits a boxed `lua_Value` whose numeric payload is a `double` —
which is what once rounded every `f64.const` above 2^53 and cost the low byte.

## Rules this engine learned the hard way

- **"It produced a result" is not coverage.** A harness counting any
  non-sentinel result reported 8/18; differencing against wasmtime showed two
  were plain wrong. Only oracle agreement counts.
- **Every range arm needs a terminal `else return -1`.** `i32.div_s`/`rem_s`
  silently returned **0** for months.
- **The JIT falls back silently.** Check the `engine=` line, or a correctness
  gate stays green while the JIT is dead.
- **Never quote the printed `seconds=`** for a perf claim — it is `os.clock`,
  which on macOS accumulates CPU across threads. Use an interleaved harness.
- **Positive-control every zero, negative-control every oracle.** A gate that
  cannot fail is not evidence.
