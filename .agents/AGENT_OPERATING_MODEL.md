# AGENT_OPERATING_MODEL — multi-agent allocation for the self-host frontier

Durable coordination projection. No language law lives here; authority
is unchanged: `AGENTS.md` routes to `docs/spec/constitution.md`, the
sole semantic law (C0). All gates, docs, briefs, and censuses are
derived projections — none can outrank C0 or independently own
vocabulary. Lane ownership and
claim discipline are defined by `AGENT_COORDINATION.md`; this file only
decides **which agent class receives which class of work**.

Expected repository base at materialization: the HEAD recorded in the
assignment. Every work order expires immediately when HEAD differs.

## Operating model

Lower-context agents are never asked to understand Idol's full architecture.
They receive work where:

- the semantic ruling already exists
- the current failure is reproducible
- the permitted files are explicit
- the correct after-state is exact
- damage controls can prove the work
- ambiguity causes a stop, not improvisation

The repository's durable coordination map divides production into eight
lanes and requires live path/semantic claims before editing: ingress and
parser transfer in lanes 1–2, graph authority in lane 3, realization /
runtime / Wasm in lanes 4–7, evidence / anti-drift in lane 8.

No compiler B exists. The critical chain remains:

```
source-family → lexical identity → grammar roles → parser → exact graph
→ demand → one representation decision → specialization → realization
→ artifact → B → C
```

Lower-context agents therefore primarily:

1. make failures reproducible and minimal
2. make evidence impossible to fake
3. enumerate remaining duplicate authorities
4. implement an already-ruled physical behavior behind exact graph facts
5. migrate mechanical consumers only after Codex establishes the semantic
   interface

They do not design `@{}`, retire DNIR, define worlds, modify application
roles, invent pack laws, or decide Wasm semantics. Current realization is
explicitly AST→DNIR and uses AST-expression correspondence to find graph
applications, while DNIR still carries a mixture of semantic and physical
data.

## Allocation

| Agent | Primary role | Production semantic edits | Main deliverable |
|---|---|---|---|
| Z.ai MOP | Self-host blocker laboratory and work-order coordinator | No | Minimal repros, exact blocker/fact handoffs, current B-readiness matrix |
| Ollama GLM-5.2 | Read-only exhaustive census | No | Machine-readable authority, bridge, consumer, and canonicality manifests |
| OpenCode Big Pickle | Evidence / reduction / fuzz / tooling | No | Reducer, perturbation verifier, revision-bound evidence tools |
| Poolside | Bounded physical implementer | Only by exact work order | One pre-decided backend/runtime capability |
| Pi / Z.ai verifier | Independent falsification and platform measurement | No | Cross-target matrices, damage controls, Wasm differentials |
| Small miscellaneous agents | Mechanical generated/migration work | No semantic interpretation | Fixture promotion, generated projections, canonicalizer-applied changes |

## Waves

- **Wave 0 — start immediately, fully disjoint.** MOP: current self-host
  matrix, minimal repros, mask analysis. Ollama: reconstruction / fact /
  bridge / canonicality / Wasm manifests. OpenCode: reducer + perturbation
  helper. Pi: current merged-head integration and gate falsification. Small
  agent: verify routed obsolete guards, produce work orders only. Nobody in
  Wave 0 touches core semantic files.
- **Wave 1 — after Codex publishes exact graph accessors.** Poolside A:
  migrate one lowerer consumer from AST to graph accessor. Poolside B:
  one pack physical realization. OpenCode: reducer graph predicates. MOP:
  damage fixtures for the new accessor. Ollama: re-run consumer census and
  prove one reconstruction disappeared.
- **Wave 2 — after compiler-B driver skeleton exists.** MOP: stage-by-stage
  driver matrix and minimal first failures. Pi: B versus seed
  behavior/diagnostic comparison. OpenCode: graph-correspondence comparison
  tooling. Ollama: compiler-source canonicality and runtime-dependency
  census. Poolside: already-ruled object/ABI gaps.
- **Wave 3 — after Wasm lawset vertical slice exists.** OpenCode: Wasm
  reducer and generated fuzz grid. Pi: cross-runtime conformance
  differential. Ollama: proposal/operation coverage matrix. Poolside: exact
  target physical realization. MOP: first-failure minimization for every
  unsupported proposal family.

## Never assigned to lower-context agents

Kept with Codex / architectural review: closed `@{…}` world-injection law (no changes to C0 surface law), DNIR
retirement architecture, fact strata, semantic identity/incarnation law,
observation equivalence, graph transaction semantics, application role
assignment, pack/default semantics, world/authority design, protocol
coherence, numeric semantics, table/metatable semantics, foreign-lawset
taxonomy, compiler-B stage interfaces, Wasm semantic lawset,
representation-one, candidate/value-of-information engine, new syntax.

A low-context agent may implement a prewritten interface resulting from one
of those decisions. It may not make the decision.

## Vocabulary, instrument, and claims law (all agents)

- **No compound words, ever, anywhere** (LAW-ONE under C0). The
  `tools/node/dev/census/compound` ratchet parses the gate/path.id word
  set as a TEMPORARY MIGRATION-DETECTOR vocabulary — a heuristic, not
  an authority; it may miss and over-report (it missed `byteat`).
  No compound words, ever, anywhere:
  no mashed compounds (`readline`), no separators or case in path
  components, no numeric-suffix taxonomy, no role/mediator/plurality
  stems, no `*able/*ible`, no organizational namespaces. Decompose into
  existing edges/nodes, homes/worlds through hierarchy, or eliminate.
  New work must not raise the compound-census baseline.
- **No plurality**: one entity plus facts — singular stems only
  (`law.identity.cardinal`, docs/spec/canonical.md §26).
- **`!` over `not`** in Idol source, where appropriate.
- **Subject-first invocation**: `subject:edge(rest)` — never
  `edge(subject, rest)` (H-1; `gate/subject.id` teaches and proves it).
- **No antipattern spellings in Idol source**: single-letter table
  bindings (`M = {…}`), snake_case (`OP_unreachable`), and mashed
  compound names are the measured antipattern set. The wasm engine
  sources under tools/wasm/src are saturated with all three — their
  documented SOURCE-ZERO debt; convergence renames to subject-first
  edges rather than carrying spellings forward.
- **The wasm runtime leverages ALL language features in service of
  highest performance at lowest syntax**: opcode tables via comptime
  tabulation, dispatch via call specialization, memory via place/region
  facts, SIMD via simd_lower, lawset import through the one graph. A
  private standalone engine with hand-rolled tables is the antipattern;
  the interpreter/JIT/AOT are realization candidates the registry
  selects, not a second architecture.
- **Instrument**: the semantic graph via the `idol-native` MCP server
  (`check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`,
  `explain`, `fmt`, `asm`) — applications carry cardinality cards,
  `fact_coverage` is the blocker meter, `places`/`regions` are the
  control algebra. Working notes: `.agents/MOP_HANDOFFS.md` appendix.
- **Tooling**: `tools/reduce/idol` (predicate reducer),
  `tools/evidence/{subject,perturb,rotate}`, `tools/parity/grammar`,
  `tools/node/dev/census/compound`.
- **Claims**: obtain live claims before editing; aggressively clear
  stale claims (clean-file claims with no live work) rather than
  waiting; never edit a path a live claim owns.

## Work orders

Every assignment is materialized through `.agents/WORK_ORDER.md`
(the universal shape) and the per-agent briefs under `.agents/briefs/`.
The briefs are the injectables; the work order is the envelope.

## Highest-value immediate allocation

- **Z.ai MOP** — turn every self-host refusal into a minimized executable
  theorem
- **Ollama** — enumerate every remaining duplicate authority and missing
  consumer
- **OpenCode** — make crashes, wrong answers, and graph divergences
  automatically reducible
- **Pi** — attempt to falsify every green claim
- **Poolside** — implement exactly one physical consequence of graph facts
  Codex already owns

This advances self-hosting and FTCFTW because the primary Codex session
spends its scarce architectural attention on actual semantic closure while
every surrounding agent continuously converts ambiguity, masked failures,
and unverifiable claims into small, deterministic implementation work.
