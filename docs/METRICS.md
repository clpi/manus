# Idol progress metrics

This file is a **human audit projection** of how progress is measured. It is not
semantic law and not a substitute for executed gate output.

Two kinds of statement live here and they are never interchangeable:

- **Measurements.** Every one names the COMMAND that recomputes it. No count,
  exit code, or census total is written as a literal in this file's prose
  (`AGENTS.md`, "Numbers live in exactly one place, and that place runs"). Where
  a number must be pinned, it is pinned inside the runner that checks it, and
  this file cites the runner.
- **Judgments.** Percentage-like scores are normalized architectural opinions.
  They are labelled as judgments and dated. A judgment is never a counter, and a
  dated judgment does not become a measurement by being repeated.

Repository truth lives in `docs/spec/law.md` (supreme) and
`docs/spec/constitution.md`; executed authority in `docs/bootstrap.md`; and
machine-measurable counts in the ledgers and gates cited below, run against a
clean HEAD.

## The three questions this file must not conflate

The single largest error this document has made is collapsing these into one
"grammar" score. They have different answers.

| Question | Answer | Proof command |
|---|---|---|
| Does an executable **grammar owner** exist? | **Yes.** `lib/compiler/token.id` is the one executable grammar-fact owner (`law.grammar.one`). | `zig build grammar-projection` on a direct-native-supported host; on this x86_64-linux host it refuses DNB004 before the owner runs, so the command measures environment here (see `gaps/GAP-134.md`). |
| Is **grammar consumer closure** reached? | **No.** Only bounded recognition decisions consume the owner's facts; `lib/compiler/token_view.id` is now checkable and `dump-c --lib` linkable, but the editor grammar is still authored and still disagrees within a pinned ratchet, and `docs/spec/grammar.md` does not generate the parser. | `zig build treesitter-agreement` on a direct-native-supported host; on this x86_64-linux host `agreement.sh` reports NOT MEASURED for the same DNB004 reason. |
| Is the **parser** Idol-owned? | **No.** `src/parser.zig` still decides expressions, bindings, and source structure. Parser SHC has not started. | `docs/bootstrap.md` "Parser recognition — HOST OWNED" |

An owner existing is not consumer closure, and consumer closure would still not
be parser ownership. Progress on the first two does **not** move the bootstrap
stage.

## Top-line dashboard (dominant)

All other metrics — file counts, Zig counts, `.id` percentage, keyword counts —
are **subordinate diagnostics**. Report these three first.

### 1. Executed authority frontier

Earliest → latest **production stage actually owned by Idol** on the path:

```text
source ingress → lexer → lexical identity → grammar → parser → binding →
semantics → resolution → demand → realization → machine → object → runtime/link
```

**Current honest state: S0. No compiler B exists. No compiler C exists.**
Executed parser ownership is seven bounded production decisions; the host still
owns the parser stage and AST construction.

What has crossed the frontier is real and larger than one boundary: source
ingress classification, the production lexer and token/span production, and the
grammar-fact ontology are executed Idol authority. What has *not* crossed is
the parser stage as a whole and everything rightward. `docs/bootstrap.md` owns the
per-boundary contract and is the authority when this table and that one differ.

**Score executed SHC authority:** milestone table (S0), not a percentage headline.

| Milestone | State |
|-----------|-------|
| S0 source ingress + lexer + token/span | **current** |
| B-L0 lexical identity + GAP-145 consumer zero | open (owner executes; consumers remain) |
| B-G0a grammar Idol **owner** exists | **met** — `lib/compiler/token.id` |
| B-G0b grammar **consumer** closure | open (GAP-134; token_view prerequisite linkable, parser still host-owned) |
| B-P0 one parser production decision | **met** — seven bounded relations execute from `lib/compiler/parser.id`; complete parser stage remains open |
| B0 compiler B executable | open — B does not exist |
| C0 B compiles C | open — C does not exist |

B-G0a being met is an ownership fact about grammar *facts*. It is not a stage
advance. S0 remains the honest stage until parser recognition crosses.

**Four-axis commit test:** CAPABILITY, OWNERSHIP, CONVERGENCE, FTCFTW —
capability-only is not SHC progress. `gate/taint.sh` supplies the executable
counterfactual for the transferred lexer boundary; `gate/grammar-projection.sh`
supplies it for the grammar owner; `docs/bootstrap.md` owns the stage contract.

**Do not conflate with DIRECT-COVERAGE.** The sibling native surface
(`clpi/idol-native`) tracks a separate **LOWERABLE** ledger
(`../idol-native/gate/selfhost.sh`: how many `lib/compiler/*.id` modules lower
on `--backend=direct`). That count is backend-capability coverage only.
**CANONICAL-COMPILER** and **EXECUTED-OWNER** are orthogonal; see
`../idol-native/docs/shc-ownership-ledgers.md` and
`../idol-native/docs/compiler-b-manifest.md`. Many green compiler modules are
capability probes, not compiler B. HOST-DEPENDENCY closes only through a live
former-host death control, never through a prose or source-string ledger.

The `../idol-native/` prefix on those three paths is deliberate and must not be
"repaired" to a bare `gate/…` spelling: `gate/all.sh`'s citation census counts a
qualified sibling citation as its own class, names this file as the example of
the correct form, and would score a bare spelling as an unresolved citation.

### 2. Semantic reconstruction debt

Count of **production downstream decisions that still derive known meaning**
from source text, AST shape, callee name, opcode family, host module pattern,
or hash/fingerprint after resolution.

**Trend:** major islands deleted — AST-machine reconstruction, evidence identity
shadows, target-spelling realization selection, and now the parser's second
operator ontology (see "Recomputing every count" below). Not zero.

### 3. FTCFTW evidence matrix coverage

Supported workloads × {direct native, C-equivalent, Wasm} × {correctness,
runtime, startup, compile, memory, artifact size}. Cells remain **explicitly
empty** until revision-bound aggregate proof fills them.

**Complete FTCFTW claim is not proven.** `scripts/ledger/ftcftw.id` passing
means indexed contracts exist — not that the bound is proven. Stale proof
bundles do not certify current HEAD. `docs/bootstrap.md` records FTCFTW as
**invalid** as a performance claim at this stage.

## Recomputing every count on this page

No count below is written out here. Each row names what to run.

| Claim | Command that recomputes it |
|---|---|
| The generated grammar projections are load-bearing — `src/grammar_role_table.zig` and `lib/token/grammarrole.id` regenerate byte-identically from `lib/compiler/token.id`, and a malformed producer that exits zero changes no tracked byte | `zig build grammar-projection` (or `sh gate/grammar-projection.sh`) on a direct-native-supported host; on this x86_64-linux host the command refuses DNB004 before the owner runs, so use the prior measured witness in `gaps/GAP-134.md` rather than treating the local red as a semantic regression |
| The editor grammar's disagreement with the owner is exactly the pinned baseline — the gate prints owner infix identities, editor operator rows, and divergences found / pinned / unpinned / stale | `zig build treesitter-agreement` (or `sh gate/treesitter/agreement.sh`) on a direct-native-supported host; on this x86_64-linux host the gate reports NOT MEASURED because the same DNB004 blocks the local direct-native witness |
| The parser holds no token→operation or operation→token map of its own; `src/ast.zig` aliases the generated ontology and `src/pretty.zig`'s inverse is compile-time checked for totality and injectivity | `zig build unit-test`; inspect `src/grammar_roles.zig` tests and `src/ast.zig` `BinOp`/`UnOp` |
| The `demandsOperand` membership is an owner fact, and its size is pinned by a counting control rather than by prose | `zig build unit-test` — `src/grammar_roles.zig`, test "the demand fact is the exact dual of expression start" |
| The line-head decision executes from parser.id `lead`, consumes the generated owner row, and preserves prefix-vs-continuation behavior | `sh gate/gap-145-consumer.sh`; `IDOL=./zig-out/bin/idol sh tools/node/dev/parser/artifact`; `zig build unit-test` — tests "production line-head decision executes the Idol relation" and "production line-head relation separates prefix from continuation" |
| Executed self-host boundaries and their remaining host residue | `./zig-out/bin/idol run scripts/ledger/shc.id` |
| Historical canonical-surface debt (not gate pass) | `./zig-out/bin/idol run scripts/ledger/debt.id` |
| FTCFTW contract index (presence ≠ complete proof) | `./zig-out/bin/idol run scripts/ledger/ftcftw.id` |
| Staged-index migration censuses | `./zig-out/bin/idol run gate/architecture.id` |
| Added-line canonicality | `./zig-out/bin/idol run gate/idiom.id` |
| Lexer transfer counterfactual | `sh gate/taint.sh` |
| Graph sovereignty audits | `./zig-out/bin/idol run scripts/ledger/graph.id`; `./zig-out/bin/idol run gate/graph.id` |
| Application consumer audit | `./zig-out/bin/idol run scripts/ledger/application.id` |

All of the above require a built compiler: `zig build` (produces
`./zig-out/bin/idol`). A gate run against a stale binary measures the stale
binary.

**Do not** copy an output of any of these into this file. If a number matters
enough to assert, it belongs in the runner that checks it — which is where the
`demandsOperand` membership size already lives, and why that one has not gone
stale.

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

For grammar specifically, that split is now three-valued rather than two, and
the middle value is the one that moved — see "The three questions this file must
not conflate" above. Design closure being high has never implied consumer
closure, and consumer closure does not imply parser ownership.

### Ownership is not coverage

An Idol file existing on a production path is ownership. An Idol file compiling
under a backend is coverage. A generated artifact is only evidence of ownership
when a gate proves it regenerates byte-identically from its owner — otherwise it
is a tracked file that may drift, and "the grammar is Idol owned" becomes a
claim with no counterfactual. That reasoning is written into
`gate/grammar-projection.sh` itself.

## Dated architectural judgments (2026-08-23)

**These are opinions, not counters.** They carry a date because they are
assessments of a frontier that moves. Do not cite one as a measurement, do not
diff two of them as if that were a trend line, and do not report one without its
date. Where a judgment and a gate disagree, the gate is right.

| Dimension | Judgment (2026-08-23) |
|---|---|
| Conceptual architecture convergence | green |
| Language/semantic-law closure | green |
| Mechanical anti-drift enforcement | green, incomplete coverage |
| Naming/vocabulary architecture | green |
| Grammar **owner** existence | **met** (fact, not judgment — the executable witness is host-sensitive: `zig build grammar-projection` runs on a direct-native-supported host; on this x86_64-linux host it refuses DNB004 before the owner runs) |
| Grammar **consumer** closure | yellow — bounded consumers only; editor grammar authored; `docs/spec/grammar.md` does not generate the parser |
| Parser ownership | red-yellow — seven bounded Idol relations execute; host owns the parser stage and AST construction |
| Source/corpus canonical migration | yellow |
| Graph/application semantic authority | yellow-green |
| End-to-end semantic identity preservation | yellow |
| DNIR semantic unification | yellow — significant legacy op families |
| Transformation lineage | yellow-green — fail-closed lineage gate landed |
| Machine/object lineage | yellow-red (`GAP-137`) |
| World/std/host semantic migration | yellow-red |
| Executed self-host ownership | red — S0 |
| Compiler B/C closure | red — B does not exist |
| Foreign semantic-authority elimination | red |
| FTCFTW architecture | green as concept |
| FTCFTW complete experimental proof | red — **near 0%** of the bound demonstrated; not proven |
| Release readiness | not ready (`.agents/RELEASE_READINESS.md`) |
| Agent-orientation durability | green |
| Trajectory | positive |

**This table is load-bearing, and one row is checked by a runner.**
`scripts/ledger/ftcftw.id` reads this file and FAILS unless the
"FTCFTW complete experimental proof" row still carries the literal anti-claim
`near 0%`. That is the one percentage on this page that is not merely a
judgment: it is a refusal, pinned in the runner that checks it, so that no
future edit can quietly upgrade the FTCFTW claim by rewording a table cell. Do
not delete or soften that row without changing the ledger in the same diff.
Verify with `./zig-out/bin/idol run scripts/ledger/ftcftw.id`.

**Headline:** the grammar *owner* question is answered and executable; grammar
*consumer* closure and parser ownership are not. Architecture is green; SHC is
red at S0; FTCFTW proof is red. Metrics are harder to fake than in earlier eras
— that is the progress, and it is why this table no longer carries percentages
that could be mistaken for counters.

## Identity (current)

Project identity: **Idol** (`idol`, `.id`). Constitution §67 is sole semantic
algebra authority. Git owns historical archive.

Repository identity is a dev/release split, not a contradiction:
`docs/spec/AUTHORITY.md` names `clpi/idol` as the living development
authority, and `docs/spec/constitution.md`'s `idollang/idol` is the release
identity the project SHIPS as (`tools/node/dev/orient` projects both:
`devrepository: clpi/idol`, `releaserepository: idollang/idol`, the latter
untouched until RELEASE_READINESS authorization). Cite the orient
projection, not this paragraph.

## Ledgers and fresh evidence

Machine-measurable values must come from running the current ledgers against one
clean HEAD — see "Recomputing every count on this page" above for the exact
commands.

Inspect committed evidence artifacts for revision, dirty state, and aggregate
outcome. A proof bundle at an older revision does not certify current HEAD; the
live tree is not automatically the measured program (`law.evidence.subject`,
`docs/bootstrap.md`).

## Prohibited headline metrics

Do not report as primary progress:

- `.id` file count or "percent in language"
- keyword removal counts alone
- green focused tests without aggregate revision-bound proof
- file-count or Zig-count reduction as self-hosting
- architecture convergence percentages without executed frontier movement
- **grammar-owner existence presented as grammar closure, or grammar work of any
  kind presented as movement toward compiler B**
- any count copied out of a gate's output into prose

## Superseded observations

Everything below described an earlier frontier. It is kept for trend reading
only. Where it conflicts with the sections above, the sections above are
current; where it conflicts with `docs/bootstrap.md`, that document is current.

### Superseded: frontier statement (pre-2026-08-23)

The dashboard formerly read: *"no compiler B exists. One substantive executed
transfer: production lexer/token-span boundary. Lexical identity, generated
grammar roles, and parser recognition remain blocked or host-owned."*

Superseded in part. "No compiler B exists" remains true and is restated above.
The rest understated the frontier: source ingress classification executes in
Idol, lexical identity is Idol-owned with `GAP-145` consumers remaining, and
generated grammar roles are Idol-owned with `GAP-134` consumer closure
remaining. Parser recognition remains host-owned — that clause was correct.

The milestone table formerly listed `B-G0 grammar Idol owner` as a single `open`
row. It is split above, because the owner exists and the consumers do not.

### Superseded: normalized dimension percentages

These were normalized judgments against an older frontier and are replaced by
the dated judgment table above. They are listed here so that a reader who
remembers a number can see it retired rather than silently changed.

Retired rows included: conceptual architecture convergence, language/semantic-law
closure, mechanical anti-drift enforcement, naming/vocabulary architecture,
**grammar single-authority implementation**, source/corpus canonical migration,
graph/application semantic authority, end-to-end semantic identity preservation,
DNIR semantic unification, transformation lineage, machine/object lineage,
world/std/host semantic migration, executed self-host ownership, compiler B/C
closure, FTCFTW architecture, FTCFTW complete experimental proof, and
agent-orientation durability.

The grammar row is the reason this section exists. A single
"grammar single-authority implementation" percentage could not distinguish an
owner that does not exist from an owner whose consumers have not closed, so it
kept reporting a middling fraction across a period in which the owner was built,
the parser's operator ontology was deleted, and two parser membership sets moved
to the owner. A number that cannot move when the architecture moves is not a
measurement.

### Superseded: longitudinal scorecard

Normalized assessment against an older frontier — not repository counters. The
grammar and self-hosting rows are the ones most affected; read the current
sections above instead.

| Metric | Earlier meaning | Current correct meaning | Trend |
|---|---|---|---|
| Language/semantic closure | settle syntax/features | one semantic authority + closed source law | ↑↑ |
| Naming convergence | lowercase/no snake/camel | one meaning → one native word; qualifiers → facts | ↑↑ |
| Canonical source | `.id` only | Idol command + `.id` suffix; constitution is semantic law | ↑↑ |
| Canonicality gate quality | lexical grep / convention | fail-closed positive controls + semantic classifications | ↑↑ |
| Canonical corpus debt | inferred from green gate | entire existing corpus satisfies current law | ↑, lagging |
| Semantic application authority | schema / call metadata | exact graph relation/subject/argument/result facts | ↑↑↑ |
| Semantic reconstruction | tolerated downstream lookup | zero rediscovery from source/name after resolution | ↑↑ |
| Identity integrity | hashes sometimes accepted | graph entity is identity; hashes evidence/index only | ↑↑↑ |
| DNIR vocabulary | conventional op taxonomy OK | same relation identity + realization facts | ↑ |
| Fact preservation | correctness through lowering | strongest known fact survives every boundary | ↑↑ |
| Transform lineage | text/hash provenance | exact graph entity lineage through transforms | ↑↑↑ |
| Machine lineage | tooling goal | application → realization → machine/object bytes | ↑ |
| World/authority model | std/modules/helpers | world facts; homes organize, never grant authority | ↑↑ |
| Grammar authority | parser-local knowledge | lexer → token → grammar role → parser; one authority | ↑↑↑ (owner landed; consumers open) |
| Host-pattern elimination | stylistic cleanup | no host technique becomes native semantics | ↑ |
| Self-hosting | file/conversion % | executed semantic authority → compiler B | ↑ honesty; still S0, no B |
| Foreign-code elimination | fewer Zig/C files | zero foreign **semantic** authority | ↑ slowly |
| FTCFTW architecture | "beat C / Wasmtime" | knowledge + realization freedom + demand deletion | ↑↑↑ |
| FTCFTW evidence | benchmark wins alone | multidimensional bound evidence on exact revision/path | ↑ rigor |
| Release evidence | green individual tests | revision-bound aggregate proof | → |
| Agent orientation | prompt discipline | repository-enforced authority + scoped projections | ↑↑ |
| Anti-drift durability | tell agents what not to do | forbidden semantic authority fail-closed | ↑↑ |

### Superseded: "What improved" inflection list

- **Canonical gates:** idiom controls fail-closed; subject-first loopholes
  tightened; boxing census separated "green path" from whole-compiler clean.
- **SEMANTIC-ONE target:** zero independent semantic taxonomies, downstream
  source-name reconstruction, storage-as-meaning, DNIR meanings without
  canonical relations, duplicated spellings, lost facts, tooling-owned vocab.
- **Graph application authority:** packed application roles authoritative;
  negative controls damage descriptors/ranges and verify invalid applications —
  stronger than bulk source rewrites.
- **Suffix migration:** tracked canonical source → `.id`; hooks/gates redirected;
  migration reported idiomgate/semanticgate clean on the **staged diff**
  (qualification: not whole-corpus purity).
- **Evidence integrity:** synthetic bootstrap verifier deleted; benchmark/trace
  binding to revision, environment, hashes; graph-backed assumptions required.
- **Grammar ownership:** one executable owner with byte-identical regeneration
  proved by a gate that includes a malformed-producer control, and an editor
  grammar disagreement pinned as a ratchet rather than a budget.
