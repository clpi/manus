# Idsem MCP Bootstrap Scope

Root [`AGENTS.md`](../../AGENTS.md) is the entry point and
[`docs/spec/constitution.md`](../../docs/spec/constitution.md) is the sole
semantic law. This file contains only scoped implementation constraints.

The files in this directory are historical `.duo` bootstrap transports. Their
physical use of `std.mcp`, `std.fs`, `std.proc`, `std.json`, or `std.os` is
migration debt, not Idsem architecture or a preferred API. Do not add another
`std.*` operation, dependent, or semantic responsibility. Do not introduce a
replacement namespace. A changed bridge must remove authority, fail closed,
pass an already authoritative Idsem fact, or immediately enable its deletion.

MCP tools project graph facts, evidence, claims, and current repository state.
They do not own language meaning. Current-language output says Idsem and `.id`;
historical Duo/Duon/`.duo` appears only when provenance is the subject.
Descriptions and onboarding responses are executable training material.

Session bootstrap derives P0 obligations from `gaps/GAP-*.md`, carries an
explicit completeness fact, and routes to `AGENTS.md`, `docs/bootstrap.md`, and
live claims. It must never turn a failed census into zero. Heavy runs retain the
inner outcome under the repository lock; transport completion is not success.

Discover the live tool surface with MCP `tools/list`. Do not copy counts or
retired tool catalogs into documentation. Validate changes with the locked
`mcp-gate` and its positive controls.
