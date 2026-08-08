> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 20 — Universal Cross-Language Metaprogramming Harness

Make Duo immediately useful to projects written in any language — without requiring a rewrite.

**Status:** M0 tracking + C harness proof (2026-08-05).  
**Foundation:** [Pass 5 semantic interchange](pass5_semantic_interchange.md) (SIM v0, C import, foreign adaptation).

## Governing model (§1–§3)

```
foreign project → semantic import → Duo staged values → metaprogram → validated transform → native emit
```

Imported foreign semantics are **ordinary staged Duo data**, not textual macros.

## Pipeline

| Stage | Owner | Status |
| --- | --- | --- |
| C header frontend | `src/c_frontend.zig` | partial |
| SIM import | `src/c_sim_import.zig` | partial |
| Foreign adaptation | `src/foreign_adapter.zig` | partial |
| Import strength | `src/pass20_import_strength.zig` | partial |
| Direct native call | `@comp.c.import` / sema | done (Pass 5 M1) |
| Multi-language frontends | Rust/TS/Python/… | open |
| `duo meta *` CLI | `src/main.zig` | open |

## Adoption ladder (§18)

| Level | Capability | M0 |
| --- | --- | --- |
| 0 Inspect | `duo sim --import-c`, catalog | partial |
| 1 Generate | bindings, docs (planned) | partial |
| 2 Validate | ABI specialize, layout | partial |
| 3–8 Transform → optimize | semantic patches, mixed-language | open |

## Ready tools (§12)

Tracked in `pass20_catalog.ready_tools` — binding generator and ABI auditor partial via Pass 5; remainder open.

## Completion gates (§20)

Validate: `zig build pass20-gate`

| Gate | Title | M0 |
| --- | --- | --- |
| G01 | Useful without Duo prod code | partial |
| G02 | Foreign project as staged values | partial |
| G04 | One source → several artifacts | partial |
| G05 | Deterministic + provenance | partial |
| G09 | CLI/LSP/MCP parity | partial |

## Import strength (§4)

Levels 0–5 in `pass20_import_strength.zig`. C `point.h` reaches **declared_semantic** minimum; post-`abi.specialize` may reach **typed_executable**.

## Commands

```bash
zig build pass20-gate
duo catalog audit gate pass20
duo sim --import-c examples/pass5/fixtures/point.h
duo catalog   # includes pass20 JSON
```

## Prohibited outcomes

Text inference as proven truth; parallel import frameworks per language; requiring full project rewrite for adoption.

## Related

- [`pass5_semantic_interchange.md`](pass5_semantic_interchange.md)
- [`pass22_compiler_architecture_expansion.md`](pass22_compiler_architecture_expansion.md) — foreign semantic capsule (WS28)
