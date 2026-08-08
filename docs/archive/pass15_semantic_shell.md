> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 15 — The Semantic Shell

> **Mission:** Make Duo the best shell and interactive computing environment ever built — by collapsing shell interaction into Duo's existing semantic foundations.
>
> **Gate:** `zig build pass15-gate` or `duo catalog audit gate pass15`
>
> **Catalog:** `duo catalog` → `pass15`

## Governing vision

Traditional shells route text. Duo routes **semantic values → semantic calls → semantic streams → optimized realization**.

The shell is an **interactive realization planner**, not a command runner.

## Non-negotiable identity

1. **One language** — interactive input lowers to canonical `.duo`; no second shell syntax.
2. **No universal text intermediary** — records, paths, streams stay structured until explicit foreign boundaries.
3. **No mandatory process per stage** — pipelines may fuse to native loops or spawn explicitly.
4. **No hidden authority** — effects, capabilities, and boundaries are inspectable (`@comp.why`, `@comp.effects`).
5. **Deterministic local correctness** — AI proposes; Duo validates and executes.

## New permanent concepts (minimal)

| Concept | Module |
|---------|--------|
| Command descriptor | `src/command_descriptor.zig` |
| Execution context | (P15-WS3 — future) |
| Stream realization | (P15-WS5 — future) |
| Shell session snapshot | `src/shell_session.zig` |
| Cross-platform raw shell | `src/shell_host.zig` |

## First vertical proof

See `examples/pass15_vertical_proof.duo` — project-aware discovery, structured filtering, export, and inspection hooks.

## Workstreams

Twenty bounded workstreams (`P15-WS1` … `P15-WS20`) tracked in `src/pass15_catalog.zig`.

## Acceptance

Pass 15 completes when all 33 criteria in §44 of the full specification are met. Current status: foundation delivered (M0–M4 partial); fusion, streams, MCP, and competitive proofs remain open.

## Full specification

The authoritative Pass 15 agent brief includes sections 1–44 (ergonomics standard, pipes, streams, agent integration, benchmarks, prohibited outcomes). This plan doc is the operational index; agents claim workstreams in `.agents/AGENT_COORDINATION.md`.
