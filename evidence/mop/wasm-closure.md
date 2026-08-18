# Wasm closure matrix — measured, not claimed (GLM-E mission)

Base: idol @ aa37b771 + codex in-flight worktree. Every row below is
either executed or source-counted; nothing is taken from README prose
(the tree's own law: capability is only ever read off `zig build wasm-test`).

## Admission path: BLOCKED (fail-closed, by design)

`zig build wasm-test` fails at the engine subject: `idol compile
tools/wasm/src/engine.id --backend=direct` refuses with
`DNB001 missing: keyed-table-export` (dnir_lower). The engine is 6,886
lines of SOURCE-ZERO standalone machinery (README/HANDOFF say exactly
this); `idol check` passes it, object admission does not.

**The same missing fact blocks `tools/lsp/src/server.id`.** One published
fact family unblocks both admission paths. Recorded as handoff H8.

## Proposal matrix (source-class evidence)

| Proposal | State | Evidence |
|---|---|---|
| core (i32/i64/f32/f64, control, calls, memory, tables) | implemented-in-source, differentially tested historically | engine.id 6,886 lines; HANDOFF: "every bench in bench/ that has a wasmtime reference now matches it" |
| SIMD | near-stub | src/wasm/simd.id = 268 lines; bench fixtures exist (simd_family/simd_float) |
| threads / shared / atomics | no evidence | zero atomic/fence/shared opcode sites in engine sources |
| GC / reference types | minimal only | 8 ref.null/ref.func-class sites; no anyref/externref machinery |
| exceptions | none | zero sites |
| tail calls | none | zero sites |
| multi-memory | none | zero sites |
| WASI preview1 | REAL, partial | 73 fd_write/proc_exit/wasi sites; wasi_abi.id live; documented conformance history (9/18 wasi_rt, printf-buffer fixes) |
| WASIX | none | zero source sites; `wart_wasix_extended.wasm` is ORACLE CORPUS ONLY — a fixture to test against, not support |

## Performance: oracle baselines fixed; engine unverifiable

| Bench | Value | wasmtime (this machine) |
|---|---|---|
| fib.wasm | 2178309 | 0.07 s |
| hash.wasm | 1899277430 | 0.50 s |
| wart_wasi_preview1_comprehensive.wasm | runs | 0.09 s |

`engine.out` (Aug 14 artifact) no longer speaks the current CLI — zero
output, instant exit. No honest idol-engine number exists until the
admission path unblocks. wart checkout present at /Volumes/d 1/x/wart
(frozen oracle ca2b0b9c per OPCODE_PLAN); no in-repo wart binary.

## The honest path to "faster than wasmtime and wart"

1. **H8**: publish the keyed-table-export fact family (one fix unblocks
   wasm admission AND the LSP server admission).
2. Engine compile unblocks -> `wasm-test` runs fail-closed conformance ->
   fresh JIT-vs-interpreter-vs-wasmtime-vs-wart table on the existing
   bench corpus (the measurement harness already exists; the corpus
   already has wasmtime references).
3. SOURCE-ZERO convergence of engine.id into the shared graph (codex
   lane; the README's own target architecture).
4. Then the perf ladder is steerable by measurement, per HPLS.

Gating per the operating model: Wasm semantic lawset is never-assign;
Wave 3 starts after the lawset vertical slice. This matrix is the
GLM-E deliverable for it.
