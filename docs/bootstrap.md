# Idol bootstrap contract

No executable compiler-B/C evidence producer exists yet. The seed remains the
host compiler; it does not obtain bootstrap authority from a project-owned
source model. This document is a human projection of the executed authority
frontier, not bootstrap evidence or production authority. The immediate target
is compiler B, not a sovereign backend. No compiler B exists.

**Progress dashboard:** three dominant metrics and normalized audit scores live
in [`docs/METRICS.md`](METRICS.md). Subordinate diagnostics (file counts, Zig
counts, keyword counts) must not headline status reports.

**Evidence-subject (`law.evidence.subject`):** live tree is not automatically
the measured program. `59093d7b` is an evidence revision whose subject is
`29f62035`. Do not report FTCFTW or unit aggregates “at HEAD” unless the
measured subject equals the live tree. FTCFTW is **invalid** as a performance
claim. No compiler B exists.

**Critical path to B:** source-family → lexical identity (GAP-145) → grammar
role (GAP-134) → parser → exact graph → demand → **one representation
decision** → specialization (budgeted) → direct realization → object →
evidence → B → C. Eight production lanes live in
`.agents/AGENT_COORDINATION.md`. Do not start parser SHC before GAP-145.
Do not let later passes re-decide boxing/stack/register/heap.

## Current stage: S0

**S0 (active):** the pinned Zig seed produces the host compiler.

A production host-built `idol` executable exists. No compiler B built from
canonical Idol compiler source exists. Host `idol check` / `idol run` are
not self-host proof.

The production front end nevertheless has one executed Idol-owned boundary:
the executed production file
`lib/compiler/lexer.id` owns token-kind production, token content,
and exact source spans. Its `.id` suffix is not evidence of canonical source or
compiler B. The host bounds-checks those spans and projects them into its
temporary parser representation. It does not reconstruct token text or source
locations.
Canonical lexical identity is not closed (`GAP-145` OPEN): producer identities
for text/bytes/compat/long, `#` comment, shebang, dash comments, and reserved
backtick now cross `tokenize()`. Producer `KIND_STRING_LIT` and host
`TokenKind.string_lit` and AST `.string_lit` are deleted without renumbering
live producer slots; Tree-sitter and quote/source-law consumers remain. The historical
`lib/` distribution path is retired filesystem
provenance (GAP-157), not semantic ownership.

The production route is now fail-closed. Allocation, record-buffer, and token
projection failures leave no accepted token stream and return an error to the
caller; they no longer return success and resume the host scanner. The host
scanner remains a differential oracle. This removes one automatic host semantic
fallback, but it does not close the missing canonical lexical identities in
`GAP-145`, the generated grammar roles in `GAP-134`, or later code-generation
fallbacks. Module-embed callers still convert a route error into a declined
embed or optimization path; deleting those higher-level fallbacks requires the
corresponding realization owner to distinguish physical refusal from semantic
failure.

Source ingress classification is now executed Idol authority. The producer owns
physical forms, corpus roles, longest-match admission, unlisted fallback, law,
and provenance through `sourceform*`, `sourceentry*`, and `sourcefact*`. Zig
normalizes a physical file to one repo-relative provenance spelling, calls the
producer once, and binds returned names to the temporary host ABI; it owns no
role roster or role→law mapping.
Production lexing now goes through the Idol lexer
(`tokenize()`); host `tokenizeHost()` is differential-only. The identity
blocker is `GAP-145` remaining consumers (Tree-sitter and source-law collapse)
before parser SHC. Physical producer slot 3 remains
unpublished and fails closed; it is not a token identity.
Parser long-bracket reconstruction is deleted (level in `int_val`).
`GAP-134` now has generated roles (separate semantic identity count and physical
slot span, `body_start`, infix)
consumed for expression-start / body-start / header-infix; it is not closed. Porting the host
recognizer would duplicate grammar authority through token-text lists and
mutable lookahead, so S0 remains the honest stage until those facts cross
the frontier.

The transfer must also preserve PREDICATE-ZERO. Parser and resolver output
retain cases, refinements, descriptor and world facts, unknowns, demands, and
transitions directly. It must not reproduce host `has`, `is`, `can`, `exists`,
sentinel, or query-then-mutate helpers as Idol semantic architecture.

## Production authority ledger

| Boundary | Current state | Exact remaining authority |
| --- | --- | --- |
| Source ingress | IDOL OWNED, HOST FS/ABI BRIDGE | `lib/compiler/lexer.id` executes physical-form and corpus-role admission and returns exact law/provenance. `src/lexer_bridge.zig` only resolves physical provenance to the producer's repo-relative spelling and binds producer names to temporary host enums. The roster is a deletion bridge until launch/provider ingress supplies explicit law facts. |
| Lexer producer | IDOL OWNED | `lib/compiler/lexer.id` owns token-kind, content, and span production and fails closed. Canonical lexical-law closure remains `GAP-145`. |
| Canonical `.id` lex route | IDOL OWNED | `src/lexer_dispatch.zig` `route()` calls `tokenize()` for every source. Host `tokenizeHost()` is differential-only (legacy-equivalent subset; must not veto intentional Idol divergence; `law.bridge.death`). Generated `src/lexer_tokenize.c` is from current `lib/compiler/lexer.id` via `dump-c --lib`. Every lexer export takes family as an operand (`law.family.one`); `new()` does not read suffix bytes. Production compile, fmt, and embed call the `sourceFacts` bridge once, then `Lexer.initFacts`; the law/provenance answer is executed Idol output. `route()`, parse, sema, and token-view consume `lex.family`. `Lexer.init` is a test convenience. |
| Lexer ABI schema | HOST OWNED (bridge) | `RECORD_SLOTS` / `lexErrorFromCode` / `tokenKindFromOrdinal` deleted. Consumer queries `recordslots()` / `field*()` / `rejectionname()` / `kindname()` / `kindcount()`; `bindKindSchema` binds ordinals once. `bindKindSchema` is a deletion-gated bridge (`law.bridge.death`): endpoint is token-role-id, not producer-name → runtime bind → host enum. Remaining: host `TokenKind` enum, `duo_lexer_*` / `useDuoTokens` names (`law.schema.one`, `law.magic.zero`, GAP-107). |
| Lexical identity | IDOL OWNED, GAP-145 OPEN | Text/bytes/compat/long, `#` comment, shebang, `--` / `--[[` comments, and reserved backtick cross `tokenize()`. Long-text delimiter level is `int_val`; parser no longer scans `[[`. Producer, host-token, and AST `string_lit` identities are deleted; physical slot 3 is unpublished. AST `.quoted` retains exact quote provenance without a text/bytes taxonomy. Tree-sitter and semantic quote/source-law consumers remain. Do not start parser SHC. |
| Token/span | IDOL OWNED | Exact token content spans are projected through the generated-C physical bridge; the host retains a temporary parser representation. |
| Grammar roles | IDOL OWNED, GAP-134 partial | `lib/compiler/token.id` is the **one executable grammar-fact owner** (`law.grammar.one`): token identities and every role, precedence and associativity fact. It emits `src/grammar_role_table.zig` (host bridge the production parser reads, `law.bridge.death`) and `lib/token/grammarrole.id` (Idol projection). `src/grammar_roles.zig` is accessors only and holds no fact; `src/grammar_role_gen.zig` and `src/emit_grammar_role.zig` are deleted. `zig build grammar-projection` (on `test`) fails unless both artifacts regenerate byte-identically, so damaging the Idol owner changes what the compiler accepts. NOT closure: `docs/spec/grammar.md` still does not generate the parser, Tree-sitter is still a second authored grammar, and the parser `BinOp` map remains reconstruction debt. |
| Parser recognition | HOST OWNED | `src/parser.zig` still decides expressions, bindings, and source structure. `parse_module` installs the producer pack when missing (`route()`); header recognition is one `headerSignal` over that pack. Host save/scan/restore snapshot walk is deleted. Not parser SHC. |
| Binding/scope | HOST OWNED | Production binding and scope construction remain in the host parser and semantic producer. |
| Semantic construction | HOST OWNED | The graph work is an improving host implementation, not executed compiler-B source. |
| Relation/application resolution | HOST OWNED | Production resolution remains host-executed; exact graph application authority is still under integration. |
| Demand | HOST OWNED | No executed Idol compiler demand stage exists. |
| Lowering/realization | HOST OWNED | Host lowering and realization select the artifact path. |
| Machine selection | HOST OWNED | Host code selects direct native or generated-C realization. |
| Object emission | HOST OWNED | The native object emitter is host implementation and production lineage is incomplete. |
| Runtime/link selection | HOST OWNED | Host code still selects runtime support and link behavior. |
| Assembler/linker execution | FOREIGN REALIZATION ONLY | Foreign tools perform physical realization after the host selection. |

For the fail-closed lexer transfer:

- **BEFORE:** a storage failure returned success without installing the Idol
  token pack, so the next parser read silently resumed the host scanner.
- **AFTER:** the same failure propagates, partial route storage is released, and
  no host token stream is accepted by that route.
- **NEXT:** `GAP-145` remaining is Tree-sitter `grammar.json` and semantic
  consumers that collapse quote/source-law distinctions. Source-form and
  corpus-home admission now execute in Idol; filesystem normalization and host
  enum binding remain explicit bootstrap bridges. Do not start parser SHC. `GAP-134` remaining is closing
  grammar.md as the generatable owner. Header recognition is one
  `headerSignal` over the producer pack (snapshot walk deleted); Pratt
  left/right come from roles; BinOp map remains.
  Replace the temporary host enum/name ABI only after compiler B consumes the
  same source-law contract directly.

Canonical source ingress recognizes `.id` as Idol. New canonical `.id` is
admitted. Retired `.duo` / `.duon` / `.idsem` are not source suffixes.
`.lua` remains foreign compatibility input. Tracked noncanonical `.id`
content remains SOURCE-ZERO debt and must reach zero; the `.id` extension
itself is not debt. Compatibility testing must move to generated, structured,
or external material rather than an in-tree stale source library.
`src/lexer_bridge.zig` is one bootstrap helper, not source-family authority. It
normalizes filesystem provenance and consumes the executed producer's exact
law/provenance answer. Build entry, embedded module discovery, and direct-native
module metadata discovery consume that fact. Tooling and corpus gates that
still enumerate `.id` independently remain migration bridges, not bootstrap
evidence.

Suffix-independent semantic identity is not closed by the existing differential.
Byte-identical object output demonstrates only one realization result; it does
not prove equality of every normalized graph fact. `GAP-142` owns the exact
identity and continuity boundary. Until the complete checked-fact comparison
passes, suffix and path influence remain unclosed rather than being inferred
from machine equality.

Active bootstrap bridges (lock scripts, generated C lexer tables, physical tool
aliases) remain only while `law.bridge.death` records owner, replacement, and
deletion condition in `docs/bootstrap.md` or an open gap. Delete each bridge
when its condition is met — do not relocate to legacy paths.

The former synthetic bootstrap verifier was deleted. It had no production
consumer, observed no compiler run, and modeled identity through three invented
numeric coordinates. A real bootstrap projection must consume exact graph ids,
facts, witnesses, provenance, and observations from an execution world before
the contract can accept B or C.

`lib/compiler/application.id` is **role documentation only** (decomposed;
APPLICATION-CONSUMER-ZERO). The graph entity is identity. A coordinate
`identity` record or parallel application schema is forbidden. Agents must
not treat that file as canonical application schema or extend it with tables.
Production authority is graph accessors (`applicationRelation`, …).
Production authority begins when exact graph entities and explicit fact
cardinality survive graph, demand, realization, and machine lineage without
source-name reconstruction. Audit: `scripts/ledger/application.id`.
Lowering that reads `ApplicationFact.relation` from the graph must not
reconstruct subject, operand, result, descriptor, effect, world, witness,
demand, or target downstream (`law.application.consumer`).

**Graph sovereignty (P0, not closed):** `NodeKind` tags are physical indexes
only (`law.tag.authority`). Production query/validity must use published
facts (`callable`, `hasDescriptorFacts`, graph accessors) — never
`kind == .func` / `.table_shape` / `.module` for meaning. Audits:
`scripts/ledger/graph.id`, `scripts/ledger/application.id`, `gate/graph.id`.
Open: `Card` cardinality on application facts; `ast_ref` semantic reads → 0;
columnar fact storage; graph core imports AST/sema/transform — endpoint is
GRAPH-SOVEREIGNTY. Partial: caller-indexed `home_apps` adjacency;
`applicationsIn` / `relationsReferencedBy` query API; zero-copy operand views;
`nested` reverse index for scope/contains; `descriptor_refs` for recursion walks.

Generated `src/lexer_tokenize.c` plus host `Token` rematerialization is a
**physical** bridge. Semantic authority is Idol `tokenize()`; compile-time
FTCFTW still needs Idol lexer → immutable token view → Idol parser without
generated-C call, oversized records, or host token copies. `lib/` remains
retired filesystem provenance (GAP-157), not a semantic namespace.

Do not claim combined CI green from local ledgers or focused unit runs.
Remeasure the integrated build at the current revision. Crash count is
qualitatively above pass-count (`law.crash.first`). Every compiler refusal
(parser, resolver, world, descriptor, realization, specialization) names
application, missing fact, producer, and consumer — not only DNB backend
bail.

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host-built `idol` binary (not compiler B) | Remeasured CI/unit/bench at the revision — not assumed from local ledgers |
| **S1 / B** | S0 + canonical Idol compiler source | First Idol-built compiler | Exact graph facts, witnessed correspondence, and behavior vs the seed oracle |
| **S2 / C** | B + identical source | Self-built compiler | Semantic, diagnostic, and behavioral parity with B |
| **S3** | C + identical source | Fixed-point candidate | Artifact comparison and reproducibility bundle |

## Trusted seed requirements

The seed must be:

- Pinned and checksummed
- Archived and reproducibly obtainable
- Minimal enough to audit
- Clearly separated from canonical Idol compiler source
- Used for bootstrap only — not semantic authority after S2

## Stage comparisons (always required)

- Exact graph identities, facts, and witnessed cross-incarnation correspondence
- Public capability manifests
- Graph-grounded realization facts and causal lineage
- Object structure
- Binary behavior (test matrix)
- Diagnostics parity

Fingerprints may accelerate candidate comparison or summarize evidence. They
never establish B/C semantic identity, correspondence, or lineage.

The executed foundation now qualifies the one resident graph `id` with an
owning graph-incarnation coordinate, freezes registered incarnations, and
admits explicit witnessed preserved/replaced/split/merge/generated/retired
correspondence facts with checked cardinality. The public knowledge snapshot
projects those exact references and no longer manufactures identity from a
kind/name string or fingerprint. This is not B/C closure: no bootstrap driver
yet persists two incarnations, supplies B and C producer witnesses, or compares
their complete graph and diagnostic facts.

## Stage comparisons (when declared)

- Compiler performance baselines
- Binary identity (deterministic builds only)

## Bootstrap subset

The minimum Idol subset required to compile the next stage is a staged
capability level of canonical Idol, not a permanent second language.

The compiler-critical basis is required capabilities and facts, not named
container kingdoms:

- element width and sequence shape
- view lifetime and alias facts
- table shape
- arena realization option
- vector realization option
- intern correspondence
- bit representation
- source and span provenance
- filesystem read as a subject / world / effect application
- diagnostic output as a subject / world / effect application

Do not resurrect bytes, strings, vectors, maps, or bitsets as permanent native
ontologies. No graph/world-backed projection currently records or observes that
basis for B and C. Filesystem read and diagnostic output still need their
subject, world, and effect facts, and production reachability must be observed
rather than asserted. `GAP-139` owns that missing evidence boundary. Adding
unrelated standard vocabulary does not advance this contract.

## FTCFTW constraint

Bootstrap work must preserve maximum semantic knowledge with minimum physical
compiler state. The graph retains meaning; demand deletes work before
materialization; realization keeps compact lawful choices until commitment;
machine selects the cheapest concrete execution. Rich meaning does not justify
a large runtime, boxed compiler state, or a fully materialized realization
program.

The source-family projection in this stage is one bounded ingress query with no
allocation. It selects one language law and records provenance. It does not
select machine realization. Equivalent canonical `.id` and temporary
compatibility input must normalize to identical semantic entities and facts
apart from admitted source provenance; focused byte equality alone does not
prove that boundary.

The direct-native metadata lookup adds two fixed suffix probes per candidate
prefix and no allocation beyond the path/source work already required. Exact
focused and aggregate outcomes are volatile evidence and therefore do not live
in this contract. Session bootstrap must bind them to the tested revision,
dirty state, command, requested-run outcome, and artifact; unavailable evidence
fails closed. `GAP-131` remains an onboarding P0 until that projection reads
canonical gap files and live claims. A focused pass never changes a red
aggregate into a pass, and a zero returned by the current broken reader is not
evidence of a clean project.

Future B/C acceptance requires two distinct application and output
incarnations, the seed as B's exact producer, B as C's exact producer,
identical source content, the same backend and execution-world content, and
semantic, behavioral, and diagnostic observations with witness and provenance
bound to each application. No synthetic structural self-check substitutes for
those observations. B and C may have different artifact content; binary
identity is not required for B-to-C acceptance.

## Source-zero deletion gate

Do not add a bootstrap verifier beside the production graph. The remaining
tracked application inventory is migration evidence only; its demanded facts
must move into executed `.id` with production perturbation and differential
proof before that source is deleted. A future bootstrap projection derives its
evidence from the executed Idol compiler graph rather than making a host build
step authoritative.

## Prohibited claims

- "Self-hosted" when Idol code exists but is not on the production compile path
- Silent fallback. A pinned trusted-seed C/native backend may remain only as
  foreign physical realization with zero Idol semantic authority; it does not
  prove backend sovereignty or authorize new host implementation.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
- Synthetic verifier controls presented as observed bootstrap evidence
