| field | value |
|---|---|
| title | Foreign-implementation obligation inventory (initial) |
| policy | `docs/spec/foreign-obligation.md` |
| status | OPEN obligations. This file is the backlog, not a licence. |

| # | directive |
|---|---|
| 1 | Every row is an unclosed obligation until its `until:` replacement executes and the foreign implementation is deleted from the closure. |
| 2 | `next:` is the single concrete action that advances closure. A row with no actionable `next:` is STALLED. |
| 3 | Rows are ordered by closure impact: what blocks the most downstream Idol-only completion. |

| obligation | scope | until | next | status |
|---|---|---|---|---|
| `src/*.zig` (130 files): the compiler itself | compilation | canonical Idol compiler source executing the full pipeline (compiler B) | close GAP-145/GAP-134 parser identities; transfer semantic construction per `docs/bootstrap.md` production authority ledger | OPEN |
| `build.zig`: the build description | delivery | build description written in Idol | express the build graph (steps, dependencies, artifacts) as Idol facts consumed by an Idol driver | OPEN |
| `bench/timing.py` + `bench/*.py` (22 files): timing harness, benchmark drivers, statistical analysis | verification | Idol-native timing harness with per-invocation validation | complete the in-flight Idol rewrite (branch work, 2026-09-13); delete the Python when the Idol harness is the real consumer | OPEN |
| `gate/*.sh` (74 files): gate drivers | verification | Idol gate implementations | port gate drivers to Idol one by one, starting with highest-frequency gates; each port deletes the shell driver | OPEN |
| `gatecap` sites (69 `.id` files): Idol wrapping shell | verification | Idol-native capability for each wrapped operation | enumerate each `gatecap` call site; replace with Idol filesystem/process capability or record as a named sub-obligation | OPEN |
| `@c.emit` / `@c.include` embedded sites (181): foreign code inside `.id` files | realization | zero embedded sites (`scripts/ledger/embed.id` enforces the floor) | continue the shrinking ratchet; each site needs its Idol-native capability | OPEN |
| `lib/os.id`, `lib/io.id` via raw C: ambient authority | execution | Idol-owned OS/IO capability with explicit authority | replace raw-C authority with Idol facts; the authority must be findable by the ambient-authority audit | OPEN |
| `ext/vscode-idol/extension.js`, `ext/tree-sitter-idol/grammar.js`: generated bridges | development | hosts consuming Idol projections directly | complete `scripts/vscodeemit.id` / `scripts/treesitter_emit.id` projection path; delete the JS when the host consumes Idol | OPEN |
| `.pi/extensions/idol-mcp.ts`: MCP bridge | development | pi loading repository MCP servers without TypeScript | implement the Idol MCP server path; delete the TS bridge | OPEN |
| `zig` toolchain itself: the host compiler building the seed | compilation | compiler B built from canonical Idol source by Idol-executed steps | per `docs/bootstrap.md` S1 acceptance; seed provenance recorded, not assumed | OPEN |
| External solver / proof capability (if any undisclosed) | verification | Idol-executed proof checking | audit: name every proof-producing component; any external solver becomes a row here | OPEN |

| section |
|---|
| What is NOT an obligation (positive controls) |

| # | directive |
|---|---|
| 1 | `examples/`, `benchmarks/`, `tests/` foreign-language fixtures: inert input to Idol importers and oracles. Comparison is not dependency. |
| 2 | The C differential baseline: the foreign compiler is the referee, never the shipping path. Invoking it to perform Idol's own work would create an obligation; measuring against it does not. |
| 3 | Native instructions / object bytes / Wasm bytes produced by Idol: realizations, not implementations. |
| 4 | Kernel, drivers, firmware: the named platform, not the toolchain. |
