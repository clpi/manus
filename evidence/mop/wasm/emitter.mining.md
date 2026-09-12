| field | value |
|---|---|
| title | wart emitter mining — the minimum physical emitter basis |

| # | directive |
|---|---|
| 1 | Lane 6 per the FTCFTW directive (runtime lane: mine wart's proven emitters; do NOT inherit its architecture). |
| 2 | Source: clpi/wart @ ca2b0b9c (frozen oracle), read-only. |

| section |
|---|---|
| Measured emitter surface |

| File | LOC | Role |
|---|---|---|
| src/wasm/jit_arm64.zig | 12,646 | arm64 emitter + selection |
| src/wasm/jit_x64.zig | 4,103 | x64 emitter + selection |
| src/wasm/jit_compile.zig | 23,272 | shared compile driver |
| src/wasm/jit_x64_engine.zig | 965 | x64 execution engine |
| **total** | **40,986** | the whole baseline-JIT subsystem |

| # | directive |
|---|---|
| 1 | Emitter API shape (arm64, 17 emit/enc functions, ~1,394 raw hex encodings): instruction helpers named for the MACHINE operation — `add/adds/cmp/cmn/csel/cbz/cbnz/b/bcond/blr/binop/cmpop/copysign/ accum/...` — each emitting fixed encodings with register operands, plus `__clear_cache` for icache coherence. |
| 2 | That is the whole trick: a thin mnemonic → bytes table plus operand slots. |

| section |
|---|---|
| The minimum physical emitter basis (the extraction target) |

| # | directive |
|---|---|
| 1 | **Encoder core**: one table per ISA mapping (mnemonic, operand shape) → bytes. wart's arm64 emitter is ~12.6k LOC BECAUSE it also carries Wasm-specific selection; the pure encoding table is a small fraction. Mine the tables, not the driver. |
| 2 | **Register operand model**: fixed slot assignment (w/x views on arm64) — mirrors the graph's place residency facts (register candidates), so selection can be driven by PLACE facts rather than a Wasm operand stack. |
| 3 | **Branch/condition helpers** (`bcond/cbz/cbz/csel`): the physical face of region shapes (alternative/recurrence) — one helper per region edge class, not per Wasm opcode. |
| 4 | **Call helpers** (`blr/call/ret`): the physical face of application realization; target selection stays a graph fact (exact/one-of/ unknown card), the emitter only encodes the chosen form. |
| 5 | **icache coherence** (`__clear_cache`): required on arm64 after emitting — a realization fact, not architecture. |
| 6 | **Selection driven by facts**: wart selects per Wasm opcode; the Idol basis selects per APPLICATION/PLACE facts (width 32 + wrap → `add w` variants; f64 → `fadd d`; lane pack → SIMD encodings), so one selector serves Idol AND Wasm origins. |

| section |
|---|---|
| What NOT to inherit (per the directive) |

| # | directive |
|---|---|
| 1 | The 23k-LOC shared compile driver (Wasm-IR-shaped), the separate interpreter/JIT semantic models, opcode-by-opcode architecture, the Wasm-specific register allocator assumptions, and the POSIX-shaped WASI subsystems. |
| 2 | The 512,986-assertion corpus, WASI/WASIX/component oracles, and both ISA encoding tables ARE the assets. |

| section |
|---|---|
| Min-LOC thesis check |

| # | directive |
|---|---|
| 1 | The full wart JIT is ~41k LOC because encoding, selection, and Wasm semantics are fused. |
| 2 | Split by the basis above: encoders (small tables), selection (fact-driven, shared with Idol), semantics (graph facts — already the compiler's). |
| 3 | The emitter basis target is a LOW single-digit thousand LOC for both ISAs, with selection authored once against graph facts — that is the convergence-from-both-sides the directive specifies. |
