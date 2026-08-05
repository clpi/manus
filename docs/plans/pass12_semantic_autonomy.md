# Pass 12 — Semantic Autonomy & Proof-Carrying Development

> **Mission:** Humans and agents express semantic intent; Duo deterministically owns correctness, performance, provenance, and release truth.  
> **Catalog:** `duo catalog | jq '.pass12'`

---

## Governing rules

1. **AI proposes; Duo proves** — no online model on the compile/release path
2. **Reuse foundations** — descriptors, effects, laws, transforms, evidence (no parallel intent DSL)
3. **Bounded autonomy** — every operation has targets, budgets, validation, rollback
4. **Claims are objects** — linked to proof bundles in `src/proof_carrying.zig`
5. **Pretty, dense output** — same vocabulary in CLI, LSP, MCP

---

## Eight goals (track in catalog)

| ID | Goal | Owner module |
| --- | --- | --- |
| A | Proof-carrying transforms | `src/proof_carrying.zig` |
| B | Counterexample-guided synthesis | `src/realization.zig` (future) |
| C | Executable bidirectional specs | `src/wasm_semantic_gen.zig` (partial) |
| D | Agent semantic loop | `src/semantic_cli.zig` + `~/x/duo-mcp` |
| E | Living architecture query | `src/semantic_ownership.zig` |
| F | Semantic compression metrics | P12-WS11 |
| G | Self-hosting via same workflow | P12-WS7 / M1 |
| H | Safe self-improvement | `src/assumption_guard.zig` |

---

## Execution order (from spec §15)

1. Close Pass 11 release architecture (P12-WS1)
2. Intent + proof obligation records (P12-WS2) — **partial**
3. One transform with full proof record (P12-WS3) — **partial** (`transform_engine.logProvenance`)
4. Candidate comparison (P12-WS4) — **partial** (`realization.compareCandidates`)
5. Property/differential/fuzz evidence (P12-WS5)
6. Canonical semantic source + projections (P12-WS6)
7. **M1:** Production lexer/token component (P12-WS7)
8. MCP transaction loop (P12-WS8) — **partial** (`duo semantic preview|validate`, `src/semantic_transaction.zig`)
9. LSP presentation (P12-WS9)
10. Release truth registry (P12-WS10) — **partial** (`seed_capabilities`, `effectiveClaimStatus`)
11. Compression harness (P12-WS11) — **partial** (`semantic_compression.zig`)
12. **M2:** Ward dispatch transfer (P12-WS12)

---

## Vertical milestones

### P12-M1 — Compiler component (recommended first)

Descriptor-defined **keyword/token classifier** used by the **actual** compiler:

- Canonical source: token metadata (lexer + grammar)
- Projections: classifier, formatter metadata, Tree-sitter input, LSP/MCP entities, tests
- Candidates: branch chain, trie, perfect hash, dense table
- Proof: exact classification, deterministic, no alloc, no boxing
- Integration: replace host path in `src/lexer.zig`

### P12-M2 — Ward dispatch

Descriptor-generated instruction dispatch with proof-carrying selection — reuses M1 infrastructure without Ward-only schemas.

---

## Reuse map (no parallel systems)

| Pass 12 concept | Canonical owner |
| --- | --- |
| Evidence classes | `src/evidence_record.zig` |
| Assumptions / guards | `src/assumption_guard.zig` |
| Contract hardness | `src/contract_model.zig` |
| Intent / obligations / bundles | `src/proof_carrying.zig` |
| Transform proof records | `src/transform_engine.zig` (`buildTransformProofRecord`, `proofLogEntries`) |
| Candidate comparison | `src/realization.zig` (`compareCandidates`) |
| Token/keyword semantic source (M1) | `src/token_semantic.zig` → `src/lexer.zig` |
| Transform registry | `src/transform_engine.zig` |
| Realization candidates | `src/realization.zig` |
| Semantic ownership | `src/semantic_ownership.zig` |
| Bounded context packages (Audit 6) | `src/semantic_context.zig` |
| CLI semantic projections (WS8 partial) | `src/semantic_cli.zig` (`duo semantic`) |
| Bounded transaction preview (WS8) | `src/semantic_transaction.zig` |

---

## Validation

```bash
duo catalog | jq '.pass12'
duo catalog | jq '.pass12.proof_carrying'
duo catalog | jq '.pass12.semantic_compression'
duo catalog | jq '.pass12.m1_token_semantic'
duo semantic compare | jq .
duo semantic proof | jq .
duo semantic preview classifier.sorted_lookup | jq .
duo semantic validate classifier.perfect_hash | jq .
duo semantic transforms | jq .
duo semantic context | jq .
duo semantic intent | jq .
duo semantic projections | jq .
zig test src/proof_carrying.zig
zig test src/pass12_catalog.zig
zig test src/semantic_compression.zig
zig test src/semantic_cli.zig
zig test src/semantic_transaction.zig
zig test src/transform_engine.zig --test-filter "proof"
```

---

*Pass 12 succeeds when one semantic source drives multiple validated artifacts through an inspectable, bounded, deterministic workflow — not when more AI-generated code exists.*
