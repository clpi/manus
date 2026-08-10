# Duon bootstrap contract

`lib/compiler/bootstrap.duo` is the executable machine-readable authority. This
document is its human projection. The immediate target is compiler B, not a
sovereign backend.

## Current stage: S0

**S0 (active):** the pinned Zig seed produces the host compiler.

No Duo-built compiler binary exists in the production path yet.

SHC-00 supplies an executable structural verifier in
`lib/compiler/bootstrap.duo`. Its synthetic controls validate lineage and
parity relationships only; they neither authenticate the supplied identities
nor observe a compiler run. A real bootstrap command must eventually supply
graph-minted identities, witnesses, provenance, and observations from an
execution world before the contract can accept B or C.

`lib/compiler/application.duo` states the identity and projection shapes
required by SHC-01. It contains no synthetic proof. Production authority begins
when checked application identities survive the graph, DNIR, realization, and
machine lineage without being reconstructed from source names.

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host `duo` binary | CI, unit tests, bench gates |
| **S1 / B** | S0 + canonical Duon compiler source | First Duon-built compiler | Semantic fingerprint vs S0 oracle |
| **S2 / C** | B + identical source | Self-built compiler | Semantic, diagnostic, and behavioral parity with B |
| **S3** | C + identical source | Fixed-point candidate | Artifact comparison and reproducibility bundle |

## Trusted seed requirements

The seed must be:

- Pinned and checksummed
- Archived and reproducibly obtainable
- Minimal enough to audit
- Clearly separated from canonical Duo compiler source
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

The minimum Duon subset required to compile the next stage is a staged
capability level of canonical Duon, not a permanent second language.

The frozen compiler-critical basis is: bytes, views, strings, arenas, vectors,
maps, interning, bitsets, source/span, filesystem read, and diagnostic output.
`lib/compiler/bootstrap.duo` records the required capability identities and the
exact chain/evidence shape. A capability row requires a relation, descriptor,
and witness identity; the file does not claim that production reachability has
already been observed. Adding unrelated standard vocabulary does not advance
this contract.

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

## Prohibited claims

- "Self-hosted" when Duo code exists but is not on the production compile path
- Silent fallback. An explicit existing C/native bootstrap backend is allowed
  for B and C, but it does not prove backend sovereignty.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
- Synthetic verifier controls presented as observed bootstrap evidence
