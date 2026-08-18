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

The retained VS Code and Helix integrations associate `.id` files and start
`idol-lsp`. At the current executed frontier, that server provides diagnostics
and document symbols. It does not provide formatting, completion,
go-to-definition, or semantic tokens.

The former handwritten TextMate grammar, snippets, Helix Tree-sitter queries,
and placeholder Zed grammar were deleted: they duplicated or invented grammar
and semantic classifications instead of projecting the shared authority. Zed
support remains withheld until it can use a valid pinned grammar projection and
an executable `idol-lsp` launcher without claiming absent features.

The production frontend has not yet closed generated grammar roles and executed
Idol parser recognition. Read [`docs/bootstrap.md`](../bootstrap.md) for the
exact current frontier before claiming formatter, highlighter, parser, or LSP
coverage. File association, diagnostics, and document symbols are useful editor
projections; they are not evidence of grammar or semantic ownership.

Canonical tooling must preserve the delimiter law: computed access is ordinary
application, such as `table(key)`, while statically known identity uses named
projection or a structured label. Source faces remain provenance after
resolution and never select physical representation.

Tooling suggestions must also preserve PREDICATE-ZERO. They expose semantic
facts, cases, refinements, unknowns, and transitions rather than generating
boolean helper predicates, sentinel comparisons, or query-then-act repairs.
