# Idol progress metrics

This file is a **human audit projection** of how progress is measured. It is not
semantic law and not a substitute for executed gate output. Percentage-like
scores below are normalized architectural judgments unless explicitly tied to a
named ledger run at a named revision.

Repository truth lives in `docs/spec/constitution.md`, executed authority in
`docs/bootstrap.md`, and machine-measurable counts in the ledgers under
`scripts/*ledger.id` run against clean HEAD.

## Top-line dashboard (dominant)

All other metrics — file counts, Zig counts, `.id` percentage, keyword counts —
are **subordinate diagnostics**. Report these three first:

### 1. Executed authority frontier

Earliest → latest **production stage actually owned by Idol** on the path:

```text
source ingress → lexer → lexical identity → grammar → parser → binding →
semantics → resolution → demand → realization → machine → object → runtime/link
```

**Current honest state (S0):** no compiler B exists. One substantive executed
transfer: production lexer/token-span boundary (`docs/bootstrap.md`). Lexical
identity, generated grammar roles, and parser recognition remain blocked or
host-owned.

**Score executed SHC authority:** milestone table (S0), not a percentage headline.

| Milestone | State |
|-----------|-------|
| S0 source ingress + partial lexer | **current** |
| B-L0 lexical + GAP-145 taint zero | open |
| B-G0 grammar Idol owner | open |
| B-P0 one parser production decision | open |
| B0 compiler B executable | open |
| C0 B compiles C | open |

**Four-axis commit test** (see `../idol-native/docs/bootstrap-critical-path.md`):
CAPABILITY, OWNERSHIP, CONVERGENCE, FTCFTW — capability-only is not SHC progress.
**Do not conflate with DIRECT-COVERAGE.** The sibling native surface tracks a
separate **LOWERABLE** ledger (`../idol-native/gate/selfhost.sh`: how many
`lib/compiler/*.id` modules lower on `--backend=direct`). That count is useful
backend-capability coverage only. **CANONICAL-COMPILER** and **EXECUTED-OWNER**
are orthogonal; see `../idol-native/docs/shc-ownership-ledgers.md` and
`../idol-native/docs/compiler-b-manifest.md`. Extended ledgers: HOST-TAINT
(`../idol-native/docs/shc-host-taint.md`), BRIDGE-DEBT, HOST-DEPENDENCY,
DELETION-VELOCITY (`../idol-native/gate/deletion_velocity.sh`), B-SOURCE
canonicality (`../idol-native/gate/bsource.sh`) —
see `../idol-native/docs/shc-ownership-ledgers.md`. Many green compiler modules are
capability probes, not compiler B.


### 2. Semantic reconstruction debt

Count of **production downstream decisions that still derive known meaning**
from source text, AST shape, callee name, opcode family, host module pattern,
or hash/fingerprint after resolution.

**Trend:** major islands deleted (AST-machine reconstruction, evidence identity
shadows, target-spelling realization selection); not zero. Application identity
upstream (~75–85% of local architecture) runs ahead of end-to-end
source→machine continuity (~45–55%).

### 3. FTCFTW evidence matrix coverage

Supported workloads × {direct native, C-equivalent, Wasm} × {correctness,
runtime, startup, compile, memory, artifact size}. Cells remain **explicitly
empty** until revision-bound aggregate proof fills them.

**Current:** architectural readiness ~75–85%; measurement infrastructure
~60–70%; **complete FTCFTW claim not proven** (near 0% for the full bound).
`scripts/ledger/ftcftw.id` passing means indexed contracts exist — not that
the bound is proven. Stale proof bundles do not certify current HEAD.

## Traffic-light summary

| Dimension | Status |
|---|---|
| Conceptual architecture convergence | green (~90%) |
| Semantic spine / application authority | yellow-green (~80%) |
| Canonical corpus migration | yellow (~55–70%) |
| Executed self-host (SHC) | red (~10%; S0 honest) |
| Compiler B/C closure | red (0%; B does not exist) |
| FTCFTW complete proof | red (not demonstrated) |
| Trajectory | strongly positive |

**Headline:** architecture is green; semantic spine yellow-green; canonical
corpus yellow; SHC red; FTCFTW proof red; metrics are harder to fake than
earlier eras — that is progress.

## Permanent metric splits

### New debt vs existing corpus

| Metric | Meaning |
|---|---|
| **New debt introduced** | Must be **0** on added/changed canonical lines (idiomgate, host/path gates, semanticgate ratchets) |
| **Existing canonical-surface debt** | Historical ledgers and corpus (`scripts/ledger/debt.id`, `scripts/ledger/ftcftw.id`, etc.) — substantial, preexisting; not conflated with gate pass on a migration diff |

A staged migration diff passing idiomgate/semanticgate proves **no new debt in
that diff**, not that the entire historical `.id` corpus satisfies present law.

### Architecture vs embodiment

Recurring pattern: **specification closure high; executable closure lower.**

| Area | Design / law | Implementation |
|---|---|---|
| Grammar single authority | ~90–95% | ~55–65% (`GAP-134`, `GAP-145`) |
| World / std / shell law | ~85–90% | corpus ~40–60%; host sovereignty lower |
| DNIR semantic unification | ~55–65% yellow-green | legacy op families remain |
| Agent orientation | ~85–90% | fail-closed gates on changed lines |

## Longitudinal scorecard

Normalized assessment — not claimed repository counters.

| Metric | Earlier meaning | Current correct meaning | Current state | Trend |
|---|---|---|---|---|
| Language/semantic closure | settle syntax/features | one semantic authority + closed source law | ~90% design / lower implementation | ↑↑ |
| Naming convergence | lowercase/no snake/camel | one meaning → one native word; qualifiers → facts | strong ratchet, corpus incomplete | ↑↑ |
| Canonical source | `.id` only | Idol command + `.id` suffix; constitution is semantic law | current | ↑↑ |
| Canonicality gate quality | lexical grep / convention | fail-closed positive controls + semantic classifications | strong for **changed** lines | ↑↑ |
| Canonical corpus debt | inferred from green gate | entire existing corpus satisfies current law | far from zero | ↑, lagging |
| Semantic application authority | schema / call metadata | exact graph relation/subject/argument/result facts | substantial progress | ↑↑↑ |
| Semantic reconstruction | tolerated downstream lookup | zero rediscovery from source/name after resolution | major islands deleted, not zero | ↑↑ |
| Identity integrity | hashes sometimes accepted | graph entity is identity; hashes evidence/index only | stronger, transitional | ↑↑↑ |
| DNIR vocabulary | conventional op taxonomy OK | same relation identity + realization facts | significant legacy ontology | ↑ |
| Fact preservation | correctness through lowering | strongest known fact survives every boundary | improving materially | ↑↑ |
| Transform lineage | text/hash provenance | exact graph entity lineage through transforms | landed (e.g. fail-closed lineage gate) | ↑↑↑ |
| Machine lineage | tooling goal | application → realization → machine/object bytes | partial (`GAP-137` era) | ↑ |
| World/authority model | std/modules/helpers | world facts; homes organize, never grant authority | law strong, corpus weak | ↑↑ |
| Grammar authority | parser-local knowledge | lexer → token → grammar role → parser; one authority | architecture settled, projection blocked | ↑↑ |
| Host-pattern elimination | stylistic cleanup | no host technique becomes native semantics | excellent law, substantial debt | ↑ |
| Self-hosting | file/conversion % | executed semantic authority → compiler B | S0; no B | ↑ honesty |
| Foreign-code elimination | fewer Zig/C files | zero foreign **semantic** authority | large remaining debt | ↑ slowly |
| FTCFTW architecture | “beat C / Wasmtime” | knowledge + realization freedom + demand deletion | strong concept | ↑↑↑ |
| FTCFTW evidence | benchmark wins alone | multidimensional bound evidence on exact revision/path | not proven | ↑ rigor |
| Release evidence | green individual tests | revision-bound aggregate proof | not release-ready | → |
| Agent orientation | prompt discipline | repository-enforced authority + scoped projections | strong | ↑↑ |
| Anti-drift durability | tell agents what not to do | forbidden semantic authority fail-closed | much better, incomplete | ↑↑ |

## Identity (current)

Project identity: **Idol** (`idol`, `.id`, repository `idollang/idol`).
Constitution §67 is sole semantic algebra authority. Git owns historical archive.

## What improved (objective inflections)

- **Canonical gates:** idiom controls fail-closed; subject-first loopholes
  tightened; boxing census separated “green path” from whole-compiler clean.
- **SEMANTIC-ONE target:** zero independent semantic taxonomies, downstream
  source-name reconstruction, storage-as-meaning, DNIR meanings without
  canonical relations, duplicated spellings, lost facts, tooling-owned vocab.
- **Graph application authority:** packed application roles authoritative;
  negative controls damage descriptors/ranges and verify invalid applications —
  stronger than bulk source rewrites.
- **Suffix migration:** tracked canonical source → `.id`; hooks/gates redirected;
  migration commit reported idiomgate 0 / semanticgate pass on **staged diff**
  (qualification: not whole-corpus purity).
- **Evidence integrity:** synthetic bootstrap verifier deleted; benchmark/trace
  binding to revision, environment, hashes; graph-backed assumptions required.

## Normalized dimension table

| Dimension | Assessment |
|---|---|
| Conceptual architecture convergence | ~90% |
| Language/semantic-law closure | ~90% |
| Mechanical anti-drift enforcement | ~80–85% |
| Naming/vocabulary architecture | ~85% |
| Grammar single-authority implementation | ~60% |
| Source/corpus canonical migration | ~55–70% |
| Graph/application semantic authority | ~80% |
| End-to-end semantic identity preservation | ~50% |
| DNIR semantic unification | ~55–60% |
| Transformation lineage | ~70–80% |
| Machine/object lineage | ~40–50% |
| World/std/host semantic migration | ~45–60% |
| Executed self-host ownership | ~10% |
| Compiler B/C closure | 0% |
| Foreign semantic-authority elimination | low |
| FTCFTW architecture | ~80% |
| FTCFTW complete experimental proof | near 0% |
| Release readiness | not ready |
| Agent-orientation durability | ~85–90% |

## Ledgers and fresh evidence

Machine-measurable values must come from running current ledgers against one
clean HEAD, for example:

- `scripts/ledger/debt.id` — historical canonical-surface debt (not gate pass)
- `scripts/ledger/ftcftw.id` — FTCFTW contract index (presence ≠ complete proof)
- `scripts/ledger/shc.id` — self-host authority stages
- `gate/architecture.id` — staged-index migration censuses
- `gate/idiom.id` — added-line canonicality

Inspect committed evidence artifacts for revision, dirty state, and aggregate
outcome. A proof bundle at an older revision does not certify current HEAD.
Release readiness: `.agents/RELEASE_READINESS.md`.

## Prohibited headline metrics

Do not report as primary progress:

- `.id` file count or “percent in language”
- keyword removal counts alone
- green focused tests without aggregate revision-bound proof
- file-count or Zig-count reduction as self-hosting
- architecture convergence percentages without executed frontier movement
