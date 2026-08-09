# Duo bootstrap architecture (Pass 16)

This document describes the **honest** bootstrap strategy for Duo self-hosting.
Machine-readable state: `duo catalog` → `pass16.bootstrap_dag`.

## Current stage: S0

**S0 (active):** Pinned Zig bootstrap via `mise` + `scripts/ci_zig_version.duo`.
`zig build` produces `zig-out/bin/duo`, which is the host compiler (Zig implementation).

No Duo-built compiler binary exists in the production path yet.

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host `duo` binary | CI, unit tests, bench gates |
| **S1** | S0 + canonical Duo compiler source | First Duo-built compiler | Semantic fingerprint vs S0-oracle |
| **S2** | S1 + same source | Self-built compiler | Behavioral + test parity with S1 |
| **S3** | S2 + same source | Third generation | Reproducibility bundle (optional binary identity) |

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

The minimum Duo subset required to compile the next compiler stage is a **staged
capability level** of canonical Duo — not a permanent second language.

Track supported syntax, descriptors, compile-time capabilities, native structures,
runtime profile, backend capabilities, target, unsupported features, and migration plan
in `src/pass16_catalog.zig` workstreams.

## Commands

```bash
duo catalog | rg pass16
zig build pass16-gate
duo run examples/pass16_m1_lexer_proof.duo
```

## Prohibited claims

- "Self-hosted" when Duo code exists but is not on the production compile path
- Silent fallback to generated C, Lua VM, or external compiler on the canonical path
- Undocumented bootstrap binaries or unpinned dependencies

See `(archived, deleted — git history)` for the full Pass 16 mission.
