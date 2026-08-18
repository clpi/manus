# Wasm proposal space — opcode-level gap map and perf lanes

Measured at 6dce585a. Opcode table: tools/wasm/src/wasm/op.id (151
entries; saturated with the ruled antipatterns — `M = {`, snake_case
`OP_*` — its documented SOURCE-ZERO debt). Spec totals are public
proposal constants; oracle = wasmtime on this machine.

## Convergence doctrine (user ruling, 2026-08-17)

The runtime leverages ALL language features in service of highest
performance at lowest syntax: opcode tables via comptime tabulation,
dispatch via call specialization, memory via place/region facts, SIMD
via simd_lower, the lawset imported through the one graph. The private
standalone engine with hand-rolled tables IS the antipattern; candidate
realizations are selected by the transform registry.

## Proposal ledger (to completion)

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
| WASI p2 (component) | — | 0 | wasmtime component ✓ | architectural |
| WASIX | ~70 syscalls | 0 | NO local oracle (wart calibration first) | largest surface |

Completion order by leverage: bulk-memory -> reference-types ->
tail-call -> multi-value/multi-memory verification -> SIMD -> threads ->
WASI p1 closure -> relaxed-simd -> GC -> exceptions -> WASI p2 -> WASIX.

## Perf lanes (measured)

Full-corpus wasmtime baseline: bench.oracle.tsv (66 fixtures, 0
timeouts, 12.33 s total).

1. **STARTUP LANE — winnable now.** Every fixture pays wasmtime's
   ~130 ms floor; only hash (583 ms) and hash2b (4405 ms) exceed it.
   A native-AOT realization beats this floor by 2-3 orders of
   magnitude, and 60+ fixtures of the EXISTING corpus already measure
   exactly this lane.
2. **COMPUTE LANE — needs fixtures.** Generate scaling variants of
   hash/fib until runtime >> startup; compare crossover curves.
3. **JIT/interpreter crossover** — the jit_* grid corpus exists for
   this; unmeasured until admission.
4. **WASI syscall lane** — design syscall-dense loops when p1 closes.

## Standing blockers

Admission blocked at module-table representation (corrected H8) plus
req's unresolved applications. Oracles pinned: wasmtime + wart
(ca2b0b9c ReleaseFast).
