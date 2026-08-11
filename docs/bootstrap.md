# Idsem bootstrap contract

The seed currently obtains structural bootstrap candidate data from the tracked
project-owned file `lib/compiler/bootstrap.duo`. That file is SOURCE-ZERO debt,
not canonical source or an implementation pattern. This document is a human
projection of the executed authority frontier; it is not bootstrap evidence or
production authority. The immediate target is compiler B, not a sovereign
backend.

## Current stage: S0

**S0 (active):** the pinned Zig seed produces the host compiler.

No Idsem-built compiler binary exists in the production path yet.

The production front end nevertheless has one executed Idsem-owned boundary:
the historical distribution file `lib/std/compiler/lexer.duo` owns legacy
token-kind production, token content, and exact source spans. The host
bounds-checks those spans and projects them into its temporary parser
representation. It does not reconstruct token text or source locations.
Canonical lexical identity is not closed: text, bytes, Lua long text, comments,
shebang, and reserved backtick still lack the distinct law-bearing identities
required by `GAP-145`. The `std` path is migration distribution, not semantic
ownership. This tracked project-owned source must move semantically into
canonical `.id` and the old file must be deleted in the same proven production
slice; compatibility support does not justify retaining it as a pattern source.

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

Source ingress remains the earliest host-owned entry seam: Zig still derives
source law and provenance from suffix/path text instead of consuming an
executed Idsem source-family fact. It is migration debt, but the current
executable blocker is `GAP-145`: the lexer must publish the distinct canonical
lexical identities needed by `GAP-134`. Generated grammar roles and an
immutable token view can then move the first production parser recognition
into executed Idsem. Porting the host recognizer would duplicate grammar
authority through token-text lists and mutable lookahead, so S0 remains the
honest stage until those facts cross the frontier.

The transfer must also preserve PREDICATE-ZERO. Parser and resolver output
retain cases, refinements, descriptor and world facts, unknowns, demands, and
transitions directly. It must not reproduce host `has`, `is`, `can`, `exists`,
sentinel, or query-then-mutate helpers as Idsem semantic architecture.

## Production authority ledger

| Boundary | Current state | Exact remaining authority |
| --- | --- | --- |
| Source ingress | HOST OWNED | Zig currently classifies suffix/path text into source law and provenance. The helper is centralized but remains host authority and does not consume the complete corpus classification. |
| Lexer | IDSEM OWNED | Executed Idsem lexer owns legacy token-kind, content, and span production and now fails closed; canonical lexical-law closure remains `GAP-145`. |
| Lexical identity | BLOCKED | Distinct text, bytes, compatibility literal/comment, shebang, and reserved-backtick facts do not yet cross the token boundary (`GAP-145`). |
| Token/span | IDSEM OWNED | Exact token content spans are projected through the generated-C physical bridge; the host retains a temporary parser representation. |
| Grammar projection | BLOCKED | No complete machine-readable canonical role projection or immutable token view exists (`GAP-134`, `GAP-145`). |
| Parser recognition | HOST OWNED | `src/parser.zig` still decides callable headers, expressions, bindings, and source structure. |
| Binding/scope | HOST OWNED | Production binding and scope construction remain in the host parser and semantic producer. |
| Semantic construction | HOST OWNED | The graph work is an improving host implementation, not executed compiler-B source. |
| Relation/application resolution | HOST OWNED | Production resolution remains host-executed; exact graph application authority is still under integration. |
| Demand | HOST OWNED | No executed Idsem compiler demand stage exists. |
| Lowering/realization | HOST OWNED | Host lowering and realization select the artifact path. |
| Machine selection | HOST OWNED | Host code selects direct native or generated-C realization. |
| Object emission | HOST OWNED | The native object emitter is host implementation and production lineage is incomplete. |
| Runtime/link selection | HOST OWNED | Host code still selects runtime support and link behavior. |
| Assembler/linker execution | FOREIGN REALIZATION ONLY | Foreign tools perform physical realization after the host selection. |

For the fail-closed lexer transfer:

- **BEFORE:** a storage failure returned success without installing the Idsem
  token pack, so the next parser read silently resumed the host scanner.
- **AFTER:** the same failure propagates, partial route storage is released, and
  no host token stream is accepted by that route.
- **NEXT:** `GAP-145` must publish distinct canonical lexical identities;
  `GAP-134` can then project generated grammar roles to an immutable token view
  and replace the first host parser recognition. The source-family projection
  must replace suffix-derived ingress authority before compiler-B source ingress
  can be called Idsem-owned.

Canonical source ingress now recognizes `.id` as Idsem and temporarily accepts
`.duo` compatibility input with noncanonical provenance. Both suffixes select
the same lexer, parser law, semantic production, and realization path. Tracked
project-owned `.duo` source remains SOURCE-ZERO debt and must reach zero;
compatibility testing must move to generated, structured, or external material
rather than an in-tree stale source library. `src/duo_lexer_bridge.zig` is one
bootstrap helper, not the constitutional source-family authority: it still
decides from suffix text and maps every `.duo` to the same law/provenance pair even though
the corpus distinguishes compatibility, historical, generated, and current
migration inputs. Build entry, embedded module discovery, and direct-native
module metadata discovery prefer `.id` and fall back to `.duo`. The native
metadata path consumes the source-family constants rather than maintaining its
own suffix spelling. Tooling and corpus gates that still enumerate `.duo`
independently remain migration bridges, not bootstrap evidence.

Suffix-independent semantic identity is not closed by the existing differential.
Byte-identical object output demonstrates only one realization result; it does
not prove equality of every normalized graph fact. `GAP-142` owns the exact
identity and continuity boundary. Until the complete checked-fact comparison
passes, suffix and path influence remain unclosed rather than being inferred
from machine equality.

The host names `duo_lexer_bridge`, `duo_mode`, and the `duo` executable are
historical bootstrap symbols. They remain one implementation path, not a second
language or command authority. Delete the bridge names when compiler B consumes
the constitutional source fact directly; remove the executable alias after an
`idsem` entry invokes that same command authority in production. The generated
runtime package search still spells `.duo` in emitted C, and the current corpus,
formatter, LSP, MCP, Tree-sitter, generators, and census enumerations still
contain independent `.duo` assumptions. Their deletion gate is a generated
source-family projection consumed by each surface, with untracked `.id`
candidates included and missing census input failing closed.

SHC-00 supplies an executable structural verifier in
`lib/compiler/bootstrap.duo`. Its synthetic controls validate lineage and
parity relationships only; they neither authenticate the supplied identities
nor observe a compiler run. Its historical three-coordinate `identity` record
is not the constitutional graph-owned identity model and must not be promoted to
canonical `.id` source. A real bootstrap projection must consume exact graph
entities, witnesses, provenance, and observations from an execution world
before the contract can accept B or C.

The tracked SOURCE-ZERO file `lib/compiler/application.duo` inventories the
application and pack facts required by the next bootstrap transfer. It is not a complete
identity owner: its three-coordinate `identity` record conflicts with the rule
that the graph entity is identity, and unconditional identity fields cannot
represent unknown, absent, and empty facts honestly. Production authority begins
when exact graph entities and explicit fact cardinality survive graph, demand,
realization, and machine lineage without source-name reconstruction.

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host `duo` binary | CI, unit tests, bench gates |
| **S1 / B** | S0 + canonical Idsem compiler source | First Idsem-built compiler | Exact graph facts, witnessed correspondence, and behavior vs the seed oracle |
| **S2 / C** | B + identical source | Self-built compiler | Semantic, diagnostic, and behavioral parity with B |
| **S3** | C + identical source | Fixed-point candidate | Artifact comparison and reproducibility bundle |

## Trusted seed requirements

The seed must be:

- Pinned and checksummed
- Archived and reproducibly obtainable
- Minimal enough to audit
- Clearly separated from canonical Idsem compiler source
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

## Stage comparisons (when declared)

- Compiler performance baselines
- Binary identity (deterministic builds only)

## Bootstrap subset

The minimum Idsem subset required to compile the next stage is a staged
capability level of canonical Idsem, not a permanent second language.

The candidate compiler-critical basis is: bytes, views, strings, arenas,
vectors, maps, interning, bitsets, source/span, filesystem read, and diagnostic
output. `lib/compiler/bootstrap.duo` records a relation, descriptor, and witness
identity for each candidate row plus the chain/evidence shape. That is not yet
an exact frozen capability contract: filesystem read and diagnostic output
still need their subject, world, and effect identities, and no row has observed
production reachability. Adding unrelated standard vocabulary does not advance
this contract.

## FTCFTW constraint

Bootstrap work must preserve maximum semantic knowledge with minimum physical
compiler state. The graph retains meaning; demand deletes work before
materialization; realization keeps compact lawful choices until commitment;
machine selects the cheapest concrete execution. Rich meaning does not justify
a large runtime, boxed compiler state, or a fully materialized realization
program.

The source-family projection in this stage is a constant-time ingress fact with
no allocation. It selects one language law and records provenance. It does not
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
bound to each application. The structural controls check those relationships,
not the authenticity of their synthetic identities. B and C may have different
artifact content; binary identity is not required for B-to-C acceptance.

## Source-zero deletion gate

Do not copy or run the tracked bootstrap sources as canonical examples. Their
retained structural behavior must move into executed `.id`, receive production
perturbation and differential proof, and then be deleted. A future bootstrap
projection derives its evidence from the executed Idsem compiler graph rather
than making a host build step authoritative.

## Prohibited claims

- "Self-hosted" when Idsem code exists but is not on the production compile path
- Silent fallback. A pinned trusted-seed C/native backend may remain only as
  foreign physical realization with zero Idsem semantic authority; it does not
  prove backend sovereignty or authorize new host implementation.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
- Synthetic verifier controls presented as observed bootstrap evidence
