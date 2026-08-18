# Session state — 2026-08-18, canonical main @ cad1a55f

53 commits from agent-integration through wasm lane 3. This file is
the pick-up point: what exists, what's red, what's next, who owns it.

## Gates (current)

| Gate | State |
|---|---|
| tools/reduce/verify | **RED (1)** — argface.id fires until the compiler lane fixes the arg-form defect (H10). All 9 other theorems PASS. |
| census/compound | 1226 < 1235 baseline (main's lawful deletions keep landing) |
| census/identity | pass |
| parity/grammar | generated agrees with canonical |
| probe-mcp | PASS (2 servers) |
| mcp-gate | PASS |

## Active handoffs (owner: compiler lane)

| ID | Item | Status |
|---|---|---|
| H10 | arg-form face-equivalence | causal test RED in verify; fix in dnir_lower lowerSubjectCall; outranks all breadth |
| H9 | binary-safe path:read | deletes byteat + hex transport; one accessor body, 50 call sites already subject-first |
| GAP-145 | lexical identities | the SHC critical path frontier; do not start GAP-134 until closed |
| GAP-134 | grammar roles + token view | next after GAP-145 |

## Wasm lane 3 (research; defensible status per audit)

- Section census, body walk, instruction count: exact (66/66 corpus)
- Record emission: 55,942 graph-SHAPED records (not graph-conformant —
  sequential counters and local taxonomy strings, not semantic ids)
- name(op): manually maintained family classifier (float/arith64 are
  labels) — needs exact source-law semantic resolution
- Validation: partial (no stack typing, signatures, arity)
- The ingest file is executable research bootstrap with recorded
  canonicality debt (see edgemax.audit.md)
- MCP serve: line transport (not JSON-RPC parsing; claim corrected)

## Recorded rulings (all in the operating model)

- C0 constitution is sole law; gates/censuses are projections
- No compound words; compound census is a migration heuristic, not
  authority
- Subject-first invocation; `.` for static members; `!` over `not`
- No plurality; no antipattern spellings
- Wasm runtime leverages ALL language features (one graph)
- Fact separation: runtime need never infers from opcodes; law/
  provider/ABI/ownership/realization stay separate families

## Tool inventory (all committed, all working)

tools/reduce/idol (selftest PASS) · tools/reduce/verify (10 checks)
tools/reduce/fixtures/* (theorems + controls + causal tests)
tools/evidence/{subject,perturb,rotate} (selftest PASS)
tools/parity/grammar · tools/node/dev/census/compound
tools/wasm/{ingest.id,factsprobe,perf} · tools/wasm/bench (66 fixtures)
evidence/mop/* (measurement records, now summary-sized)

## What NOT to do next (per audit + rulings)

- Do not touch GAP-145/GAP-134 (compiler lane, claims active)
- Do not add wasm breadth before semantic-id publication (audit P0)
- Do not rename byteat — delete it on H9
- Do not treat num() as a naming choice — it is register relief
- Do not re-claim graph conformance without semantic ids
- Do not "optimize" rung 24 while a higher FTCFTW rung dominates
