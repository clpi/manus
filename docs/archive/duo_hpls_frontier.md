> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Duo HPLS Frontier — Pass 34 canonical spec (v2 summary)

**HPLS** = high leverage × high attention × high compaction/performance × low syntax cost.

Machine-readable catalog: `src/pass34_catalog.zig` (`SCHEMA_VERSION = pass34-hpls-catalog-v1`)

## Charter

Ranking formula:

```
rank = (runtime impact × frequency × architectural leverage × Ward relevance × self-hosting relevance)
       ─────────────────────────────────────────────────────────────────────────────────────────────
       (risk × required redesign × overlap with active work)
```

Guardrails: no broad rewrites; no backend-specific semantic decisions; never replace dynamic with dynamic; test-first smallest fix; barrier record if no safe fix; public Lua behavior unchanged.

New rules (v2):

- **One decision, one owner** — canonical subsystem per item; §8 mapping is normative
- **Descent before ascent** — deopt, unwind, invalidation specified before new ladder rungs
- **Measured or marked** — manifest diff or tagged `estimated`
- **Nothing blocked; everything bridges** — every prerequisite has a named bridge
- **No optimization without a witness** — `@comp.why`, L6 manifest, E5 ledger, U12, U11 share one substrate
- **Convergence closes on deletion** — Tier C DONE when redundant implementation is removed

## §1 Barrier record schema

Fields: `id`, `class`, `file`, `symbol`, `semantic_path`, `cause`, `semantically_required`, `prerequisites`, `prerequisite_bridges`, `impact`, `backends`, `tests`, `bounded_fix`, `witness`, `status`, `rank_inputs`.

Classes add **convergence**. Status lifecycle: `DISCOVERED | SPECIFIED | IMPLEMENTED | VALIDATED | ADOPTED | WONT_FIX | SUPERSEDED`. Phase 0: all `DISCOVERED`.

## §2–6 Tiers

| Tier | IDs | Count |
| --- | --- | ---: |
| C Convergences | C1–C5 | 5 |
| E Elephants | E1–E10 | 10 |
| L Levers | L1–L15 | 15 |
| U Unicorns | U1–U15 | 15 |
| T Traps | T1–T8 | 8 |

**Total: 53 records.**

## §7 Ranked order (v2 — measurement first)

1. L6 · 2. L1 · 3. E1 · 4. E8 · 5. L2 · 6. C1 · 7. E9 · … (28 ordinals in `ranked_item_ids`)

## §8 Canonical-home mapping

20 externally proposed innovations mapped to canonical homes — see `canonical_home_mappings` in catalog. Pattern: nearly every innovation is a projection of graph + witnesses + provenance + cost model.

## §9 Dependency graph

Encoded in `pass34_catalog.dependency_edges` — every edge uses valid barrier IDs and carries a bridge string.

## §10 Execution plan

Phases P34-PH0 through P34-PH6 in `pass34_catalog.execution_phases`.

## §11 Validation discipline

Regression test → smallest fix → inspect output → manifest diff → before/after counts tagged `measured` → deposit witness. `IMPLEMENTED ≠ VALIDATED ≠ ADOPTED`.

## §12 Governing question

> Does this item specify how the system comes back down as precisely as how it goes up?

## §13 Agent idiom enforcement

**Idiomatic Duo is not a prose rule set. It is code whose manifest is clean and whose facts are provable.** A style guide or a linter over source text cannot enforce that — it can only pattern-match syntax it was told about in advance, and it says nothing about whether the code specialized. Duo already owns the right enforcement machinery; §13 points it at agents.

Six mechanisms, zero new subsystems. Each is a projection of records that already exist (`agent_idiom_projections` in the catalog; gate-checked against `isValidBarrierId`):

| Mechanism | Home | Enforcement |
| --- | --- | --- |
| The manifest is the style guide | L6 | CI rejects a diff whose manifest grew a box, allocation, dynamic dispatch, or hot-region helper. Style becomes a number, not a review comment. |
| Goals are the agent's contract, not hints | U11 | Every agent-authored function of consequence carries `@goal { allocations == 0 }`. Failure returns negotiation output ("achievable at +32B") — a structured repair instruction, not a diagnostic. |
| Assert-and-verify replaces write-and-hope | U1 + U14 | The agent declares facts (monomorphic, non-escaping, sealed); the compiler verifies or returns the minimal semantic counterexample. Declaring facts forces the agent to think in the knowledge lattice, which *is* the idiom. |
| Semantic edits close the text loophole | U15 + C3 | Proven-legal graph operations have no unidiomatic outcome — "replace dynamic dispatch with sealed dispatch where legal" is correct by construction. Text editing stays possible and pays the manifest gate. |
| Golden corpus ships manifests, not comments | L15 + L6 | Exemplars (Ward decoder, sealed-record kernel, staged generic) ship with manifest and `@comp.why` output. L15 coverage ensures the corpus exercises every metaprogramming surface. |
| Idiom served by query, not source reading | C5 | Pass 12 bounded context packages over MCP, with `@comp.why.not.*` counterfactuals in every response — the counterfactual teaches faster than the positive case. |

**T8** records the incumbent this supersedes: `scripts/duo_idiom_gate.duo`, a regex-over-text linter (`^%s*local%s`, `%f[%w]then%f[%W]`, …). Per the convergence rule it closes only on deletion — `proveT8ClosesOnlyOnDeletion` fails the gate if T8 reaches `ADOPTED` while the script still exists.

Prerequisites and bridges: L6 (manifest-delta gate lands before text rules are retired), L15 (semantic coverage replaces the hand-maintained rule list), U11 (per-function goal replaces the lint comment).

> One line: make idiomatic the path of least resistance by making the compiler's evidence system the reviewer.

Operational projection: [`pass34_hpls_frontier.md`](pass34_hpls_frontier.md)

Full v2 constitution: see agent transcript / `pass34_hpls_frontier.md` operational doc for Phase gates.
