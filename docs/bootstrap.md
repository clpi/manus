# Duon bootstrap contract

`lib/compiler/bootstrap.duo` is the executable machine-readable authority. This
document is its human projection. The immediate target is compiler B, not a
sovereign backend.

## Current stage: S0

**S0 (active):** the pinned Zig seed produces the host compiler.

No Duo-built compiler binary exists in the production path yet.

SHC-00 is executable: the seed compiler checks and runs
`lib/compiler/bootstrap.duo` through the explicit C bootstrap path. The emitted
translation contains zero `lua_Value`, `lua_invoke`, and `lua_require` markers.
Its positive chain and two negative controls pass. This proves the contract,
not compiler B. Direct ARM64 currently refuses its record signatures with
`InvalidMainSignature`; backend sovereignty begins at SHC-15 and does not block
the first B/C closure.

SHC-01 is executable in `lib/compiler/application.duo`. One application retains
semantic, content, and incarnation identity plus its relation, subject,
argument pack, result, descriptor facts, world, effects, witness, provenance,
and demand. Its controls prove that content reuse does not collapse semantic
identity, a content revision preserves semantic identity, and missing lineage
is rejected.

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
`lib/compiler/bootstrap.duo` records the basis and the exact chain/evidence
shape. Adding unrelated standard vocabulary does not advance this contract.

## Commands

```text
duo check lib/compiler/bootstrap.duo
duo run lib/compiler/bootstrap.duo
duo check lib/compiler/application.duo
duo run lib/compiler/application.duo
```

## Prohibited claims

- "Self-hosted" when Duo code exists but is not on the production compile path
- Silent fallback. An explicit existing C/native bootstrap backend is allowed
  for B and C, but it does not prove backend sovereignty.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
