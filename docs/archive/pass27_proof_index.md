# Pass 27 Proof Bundle Index

Authority: `docs/plans/pass27_proof_bundle.md`

## Proof bundle pipeline

```
source → compile → emission audit → manifest → proof JSON → correctness hash → bench/disasm/explain
```

## P0–P8 priority

| P | Focus | Gate |
|---|-------|------|
| P0 | Honest benchmarks + counters + `.proof.json` | P27-G01, `bench-proof-gate` |
| P1 | Ward cursor/LEB128/direct ARM64 | P27-G02 |
| P2 | Records + return packs | P27-G03–G04 |
| P3 | Meta-object API + transactions | P27-G05 |
| P4 | Ward decoder flagship | P27-G10 |
| P5 | Zero-copy C | P27-G11 |
| P6 | Shared derivation | P27-G12 |
| P7 | Reverse projection | P27-G13 |
| P8 | Pipeline fusion | P27-G14 |

## Flagship proofs

- **P27-PROOF-01** — Descriptor-generated Ward decoder (north star)
- **P27-PROOF-02** — Shape ladder
- **P27-PROOF-03** — Selective returns
- **P27-PROOF-04** — Closure/pipeline fusion
- **P27-PROOF-05** — Zero-copy C boundary
- **P27-PROOF-06** — Static parallel tasks

## CLI

```bash
zig build pass27-gate          # schema + M0 proofs (alias: proof-bundle-gate)
zig build bench-proof-gate     # 3-profile matrix + correctness
DUO_EMIT_PROOF=1 duo compile examples/benchmark.duo -o /tmp/x
duo catalog | jq '.pass27'
```

## Modules

| Module | Role |
|--------|------|
| `pass27_catalog.zig` | 27 WS + 10 gates + 6 proofs + P0–P8 |
| `pass27_proof_bundle.zig` | Eight-stage pipeline record |
| `pass27_benchmark_evidence.zig` | Counters, matrix, `.proof.json` |
| `pass27_meta_proof.zig` | Metaprogramming proof backlog |
| `pass27_gate.zig` | M0 native gate proofs |
