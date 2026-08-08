> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 9 — Ward Readiness, Vertical Proof, and Runtime Supremacy

**Status:** active (2026-08-04)  
**Mission:** Make Duo capable of producing **Ward** — a Duo-native WebAssembly runtime that beats Wart through semantic leverage, not reduced semantics.

Ward is a **consumer** of Duo’s canonical architecture (Passes 1–8), not a fork.

## Machine-readable tracking

```bash
duo catalog | jq '.pass9'
duo catalog | jq '.pass9.duo_capabilities[] | select(.status=="partial")'
duo catalog | jq '.pass9.wasm_semantic_gen.validator_table'
duo catalog | jq '.pass9.wasm_semantic.decoder_table'
duo catalog | jq '.pass9.readiness_summary'
```

| Module | Role |
| --- | --- |
| `src/ward_readiness.zig` | Duo capability ↔ Ward subsystem matrix |
| `src/wasm_semantic.zig` | Canonical Wasm instruction descriptors (63 MVP ops) |
| `src/wasm_semantic_gen.zig` | Comptime decoder index + validator stack metadata |
| `lib/std/wasm/decode.duo` | Opcode + immediate decode via `std.bytes` (P9-06 partial; `std.cursor` when native) |
| `lib/std/wasm/instruction.duo` | Stdlib facade — points to wasm_semantic + gen |
| `~/x/ward` | Vertical proof runtime (Duo sources) |
| `~/x/wart` | Reference baseline (Zig) |

## Governing principles (summary)

1. **Ward reuses Duo** — no Ward-only descriptors, staging, IR, or realization planner.
2. **Duo readiness precedes Ward dependence** — capabilities must reach `WARD_READY` before milestones depend on them.
3. **Beat Wart with equivalent semantics** — disclosed target, warmup, correctness evidence required.
4. **No hidden delegation** — foreign boundaries must be queryable; no generic Lua boxing on hot paths.

## Capability ladder

| Level | Title | Status |
| --- | --- | --- |
| L0 | Repository and benchmark truth | partial |
| L1 | Duo-native systems substrate | open |
| L2 | Wasm semantic model | partial |
| L3 | Decoder and validator proof | open |
| L4 | Baseline interpreter | spike (Ward exists; not proven via Pass 9 gate) |
| L5 | Specialization-aware interpreter | open |
| L6 | Baseline native compiler/JIT | spike |
| L7 | Optimizing compiler | open |
| L8 | Persistent and adaptive Ward | open |

## Milestones

| ID | Title | Status |
| --- | --- | --- |
| P9-M0 | Readiness matrix + repository truth | partial |
| P9-M1 | Descriptor-generated LEB128 + instruction decoder | partial |

## First implementation milestone (P9-M1)

**Descriptor-generated LEB128 + instruction decoder** for a bounded Wasm subset.

Must demonstrate:

- One semantic instruction descriptor source (no duplicated opcode tables)
- Generated decoder + validation metadata
- Native hot path: direct byte loads, no universal boxing, no generic Lua call stack
- Positive + malformed fixtures; differential vs reference where available
- `duo explain` / catalog / MCP visibility of provenance

**Current blockers** (from readiness matrix):

- `duo.lang.slices_buffers` — byte cursor in progress (other agents)
- Opcode facts duplicated: `ward/src/wasm/op.duo` vs legacy paths — **canonical owner now `src/wasm_semantic.zig` (63 MVP instructions)**
- P9-05 generator — **`duo wasm-tables emit`** → `lib/std/wasm/opcode_lookup.duo` (63 MVP ops)
- P9-06 decode — **`lib/std/wasm/decode.duo`** + `decode_semantic_smoke.duo` (semantic id + immediate dispatch)
- Next: validator hot path, dedupe `ward/src/wasm/op.duo`, differential harness (P9-07)

## Workstreams

| ID | Title | Status |
| --- | --- | --- |
| P9-01 | Wart and Ward truth audit | partial |
| P9-02 | Ward readiness registry | partial |
| P9-03 | Native bytes and cursor substrate | partial |
| P9-04 | Wasm semantic descriptor | partial |
| P9-05 | Compile-time generator | partial |
| P9-06 | Native decoder lowering | partial |
| P9-07 | Differential and fuzz harness | open |
| P9-08 | Performance and complexity harness | open |
| P9-09 | LSP + end-user MCP integration | open |
| P9-10 | Development MCP coordination | open |
| P9-11 | Baseline interpreter design gate | open |

## Agent execution order

1. Repository truth audit (P9-01)
2. Readiness registry (P9-02) ← **this pass**
3. Choose bounded Wasm subset
4. Native byte/cursor substrate (P9-03)
5. Semantic instruction descriptor (P9-04)
6. Compile-time generation (P9-05)
7. Native decoder lowering (P9-06)
8. Validator + differential/fuzz (P9-07)
9. Tooling exposure (P9-09)
10. Performance + semantic-density comparison (P9-08)
11. Pass 6-style reconciliation
12. Baseline interpreter gate (P9-11) — **not before P9-M1 complete**

## Readiness status enum

`absent` → `spike` → `partial` → `stable_internal` → `public_experimental` → `ward_ready` → `proven_in_ward`

A capability is `WARD_READY` only when it has one owner, tests, explicit fallback, native lowering, and survives an end-to-end native example.

## Rejection criteria (defer if…)

- Broad Wart port before Duo readiness
- Ward-only language features
- Duplicated instruction facts
- Generated C as canonical Ward path
- Optimizing JIT before decoder/validator foundations
- Separate Wasm semantic graph for interpreter vs compiler

## Validation commands

```bash
zig build
zig test src/ward_readiness.zig
zig test src/pass9_catalog.zig
duo catalog | jq '.pass9.milestones'
duo catalog | jq '.pass9.readiness_summary'
```

## Related plans

- Pass 8: `pass8_persistent_semantic_computing.md` (realization + persistence — Ward L8 builds on this)
- Pass 6: architectural reconciliation (single owner per concept)
- Semantic universe: `docs/semantic_universe.md`

---

## Key Finding: Native Byte Buffer Workaround (2026-08-04)

**Problem:** Duo strings are null-terminated C strings. `string.char(0, ...)` produces
empty string. Wasm binaries start with `\0asm` — first byte is NUL.

**Workaround proven:** `@c.emit` + `@ffi` creates native `uint8_t*` byte buffers:
```duo
@c.emit("static int64_t bb_test(void){uint8_t b[4]={0,97,115,109}; return b[0]|(b[1]<<8)|(b[2]<<16)|((uint32_t)b[3]<<24);}")
@ffi("bb_test") fun wasm_magic(): i64
-- Returns 1836278016 = 0x6D736100 = correct Wasm magic with NUL byte
```

**Conclusion:** Ward CAN proceed with binary parsing today via `@c.emit` primitives.
The long-term fix (native `[N]u8` type) remains an open architectural item.
