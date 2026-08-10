# Idsem bootstrap contract

`lib/compiler/bootstrap.duo` is the executable machine-readable structural
candidate. This document is its human projection. It is not bootstrap evidence
or production authority. The immediate target is compiler B, not a sovereign
backend.

## Current stage: S0

**S0 (active):** the pinned Zig seed produces the host compiler.

No Idsem-built compiler binary exists in the production path yet.

The production front end nevertheless has one executed Idsem-owned boundary:
`lib/std/compiler/lexer.duo` owns token content, token identity, and exact
source spans. The host bounds-checks those spans and projects them into its
temporary parser representation. It does not reconstruct token text or source
locations.

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

The next boundary remains production parse recognition. It is blocked by
`GAP-134`: C0 requires the self-hosted parser to consume a generated
constitutional grammar, while the current repository has no machine-readable
canonical grammar-role projection. Porting the host recognizer would duplicate
grammar authority through token-text lists and mutable lookahead. S0 therefore
remains the honest stage until grammar roles and an immutable token view are
available to executed Idsem parser code.

## Production authority ledger

| Boundary | Current state | Exact remaining authority |
| --- | --- | --- |
| Source ingress | MIGRATION BRIDGE | Zig discovers source and projects the centralized `.id`/historical `.duo` family fact. |
| Lexer | IDSEM OWNED | Executed Idsem lexer owns the current token stream and now fails closed; canonical lexical-law closure remains `GAP-145`. |
| Token/span | IDSEM OWNED | Idsem token identities and exact spans are projected through the generated-C physical bridge. |
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
- **NEXT:** `GAP-145` must publish distinct canonical lexical identities and
  source-law provenance; then `GAP-134` can project generated grammar roles to
  an immutable token view and replace the first host parser recognition.

Canonical source ingress now recognizes `.id` as Idsem and retains `.duo` as
historical provenance. Both suffixes select the same lexer, parser law, semantic
production, and realization path. The source-family projection is centralized
in `src/duo_lexer_bridge.zig` until compiler B can consume the constitutional
source fact directly. Build entry, embedded module discovery, and direct-native
module metadata discovery prefer `.id` and fall back to `.duo`. The native
metadata path consumes the source-family constants rather than maintaining its
own suffix spelling. Tooling and corpus gates that still enumerate `.duo`
independently remain migration bridges, not bootstrap evidence.

Suffix-independent semantic identity is not closed on current main. An executed
negative control over byte-identical `.id` and `.duo` inputs produced identical
direct-native object bytes, but every exported graph `stable_id` changed because
the graph hashes the source path. `GAP-142` owns removal of that path-derived
identity authority. Until then, the suffix distinction is not confined to
provenance even though the tested machine realization is equal.

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

`lib/compiler/application.duo` inventories the application and pack facts
required by SHC-01. It is still historical migration source, not a complete
identity owner: its three-coordinate `identity` record conflicts with the rule
that the graph entity is identity, and unconditional identity fields cannot
represent unknown, absent, and empty facts honestly. Production authority begins
when exact graph entities and explicit fact cardinality survive graph, demand,
realization, and machine lineage without source-name reconstruction.

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host `duo` binary | CI, unit tests, bench gates |
| **S1 / B** | S0 + canonical Idsem compiler source | First Idsem-built compiler | Semantic fingerprint vs S0 oracle |
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

- Semantic fingerprints
- Public capability manifests
- Optimized IR fingerprints (when applicable)
- Object structure
- Binary behavior (test matrix)
- Diagnostics parity

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
select machine realization: the current focused direct-native differential emits
byte-identical objects for equivalent `.id` and `.duo` source. The downstream
graph still hashes the full source path into `stable_id`, however, so semantic
identity equivalence remains open until `GAP-142` removes that authority.

The direct-native metadata lookup change adds two fixed suffix probes per
candidate prefix and no allocation beyond the path/source work already required.
Its earlier serialized aggregate reached **1183/1186** with three known semantic
failures. That is historical evidence for that exact snapshot, not current-tree
admission. On the current fail-closed lexer working tree, the focused production
route controls passed **6/6**, `zig build` completed, the rebuilt compiler checked
`examples/shc/lexer.id`, and `pass16-m1-smoke` completed **16/16**. The current
unit aggregate remains red after execution at **1191/1194**: interpolation
indexed holes, ordinary root relation projection, and independent `eq`
derivation still fail. The new lexer controls pass inside that exact aggregate;
the baseline failures remain failures rather than being renamed a pass.

Future B/C acceptance requires two distinct application and output
incarnations, the seed as B's exact producer, B as C's exact producer,
identical source content, the same backend and execution-world content, and
semantic, behavioral, and diagnostic observations with witness and provenance
bound to each application. The structural controls check those relationships,
not the authenticity of their synthetic identities. B and C may have different
artifact content; binary identity is not required for B-to-C acceptance.

## Commands

```text
duo check lib/compiler/bootstrap.duo
duo run lib/compiler/bootstrap.duo
duo check lib/compiler/application.duo
```

These historical `.duo` checks validate migration structures only. They are not
canonical `.id` source, an SHC stage, or an aggregate. A future bootstrap
projection must derive its evidence from the executed Idsem compiler graph
rather than make a host build step authoritative.

## Prohibited claims

- "Self-hosted" when Idsem code exists but is not on the production compile path
- Silent fallback. An explicit existing C/native bootstrap backend is allowed
  for B and C, but it does not prove backend sovereignty.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
- Synthetic verifier controls presented as observed bootstrap evidence
