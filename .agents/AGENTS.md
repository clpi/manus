# Idol Agent Scope

Root [`AGENTS.md`](../AGENTS.md) is the repository entry point.
[`docs/spec/constitution.md`](../docs/spec/constitution.md) is the sole
semantic law. This file adds no law and no live status.

Use [`AGENT_CANONICAL.md`](AGENT_CANONICAL.md) for stable paths,
[`AGENT_COORDINATION.md`](AGENT_COORDINATION.md) for ownership protocol, and
[`AGENT_INTEGRATION.md`](AGENT_INTEGRATION.md) for bootstrap MCP transport.
Read the current production frontier from [`docs/bootstrap.md`](../docs/bootstrap.md)
and obligations from the exact current `gaps/GAP-*.md` files. Read live
ownership through `duo_dev_claim_files` rather than copying claims here.

The current language and project are Idol (`idol`, `idollang/idol`), with
canonical `.id` source. Bounded bootstrap bridges may remain only while executed
with known deletion conditions (`law.bridge.death`, `docs/bootstrap.md`).
An executed gate, lock, or MCP entrypoint remains bootstrap transport until
`docs/bootstrap.md` credits the authority transfer.

**Gate scan law:** diff/path boundaries are curried symbols —
`scan(diff)(body)`, never `scandiff` or `scan("diff")`. See root `AGENTS.md`
§ Gate scan boundaries and `gates/idiom.id` header.

Do not treat this directory as a semantic registry. `std` is migration
distribution, `std.script` is frozen debt, and neither an agent document nor a
package path grants a world or owns a relation. If any scoped instruction
conflicts with root routing or the constitution, stop and repair the scoped
projection.
