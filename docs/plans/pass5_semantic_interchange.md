# Pass 5 — Semantic Interchange, Cross-Language Metaprogramming, and Ecosystem

> **Date:** 2026-08-04  
> **Follows:** Pass 4 (native boundaries, Duo-owned pipeline, self-hosting)  
> **Mission:** Duo-owned semantic interchange (SIM) for import, transform, validate, and selective re-emission across language boundaries — without reversing Pass 4 architecture.

**Constraint:** Pass 5 must not outrun Pass 4. Cross-language work reuses stable Duo foundations only.

---

## A. Phase 0 repository audit (2026-08-04)

| Area | File(s) | Symbol / behavior | Pass 5 role | Stability |
| --- | --- | --- | --- | --- |
| Descriptors / types | `src/types.zig` | `ResolvedType`, `StorageClass`, `explainStorageClass` | SIM field source | ✅ stable |
| Semantic analysis | `src/sema.zig` | `Sema`, `type_map` | Type facts for export | ✅ stable |
| Semantic graph (internal) | `src/semantic_graph.zig` | `liftModuleWithCalls`, `writeJson` | Pre-SIM agent JSON; not SIM | 🔄 partial |
| Transform registry | `src/transform_engine.zig` | `descriptor()`, contracts | Shared transformations | ✅ stable |
| Dynamic boundaries | `src/dynamic_boundary.zig` | `explainBoxed`, `ExprFacts` | Native-path explanations | 🔄 partial |
| C include/import surface | `src/parser.zig`, `meta_module.zig` | `@c.import`, `__c_import` | Layer B frontend hook | 🔄 header-only today |
| Foreign transpile (legacy) | `src/foreign_transpile.zig` | text transpile | **Not** SIM — defer | ⚠️ text-based |
| Native backend | `src/native_backend.zig` | arm64 Mach-O, f64 records | Layer E native bridge | 🔄 partial |
| MCP / LSP | sibling repos | — | Layer A transport (planned) | ⬜ |
| **SIM v0** | `src/sim.zig` | `exportNativeModule`, `writeSnapshotJson` | **Layer A foundation** | 🆕 experimental |

### Pass 4 blockers relevant to Pass 5

| Blocker | Impact on Pass 5 |
| --- | --- |
| PB-011 (~1870 `lua_Value` refs) | Foreign calls must not route through boxed center |
| C import is include-only today | Layer B requires C→SIM importer, not `#include` |
| No C layout verifier in-tree | Phase 2 needs target layout fixtures |
| MCP/LSP lack SIM tools | Phase 6 tooling after compiler API stabilizes |

### Dependency direction (mandatory)

```
Duo semantic foundations → SIM → foreign import → transforms → native/emission
```

Never: foreign AST → compiler internals without SIM.

---

## B. SIM (Semantic Interchange Model)

**Not** the internal semantic graph. A versioned, serializable projection.

| Property | SIM v0 |
| --- | --- |
| Schema | `sim-v0` |
| CLI | `duo sim <file.duo>` |
| Module | `src/sim.zig` |
| Entities | record, enum, function (+ contract, origin, completeness) |
| Uncertainty | `completeness`: complete \| partial \| opaque \| unsupported \| unknown |
| IDs | `duo:{kind}:{name}` sorted deterministically |

### SIM v0 fields (implemented)

- semantic identity (`id`, `kind`, `name`, `namespace`)
- origin (`language`, `artifact`, `importer`, `importer_version`)
- record: `fields`, `storage_class`, `shape_id`, `why`, `size_bytes`, `align_bytes`
- enum: `variants`, `shape_id`
- function: `params`, `return_type`, `abi` stub
- contract: completeness dimensions

### Explicitly deferred to SIM v1+

- foreign C entities
- effects / capabilities detail
- provenance spans
- layout verification status
- transformation permissions
- opaque import nodes from C

---

## C. Five layers (incremental)

| Layer | Description | Status |
| --- | --- | --- |
| **A** | SIM foundation | 🔄 v0 native export |
| **B** | Foreign interface import (C headers) | ⬜ Phase 2 |
| **C** | Cross-language transformation | ⬜ Phase 5 (`abi.specialize`) |
| **D** | Foreign implementation import | ⬜ deferred |
| **E** | Semantic re-emission | ⬜ deferred |

---

## D. First foreign target: C interface import

**Not** whole-C source. Bounded header subset (Phase 2):

- scalars, enums, records, pointers, const arrays, function declarations
- defer: macros, variadics, C++, bitfields, inline bodies

**First milestone demo (target):** `CPoint` + `distance2` from `point.h` → SIM → foreign descriptor → direct native call.

Syntax **not approved** — may be `@c.import "point.h"` when Layer B lands.

---

## E. First shared transformation

**`abi.specialize`** — descriptor-driven ABI specialization on native Duo + imported C callables.

Requires: SIM callable entities, representation selection, provenance (Phase 5).

---

## F. Execution phases

| Phase | Deliverable | Gate |
| --- | --- | --- |
| 0 | Repository audit (this doc) | SIM fields mapped to sources |
| 1 | SIM v0 + native export | Deterministic snapshots ✅ |
| 2 | C declaration import | Layout + unsupported explicit |
| 3 | Foreign descriptor adaptation | Duo refs without generated bindings |
| 4 | Direct native call (imported fn) | No C wrapper, disassembly proof |
| 5 | Shared `abi.specialize` transform | Same code path native + imported |
| 6 | Semantic patch prototype | MCP transactional requests |
| 7 | Second importer (Wasm / Rust / SQL) | Reuses SIM without fork |

---

## G. Agent workstreams

| ID | Workstream | Status |
| --- | --- | --- |
| P5-WS01 | Repository cartographer (Phase 0 audit) | ✅ |
| P5-WS02 | SIM schema v0 | 🔄 |
| P5-WS03 | Native snapshot export | 🔄 |
| P5-WS04 | C frontend spike | ⬜ |
| P5-WS05 | C-to-SIM mapping | ⬜ |
| P5-WS06 | Foreign descriptor adaptation | ⬜ |
| P5-WS07 | Native ABI call (imported) | ⬜ |
| P5-WS08 | `abi.specialize` transformation | ⬜ |
| P5-WS09 | MCP SIM tools | ⬜ |
| P5-WS10 | LSP foreign hover | ⬜ |

Machine-readable: `duo catalog` → `pass5` section.

---

## H. Validation

```bash
zig test src/sim.zig
duo sim examples/pass4_native_milestone.duo
duo catalog   # includes pass5 workstreams
```

---

## I. Non-goals (initial pass)

Universal parsing, whole-language equivalence, C++ templates, Python runtime, bidirectional round-trip, text-only transpile as SIM substitute.
