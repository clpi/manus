> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 16 — Self-Hosted Compiler Supremacy

> **Status:** Level 1 partial (keyword classify production-integrated) + M1 lexer substrate  
> **Gate:** `zig build pass16-gate` or `duo catalog audit gate pass16`  
> **Catalog:** `duo catalog` → `pass16`  
> **Bootstrap:** `docs/bootstrap.md`  
> **Mission:** Canonical production compiler in Duo; bootstrap closure; compiler-as-proof.

> **Canonical spec:** `docs/archive/duo_self_hosting_foundation.md` is the authoritative
> statement of the self-hosting architecture (bootstrap ladder S0-S3, the single semantic
> graph, the nine IR layers and their invariants, the foundation completion gate). This
> document is the **execution plan** — milestones, gates, catalog wiring. Where the two
> disagree, the canonical spec wins.

## Governing thesis (§1)

Self-hosting is the **architectural closure test** for the entire language. Every weakness exposed while implementing the compiler in Duo must improve the smallest general Duo foundation — not introduce compiler-only escape hatches.

The self-hosted compiler is an ordinary Duo program exercising extraordinary amounts of Duo's semantic system. Privileged capabilities are allowed only when explicitly modeled, generally useful, semantically justified, queryable, testable, and not hidden host-language access.

## Definition of genuine self-hosting (§2)

| Criterion | Requirement | Current status |
| --- | --- | --- |
| **Implementation** | Canonical production compiler predominantly in Duo | **partial** — `lib/std/compiler/*` exists; production still Zig |
| **Canonical path** | Source → Duo semantic graph → **DNIR** → ARM64 object (C emit bootstrap-only via `--backend=c`) | **partial** — typed subset: AST→DNIR→Mach-O in `native_backend.zig`; full graph feed open |
| **Bootstrap closure** | S0→S1→S2 with semantic/behavioral equivalence | **S0 only** — see `src/bootstrap_dag.zig` |
| **Semantic ownership** | Lexer/parser/binding/transforms/ABI owned by Duo compiler | **partial** — Zig host authoritative |
| **Runtime independence** | Minimal compiler runtime profile, enumerable boundaries | **open** |
| **Tooling closure** | LSP/MCP/formatter consume shared compiler facts | **open** |

## Honest current state

| Claim | Evidence | Status |
| --- | --- | --- |
| Compiler written in Duo | `lib/std/compiler/{source,token,lexer}.duo` | **partial** |
| Production path uses Duo components | Keyword classify via `duo_keyword_classify.c` | **partial (SH-02)** |
| Bootstrap closure S0→S1→S2 | Zig seed only | **open** |
| No silent generated-C canonical path | Default release still C via `codegen.zig` | **bootstrap (explicit)** |
| `claim.self_hosted` | `selfhosting_matrix.publicManifest()` → `partial`, level **1** | **honest** |

**Completion level:** **1** (keyword classify on production path) with **M1 partial** (Duo-native lexer compiles; full lexer not production-authoritative).

| Claim | Evidence | Status |
| --- | --- | --- |
| Keyword production dispatch | `duo_keyword_classify` ← `classify.duo` via `src/duo_keyword_classify.c` | **integrated** |
| Production lexer keyword path | `src/lexer.zig` → `token_semantic.lookupKeyword` → `duo_keyword_bridge` | **integrated** |
| Host differential oracle | `token_semantic.lookupKeywordOracle` / branch_chain | **retained** |
| Full Duo lexer in production | `lib/std/compiler/lexer.duo` | **not yet** |

## Success priorities (§3)

1. **Correctness** — no self-hosting claim via skipped validation or narrowed semantics  
2. **Compiler execution speed** — phase-cost instrumentation; incremental by dependency  
3. **Generated program performance** — preserve specialization ladder in compiler implementation  
4. **Architectural sovereignty** — no parallel semantic authority in host language  
5. **Semantic compression** — one canonical fact drives parser/formatter/LSP/MCP/docs  
6. **Development ergonomics** — every subsystem exposes owner, inputs, outputs, invariants, cost

## Canonical compiler layers (§5)

| Layer | Owner today | Duo target |
| --- | --- | --- |
| Source substrate | `lib/std/compiler/source.duo` | Production source identities + incremental edits |
| Token/grammar descriptor | `lib/std/token/classify.duo` → `duo_keyword_classify.c` (production) | `token_semantic.zig` (oracle) |
| Syntax graph | open | Persistent green/lossless structure |
| Semantic graph | `src/semantic_graph.zig` (Zig partial) | Canonical compiler truth |
| Transformations | `src/transform_engine.zig` (partial) | Unified transformation model |
| Low-level IR | **`src/duo_native_ir.zig` + `src/dnir_lower.zig`** (DNIR) | Typed SSA-ish IR; hardware intrinsics via `src/dnir_hardware.zig` |
| Machine IR | **`src/native_backend.zig`** (ARM64 DNIR backend) | Direct `dmb`/`cnt`/`yield` — not `__builtin_*` |
| Object/link | `src/native_backend.zig` (ARM64 subset) | Duo-owned Mach-O/ELF/Wasm writers |

## Bootstrap stages (§12)

| Stage | Artifact | Status |
| --- | --- | --- |
| S0 | Pinned Zig bootstrap (`zig build`) | **active** |
| S1 | S0 compiles canonical Duo compiler source | **open** |
| S2 | S1 recompiles same source | **open** |
| S3 | S2 recompiles again (reproducibility) | **open** |

See `docs/bootstrap.md` and `src/bootstrap_dag.zig`.

## First vertical milestone — M1 (§14)

Duo-native **source + lexer + token descriptor** used by the **production** compiler for a bounded subset, with differential validation against the Zig host.

**Proof:** `examples/pass16_m1_lexer_proof.duo`, `examples/pass16_source_cursor_proof.duo`  
**Modules:** `std.compiler.source`, `std.compiler.token`, `std.compiler.lexer`, `std.token.classify`

**Integration gate (not yet met):** production compiler invokes Duo-native lexer; host path becomes differential oracle only.

**M1 language/codegen progress (2026-08-04):**

| Fix | Files | Effect |
| --- | --- | --- |
| Table literal vs destructure disambiguation | `src/parser.zig` | `{ file = x }` parses as table literal, not `{ file } =` pattern |
| Nested block tail return check | `src/sema.zig` | `while`/`if` bodies no longer inherit enclosing function return type |
| Record decl dependency order | `src/codegen.zig` | Nested record typedefs emit before use |
| Alias-aware function return type | `src/codegen.zig` | `resolve_type` for `: Loc` / `: Tok` record returns |
| Native record implicit/explicit return | `src/codegen.zig` | `(Type){ .field = ... }` for table literal returns |
| Native record call returns in allowlist | `src/codegen.zig` | `expr_is_native_scalar` admits `table_type` that lowers native |
| Main-module native direct calls | `src/codegen.zig` | Allowlisted callees emit `cur_loc(self)` not `lua_invoke` |
| Native record mutation (MP4-B01) | `src/codegen.zig` | Record params emit as `T *self`; field access via `->`; call sites pass `&arg`; Lua thunk write-back |
| Lexer native hint buffer | `lib/std/compiler/lexer.duo` | Fixed `hint_count` + 8 slots; no `pending_hints: any` |
| Lexer save/restore state | `lib/std/compiler/lexer.duo` | `has_peeked` + `peeked_token` instead of `any` peeked |

**Full `lib/std/compiler/lexer.duo` embed — status (2026-08-05):**

- **Compiles and links** via `duo lib/std/compiler/lexer.duo` (mixed native mode)
- Same-module native direct calls working (`cur_loc(self)`, `read_num(self)`, etc.)
- **MP4-B01 closed:** `Lexer.next()` tokenizes at runtime (no infinite loop); record params emit as pointers so `adv(self)` mutations persist
- **Sema clean:** `adv(self)` is void; one-line `if cond adv(self)` patterns expanded to block form
- **Production integration partial (MP4-B02):** `src/duo_lexer_bridge.zig` documents explicit authority split — keyword leg Duo-native via `duo_keyword_bridge`; full tokenize remains host `src/lexer.zig` until C projection lands
- `consume_hints` / dynamic table append in hint export remains on dynamic boundary (non-hot)

**Proof:** `examples/pass16_m1_lexer_proof.duo` — token classify + native `Loc` record returns (exit 0).  
**Proof:** `examples/pass16_hardware_direct.duo` — `@fence` + `@popcount` on DNIR→ARM64 (exit 0; no C emit).  
**Proof:** `examples/pass16_source_cursor_proof.duo` — inline 1-based cursor walk (exit 0; avoids embedded `req` until record module lowering is production-ready).  
**Proof:** `examples/pass16_lexer_embed_proof.duo` — constructor-only embed smoke (exit 0).  
**Proof:** `examples/pass16_lexer_tokenize_proof.duo` — `Lexer.next()` returns `fun` + EOF (exit 0; MP4-B01 regression).  
**Proof:** `lib/std/compiler/lexer.duo` — full Duo-native lexer module compiles to native C (exit 0).  
**Verify:** `duo selfhost verify` — keyword + source cursor + lexer corpus/embed/tokenize (`selfhost-verify-v1`).  
**Introspect:** `duo selfhost lexer-bridge` — tokenize vs keyword authority JSON (`duo-lexer-bridge-v0`).

## Workstreams

Thirty bounded workstreams (`P16-WS1` … `P16-WS30`) in `src/pass16_catalog.zig`. Suggested migration order follows §13 (source → tokens → lexer → parser → semantic graph → IR → backend → bootstrap → tooling).

## Required audits (§21)

Twelve audits tracked in `src/pass16_selfhost_audit.zig`:

1. Self-hosting truth  
2. Host-shape contamination  
3. Duplicate semantic ownership  
4. Compiler dynamic-boundary audit  
5. Compiler memory audit  
6. Compiler latency audit  
7. Bootstrap dependency audit  
8. Backend closure audit  
9. Target parity audit  
10. Tooling duplication audit  
11. Bootstrap reproducibility audit  
12. Self-hosting ergonomics audit  

## Deliverables (§22)

| Deliverable | Location |
| --- | --- |
| Self-hosting matrix | `src/selfhosting_matrix.zig` |
| Bootstrap DAG | `src/bootstrap_dag.zig` |
| Bootstrap subset (S1) | `src/bootstrap_subset.zig` |
| Capability closure matrix | `src/compiler_capability_matrix.zig` |
| Dynamic boundary report | `src/compiler_dynamic_boundary.zig` |
| Removal ledger | `src/removal_ledger.zig` |
| Semantic compression report | `src/semantic_compression_report.zig` |
| Compiler performance baseline | `src/compiler_perf_baseline.zig` |
| Proof bundles | `src/bootstrap_proof.zig` |
| Stage comparison (S0→S3) | `src/stage_compare.zig` |
| Production path manifest | `src/selfhost_production_path.zig` |
| Migration plan (§22.7) | `src/selfhost_migration_plan.zig` |
| Cross-target matrix (§17) | `src/selfhost_target_matrix.zig` |
| Production keyword verify | `src/selfhost_verify.zig` |
| Twelve audits | `src/pass16_selfhost_audit.zig` |
| Workstreams + milestones | `src/pass16_catalog.zig` |
| Public manifest + CLI | `duo selfhost manifest` / `duo catalog` → `pass16` |

## Commands

```bash
duo selfhost manifest          # public self-hosting manifest (§22.10)
duo selfhost matrix            # host vs Duo ownership map
duo selfhost bootstrap         # S0→S3 DAG
duo selfhost subset            # minimum Duo subset for S1
duo selfhost boundary          # dynamic boundary report
duo selfhost capabilities      # compiler capability closure matrix
duo selfhost ledger            # host-path removal ledger
duo selfhost compression       # semantic compression report
duo selfhost perf measure       # native keyword lookup timing (CP-04)
duo selfhost perf baseline     # compiler performance baseline
duo selfhost proof bundles     # bootstrap proof bundles
duo selfhost stage             # S0→S3 stage comparison scaffold
duo selfhost targets           # §17 cross-architecture target parity matrix
duo selfhost production        # production compile-path authority (§2.2)
duo selfhost migration         # §22.7 dependency-ordered migration plan
duo selfhost verify            # production keyword differential (M1)
duo selfhost compare/keywords  # alias for verify
duo selfhost summary           # one-line JSON rollup
duo catalog audit gate pass16
zig build pass16-gate
zig build pass16-cross-platform  # §17 target matrix + host-aware gate
zig build pass16-m1-smoke        # M1 proofs + verify + pass16-gate
zig build pass-gates           # passes 11–16
duo run examples/pass16_m1_lexer_proof.duo
duo run examples/pass12_m1_diff.duo
```

## Cross-architecture compiler supremacy (§17)

Honest target parity tracked in `src/selfhost_target_matrix.zig` — per triple:

- compiler builds / runs / self-hosts  
- object emission and bootstrap stage  
- cross-compile-from-host status  
- known gaps (notes)

Gate: `zig build pass16-cross-platform` (host-aware; no bash/jq). CI job `pass16-cross` runs on **ubuntu-latest** and **macos-latest** every PR. CLI: `duo selfhost targets`.

| Target | Builds | Runs | Self-host | Object emit | Bootstrap |
| --- | --- | --- | --- | --- | --- |
| aarch64-macos | proven | proven | open | partial | S0 |
| aarch64-linux-gnu | partial | partial | open | open | S0 |
| x86_64-linux-gnu | proven | proven | open | open | S0 |
| x86_64-macos | partial | partial | open | open | S0 |
| wasm32-wasi | partial | partial | open | partial | S0 |
| riscv64-linux-gnu | planned | planned | open | open | none |
| x86_64-windows-msvc | planned | planned | open | open | none |

Completion **level 6** remains **open** until the compiler builds and runs on at least two major architectures and cross-compilation is proven — the matrix is tracking only (milestone **P16-M5 partial**).

## Completion levels (§24)

| Level | Title | Status |
| --- | --- | --- |
| 0 | Truth | **done** |
| 1 | Production Duo frontend component | **partial** |
| 2 | Duo-native frontend | open |
| 3 | Duo-native optimizing middle end | open |
| 4 | Duo-native backend on one target | open |
| 5 | Bootstrap closure | open |
| 6 | Cross-target self-hosting | **partial** (matrix + gate; proofs open) |
| 7 | Compiler supremacy | open |
| 8 | Living self-improving compiler | open |

## Prohibited outcomes (§20)

No mechanical Zig-to-Duo translation presented as done; no self-hosted frontend that still emits C canonically; no duplicate LSP/MCP semantic graphs; no false self-hosting claims; no silent backend fallback; no undocumented bootstrap binaries.

## Governing questions (final)

For every Pass 16 decision: Does it move semantic authority into Duo? Does the production compiler actually use it? Can the old authority be retired? Would this remain defensible after a decade of compiler evolution?

**Final standard:** Duo should not merely compile its own source — the self-hosted compiler must embody the strongest expression of Duo's language philosophy: compact code progressively understood, specialized, represented, validated, and lowered without surrendering semantic authority to another system.
