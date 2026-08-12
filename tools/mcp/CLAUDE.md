# Idol MCP Bootstrap Scope

Root [`AGENTS.md`](../../AGENTS.md) is the entry point and
[`docs/spec/constitution.md`](../../docs/spec/constitution.md) is the sole
semantic law. This file contains only scoped implementation constraints.

The files in this directory are current `.id` compatibility transports. Their
suffix alone is not canonicality or self-host proof. Their
physical use of `std.mcp`, `std.fs`, `std.proc`, `std.json`, or `std.os` is
migration debt, not Idol architecture or a preferred API. Do not add another
`std.*` operation, dependent, or semantic responsibility. Do not introduce a
replacement namespace. A changed bridge must remove authority, fail closed,
pass an already authoritative Idol fact, or immediately enable its deletion.

MCP tools project graph facts, evidence, claims, and current repository state.
They do not own language meaning. Current-language output says Idol and `.id`;
historical Duo/Duon/`.id` appears only when provenance is the subject.
Descriptions and onboarding responses are executable training material.

Until `GAP-131` closes, session bootstrap reports P0 state `unknown`, names
`GAP-131` as the blocker, and routes clients to `gaps/GAP-*.md`, `AGENTS.md`,
`docs/bootstrap.md`, and live claims. It must never turn a failed census into
zero. `GAP-146` separately keeps locked child-build outcomes incomplete;
transport completion is not success.

Discover the live tool surface with MCP `tools/list`. Do not copy counts or
retired tool catalogs into documentation. Validate changes with the locked
`mcp-gate` and its positive controls.
