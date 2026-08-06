# Pass 27 — Proof bundle and honest performance evidence (P0)

> **Mission:** Replace provisional performance claims with charter-grade proof bundles.  
> **Standard:** `docs/00-ECOSYSTEM-CHARTER.md` — equivalent semantics, correctness validation, generated-output inspection, reproducibility, source-density evidence.

## 0. Problem statement

The 40-program benchmark suite historically forced the boxed Lua path, so broad “beats C” claims were **provisional**. Pass 11 WP-01 split `--bench-backend` profiles, but evidence still lacked:

- per-artifact emission counters (boxes, unboxes, table ops, …);
- manifest recording backend × representation × runtime;
- correctness hashes tied to proof JSON;
- profile matrix reports (dynamic vs specialized vs direct).

## 1. Proof bundle pipeline (implemented P0)

```
accepted source
  → compile (profile-selected)
  → generated C (+ optional direct object)
  → emission audit (codegen_emission_audit.zig)
  → manifest (backend_identity.zig)
  → proof artifact JSON (proof_bundle.zig)
  → correctness hash (RESULT lines)
  → benchmark / disassembly / LSP-MCP (next)
```

| Module | Role |
|--------|------|
| `src/pass27_catalog.zig` | 27 workstreams + gates + flagship proofs |
| `src/pass27_gate.zig` | M0 native gate |
| `src/pass27_benchmark_evidence.zig` | Counters + 3-backend matrix + `.proof.json` writer |
| `src/main.zig` | Emits `{generated.c}.proof.json` when `DUO_EMIT_PROOF=1` or bench mode |
| `scripts/run_benchmark_proof.sh` | 3-profile matrix + C correctness hash gate |
| `src/native_barrier_checks.zig` | Low-level pattern scan bridge |

### Emission counters

Each proof records:

- `boxes`, `unboxes`, `allocations`
- `generic_table_ops`, `generic_calls`
- `closure_envs`, `return_pack_materializations`, `runtime_helpers`
- `generated_bytes`

### Evidence classes

| Class | Meaning |
|-------|---------|
| `provisional-boxed-path` | Boxing traffic detected — not a zero-boxing claim |
| `native-scalar-generated-c` | Full native scalar lowering via generated C |
| `specialized-generated-c` | Typed specialization, possible mixed dynamic |
| `direct-native-subset` | Direct backend selected (subset) |
| `dynamic-runtime` | Full Lua-compatible runtime |

## 2. Priority map (user gap analysis → passes)

| Priority | Gap | Pass / WS |
|----------|-----|-----------|
| **P0** | Honest benchmark profiles + counters | Pass 27 (this), Pass 11 WP-01 |
| **P1** | Direct ARM64 cursor/LEB128 Ward path | Pass 9/11, P26-WS21 vertical |
| **P2** | Records + return packs on direct backend | Pass 25 tail-demand, Pass 11 records |
| **P3** | Meta-object API, transactions, transform composition | Pass 26 WS30-31, Pass 12 |
| **P4** | Descriptor-generated Ward decoder | Flagship proof |
| **P5–P8** | C zero-copy, shared derivation, reverse projection, fusion | Pass 5, 20, 26 |

## 3. Gates

```bash
zig build pass27-gate          # schema + M0 proofs
zig build bench-proof-gate     # 3-profile correctness + proof artifacts
DUO_EMIT_PROOF=1 duo compile examples/benchmark.duo -o /tmp/x
python3 -c "import json; print(json.load(open('/tmp/duo_benchmark.c.proof.json'))['emission'])"
duo catalog | jq '.pass27'
```

## 4. Non-regression

- `claim.zero_boxing_global` remains **stale** until matrix shows zero boxes on targeted paths.
- `claim.faster_than_c_global` stays **partial** until profile matrix + artifact inspection pass.
- Do not publish headline perf numbers without a proof artifact path.

## 5. Next steps (P0 → P1)

1. Wire proof artifacts into `run_benchmark.sh` summary JSON.
2. Add disassembly snippet + `@comp.why` linkage to proof bundle.
3. Ten-benchmark boxed vs specialized vs direct table in `docs/performance.md`.
4. Shape ladder proof program (Proof 2) as `examples/pass27_shape_ladder.duo`.
