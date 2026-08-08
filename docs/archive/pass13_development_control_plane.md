> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 13 — Development Control Plane

> **Mission:** One deterministic, inspectable development control plane so humans and
> concurrent agents operate on canonical truth — not parallel markdown narratives.
>
> **Machine-readable owner:** `src/dev_control_plane.zig`, `src/pass13_catalog.zig`
> **CLI:** `duo dev snapshot|audit|context|summary` · `duo catalog` → `pass13`
> **Does not add a new language subsystem** — reconciles LSP, MCP, CI, coordination, presentation.

## Governing thesis

Development is a semantic process:

`observe → understand → claim → propose → simulate → validate → compare → integrate → prove → audit`

All tools consume **projections of the same facts**.

## Authority order (evidence beats prose)

1. Compiler semantic facts
2. Generated capability registries (`duo catalog`)
3. Production code paths
4. Artifact inspection (`native_barrier_checks`, boxing audits)
5. Tests, fuzz, benchmarks, proof bundles
6. Git state
7. Canonical documentation
8. Decision records
9. Agent reports
10. Historical pass documents

## Markdown rule

Markdown **explains** the control plane. It must **not** own:

- active claims · task state · validation state · release evidence · semantic ownership

Generated status pages may be emitted from `.duo/dev/` and catalog JSON.

## Canonical records (Pass 13 §4)

| Record | Owner module | Status |
| --- | --- | --- |
| Project snapshot | `dev_control_plane.zig` | **partial** — `duo dev snapshot` |
| Work item | `dev_control_plane.zig` | **partial** — seed items in catalog |
| Claim lease | `dev_control_plane.zig` | **partial** — acquire + overlap; no MCP wire yet |
| Agent session | — | open |
| Semantic transaction | `semantic_transaction.zig` | partial (Pass 12) |
| Validation run | — | open |
| Integration record | — | open |
| Decision / regression | — | open |
| Audit event | `dev_control_plane.zig` | open (`.duo/dev/events.jsonl` reserved) |
| Presentation record | `presentation_record.zig` | **partial** |
| Context bundle | `dev_control_plane.zig` | **partial** — `duo dev context P13-WSn` |

## Two MCP roles (unchanged boundary)

| MCP | Serves | Owns |
| --- | --- | --- |
| **End-user** (`duo-lsp` server tools) | Projects written in Duo | Semantic inspection, builds, proof — not issue tracking |
| **Development** (`duo-bench` / `duo-mcp`) | Developing Duo | Snapshots, claims, validation orchestration — **not** compiler semantics |

## Live audit summary (2026-08-04)

Run: `duo dev audit`

| Area | Classification | Risk |
| --- | --- | --- |
| `AGENT_COORDINATION.md` claims | **unsafe** (markdown append) | No lease expiry / semantic overlap |
| `duo_coordination_update` | **partial** | File strings only |
| Claim heartbeat / transfer | **absent** | Stale agents |
| Integration queue | **absent** | "Done" ≠ integrated |
| LSP claim decoration | **absent** | Editor blind to conflicts |
| Presentation engine | **absent** as unified layer | term/MCP/LSP diverge |
| `native_barrier_checks` | **partial** | Proof exists; not universal gate |

Full entries: `src/pass13_dev_audit.zig`

## Workstreams (20)

See `duo catalog` → `pass13.workstreams`. Execution order (Pass 13 §20):

1. Truth map (**WS1** — in progress)
2. Development schema (**WS2** — in progress)
3. Claim leases (**WS3**)
4. Context compiler (**WS4**)
5. Work DAG (**WS5**)
6. Delegation (**WS6**)
7. Validation planner (**WS7**)
8. Audit log (**WS8**)
9. Integration queue (**WS9**)
10. Presentation engine (**WS10**)
11. Terminal visual language (**WS11**)
12. Structured agent output (**WS12**)
13. LSP dev projections (**WS13**)
14. Doc truth generation (**WS14**)
15. Enforcement (**WS15**)
16. Five-agent stress test (**WS16**)
17. Ward cross-repo proof (**WS17**)
18. Coordination migration (**WS18**)
19. Historical cleanup (**WS19**)
20. Control-plane reconciliation (**WS20**)

## Agent session protocol (Pass 13 §21)

Before editing, produce or consume:

- project snapshot ID · context bundle fingerprint · claim ID
- semantic targets · forbidden operations · required validation
- integration owner · proof obligations

Use `duo dev context <work-item-id>` instead of reading full pass history.

## Success criteria

35 criteria in Pass 13 §22 — tracked in `pass13_catalog.success_criteria`.
Pass 13 is **not complete** until fingerprinted snapshots, semantic claim overlap,
impact-based validation, integration queue, and five-agent stress test all land.

## Gate

```bash
zig build pass13-gate   # dev CLI + coordination status + barrier bridge + catalog JSON
bash zig build pass13-gate
```

## Related plans

- Pass 12 semantic autonomy: `docs/archive/pass12_semantic_autonomy.md`
- Pass 11 release proof: `docs/archive/pass11_release_proof.md`
- Agent router (transitional): `.agents/AGENT_CANONICAL.md`
