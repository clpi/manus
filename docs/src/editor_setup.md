# Editor and language-tooling status

Idol is the current language. Canonical native source uses `.id` and new
canonical `.id` is freely admitted — it is the Idol source extension. Only
tracked *noncanonical* `.id` content (host-shaped patterns, namespace dispatch,
duplicate authority) is SOURCE-ZERO debt, migrated by repairing the pattern; the
`.id` file itself is not debt. Idol is not a Lua superset, and a Lua grammar is
not a safe fallback authority for canonical source.

The sole semantic law is
[`docs/spec/constitution.md`](../spec/constitution.md). Tooling must project
from the same lexical identities, generated grammar roles, graph facts, and
source-family authority as the compiler. It must not maintain independent
keyword, delimiter, suffix, namespace, or semantic registries.

Current editor integrations and bootstrap executable names may still carry
historical branding. Treat those names as physical migration aliases only. Do
not use compatibility fixtures or historical syntax definitions as templates
for new `.id`.

The production frontend has not yet closed generated grammar roles and executed
Idol parser recognition. Read [`docs/bootstrap.md`](../bootstrap.md) for the
exact current frontier before claiming formatter, highlighter, parser, or LSP
coverage. A file association or successful highlighting pass is not evidence of
semantic ownership.

Canonical tooling must preserve the delimiter law: `[]` is a genuinely
computed projection, while statically known identity uses named projection or
a structured label. Source faces remain provenance after resolution and never
select physical representation.

Tooling suggestions must also preserve PREDICATE-ZERO. They expose semantic
facts, cases, refinements, unknowns, and transitions rather than generating
boolean helper predicates, sentinel comparisons, or query-then-act repairs.
