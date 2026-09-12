# Idol Agent Scope

| # | directive |
|---|---|
| 1 | Root [`AGENTS.md`](../AGENTS.md) is the repository entry point. |
| 2 | [`docs/spec/law.md`](../docs/spec/law.md) is the supreme compact law |
| 3 | [`docs/spec/constitution.md`](../docs/spec/constitution.md) is its structured long-form expansion and `law.*` identity owner only. |
| 4 | Read [`.agents/ARCHITECTURE_INJECTION.md`](ARCHITECTURE_INJECTION.md) before touching code. |
| 5 | This file adds no law and no live status. |

| # | directive |
|---|---|
| 1 | Use [`AGENT_CANONICAL.md`](AGENT_CANONICAL.md) for stable paths, [`AGENT_COORDINATION.md`](AGENT_COORDINATION.md) for ownership protocol, and [`AGENT_INTEGRATION.md`](AGENT_INTEGRATION.md) for bootstrap MCP transport. |
| 2 | Read the current production frontier from [`docs/bootstrap.md`](../docs/bootstrap.md) and obligations from the exact current `gaps/GAP-*.md` files. |
| 3 | Read live ownership through `tools/node/dev/claim list` rather than copying claims here. |

| # | directive |
|---|---|
| 1 | The current language and project are Idol (`idol`, `idollang/idol`), with canonical `.id` source. |
| 2 | Reaching the earliest executed SHC authority frontier is the priority: bounded bootstrap bridges — including new Zig where it is the fastest path to the next transfer — are admitted and preferred over stalling, each with a known deletion condition (`law.bridge.death`, `law.bootstrap.velocity`, `docs/bootstrap.md`); foreign is forbidden only as permanent architecture or semantic authority. |
| 3 | An executed gate, lock, or MCP entrypoint remains bootstrap transport until `docs/bootstrap.md` credits the authority transfer. |

| # | directive |
|---|---|
| 1 | **Gate scan law:** diff/path boundaries are curried symbols — `scan(diff)(body)`, never `scandiff` or `scan("diff")`. |
| 2 | See root `AGENTS.md` § Gate scan boundaries and `gate/idiom.id` header. |

| # | directive |
|---|---|
| 1 | Do not treat this directory as a semantic registry. `std` is migration distribution, `std.script` is frozen debt, and neither an agent document nor a package path grants a world or owns a relation. |
| 2 | If any scoped instruction conflicts with root routing or the compact law, stop and repair the scoped projection. |
