# Universal low-agent work order

| # | directive |
|---|---|
| 1 | Every assignment to a non-architectural agent is materialized in this shape. |
| 2 | Copy the block, fill every field, resolve `base_sha` to the current HEAD at assignment time. |
| 3 | The order expires when HEAD changes. |

```yaml
task: exact-task-id
tier: observer | mechanic | bounded-implementer
repository: clpi/idol
base_sha: <resolved to current HEAD at assignment>
expires_when_head_changes: true
semantic_change: forbidden
semantic_vocabulary_delta: 0
architectural_decision: already-made
objective:
  One exact transition.
before:
  - Reproducible current state.
after:
  - Exact expected state.
allowed_paths:
  - exact/file/a
  - exact/file/b
forbidden_paths:
  - docs/spec/**
  - src/semantic_graph.zig
  - src/sema.zig
  - src/parser.zig
forbidden_changes:
  - new syntax
  - new relation/world/descriptor
  - new NodeKind/EdgeKind
  - new roster
  - source-spelling dispatch
  - AST semantic reconstruction
  - fallback
  - boxing
  - forced materialization
  - expectation relaxation
required_controls:
  - positive
  - negative
  - deliberate damage
  - exact restoration
  - parent/current differential
stop_conditions:
  - HEAD changed
  - current failure absent
  - required fact absent
  - multiple lawful repairs
  - unclaimed path needed
  - protected file needed
  - unexpected graph movement
deliverable:
  - patch or read-only report
  - exact commands
  - source/compiler hashes
  - semantic diff
  - physical/evidence diff
  - unresolved fact handoff
```

## Tier definitions

- **observer** — read-only; reports and manifests only.
- **mechanic** — generated output, fixture promotion, verbatim-text
  replacement; no semantic interpretation.
- **bounded-implementer** — one pre-decided physical realization behind
  exact graph facts; deletion-only guard removals with routed instructions.

| # | directive |
|---|---|
| 1 | Ambiguity is a stop, not improvisation. |
| 2 | Obtain live claims before editing; durable lane labels are not locks. |
