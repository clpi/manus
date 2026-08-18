# MOP handoffs — self-host blocker laboratory results

Derived from the Wave-0 Z.ai MOP workstream (.agents/AGENT_OPERATING_MODEL.md).
Base at measurement: idol @ ecc5a3ff, compiler ee08e553. Machine-readable
records in evidence/mop/; executable theorems in tools/reduce/fixtures/.

Every item below is work-order ready. Fill `.agents/WORK_ORDER.md` and
dispatch per `.agents/AGENT_OPERATING_MODEL.md`.

## H1 — graph must publish application facts for f64 foreign writes (F1)

- tier: bounded-implementer (after Codex publishes the accessor)
- before: `mem.write_f64(buf, off, v)` after `mem.ptr_from_addr` refuses
  `unresolved-application-facts` (graph producer); write_i64 compiles.
- fixture: `tools/reduce/fixtures/graph/f64.id` (+ f1_neg
  negative control in the same directory).
- after: fixture compiles to an object; f1_neg still compiles; a damage
  control that drops the f64 fact re-refuses.
- likely files: graph fact production for foreign applications (lane 3,
  Codex-owned); consumer already expects the fact.

## H2 — module-global facts (F3a/F3b)

- tier: bounded-implementer
- before: any module-global read refuses with the bare name; a written
  module-global refuses `global-init-not-constant:<name>`.
- fixtures: f3_neg.id (F3a), f3_global_init_not_constant.id (F3b).
- note: the repo contains a routed note that direct-native module-global
  storage exists and a specific precheck should be removed only after its
  storage controls pass (MOP-D candidate — verify against current source;
  the guard text matches dnir_lower.zig:1010 refusal shape).
- after: both fixtures compile; damage control on the storage path
  re-refuses exactly F3b.

## H3 — reducer needed for three unminimized families (F2, F4, F5)

- tier: OpenCode Pickle Mission A (tooling)
- F2 `application-operand-abi`: verbatim `has` body + conditional call
  compiles clean; refusal depends on remaining graph.id/bind.id context.
  Reduce `lib/compiler/graph.id` against the predicate
  `first error contains "application-operand-abi"`.
- F4 `view`: 30-line token_view slice reproduces; continue reduction to
  the minimal construct (suspect: array-field pack identity + indexing).
- F5 `InvalidAggregateFact`: parser.id (1792 lines) crashes the compiler
  with a leaked stack trace at semantic_graph.zig:3945. Reduce against
  `process exits non-zero with InvalidAggregateFact`.

## H4 — diagnostics defect (F5, independent of the reducer)

- tier: mechanic (once replacement text is ruled)
- before: internal Zig stack traces leak into user-facing diagnostics.
- after: classified refusal with a DNB code, no internal frames.

## H5 — host link symbol (F6)

- tier: bounded-implementer, coordinates with the C-symbol ABI rename
- before: host.id object links fail on undefined
  `_idol_compiler_host__duo_lexer_host_stride`.
- after: symbol provided (or renamed consistently with the idol C-ABI
  rename) and host.id links to an executable.

## Mask analysis method (MOP-C — pending)

For each family: copy the compiler source tree to /tmp, bypass ONLY that
refusal, rebuild, re-run `compile --emit obj` over all 19 units, and
report { genuinely advanced, masked, next-blocker distribution }. The
ratchet scripts (`tools/node/dev/census/history/zero`) already demonstrate
the copy-patch-measure pattern; no production tree is modified.

## Remeasurement discipline

Do not carry "9 of 19" forward: remeasure at the exact source/compiler
hashes above. `idol check` is green on all 19 units — check is not
evidence of compilability; object emission is the current honest floor.

## Update 2026-08-17 — reducer landed; F5 and F2 resolved to theorems

`tools/reduce/idol` (selftest-proven) reduced the open families:

- **F5 InvalidAggregateFact: 1792 → 27 lines**
  (`tools/reduce/fixtures/crash/corpus.id`). Checks clean; crashes the
  compiler at semantic_graph.zig:3945. Perturbation experiment: hoisting
  the tail nested call `tail_pack(lx, proj_expr(lx))` to a flat binding
  does NOT clear the crash — the aggregate crash lives in the chained
  condition applications (`lexer.peek(lx).kind`). H4 (diagnostics defect)
  stands; the graph lane now has a 2-line reproducer.
- **F2 application-operand-abi: line-irreducible.** graph.id is 112 lines
  and EVERY single-line deletion breaks the predicate — the missing fact
  is module-granularity (whole-file context), not a local construct.
  The graph lane needs the module as the unit of analysis.
- F3b re-confirmed at 4 lines by the reducer (was 8 by hand).

## Update 2 — MOP-C mask analysis: headline counts are 100% masked

`evidence/mop/mask.yaml` (shadow-copy method, tree verified identical
after each restore):

- **F1** (unresolved-application-facts, 3 headline units): bypassing the
  guard advances **0** units — all three immediately expose
  `missing-application-id` at the same sites.
- **F3b** (global-init-not-constant, 2 headline units): bypassing advances
  **0** units — both expose `missing: unspecified` (unnamed entity hole).

**Lane-3 priority derived from measurement**: publish application-id and
global-entity facts FIRST. The refusal guards are correct; they are
reporting absent producers. Fixing guards before publishers would unlock
nothing (this is the routed-guard analysis conclusion, now with numbers).

New top handoff: **H6 — graph must publish application ids for foreign and
method call sites** (unblocks F1's three units past their next hole; the
2-line F5 reproducer and the F2 module-granularity finding are the
companion inputs).

## Appendix — idiomatic floor and graph instrument (working notes)


Base: idol @ 4724e589+, idol-native bin/idol. Verified by exercising
check/graph/symbols/explain over tools/mcp/native.id and idol-native
tools/mcp/server.id on 2026-08-17.

## The graph is the instrument (sim-v0)

- `applications[]` — {relation, caller, arguments, results, demand,
  provenance{file,start,end}, and cardinality cards:
  applied/effect/authority/witness/target/realization ∈ none|one|unknown}.
- `unresolved_applications` + `fact_coverage{candidates,published,bootstrap,
  blocking}` — the blocker-laboratory measurement. server.id today:
  37 candidates, 2 published, 35 bootstrap. native.id: 1/0/1.
- `bodies[].places[]` — shape (parameter|scalar), region, determinacy,
  mutation, escape, lifetime, residency (register), origin, accesses
  {bind|read, point, depth, mult exact|bounded, const_index}.
- `bodies[].regions[]` — shape refinement|alternative|recurrence with
  parent sites and carried places: the control-region algebra. while loops
  are `recurrence` regions.
- `worlds[]` (home/reach/members) + `draws[]` (application→world card).
- `enum_shapes`, `table_shapes`, `call_shapes` (callee_kind method|direct,
  arg_count, specializable, demand).

`explain` (idol-explain-v1): knowledge_snapshot entities + incarnation,
optimization_outcomes, assumption guards, transform_provenance (hash in/out,
evidence class), and the transform registry — tier-1 comptime transforms
(comp.match/map/power/derive.power/fixpoint/tabulate/interpolate/each/zip/
permute; budgets linear|exponential|factorial; parity sites) and call.*
(inline/specialize observed; memo/devirtualize/gpu_lower/simd_lower
registered, not yet observed).

## Idiom floor (what compiles under direct-native today)

- `subject:edge(rest)` — the name follows the relation; know the edge and
  the spelling is decided (gate/subject.id is the teacher; run it).
- Flat loop-body bindings only: the native subset rejects nested
  method-calls-as-arguments and bare expression-statement tails
  (GAP-155 constraints). Bind intermediates; end blocks with statements.
- PREDICATE-ZERO: no `== 0`, `== ""`, `== nil` sentinels. Presence facts
  (`x:has(needle)`) select; `:find` coordinates are used only inside a
  branch that proved presence.
- Framing: `stdout:write(resp .. "\n")` line-delimits; `stdin:line()`
  ingress; EOF ends the process (no EOF flag exists).
- JSON literals in source stay single-quoted; command substitution strips
  trailing newlines so responses never embed raw newlines.
- Module-globals: reads refuse with the bare name; runtime writes refuse
  `global-init-not-constant:<name>` (facts F3a/F3b) — avoid module-global
  state until those facts publish.
- `idol check` green ≠ compilable. Object emission is the floor;
  `--emit exe` additionally demands a process (tail / one zero-arg
  function / --entry).

## Performance doctrine (HPLS / FTCFTW)

Write the semantic minimum — the fewest LOC that states the DEMAND — and
let the graph decide the physics: demand cardinality (single vs per-item),
region shape (refinement/alternative/recurrence), access multiplicity
(exact/bounded), and const_index facts are what the transform registry
consumes. Never encode a physical strategy (manual buffers, caching,
unrolling) the graph could derive; never widen observation (order, layout,
addresses) the law does not demand. Highest performance in least LOC =
state the relation, publish the facts, let specialization choose.

## Disjoint work surface (this session, Wave 0/1)

- /tmp/idol-mop/** — matrix, fixtures, mask analysis (compiler copies
  under /tmp only).
- tools/reduce/** (new paths) — reducer + perturbation helper (Pickle
  Missions A/C): predicate = external command + expected outcome;
  selftests per the brief. Unblocks F2/F4/F5 minimization.
- Verifier rotation on demand (V-A/V-B).
- Agent-integration and work-order tooling (my established lane).

## H7 — grammar projection drift on the GAP-134 chain (parity measured)

`tools/parity/grammar` (report-only) measured:

- canonical `TokenKind` = **114** ordinals (src/lexer.zig)
- live projection `lib/token/grammarrole.id` = **114** — count-correct,
  emitted by `idol token-tables emit` (main.zig:901), consumed by
  `lib/compiler/token_view.id`; carries the old dialect (`--` comments,
  `req("std.compiler.token")`) and a retired regen banner
- `lib/token/grammar_role.id` = **110** — STALE by four ordinals and no
  emitter writes it (dead artifact or stale rename target)
- `tools/emit_grammar_role.zig` writes a third, dead
  `lib/std/token/grammar_role.id` path (forbidden namespace)
- BEGIN_EXPR vectors diverge at ordinal 3 between the two .id projections

Owner: lane 1–2 (GAP-134 generated grammar roles / immutable token view).
The parity checker must stay report-only; reconciling the three emitters
is a ruled decision for that lane. `scripts/grammarconvergence.id` already
exists as the declared convergence script for this surface.


## Update 3 — H7 mechanical subset implemented; F4 minimized

- Generator banner `duo token-tables emit` -> `idol token-tables emit`
  (src/grammar_role_gen.zig); `idol token-tables emit` regenerated the
  tracked projection (114, current format). Stale 110 artifact and the
  spent tools/ emitter deleted (foreign.md's ledger already recorded the
  latter as spent). `tools/parity/grammar`: **all projections agree**.
  The remaining H7 decisions (old-dialect emission face, tree-sitter
  convergence) stay with lane 1-2.
- F4 `missing: view` minimized 29 -> 4 lines
  (tools/reduce/fixtures/view/minimal.id). Renaming the relation moves
  the missing-fact name with it; renaming the param does not. The fact is
  the relation SHAPE (pack param + if/else over a pack field), reported
  by name — not a name-keyed lookup. Hands lane 4 a 4-line reproducer.


## Vocabulary ruling (user, 2026-08-17): `baseline` is a word

`baseline` is not a compound — added to the `words` authority in both
law copies (gate/path.id and gate/idiom.id). The compound census parses
the list at runtime and honors it with no code change.


## Update 4 — compile concurrency measured; cache publish hardened in-tree

Ground truth (30-way concurrent compiles, distinct content, one cwd):
every compile succeeds, no cross-process lock exists in `idol compile`,
and the reducer parallel-sweep regression was my throttle's spawn/poll
overhead, not compiler serialization (README corrected).

The one real multi-agent hazard on the roadmap modules:
`.id/cache/semantic/state.json` was a direct truncate-write in
src/persistent_semantic_state.zig (codex's unwired transactional-cache
WIP). It now publishes atomically (per-process temp + rename; readers see
old-or-new, writers never block; last consistent writer wins). The patch
sits in the working tree beside that WIP for the owning session to wire
and commit — committing their untracked file under my name would repeat
the ace5f7d5 sweep mistake. Build green; unit-test parity identical
(1663 pass / 3 pre-existing failures, reproduced with the patch reverted).


## Update 5 — F5 closed to a 2-line theorem: self-recursion

A second serial pass reduced the 11-line crasher further: the crash is
SELF-RECURSION. tools/reduce/fixtures/crash/corpus.id (2 lines) — a
relation invoking itself with literal arguments reaches
publishApplicationResultAggregate and returns InvalidAggregateFact (raw
internal error, leaked stack trace) instead of a classified refusal.
crash/ctrl.id is the causality control: identical shape with the call
target renamed yields a clean return-type diagnostic. Lane 3 has the
smallest possible reproducer plus its control.

Also recorded: a second parallel-sweep attempt (xargs -P) degraded to a
15-minute CPU-idle timeout — shell-level candidate parallelism has now
failed twice on this workload with different mechanisms; serial plus the
guarded inert pre-pass (3m54s for the full 1792-line reduction) is the
standing configuration.


## Update 6 — H4 fixed; H5 minimized with a corrected diagnosis

- H4 FIXED (commit 44bb7b5b): main wraps mainInner; internal errors print
  one classified line; the error-return trace only dumps under
  IDOL_TRACE=1. Classified diagnostics unchanged; unit parity 1663/3.
- H5 minimized 38 -> 3 lines (tools/reduce/fixtures/link/probe.id) and
  the diagnosis CORRECTED: the undefined symbol is not about the stride
  relation — a cross-module application reached from an exe entry does
  not pull the callee's object into the link. host.id's "ambient
  reference" comment was the workaround attempt. Owner: lane 4.
  Reducer note: predicate exit 0 means failure PRESENT (no negation).


## Update 7 — Mission B verdict; matrix remeasured

- Metamorphic generator (Pickle B) is BLOCKED ON AUTHORITY, correctly:
  the only ruled equivalence pairs live in idol-native's gate/subject.id,
  which is already self-executing there ("the agreement count IS the exit
  code"). A generator beside it would duplicate the authority the
  operating model forbids duplicating. Unblocked when the main repo
  gains its own pair authority (e.g. the graph-backed canonicalizer's
  equivalence table).
- Self-host matrix remeasured at 98e643cd per the no-carry-forward
  discipline: all 19 units, exit statuses byte-identical (10 clean,
  9 blocked, same families). evidence/mop/matrix.tsv stamped.
- Codex landed 'Retire duplicate language server authority' on the
  parallel ref reconcile/idol-canonical-all-work-20260817; not in this
  branch's history.


## H8 (corrected) — module-table REPRESENTATION gates wasm + LSP admission

`zig build wasm-test` fails closed at `module_materializes_table` in
codegen.zig: a module exporting a table built by keyed writes has no
native-scalar representation (producer drops the writes; the consumer
flattens `m.x` to undefined symbols). This is the REPRESENTATION
decision, not a missing published fact — my first H8 framing repeated
the exact false-splice main.zig:4920 documents (three historical false
findings from that comma). The engine's real first blocker is req's own
unresolved applications. Owner: realization lane; the reconcile branch
is landing table semantics (src/table_apply.zig). Wart oracle BUILT at
the frozen rev (ca2b0b9c, ReleaseFast) — the perf rail has both oracles
pinned; the engine number waits on admission.

Measured: `zig build wasm-test` fails closed at
`idol compile tools/wasm/src/engine.id --backend=direct` ->
`DNB001 missing: keyed-table-export` (dnir_lower) — the SAME missing fact
that blocks `tools/lsp/src/server.id`. One published fact family unblocks
both the wasm admission gate and the LSP server admission. Full wasm
closure matrix with proposal states and wasmtime oracle baselines:
evidence/mop/wasm/closure.md. WASIX has zero source support (the wasix
bench is oracle corpus only); WASI p1 is real but partial.


## Update 8 — one-command theorem suite

`tools/reduce/verify` runs every blocker theorem and its control with
exact expectations (9/9 PASS at 287c17fe). The crash control asserts
CLEAN DIAGNOSIS — never an internal InvalidAggregateFact — so the suite
is the post-merge regression guard: after the reconcile merge lands
(self-recursion fixed to classified refusal on that line), this command
must stay green with `missing: parse_expr` and never revert to the
crash. Post-merge pass order: merge -> tools/reduce/verify ->
census/compound --record -> parity (adopt fail-closed) -> ABI rename
window -> bridge census re-run.
