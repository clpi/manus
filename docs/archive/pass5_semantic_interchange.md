> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 5 — Semantic Interchange, Cross-Language Metaprogramming

**Status:** Phase 0 audit complete · Phase 1 (SIM v0) partial · Phase 2 (C import) partial · **P5-M1 direct call done · abi.specialize partial**
**Schema:** `sim-v0` (`src/sim.zig`)  
**C frontend:** `c-header-v0` (`src/c_frontend.zig`)  
**Catalog:** `duo catalog` → `pass5` section via `src/pass5_catalog.zig`

## Mission

Build a Duo-owned semantic interchange and transformation system through which Duo can
import, understand, transform, specialize, validate, and selectively re-emit programs and
interfaces from other languages **without** abandoning descriptors, shapes, calls, stages,
effects, provenance, representation model, or native compilation architecture.

Dependency direction (never reverse):

```
Duo semantic foundations
  → versioned semantic interchange (SIM)
  → foreign semantic import
  → shared transformations
  → Duo specialization / representation selection
  → native execution or language-specific emission
```

## Phase 0 — Repository truth audit

### Source-to-machine pipeline

| Stage | File(s) | Role |
| --- | --- | --- |
| Lex/parse | `src/lexer.zig`, `src/parser.zig` | `.duo` / `.lua`; `@c.import` → `cinclude` stmt only |
| AST | `src/ast.zig` | `alias_def`, `enum_def`, `func_decl`, attributes |
| Types | `src/types.zig` | `ResolvedType`, storage classes, shape identity hashes |
| Sema | `src/sema.zig` | Type check, call shapes, native eligibility |
| Semantic graph | `src/semantic_graph.zig` | Lift module/calls/shapes; `writeJson` agent snapshot |
| Algebra | `src/semantic_algebra.zig` | Knowledge lattice, descriptors, call/site algebra |
| Transforms | `src/transform_engine.zig` | Registered transforms + provenance |
| Dynamic boundaries | `src/dynamic_boundary.zig` | `@comp.why.boxed` explanations |
| Codegen | `src/codegen.zig` | C emission; `@c.import` → `#include` |
| Native backend | `src/native_backend.zig` | Direct object for sealed f64 kernels (Pass 4 M1) |

### Semantic entity map → SIM v0 fields

| SIM field | Current source | Status |
| --- | --- | --- |
| `id` | `duo:{kind}:{name}` from AST export | **implemented** (`sim.exportNativeModule`) |
| `origin.language` | `"duo"` for native export | **implemented** |
| `origin.artifact` | module file path | **implemented** |
| `kind` record/enum/function | `alias_def`, `enum_def`, `func_decl` | **implemented** |
| `fields[]` | `types.resolve` + `table_type.fields` | **implemented** |
| `variants[]` | `enum_def.variants` | **implemented** |
| `params[]`, `return_type` | `func_decl` | **implemented** |
| `storage_class`, `why`, `shape_id` | `types.inferStorageClass`, `explainStorageClass`, shape hash | **implemented** |
| `contract.*_completeness` | heuristics from storage class + native fields | **partial** |
| `size_bytes`, `align_bytes` | native field count × 8 heuristic | **partial** — not target-verified |
| `abi` | placeholder `duo-native` | **partial** |
| `effects`, `capabilities` | `semantic_algebra` exists; not exported to SIM | **unavailable** |
| `stage` | graph nodes only | **unavailable in SIM** |
| `provenance` / span | graph `SpanRef`; not in SIM v0 | **unavailable** |
| `dependencies` | not tracked | **unavailable** |
| `diagnostics` | sema errors separate | **unavailable** |
| foreign `origin` | `c_sim_import.zig` | **partial** — `origin.language = "c"` |

### Internal vs interchange boundaries

| Representation | Mutable internal? | Serializable? | Notes |
| --- | --- | --- | --- |
| `SemanticGraph` | yes | `writeJson` (graph-specific) | Not versioned; not foreign-import ready |
| `sim.Snapshot` | no (immutable export) | `writeSnapshotJson` | **SIM v0** — stable schema string |
| `types.ResolvedType` | sema-owned | indirect via export | Compiler-internal |
| `@c.import` / `@comp.c.import` | parse → `cinclude` stmt; sema SIM import; codegen `#include` + `extern` + direct call | **P5-M1 done** for `point.h` |

### LSP / MCP exposure (current)

| Surface | Location | Facts exposed |
| --- | --- | --- |
| `duo graph <file>` | `main.zig` | Graph JSON (shapes, calls, transforms) |
| `duo sim --import-c <header>` | `main.zig` | C header → SIM v0 via frontend + importer |
| `duo sim --import-c <header>` | `main.zig` | C declarations → SIM v0 JSON |
| `duo catalog` | `pass3_catalog.zig` | Pass 3/4/5 workstream tracking |
| duo-mcp | external repo | **partial** — `duo_semantic_snapshot`, `duo_foreign_import_preview`, `duo_pass5_catalog`, `duo_foreign_entity_lookup` |
| duo-lsp | external repo | **partial** — foreign SIM hover on `@c.import` symbols (origin, layout, ABI) |

### Pass 4 blockers relevant to Pass 5

| ID | Blocker | Pass 5 impact |
| --- | --- | --- |
| PB-011 | Boxed-value inventory incomplete | Foreign calls must not route through `lua_Value` |
| P4-05 | Native call ABI foundation partial | Direct C call depends on this |
| P4-M1 | Sealed f64 record + distance2 | Native export proof; C import must reuse same ABI path |
| Graph vs SIM | Two JSON formats | SIM must remain projection, not duplicate graph lift |

### C import current state

- `@c.import("h.h")` — parser + codegen emit `#include` only (`parser.zig`, `codegen.zig`)
- No Clang frontend, no SIM entities with `origin.language = "c"`
- `foreign_transpile.zig` — text transpile for `@foreign`, unrelated to SIM

## Layer status

| Layer | Description | Status |
| --- | --- | --- |
| **A** | Semantic interchange (SIM) | **partial** — v0 schema + native export + CLI |
| **C** | Foreign interface import | **partial** — `c_frontend.zig` + `c_sim_import.zig` + `duo sim --import-c` |
| **C** | Foreign descriptor adaptation | **partial** — `foreign_adapter.zig` + sema/codegen wiring |
| **C** | Cross-language transformation | **partial** — `abi.specialize` in `abi_specialize.zig` + transform_engine registry |
| **D** | Foreign implementation import | **deferred** |
| **E** | Semantic re-emission | **deferred** |

## First milestone (P5-M1)

C fixture (`examples/pass5/fixtures/point.h`):

```c
typedef struct { double x; double y; } CPoint;
double distance2(CPoint point);
```

Target Duo usage (syntax **proposed**, not canonical):

```duo
math = @c.import "point.h"
p: math.CPoint = { x = 3.0, y = 4.0 }
result = math.distance2(p)
```

Exit criteria checklist: SIM entity · foreign descriptor · layout verified · **direct native call (done)** · no wrapper C · MCP/LSP exposure.

## Workstreams

See `src/pass5_catalog.zig` — IDs `P5-00` … `P5-10`.

## Agent claims (Pass 5)

| Tag | Owner | Scope |
| --- | --- | --- |
| `pass5-audit` | cursor/agent | Phase 0 doc + catalog — **done** |
| `pass5-sim` | cursor/agent | `src/sim.zig`, `duo sim`, snapshot tests |
| `pass5-c-frontend` | cursor/agent | `src/c_frontend.zig`, bounded C parser |
| `pass5-importer` | cursor/agent | `src/c_sim_import.zig`, C → SIM |
| `pass5-mcp` | unclaimed | duo-mcp semantic tools |
| `pass5-lsp` | unclaimed | duo-lsp foreign hover |

## Validation commands

```bash
zig test src/sim.zig
zig test src/c_frontend.zig
zig test src/c_sim_import.zig
zig test src/c_layout_verify.zig
scripts/duo_lock.sh -- zig build unit-test --summary all
./zig-out/bin/duo sim examples/pass4_native_milestone.duo
./zig-out/bin/duo sim --import-c examples/pass5/fixtures/point.h
./zig-out/bin/duo dump-c examples/pass5/c_point_smoke.duo
zig test src/pass5_golden_tests.zig --test-filter "pass5 golden"
duo run ../duo-mcp/pass5_smoke.duo   # from DUO_ROOT (MCP shared helpers)
./zig-out/bin/duo sim --import-c examples/pass5/fixtures/point.h | jq '.entities[].name'
```

## Explicit non-goals (initial pass)

Universal AST, LLVM IR as interchange, whole-C source import, Python/Rust simultaneous
import, bidirectional source rewriting, MCP-only semantic records.
