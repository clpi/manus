| field | value |
|---|---|
| title | Wasm proposal space — opcode-level gap map and perf lanes |

| # | directive |
|---|---|
| 1 | Measured at 6dce585a. |
| 2 | Opcode table: tools/wasm/src/wasm/op.id (151 entries; saturated with the ruled antipatterns — `M = {`, snake_case `OP_*` — its documented SOURCE-ZERO debt). |
| 3 | Spec totals are public proposal constants; oracle = wasmtime on this machine. |

| section |
|---|---|
| Convergence doctrine (user ruling, 2026-08-17) |

| # | directive |
|---|---|
| 1 | The runtime leverages ALL language features in service of highest performance at lowest syntax: opcode tables via comptime tabulation, dispatch via call specialization, memory via place/region facts, SIMD via simd_lower, the lawset imported through the one graph. |
| 2 | The private standalone engine with hand-rolled tables IS the antipattern; candidate realizations are selected by the transform registry. |

| section |
|---|---|
| Proposal ledger (to completion) |

| Proposal | Spec ops | Implemented | Oracle | Lane |
|---|---|---|---|---|
| MVP core | ~134 | 141-class | wasmtime ✓ | done |
| sign-extension | 7 | 4 in table | wasmtime ✓ | trivial (verify i64 pair) |
| sat-trunc | 8 | in table | wasmtime ✓ | trivial (verify all 8) |
| bulk-memory | 7 | 0 | wasmtime ✓ | small; unblocks wasi-libc memcpy |
| reference-types | ~7 | 0 | wasmtime ✓ | small-mid; GC/func-ref prereq |
| tail-call | 2 | 0 | wasmtime ✓ | small |
| multi-value | 0 (validation) | ? | wasmtime ✓ | verification only |
| multi-memory | 0 (memidx) | 0 | wasmtime ✓ | small |
| threads | ~40 | 0 | wasmtime ✓ | mid; needs shared-memory model |
| relaxed-simd | ~35 | 0 | wasmtime partial | after SIMD |
| SIMD | 236 | 0 | wasmtime ✓ | large but mechanical (grid corpus exists) |
| GC | ~25 | 0 | wasmtime (gc on) | large + host-GC semantic decision |
| exceptions | ~10 | 0 | wasmtime ✓ | mid + control-flow design |
| WASI p1 | ~46 syscalls | partial (9/18 conform history) | wasmtime ✓ | mid |
| placeholder
| WASIX | ~70 syscalls | 0 | NO local oracle (wart calibration first) | largest surface |

| # | directive |
|---|---|
| 1 | Completion order by leverage: bulk-memory -> reference-types -> tail-call -> multi-value/multi-memory verification -> SIMD -> threads -> WASI p1 closure -> relaxed-simd -> GC -> exceptions -> WASI p2 -> WASIX. |

| section |
|---|---|
| Perf lanes (measured) |

| # | directive |
|---|---|
| 1 | Full-corpus wasmtime baseline: bench.oracle.tsv (66 fixtures, 0 timeouts, 12.33 s total). |

| # | directive |
|---|---|
| 1 | **STARTUP LANE — winnable now.** Every fixture pays wasmtime's ~130 ms floor; only hash (583 ms) and hash2b (4405 ms) exceed it. A native-AOT realization beats this floor by 2-3 orders of magnitude, and 60+ fixtures of the EXISTING corpus already measure exactly this lane. |
| 2 | **COMPUTE LANE — needs fixtures.** Generate scaling variants of hash/fib until runtime >> startup; compare crossover curves. |
| 3 | **JIT/interpreter crossover** — the jit_* grid corpus exists for this; unmeasured until admission. |
| 4 | **WASI syscall lane** — design syscall-dense loops when p1 closes. |

| section |
|---|---|
| Wart oracle calibration (measured 2026-08-17) |

| # | directive |
|---|---|
| 1 | `wart run` interpreter: effective mode; startup 29-45 ms (BEATS wasmtime's floor), compute slow (fib 654 ms, hash 14 s, hash2b >60 s). |
| 2 | `--jit`: no measurable effect on these fixtures (fib 878 ms, hash 13.5 s). |
| 3 | `--aot`: COMPILE-ONLY ("AOT compilation successful. Use -o to save native executable"); the emitted artifact is ELF arch 0x5500 — the Wasm-Machine ISA — NOT host-executable on macOS. There is no measured wart AOT execution path on this platform. An earlier 10-17 ms "--aot" reading was compilation time alone; treat any AOT execution claim as unmeasured until a wasm-machine loader exists here. |
| 4 | Competitive map on THIS machine: wasmtime = compute king (hash 0.5 s) with a 130 ms startup floor; wart = startup lane (30-45 ms) with slow compute. Beating "all competition" = wasmtime's compute AND wart's startup AND, eventually, wart's wasm-machine AOT where a loader exists. |

| section |
|---|---|
| Standing blockers |

| # | directive |
|---|---|
| 1 | Admission blocked at module-table representation (corrected H8) plus req's unresolved applications. |
| 2 | Oracles pinned: wasmtime + wart (ca2b0b9c ReleaseFast). |
