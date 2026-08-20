# Contributing to Idol

Start with [AGENTS.md](../AGENTS.md). It routes contributors to the sole
semantic law, [C0](spec/constitution.md), the
[current priority projection](AGENT_ALIGNMENT.md), the
[bootstrap authority ledger](bootstrap.md), and live agent coordination.

Canonical native source uses `.id`. New `.id` is forbidden; every remaining
tracked project-owned `.id` file must be semantically migrated or deleted and
is never an implementation template. Do not add a foreign semantic owner.
Existing foreign code is seed or compatibility debt and may change only under
the narrow bridge rules in `AGENTS.md`.

Canonical source exposes the strongest known fact with the least ceremony.
Use named projection and structured fields for static identity; use indexed
projection `table[key]` when an aggregate key is genuinely computed. Parentheses
remain ordinary application. Do not translate host namespaces, sentinels,
staging variables, storage choices, or parser categories into Idol.
Do not encode cases, descriptor/world facts, demand, refinements, or transitions
as `has`, `is`, `can`, `exists`, or other boolean helpers. Subject correction
alone does not make a weak predicate canonical. Preserve unknown, absent,
false, and unresolved as distinct semantic states.

The standard distribution does not own native meaning. Do not add `std.*`,
extend `std.script`, or create another universal namespace. Relations own
meaning, possessed values supply subjects, worlds supply authority, and package
location remains provenance. Missing vocabulary is
`SEMANTIC-VOCABULARY-BLOCKED`, not permission to add a helper.

Before editing, inspect the dirty tree, `tools/node/dev/claim list`, and live
numbered gaps, then claim exact paths through `tools/node/dev/claim acquire`.
Update the exact `gaps/GAP-*.md` authority and reserve new numbers through
`tools/node/dev/gap reserve`.
Do not stash or absorb another contributor's work. Serialize heavy validation
through `tools/node/dev/idol-lock`, run the exact gates required for the changed
boundary, and report focused and aggregate outcomes separately.

Fail closed when law conflicts, current evidence cannot be reproduced, a
required semantic fact belongs to another owner, or the canonical vocabulary
cannot express the change.
