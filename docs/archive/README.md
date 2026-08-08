# Archive — historical evidence, never an architecture input

**Everything in this directory is superseded by [`docs/spec/pass100.md`](../spec/pass100.md).**

These documents record how the design arrived where it is. They are evidence.
Nothing may cite them as authority, and no agent may treat a rule that appears
only here as live law.

Refusal protocol (from [`docs/spec/AUTHORITY.md`](../spec/AUTHORITY.md)): if a
rule you would cite lives only in an archived pass, your objection is void.
Comply with Pass 100 and repair toward it.

## Why these moved

They used to live in `docs/plans/`, a path whose name asserted they were active
plans, and `CLAUDE.md` described that directory as "Active implementation plans".
A repository search for architecture guidance surfaced 59 pre-Pass-100 documents
and nothing that outranked them, so agents kept relearning retired concepts from
the repository's own searchable context. Moving them under `archive/` and
stamping each one makes the supersession visible at the top of whatever a search
returns, rather than only in a file the searcher never opened.

Nothing was deleted. Every file moved with `git mv`, so `git log --follow` still
reaches its full history.

## Inventory

All 59 are superseded by Pass 100. Pass 100 declares itself the successor to
Pass 79; every document below is Pass 57 or earlier, or is unnumbered and
predates the epoch-2 renumbering.

### Canonical specifications (the "duo_*" pair-halves)

Each of these was the canonical half of a pass, with an operational projection
filed beside it. Pass 100 absorbs both halves.

| Path | Claimed authority over |
| --- | --- |
| `duo_canonical_specification.md` | whole-language canonical spec, SHC edition — the direct predecessor of Pass 100 |
| `duo_projection_calculus.md` | projection calculus, operator/spelling projection (Pass 38 canonical) |
| `duo_universal_semantic_access.md` | final semantic access + projection calculus (Pass 36/40/41 canonical) |
| `duo_self_hosting_foundation.md` | self-hosting foundation, bootstrap chain |
| `duo_sums_protocols_demand.md` | sum types, protocols, demand-return correction (Pass 49 canonical) |
| `duo_no_magic.md` | the no-magic doctrine (Pass 52 canonical) |
| `duo_hpls_frontier.md` | HPLS frontier (Pass 34 canonical) |
| `semantic_graph_architecture.md` | semantic graph architecture |
| `lua_superset_concurrency_supremacy.md` | Lua-superset + concurrency index |

### Operational pass plans

| Path | Claimed authority over |
| --- | --- |
| `pass1_identity.md` | Lua semantics with progressive compiler knowledge |
| `pass2_foundational_convergence.md` | foundational convergence audit |
| `pass3_directive_grammar_convergence.md` | directive surface + grammar minimalism |
| `pass4_native_end_to_end.md` | native end-to-end compilation, runtime independence |
| `pass5_semantic_interchange.md` | semantic interchange, cross-language metaprogramming |
| `pass6_architectural_reconciliation.md` | architectural reconciliation, dependency audit |
| `pass7_ai_native_compilation.md` | AI-native compilation, semantic optimization |
| `pass8_persistent_semantic_computing.md` | persistent semantic computing, negotiated realization |
| `pass9_ward_readiness.md` | ward readiness, vertical proof, runtime supremacy |
| `pass10_public_repository_readiness.md` | public repository readiness, structural coherence |
| `pass11_release_proof.md` | canonical compiler closure + release proof |
| `pass12_semantic_autonomy.md` | semantic autonomy, proof-carrying development |
| `pass13_development_control_plane.md` | development control plane |
| `pass14_constructive_evolution.md` | constructive evolution, architectural sovereignty |
| `pass15_semantic_shell.md` | the semantic shell |
| `pass16_self_hosted_compiler.md` | self-hosted compiler supremacy |
| `pass19_unified_semantic_experience.md` | unified semantic experience |
| `pass20_universal_metaprogramming_harness.md` | cross-language metaprogramming harness |
| `pass21_canonical_grammar_closure.md` | canonical grammar closure |
| `pass22_compiler_architecture_expansion.md` | compiler architecture expansion |
| `pass23_unified_metaprotocols.md` | unified metaprotocols, function compression, lifecycle |
| `pass24_execution_concurrency_lua_supremacy.md` | execution graph, call supremacy, concurrency architecture |
| `pass24_native_semantic_unification.md` | native semantic unification, lifetime model (superseded by pass25) |
| `pass25_native_semantic_unification.md` | native semantic unification, bidirectional metaprogramming, descriptors |
| `pass25_tail_result_demand.md` | tail-demand propagation and result lineage |
| `pass26_foundational_semantic_closure.md` | foundational semantic closure |
| `pass27_proof_bundle.md` | proof bundle, honest performance evidence |
| `pass34_hpls_frontier.md` | HPLS frontier (operational projection) |
| `pass36_universal_semantic_access.md` | final semantic access (operational projection) |
| `pass38_projection_calculus.md` | projection calculus (operational projection) |
| `pass41_native_first_amendment.md` | native-first amendment |
| `pass48_canonical_specification.md` | the canonical-spec consolidation |
| `pass49_sums_protocols_demand.md` | sums/protocols/demand (operational projection) |
| `pass52_no_magic.md` | no-magic (operational projection) |
| `pass57_c2_exports_are_scope.md` | exports-are-scope |

### Indexes

| Path | Claimed authority over |
| --- | --- |
| `pass25_semantic_unification_index.md` | index into the Pass 25 work packages |
| `pass26_closure_index.md` | index into the Pass 26 closure items |
| `pass27_proof_index.md` | index into the Pass 27 proof bundle |
| `SUMMARY.md` | one-page 6-pass architecture summary |
| `2026-07-09-roadmap.md` | the July 2026 roadmap implementation plan |

### Redirect stubs

Seven-line pointers left behind when superseded pairs were collapsed. They were
already historical before this move.

| Path | Redirects to |
| --- | --- |
| `pass2_convergence.md` | `pass2_foundational_convergence.md` |
| `pass4_native_compilation.md` | `pass4_native_end_to_end.md` |
| `pass6_reconciliation.md` | `pass6_architectural_reconciliation.md` |
| `pass7_ai_native.md` | `pass7_ai_native_compilation.md` |
| `pass8_persistent_semantic.md` | `pass8_persistent_semantic_computing.md` |
| `pass24_unified_calls_concurrency_constitution.md` | `pass24_execution_concurrency_lua_supremacy.md` |
| `pass26_foundational_closure.md` | `pass26_foundational_semantic_closure.md` |
| `self_hosting_foundation.md` | operational projection of `duo_self_hosting_foundation.md` |

### Measurement records, not architecture

These two are censuses — findings about the corpus at a moment in time. They
were never architecture inputs, and are archived here because their `pass57_`
naming made them look like plans.

| Path | What it records |
| --- | --- |
| `pass57_c3_chained_comparison_census.md` | corpus census of chained comparisons |
| `pass57_variadic_module_export_gap.md` | a compiler gap: a variadic function exported from a `req`'d module is never emitted |

`pass57_variadic_module_export_gap.md` describes a bug that may still be live.
Archiving it retires it as *architecture*, not as *evidence* — the gap register
under `gaps/` is where a live defect belongs. If the gap is still open, file it
there rather than citing this file.

## Known stale references

`src/*.zig` names these documents in 93 places. An earlier revision of this
README claimed they were "inert string literals compared against each other, not
filesystem reads, so the build is unaffected." **That was wrong, and it broke six
unit-test gates.** Three gates call `cwd.access()` on the path and fail with
`FileNotFound` when it does not resolve:

| Gate | Constant it accesses |
| --- | --- |
| `src/foundation_gate.zig:29-30` | `foundation_catalog.CANONICAL_SPEC_PATH`, `PLAN_PATH` |
| `src/pass34_gate.zig:273-274` | `pass34_catalog.PLAN_PATH`, `INDEX_PATH` |
| `src/pass36_gate.zig:396-397` | `pass36_catalog.CANONICAL_PATH`, `PLAN_PATH` |

`src/foundation_gate.zig:24-25` additionally re-states the two paths as literals
and `mem.eql`-compares them against the catalog constants, so those four strings
must move together or the equality check fails instead.

The lesson, recorded because it cost a red build: **a doc move is verified
against everything that NAMES the file, not just against the file.** `zig build`
alone does not catch this — `zig build unit-test` does. Grep for the path.

All 50 distinct paths `src/` names have identical basenames under
`docs/archive/`, so the repair is mechanical: rewrite `docs/plans/` to
`docs/archive/` throughout `src/`.
