# The Zig ledger: what is actually removable

Measured 2026-08-08 at `2d8b224` (branch `canonical-to-relation`). Every number
below is a measurement with its method stated. Where a claim could not be
verified it is marked **UNVERIFIED** rather than estimated.

This document answers one question: *the owner wants no Zig beyond the minimum
for a 100% self-hosted compiler — what can go, in what order, and what does
each removal cost?*

Filed as **gap[080]**. Companion: **gap[079]** finds that `src/*.zig` is the one
corpus the deny table cannot see; this one finds it is also the corpus the
removal ledger cannot see.

## 0. The ledger, reconciled

`zig build language-census` ratchets on TRACKED files (`CENSUS_ZIG_CEILING=237`).
That number is not "files in `src/`":

| set | files | lines |
|---|---|---|
| `src/*.zig` on disk | 237 | 144,804 |
| — of which UNTRACKED (`_dbg.zig`, `_dbg2.zig`, `_alias_dbg.zig`) | 3 | 93 |
| tracked `src/*.zig` | 234 | 144,711 |
| `build.zig` | 1 | 1,238 |
| `tests/test_ast.zig` + `tests/test_hash.zig` | 2 | 205 |
| **census total (tracked)** | **237** | **146,154** |

The coincidence that `src/` on disk and the census total are both 237 hid the
fact that they are different sets. The three `_dbg` files cost nothing against
the ratchet; the two `tests/*.zig` files do.

## 1. Method, and one measurement error found and corrected

Import graph: `@import("X.zig")` edges over all 237 files, transitive closure
from every `b.path("src/*.zig")` root in `build.zig` (13 roots).

**A first pass at this reported 232/237 reachable from `main.zig` and was
wrong.** The awk BFS tested `seen[from[i]]` on an array, and awk
*auto-vivifies* the key on read, so `for (k in seen)` enumerated every node that
appears as an edge source — not the reachable set. It inflated
`reach(main.zig)` from 204 to 232 and the `codegen.zig` precheck closure from 94
functions to 491. The bug was caught by a positive control: `emit_module` has
zero in-edges, so it can never be reachable from anything, yet it appeared in
the result. The fixed BFS uses `(from[i] in seen)`. **Every reachability number
in this document comes from the fixed version and carries a positive control.**

## 2. Reachability does not drive removal here

| root set | files reachable |
|---|---|
| `main.zig` | 204 |
| `tests.zig` | 224 |
| all 13 `build.zig` roots | 225 |
| **unreachable from every root** | **12** |

Cutting any single `main.zig` import loses at most 8 files — the tree is a dense
mesh, not a layered stack. **Removal must therefore be judged by purpose, not by
graph position.** The graph's only decisive contribution is the 12-file dead set
in §4.

## 3. `codegen.zig` split by purpose — the hypothesis, tested

34,971 lines. Sections found by locating the top-level declaration boundaries;
function spans by locating each `fn` and taking the run to the next one; the
intra-file call graph from `self.X(` call sites with comments stripped.

| section | lines | what it is |
|---|---|---|
| preamble + free helpers | 291 | imports, `native_diag`, reason buffer |
| `CodeGen` struct (240–24170) | 23,931 | the emitter |
| `duo_dense_runtime` (24223–24318) | 96 | **C source, as a Zig string** |
| `duo_runtime` (24319–29841) | 5,523 | **C source, as a Zig string** — 286 distinct `lua_*` symbols |
| tests (29842–34971), 213 blocks | 5,130 | |

**5,619 lines — 16% of the file — are literally C runtime source text.** They
are emitted into the generated `.c` and have no reader on the direct path.

Inside the struct, 675 functions / 23,682 accounted lines:

| partition | fns | lines | method |
|---|---|---|---|
| reachable from `can_emit_native_scalar_module` (the direct-path admission gate) | 94 | 2,481 | call-graph closure, controlled |
| reachable from `emit_module` **but not** the precheck | 477 | 19,423 | set difference |
| in neither closure | 104 | 1,778 | 97 are false negatives of the `self.X(` pattern (free/nested/callback); **4 are genuinely unreferenced, 29 lines** |

**The decisive structural finding: `reach(precheck)` is a strict SUBSET of
`reach(emit_module)` — the precheck-only partition is ZERO functions.** The
direct backend's admission gate is a method on the C emitter's struct and shares
all 2,481 of its lines with C emission. `main.zig:4074` constructs a whole
`CodeGen` with an `undefined` writer purely to ask
`can_emit_native_scalar_module`. So `codegen.zig` cannot be deleted when the C
path goes; 2,481 lines of it must be **ported**, not dropped.

### The hypothesis's four buckets, as measured

- **C emission that is a required BOOTSTRAP stage today — 19,423 + 5,619 =
  25,042 lines.** `zig build native-census`, run 2026-08-08: **native 119,
  bail 58, reachable 177.** 58 of 177 programs (33%) still reach the C emitter.
  Additionally `emitReqModuleC` (`main.zig:3758`), called from
  `directLinkInputs`, runs a full `CodeGen` over every `req`'d module — so **the
  direct path itself invokes the C emitter.** This is the waist CLAUDE.md §0b
  names.
- **C emission that is only the interop EXPORT — 0 lines.** Searched all of
  `src/` for header/`.h` emission: every hit is header *ingestion*
  (`c_frontend.parseHeader`, `c_sim_import.importHeaderSource`,
  `c_signatures`). `@comp.c.export` only fixes an emitted symbol name. **The
  Pass 103 roadmap phase-1 C-header EXPORT is not built**, so no part of the C
  emitter is export-only today.
- **Native-scalar precheck and logic the direct path genuinely uses — 2,481
  lines**, none of it separable from C emission.
- **Dead code — 29 lines** (4 functions: `all_module_functions_native`,
  `funcUsesRecordSelfPointer`, `func_decl_is_native_scalar_candidate`,
  `function_allows_native_req`). UNVERIFIED by build; found by
  reference search, not by deletion.

**Verdict on the hypothesis.** "Much of `codegen.zig` may be product, not
compiler" is **not supported as stated**. C emission is not demoted in practice:
it is the live fallback for a third of programs and the mandatory path for
`req`'d modules. What IS true and is worth banking: 5,619 lines are inert C text,
5,130 are tests, and the 2,481-line precheck is the only part the direct path
needs — so the file's removal is gated on native attainment reaching 177/177 AND
the precheck being reimplemented, not on a backend flag flip.

## 4. Per-file classification, all 237

Totals (by `src/` on-disk file, 144,804 lines; the 2 `tests/*.zig` are added to
class (b)):

| class | files | lines | share |
|---|---|---|---|
| (a) removable once a named Duo replacement lands | 3 | 44,758 | 30.9% |
| (b) removable NOW — dead or superseded | 12 (+2 in `tests/`) | 1,725 (+205) | 1.3% |
| (c) bootstrap-required until self-hosting closes | 58 | 61,865 | 42.7% |
| (d) test / oracle / audit infrastructure | 164 | 36,456 | 25.2% |

### (b) Removable NOW — PROVEN

Unreachable from all 13 `build.zig` roots. **Verified by deletion**: all 14
moved out of the tree, `rm -rf .zig-cache/h && zig build` succeeded and
`zig build unit-test --summary all` reported **1341/1341 — identical to
baseline**, then restored.

| file | lines | evidence |
|---|---|---|
| `src/autodiff.zig` | 496 | `semantic_ownership.zig:56` already classifies it `.experimental`, "none in default compile" |
| `src/wasm_dispatch.zig` | 366 | only consumer is `wasm_dispatch_gen.zig`, itself dead |
| `src/rewrite_apply.zig` | 323 | no importer |
| `src/wasm_dispatch_gen.zig` | 229 | generator whose output is not wired |
| `src/specialize_expand.zig` | 196 | no importer |
| `src/_dbg2.zig` | 37 | scratch debug test, **untracked**, `_` prefix violates §1 |
| `src/_dbg.zig` | 28 | scratch debug test, **untracked** |
| `src/_alias_dbg.zig` | 28 | scratch debug test, **untracked** |
| `src/float_lit_test.zig` | 9 | scratch test with a `std.debug.print` |
| `src/root.zig` | 7 | library re-export root from `init` (2026-05-28); no `addLibrary` uses it |
| `src/test_support.zig` | 5 | imports `src/wasm/wasi/wasi.zig` — **`src/wasm/` does not exist**; cannot compile |
| `src/token.zig` | 1 | contains the literal bytes `sed: src/token.zig: No such file or directory` — **a captured shell error, committed as a file** |
| `tests/test_ast.zig` | 154 | no `tests/` reference anywhere in `build.zig`; imports `src/lexer.zig` on a path that will not resolve |
| `tests/test_hash.zig` | 51 | orphaned; duplicates `calc_lua_hash` "because it is private to codegen.zig" |

**Census impact: 11 of these are tracked → ratchet 237 → 226.** (The `_dbg`
trio is untracked and scores nothing.)

### (a) Removable once a named Duo replacement lands

| file | lines | RL row | replacement |
|---|---|---|---|
| `src/codegen.zig` | 34,971 | RL-05 | none exists |
| `src/parser.zig` | 8,455 | RL-04 | `lib/std/compiler/parser.duo` (projection only) |
| `src/lexer.zig` | 1,332 | RL-02 | `lib/std/compiler/lexer.duo` |

### (c) Bootstrap-required — 58 files, 61,865 lines

The compile pipeline closure from `{codegen, sema, parser, lexer,
native_backend, dnir_lower, mono, arc, async_lower, ast, types, term, comptime,
native_req_support}` is 79 files / 106,222 lines; (c) is that closure minus
classes (a) and (d), plus `main.zig`.

Largest: `sema.zig` 13,163 · `native_backend.zig` 5,931 · `main.zig` 5,006 ·
`dnir_lower.zig` 4,244 · `meta_codegen.zig` 3,846 · `semantic_graph.zig` 2,173 ·
`types.zig` 2,007 · `meta_module.zig` 1,828 · `comptime.zig` 1,642 ·
`term.zig` 1,426 · `foreign_transpile.zig` 1,272 · `semantic_algebra.zig` 1,267 ·
`pretty.zig` 1,173 · `mono.zig` 1,109 · `transform_engine.zig` 992 ·
`ast.zig` 869 · `async_lower.zig` 828 · `realization.zig` 771 ·
`pipeline_gen.zig` 713 · `directives.zig` 677 · `region_transform.zig` 649 ·
`c_frontend.zig` 614 · `ml_kernels.zig` 591 · `arc.zig` 572 ·
`region_graph.zig` 526 · `native_req_support.zig` 498 · `sim.zig` 479 ·
`rewrite_rules.zig` 468 · `tail_result_demand.zig` 421 · `jit.zig` 391 ·
`c_signatures.zig` 381 · `schema_gen.zig` 359 · `derive_bundles.zig` 329 ·
`meta_directives.zig` 304 · `duo_native_ir.zig` 294 · `c_sim_import.zig` 294 ·
`c_header_parse.zig` 267 · `meta_dispatch.zig` 255 ·
`optimization_outcome.zig` 249 · `debug_trace.zig` 244 ·
`foreign_adapter.zig` 238 · `sql_to_c.zig` 228 · `dnir_hardware.zig` 213 ·
`abi_specialize.zig` 209 · `duo_lexer_bridge.zig` 204 ·
`region_schedule.zig` 200 · `graph_query.zig` 197 · `backend_identity.zig` 195 ·
`derive_eval.zig` 178 · `source_cursor.zig` 177 · `c_layout_verify.zig` 177 ·
`dynamic_boundary.zig` 135 · `type_diff.zig` 131 · `legacy_directives.zig` 101 ·
`semantic_fingerprint.zig` 63 · `host_run.zig` 43 · `duo_keyword_bridge.zig` 29 ·
`duo_module_names.zig` 25.

### (d) Test / oracle / audit infrastructure — 164 files, 36,456 lines

This is the largest surprise in the ledger: **25% of the Zig is not compiler.**
It is self-audit apparatus, and under §0f (ONE GRAPH SERVICE) and MONOGLOT it is
exactly the material that should be Duo.

| sub-class | files | lines | what |
|---|---|---|---|
| `pass*_catalog` / `pass*_gate` | 43 | 9,789 | pass audit data + CI gates; `main.zig` embeds 38 of the 43 |
| audit / registry / matrix / manifest / ledger / proof | 59 | 11,093 | incl. `passes_audit.zig` 1,152, `derive_registry.zig` 718, `pass_gates.zig` 477, `removal_ledger.zig` 94 |
| CLI tooling attached to `main.zig`, outside the compile pipeline | 43 | 11,054 | incl. `macro_expand.zig` 1,225, `dev_control_plane.zig` 1,040, `build_framework.zig` 874, `git_preservation.zig` 463 |
| `*_tests.zig` + `property_tests.zig` + `tests.zig` | 14 | 3,301 | |
| differential oracles | 4 | 745 | `duo_lexer_dispatch.zig` 382, `lexer_differential.zig` 225, `stage_compare.zig`, `wasm_decode_differential.zig` |
| `token_semantic.zig` (RL-03) | 1 | 474 | deliberately retained oracle |

**`duo_lexer_dispatch.zig` (382) and `lexer_differential.zig` (225) are class
(d), not debt.** They differential the Duo token stream against `src/lexer.zig`
on every test run — they are the instrument that makes RL-02 provable.

The 43 CLI-tooling files were separated from (c) by measuring the compile
pipeline closure and subtracting: they hang off `main.zig` as subcommands and no
compile touches them.

## 5. `src/removal_ledger.zig` reconciled with reality

Verified each row against the tree.

| row | status | finding |
|---|---|---|
| **RL-01** | **DONE — should be marked so** | `src/duo_keyword_classify.c` was deleted 2026-08-07 in `32643ed` ("its ledger gate was already met, c/h 27 → 26"). The row still reads `.after_m1` as if pending. Its replacement `lib/std/token/classify.duo` exists (8.1 KB). |
| **RL-02** | **gate ACCURATE** | 63 files `@import("lexer.zig")` (the row says 61 — measured 63 today). The type-home and driver-object reasons hold; `.after_m2` is right. |
| **RL-03** | **ACCURATE** | `token_semantic.zig` (474 lines) is imported by 12 files, incl. `lexer.zig` and 4 audit modules. `retain_oracle` is correct. |
| **RL-04** | **gate ACCURATE, one number stale** | `lib/std/compiler/parser.duo` exists (63 KB) and the structural objection stands — it emits s-expression TEXT, not the AST `sema`/`codegen` consume. |
| **RL-05** | **SCOPE WRONG** | Row reads `src/codegen.zig (canonical path)`. Under Pass 103 the C path is **not** canonical, and the row is silent on the fact that 2,481 lines are the direct backend's own admission gate and must be PORTED. Gate should also cite native attainment (119/177) as the measurable precondition. |
| **RL-06** | **ACCURATE but incomplete** | `build.zig` is 1,238 lines and counts against the ratchet; the row does not say so. |

Data-row corrections have been applied to `src/removal_ledger.zig` (rows only;
no logic changed).

## 6. Dependency-ordered removal plan

Cumulative against the census ratchet (tracked files) and tracked lines.

| step | action | precondition | files | lines | ratchet after | cum. lines |
|---|---|---|---|---|---|---|
| **0** | delete the 14 dead files (§4b) | **none — PROVEN today** | −11 tracked | −1,837 tracked | **226** | 1,837 |
| **1** | delete 4 unreferenced fns in `codegen.zig` | none; UNVERIFIED | 0 | −29 | 226 | 1,866 |
| **2** | port the 164 class-(d) audit/gate/tooling files to Duo (§0f, MONOGLOT) | Duo can host them — no compiler work | −164 | −36,456 | **62** | 38,322 |
| **3** | RL-04: Duo parser kernel emitting the real AST | parser.duo structural half | −1 | −8,455 | 61 | 46,777 |
| **4** | RL-02: `lexer.zig` falls with the parser; retain as oracle | step 3 | −1 (or 0 if kept) | −1,332 | 60 | 48,109 |
| **5** | RL-05: `codegen.zig` — needs native 177/177 AND the 2,481-line precheck ported | steps 3–4 + `emitReqModuleC` waist closed | −1 | −34,971 | 59 | 83,080 |
| **6** | RL-06: `build.zig` orchestration | S2 is canonical | −1 | −1,238 | 58 | 84,318 |

Remaining after all six steps: **the (c) bootstrap core, 58 files / 61,865
lines** — `sema.zig`, `native_backend.zig`, `dnir_lower.zig`, `main.zig` and the
IR/region/meta support around them. That is the real floor of this plan, and
nothing in the current RL rows schedules it.

### The honest headline

**Step 2 is the largest single win and it needs zero compiler work.** Porting the
audit apparatus removes 164 files and 36,456 lines — more than `codegen.zig` —
and takes the ratchet from 226 to 62 in one campaign, because it is blocked on
nothing but writing Duo. Every other step is blocked behind RL-04.

**The ledger cannot shrink much on the compiler axis until RL-04 and RL-05
land**, and RL-05 is further away than the RL row implies: it needs native
attainment to go 119 → 177 (58 programs), the `emitReqModuleC` waist closed, and
2,481 lines of precheck reimplemented in Duo. Steps 0+1 are worth 1,866 lines —
1.3% — and are the only thing removable today with zero Duo work.

## 7. Removable TODAY with zero Duo work

1. The 14 files in §4b — **1,837 tracked lines, ratchet 237 → 226. Proven:
   build green, unit-test 1341/1341 unchanged.**
2. The 4 unreferenced `codegen.zig` functions — 29 lines. UNVERIFIED by build.

Nothing else. Every other reduction is gated on a Duo replacement existing.

## 8. Caveats

- `zig build agent-smoke` is **red at baseline** on this branch, before and
  after the removal experiment (another session's in-flight `lib/std/fs.duo` and
  `tools/lsp` edits). It was confirmed red with the tree fully restored, so it
  is not attributable to anything here.
- The `self.X(` call-graph pattern under-reports edges (97 of 104 apparent
  orphans were false). It is sound for the *closure* comparisons in §3 — which
  only ever grow with more edges — but the 4-function dead set is its weakest
  claim and is marked UNVERIFIED.
- Class (c)/(d) boundary is drawn by compile-pipeline reachability. A file that
  a compile never touches is classified (d) even if its name reads like
  compiler.

---

## 9. Wave 3, 2026-08-09 — the last of the apparatus, and the first two ports

Measured on branch `canonical-to-relation` after waves 1 and 2 had taken the
census ratchet 237 → 135 by deletion. **This wave took it 135 → 121.**

### Method, re-run rather than quoted

The import closure was recomputed, not inherited: transitive `@import("X.zig")`
from `main.zig` over `src/*.zig`, with a positive control on the scanner
(`codegen.zig` must show ~10 importers — it showed 9, named). Result at the
start of this wave: **105 of 134 `src/*.zig` in the `main.zig` closure**, 29
outside it, all 29 imported by `src/tests.zig`, ~5,033 lines.

Note the closure is slightly generous: `main.zig` imports
`native_barrier_checks.zig` and never calls it, so that file is "production" by
an unused import only.

### Deleted — 11 files, apparatus asserting apparatus

Each is a hand-written table plus one test asserting the table has the length
the same file declares. None had an importer other than `tests.zig`. None
touched a compiler path.

| file | lines | the whole assertion |
|---|---|---|
| `pass25_semantic_category.zig` | 82 | `@intFromEnum(.pointer) == 4`, `invariants.len >= 5` |
| `pass26_evidence.zig` | 98 | `certaintyTermCount() == 10`, `example_proofs.len >= 2` |
| `pass26_transform_meta.zig` | 65 | `composition_rules.len >= 2`, `meta_invariants.len >= 4` |
| `pass26_protocol_attachment.zig` | 166 | its own dotted paths and its own example table |
| `conversion_graph.zig` | 105 | builds its own graph, asserts its own graph — superseded by `src/relation.zig`, which `codegen.zig` actually imports |
| `selfhost_migration_plan.zig` | 70 | `items.len >= 10`, `items[0].id == "MP-01"` |
| `selfhost_production_path.zig` | 210 | self-consistency over a hand-written phase table |
| `compiler_perf_baseline.zig` | 42 | `metrics.len >= 4` |
| `compiler_perf_measure.zig` | 114 | a timing smoke asserting `ns > 0` |
| `region_layout.zig` | 160 | a real layout planner with **zero callers** — a scaffold for passes that never arrived |
| `pass20_import_strength.zig` | 91 | the only live path it touched, `c_sim_import.importHeaderSource` on `point_h`, is already covered by `pass5_golden_tests.zig`; the classifier it asserts lives only in the deleted file |

Evidence the cut was clean: `zig build` green, and `zig test` on `tests.zig`
went **1165 → 1152**, exactly the 13 tests those files declared. A grep for each
deleted basename across `*.zig`, `*.duo` and `*.json` returns nothing.

### Ported — 3 files, replaced by two Duo gates wired into `agent-smoke`

| Zig file | lines | Duo replacement |
|---|---|---|
| `lua_superset_corpus.zig` | 131 | `scripts/luahost.duo` + `examples/luahost/*.duo` (12 fixtures) |
| `pass7_contract_tests.zig` | 94 | `scripts/explain.duo` |
| `pass7_explain_tests.zig` | 107 | `scripts/explain.duo` |

Both ports assert through the **shipping CLI** rather than through internals,
which is wider coverage than the originals: the Lua corpus went from
`Lexer` + `Parser` in memory to `duo check` on real files (parse *and* sema),
and the Pass 7 tests went from in-process structs to the JSON `duo explain`
actually prints. Both gates carry **four controls each** — the originals carried
none — and both were positive-controlled by deliberately breaking a fixture and
confirming the gate goes red, then restoring it.

Two findings fell out of the porting, and neither is a porting loss:

- **`examples/pass7/explain_smoke.duo` was broken and tracked.** It opened with
  a C-style `//` comment, which the duon lexer refuses. Nothing noticed because
  the Zig test that owned its content carried a byte-identical copy as a string
  literal and never opened the file. The marker is repaired in this commit.
- **`duo explain` does not diagnose that failure — it prints a raw Zig stack
  trace and exits 1.** That is an H-8 output-totality finding.
- **`@noalloc` is not enforced where a user stands.** `duo check`, `duo compile`
  and `duo explain` all exit **0** on a module that allocates inside a
  `@noalloc` function; the rejection is visible only as a line of JSON
  (`"transformation":"contract.noalloc","status":"rejected"`). The Zig test
  asserted `error.NoAllocViolation` from a pipeline no CLI verb reaches.

### Kept — 15 files, with the blocker named

Deletion is now exhausted. What remains outside the production closure is real
coverage, and each row says what stops the port.

| file | lines | blocker |
|---|---|---|
| `property_tests.zig` | 1495 | protected; property/fuzz harness with no Duo equivalent |
| `lexer_differential.zig` | 225 | protected; field-for-field host-vs-Duo lexer differential |
| `wasm_decode_differential.zig` | 82 | protected; 256-opcode decode/validator agreement |
| `selfhost_verify.zig` | 174 | drives the three differentials above; a port ports them |
| `meta_transform_tests.zig` | 444 | asserts `transform_engine` **provenance** — an in-process registry with no CLI projection |
| `call_transform_tests.zig` | 102 | same: transform registration and dispatch provenance |
| `pass6_dispatch_tests.zig` | 45 | same: the tier-1 registry gate is only reachable in process |
| `pass4_native_tests.zig` | 195 | asserts emitted C **and** ARM64 asm text; portable in principle via `--backend=c` / `--backend=direct` plus artifact greps, but needs a stable addressable artifact path |
| `codegen_pass3_tests.zig` | 71 | same shape, `|>` field-access fusion in emitted C |
| `pass5_foreign_tests.zig` | 225 | links and **runs** foreign C, asserting returned values (25, 10); needs a Duo gate that compiles, links and executes |
| `pass5_golden_tests.zig` | 73 | SIM snapshot JSON golden + a formatting-invariance assertion; `duo` has no verb that prints a SIM snapshot |
| `pass8_realization_tests.zig` | 158 | fingerprint drift and persistent-cache invalidation across compiles; needs cache state observable from the CLI |
| `pass8_codegen_realization_tests.zig` | 55 | realization logging, same blocker |
| `pass11_ward_barrier_tests.zig` | 37 | a 6-line driver over `native_barrier_checks.zig` (534 lines of symbol analysis). Porting means porting that; and `build.zig` owns its test root, which this wave did not touch |
| `tests.zig` | 100 | the aggregator; it dies last |

### The next honest wave

The three CLI-observability blockers above are one blocker wearing three hats:
**`duo explain` already proves the pattern.** A verb that prints the transform
provenance registry, the SIM snapshot, and the realization/cache state as JSON
would unblock `meta_transform_tests`, `call_transform_tests`,
`pass6_dispatch_tests`, `pass5_golden_tests` and both `pass8_*` files at once —
about 1,000 lines — with no compiler semantics changed. That is the highest-
leverage next move and it is `main.zig` work, not test work.

### Gate results for this wave

| gate | before | after |
|---|---|---|
| `zig build` | 0 | 0 |
| `zig build unit-test` | 0 (1165 tests) | 0 (1147 tests) |
| `zig build agent-smoke` | 0 | 0 |
| `zig build language-census` | 0 (zig 135 ≤ 135) | 0 (zig 121 ≤ 121) |
| `zig build audit100` | **1** — 4 rows red | **1** — the same 4 rows, same counts, `no row moved` |

The audit100 red is not this wave's: `accessor` +2, `arrow` +12, `trailret` +23
and `convert` +2 were red at baseline and are unchanged. The `nonduo` row FELL
434 → 420. Both new scripts cost **zero** deny points, which is what
`no row moved` in the per-diff delta reports.

### One defect found in `build.zig`, not repaired here

`build.zig` still names two roots that no longer exist —
`b.path("src/pass11_catalog.zig")` and `b.path("src/selfhost_target_matrix.zig")`
— left behind by an earlier deletion wave. `b.path` is lazy, so `zig build`
stays green and only the steps that depend on those roots break. `build.zig` was
out of scope for this wave; the repair is to drop the two `addTest` roots and
whatever steps depend on them.
