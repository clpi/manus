# Pass 19 — Unified Semantic Experience

Standard library, packages, shell, CLI, and developer platform as **one semantic computing environment**.

**Status:** M0 tracking + umbrella catalog (2026-08-05).  
**North star:** User expresses intent once; Duo resolves meaning, dependencies, execution, packaging, validation, deployment, and discoverability through the same semantic graph.

## Governing thesis (§1–§3)

Modern toolchains fragment language, package manager, build, shell, CI, deployment, and agent interfaces into incompatible metadata.

Pass 19 collapses them onto Duo’s existing foundations:

| Foundation | Pass |
| --- | --- |
| Descriptors, shapes, calls, effects, stages | Pass 2–8 |
| `@comp.*` universal compiler interface | Pass 16, G-061 |
| Realization selection | Pass 8, Pass 22 |
| Semantic shell | **Pass 15** (subsumed, not replaced) |
| Package sovereignty / dependency manifest | Pass 14 |
| Cross-language harness | Pass 20 |

**Rule:** one mechanism → many capabilities. No parallel shell language, package manifest language, or CLI builder DSL.

## One language everywhere (§3)

Interactive shell input, project metadata, builds, tasks, CI, deployment, CLI definitions, and agent workflows all lower to **canonical `.duo`**.

Flow:

```
shell expression → canonical Duo → format / test / compile / package / deploy / MCP / HTTP
```

## Unified command surface (§4–§6)

Canonical executable: **`duo`**

Commands are **composable semantic values**, not hardcoded branches. Single source: `src/command_descriptor.zig`.

| Command area | Status |
| --- | --- |
| `run`, `build`, `test`, `check`, `fmt`, `shell` | partial — CLI + descriptors |
| `package`, `add`, `publish`, `deploy` | open |
| `help`, `search`, `explain`, `graph`, `doctor` | open / partial (`duo explain`) |
| Contextual repair (`did you mean`) | partial — diagnostics |

Discoverability target: terminal as semantic documentation browser (purpose, effects, examples, MCP schema, targets).

## Semantic shell (§7–§14)

Owned by **Pass 15** — Pass 19 extends scope to full platform integration.

| Concept | Owner | Status |
| --- | --- | --- |
| Command descriptors | `command_descriptor.zig` | partial |
| Persistent session | `shell_session.zig` | partial |
| Raw host shell escape | `shell_host.zig` | partial |
| Structured arguments / Path | — | open |
| Semantic history | — | open |
| Pipeline fusion + `@comp.why(pipeline)` | Pass 22 realization | open |

## Standard library (§15–§20)

Canonical semantic vocabulary in `lib/std/` — not a pile of wrappers.

Domains: core, stream, path, file, process, shell, net, http, json, project, package, target, cli, test, bench, …

**Collections as intent:** Map/Set/Vec with compiler-selected representation (`realization.zig`).

**Serialization:** descriptor-driven (`json`, `contracts`, `@comp.concepts.*`).

## Modules and packages (§21–§36)

| Topic | Status |
| --- | --- |
| `req "std.*"` modules | partial |
| `@export` visibility | partial |
| No mandatory manifest for one-file programs | partial |
| Semantic dependency resolution | open |
| `duo need <capability>` | open |
| Content-addressed locks | partial (`dependency_manifest.zig`) |
| Semantic registry search | open |
| Package → command auto-exposure | open |

## Project, build, CLI, hosting (§37–§54)

| Topic | Owner | Status |
| --- | --- | --- |
| Universal project model | `build.zig` | partial |
| Build graph + invalidation | `build.zig`, semantic cache | partial |
| `duo doctor` | — | open |
| Descriptor-driven CLI / HTTP / MCP | `command_descriptor.zig` | open |
| `serve` / `deploy` hosting graph | — | open |
| Semantic secrets | — | open |

## Developer experience (§55–§84)

| Feature | Status |
| --- | --- |
| Terminal renderer | `lib/std/term.duo`, `presentation_record.zig` | partial |
| Universal data viewer | open |
| `@comp.why` oracle | partial |
| Native score / heatmap | open |
| Semantic search / diff / `duo improve` | open |
| Living docs from descriptors | partial |
| Agent-native MCP IDs | duo-mcp partial |

## Required audits (§89)

| Audit | Status |
| --- | --- |
| **A** Command surface | partial — `command_descriptor.duo_commands` |
| **B** Package resolution | open |
| **C** Shell integration per package | open |
| **D** Module and scope | partial |
| **E** Semantic projections | open |
| **F** User journeys | open |

## Initial vertical proof (§90)

**`search(pattern, paths)`** — one semantic declaration deriving:

- `duo search` CLI
- `search(...)` programmatic call
- shell completion + structured stream
- MCP tool + HTTP endpoint
- docs + tests
- native / SIMD / grep fallback with explainable selection

Scaffold: `examples/pass19_vertical_proof.duo` (M0).

## Workstreams

**P19-WS1 … P19-WS33** tracked in `src/pass19_catalog.zig`.

Pass 15 workstreams remain authoritative for shell-specific delivery; Pass 19 tracks platform integration.

## Success criteria (§91)

Pass 19 completes when shell, stdlib, packages, CLI, build, docs, hosting, and agents feel like **one environment** — see `success_criteria` in catalog.

## Commands

```bash
zig build pass19-gate
duo catalog audit gate pass19
duo catalog | jq '.pass19'
./zig-out/bin/duo run examples/pass19_vertical_proof.duo
```

## Related plans

- [`pass15_semantic_shell.md`](pass15_semantic_shell.md) — shell substrate
- [`pass14` / dependency manifest](../../src/dependency_manifest.zig)
- [`pass22_compiler_architecture_expansion.md`](pass22_compiler_architecture_expansion.md) — graph + realization
- [`pass8_persistent_semantic_computing.md`](pass8_persistent_semantic_computing.md)

## Final governing question (§Final)

> Does this require the user to learn, configure, or synchronize another system?

If yes → collapse into descriptors, calls, packages, streams, effects, stages, transformations, realization, and semantic projections.
