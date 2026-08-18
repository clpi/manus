# Idol Agent Scope

Root [`AGENTS.md`](../AGENTS.md) is the repository entry point.
[`docs/spec/constitution.md`](../docs/spec/constitution.md) is the sole
semantic law. This file adds no law and no live status.

Use [`AGENT_CANONICAL.md`](AGENT_CANONICAL.md) for stable paths,
[`AGENT_COORDINATION.md`](AGENT_COORDINATION.md) for ownership protocol, and
[`AGENT_INTEGRATION.md`](AGENT_INTEGRATION.md) for bootstrap MCP transport.
Read the current production frontier from [`docs/bootstrap.md`](../docs/bootstrap.md)
and obligations from the exact current `gaps/GAP-*.md` files. Read live
ownership through `tools/node/dev/claim list` rather than copying claims here.

The current language and project are Idol (`idol`, `idollang/idol`), with
canonical `.id` source. Reaching the earliest executed SHC authority frontier is
the priority: bounded bootstrap bridges — including new Zig where it is the
fastest path to the next transfer — are admitted and preferred over stalling,
each with a known deletion condition (`law.bridge.death`,
`law.bootstrap.velocity`, `docs/bootstrap.md`); foreign is forbidden only as
permanent architecture or semantic authority. An executed gate, lock, or MCP
entrypoint remains bootstrap transport until `docs/bootstrap.md` credits the
authority transfer.

**Gate scan law:** diff/path boundaries are curried symbols —
`scan(diff)(body)`, never `scandiff` or `scan("diff")`. See root `AGENTS.md`
§ Gate scan boundaries and `gate/idiom.id` header.

Do not treat this directory as a semantic registry. `std` is migration
distribution, `std.script` is frozen debt, and neither an agent document nor a
package path grants a world or owns a relation. If any scoped instruction
conflicts with root routing or the constitution, stop and repair the scoped
projection.
