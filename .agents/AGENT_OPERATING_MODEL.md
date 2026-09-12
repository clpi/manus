| field | value |
|---|---|
| title | AGENT_OPERATING_MODEL — multi-agent allocation for the self-host frontier |

| # | directive |
|---|---|
| 1 | Coordination projection only. |
| 2 | The supreme law is `docs/spec/law.md`, whose structured expansion is `docs/spec/constitution.md`; `AGENTS.md` routes to both. |
| 3 | Gates, documents, briefs, censuses, examples, and agent instructions derive from it and own no law. `AGENT_COORDINATION.md` owns lane and claim discipline; this file only routes work to agent classes. |

| # | directive |
|---|---|
| 1 | Expected repository base at materialization: the HEAD recorded in the assignment. |
| 2 | Every work order expires immediately when HEAD differs. |

| section |
|---|---|
| Operating model |

| # | directive |
|---|---|
| 1 | Lower-context agents are never asked to understand Idol's full architecture. |
| 2 | They receive work where: |

| # | directive |
|---|---|
| 1 | the semantic ruling already exists |
| 2 | the current failure is reproducible |
| 3 | the permitted files are explicit |
| 4 | the correct after-state is exact |
| 5 | damage controls can prove the work |
| 6 | ambiguity causes a stop, not improvisation |

| # | directive |
|---|---|
| 1 | The repository's durable coordination map divides production into eight lanes and requires live path/semantic claims before editing: ingress and parser transfer in lanes 1–2, graph authority in lane 3, realization / runtime / Wasm in lanes 4–7, evidence / anti-drift in lane 8. |

| # | directive |
|---|---|
| 1 | No compiler B exists. |
| 2 | The critical chain remains: |

```
source-family → lexical identity → grammar roles → parser → exact graph
→ demand → one representation decision → specialization → realization
→ artifact → B → C
```

| # | directive |
|---|---|
| 1 | Lower-context agents therefore primarily: |

| # | directive |
|---|---|
| 1 | make failures reproducible and minimal |
| 2 | make evidence impossible to fake |
| 3 | enumerate remaining duplicate authorities |
| 4 | implement an already-ruled physical behavior behind exact graph facts |
| 5 | migrate mechanical consumers only after Codex establishes the semantic interface |

| # | directive |
|---|---|
| 1 | They do not change closed `@{}` current-world law, retire DNIR, define worlds, modify application roles, invent pack laws, or decide Wasm semantics. |
| 2 | Current realization is AST→DNIR with AST-expression correspondence to graph applications |
| 3 | DNIR still mixes semantic and physical data. |

| section |
|---|---|
| Allocation |

| Agent | Primary role | Production semantic edits | Main deliverable |
|---|---|---|---|
| Z.ai MOP | Self-host blocker laboratory and work-order coordinator | No | Minimal repros, exact blocker/fact handoffs, current B-readiness matrix |
| Ollama GLM-5.2 | Read-only exhaustive census | No | Machine-readable authority, bridge, consumer, and canonicality manifests |
| OpenCode Big Pickle | Evidence / reduction / fuzz / tooling | No | Reducer, perturbation verifier, revision-bound evidence tools |
| Poolside | Bounded physical implementer | Only by exact work order | One pre-decided backend/runtime capability |
| Pi / Z.ai verifier | Independent falsification and platform measurement | No | Cross-target matrices, damage controls, Wasm differentials |
| Small miscellaneous agents | Mechanical generated/migration work | No semantic interpretation | Fixture promotion, generated projections, canonicalizer-applied changes |

| section |
|---|---|
| Waves |

| # | directive |
|---|---|
| 1 | **Wave 0 — start immediately, fully disjoint.** MOP: current self-host matrix, minimal repros, mask analysis. Ollama: reconstruction / fact / bridge / canonicality / Wasm manifests. OpenCode: reducer + perturbation helper. Pi: current merged-head integration and gate falsification. Small agent: verify routed obsolete guards, produce work orders only. Nobody in Wave 0 touches core semantic files. |
| 2 | **Wave 1 — after Codex publishes exact graph accessors.** Poolside A: migrate one lowerer consumer from AST to graph accessor. Poolside B: one pack physical realization. OpenCode: reducer graph predicates. MOP: damage fixtures for the new accessor. Ollama: re-run consumer census and prove one reconstruction disappeared. |
| 3 | **Wave 2 — after compiler-B driver skeleton exists.** MOP: stage-by-stage driver matrix and minimal first failures. Pi: B versus seed behavior/diagnostic comparison. OpenCode: graph-correspondence comparison tooling. Ollama: compiler-source canonicality and runtime-dependency census. Poolside: already-ruled object/ABI gaps. |
| 4 | **Wave 3 — after Wasm lawset vertical slice exists.** OpenCode: Wasm reducer and generated fuzz grid. Pi: cross-runtime conformance differential. Ollama: proposal/operation coverage matrix. Poolside: exact target physical realization. MOP: first-failure minimization for every unsupported proposal family. |

| section |
|---|---|
| Never assigned to lower-context agents |

| # | directive |
|---|---|
| 1 | Kept with Codex / architectural review: changes to closed `@{…}` current-world law, DNIR retirement, fact strata, identity/incarnation law, observation equivalence, graph transactions, application roles, pack/default law, worlds, protocol coherence, numeric and table law, foreign lawsets, compiler-B stage interfaces, Wasm law, representation-one, candidate/value-of-information selection, and new syntax. |

| # | directive |
|---|---|
| 1 | A low-context agent may implement a prewritten interface resulting from one of those decisions. |
| 2 | It may not make the decision. |

| section |
|---|---|
| Vocabulary, instrument, and claims law (all agents) |

| # | directive |
|---|---|
| 1 | **C0 alone governs vocabulary.** Decompose facts first; morphology only suggests migration candidates. `gate/path.id` and `tools/node/dev/census/compound` are incomplete derived instruments allowed to miss and over-report. Their inputs own no vocabulary: hits require review, misses prove nothing. Do not raise the census baseline; green is not proof of canonicality. |
| 2 | **No plurality**: one entity plus facts — singular stems only (`law.identity.cardinal`, docs/spec/canonical.md §26). |
| 3 | **`!` over `not`** in Idol source, where appropriate. |
| 4 | **Subject-first invocation**: `subject:edge(rest)` — never `edge(subject, rest)` (H-1; `gate/subject.id` teaches and proves it). |
| 5 | **No antipattern spellings in Idol source**: single-letter table bindings (`M = {…}`), snake_case (`OP_unreachable`), and mashed compound names are the measured antipattern set. The wasm engine sources under tools/wasm/src are saturated with all three — their documented SOURCE-ZERO debt; convergence renames to subject-first edges rather than carrying spellings forward. |
| 6 | **The wasm runtime leverages ALL language features in service of highest performance at lowest syntax**: opcode tables via comptime tabulation, dispatch via call specialization, memory via place/region facts, SIMD via simd_lower, lawset import through the one graph. A private standalone engine with hand-rolled tables is the antipattern; the interpreter/JIT/AOT are realization candidates the registry selects, not a second architecture. |
| 7 | **Instrument**: the semantic graph via the `idol-native` MCP server (`check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`, `explain`, `fmt`, `asm`) — applications carry cardinality cards, `fact_coverage` is the blocker meter, `places`/`regions` are the control algebra. Working notes: `.agents/MOP_HANDOFFS.md` appendix. |
| 8 | **Tooling**: `tools/reduce/idol` (predicate reducer), `tools/evidence/{subject,perturb,rotate}`, `tools/parity/grammar`, `tools/node/dev/census/compound`. |
| 9 | **Claims**: obtain live claims before editing; aggressively clear stale claims (clean-file claims with no live work) rather than waiting; never edit a path a live claim owns. |

| section |
|---|---|
| Work orders |

| # | directive |
|---|---|
| 1 | Every assignment is materialized through `.agents/WORK_ORDER.md` (the universal shape) and the per-agent briefs under `.agents/briefs/`. |
| 2 | The briefs are the injectables; the work order is the envelope. |

| section |
|---|---|
| Highest-value immediate allocation |

| # | directive |
|---|---|
| 1 | **Z.ai MOP** — turn every self-host refusal into a minimized executable theorem |
| 2 | **Ollama** — enumerate every remaining duplicate authority and missing consumer |
| 3 | **OpenCode** — make crashes, wrong answers, and graph divergences automatically reducible |
| 4 | **Pi** — attempt to falsify every green claim |
| 5 | **Poolside** — implement exactly one physical consequence of graph facts Codex already owns |

| # | directive |
|---|---|
| 1 | This advances self-hosting and FTCFTW because the primary Codex session spends its scarce architectural attention on actual semantic closure while every surrounding agent continuously converts ambiguity, masked failures, and unverifiable claims into small, deterministic implementation work. |
