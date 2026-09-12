| field | value |
|---|---|
| title | Idol grammar-role projection |

| # | directive |
|---|---|
| 1 | The supreme law is [`docs/spec/law.md`](law.md) and [`docs/spec/constitution.md`](constitution.md) is its structured expansion. |
| 2 | This page describes the role projection required by the production frontend; it is not a role taxonomy or a second grammar authority. |

| section |
|---|---|
| One owner |

| # | directive |
|---|---|
| 1 | One machine-readable grammar must project every lexical and parser role needed by the compiler, formatter, canonicalizer, Tree-sitter, LSP, MCP, tests, and documentation. |
| 2 | [`GAP-134`](../../gaps/GAP-134.md) owns that missing projection. |
| 3 | [`GAP-145`](../../gaps/GAP-145.md) owns the distinct lexical identities and immutable token view it consumes. |

| # | directive |
|---|---|
| 1 | The generated projection must include, as demanded: |

| # | directive |
|---|---|
| 1 | token identity and exact source span; |
| 2 | canonical, compatibility, deprecated, and removed status; |
| 3 | expression, binding, statement, and descriptor-member starts; |
| 4 | prefix, postfix, delimiter, and offside capabilities; |
| 5 | precedence and associativity; |
| 6 | payload and source-law provenance. |

| # | directive |
|---|---|
| 1 | No handwritten LSP table, parser switch, punctuation list, token text, or highlight color may outrank or extend that owner. |
| 2 | Protocol and editor classes are renderings of generated roles, never semantic identities. |

| section |
|---|---|
| Recognition boundary |

| # | directive |
|---|---|
| 1 | Roles answer only what source structure can be recognized. |
| 2 | They do not assign relation, subject, application, descriptor, world, demand, case, value, or realization identity. |
| 3 | Resolution consumes the minimum recognized structure and establishes those graph facts. |

| # | directive |
|---|---|
| 1 | Current delimiter roles remain: |

| # | directive |
|---|---|
| 1 | `()` ordinary application and grouping; it never means aggregate indexing; |
| 2 | `{}` structured packs, descriptor application, and descriptor homes; |
| 3 | `[]` computed or indexed projection (`values[i]`, `table[key]`); read and write are demand-selected faces of one projected place/value relation; |
| 4 | `.` statically named projection after an explicit subject; |
| 5 | `:` admitted descriptor, subject, and home roles; |
| 6 | `@` the current-world accessor: bare `@` the current-world value, `@member` world access (never `@.member` or `@:member` — `@` already accesses), `@member = v` mutation, `thing@world` qualification, `@{ k = v }` injection, never a directive or a postfix relation anchor. |

| # | directive |
|---|---|
| 1 | An incompatible source face and resolved subject diagnose before lowering. |
| 2 | Parser acceptance never authorizes a backend fallback. |

| section |
|---|---|
| Current implementation boundary |

| # | directive |
|---|---|
| 1 | The tracked parser and Tree-sitter grammar still contain handwritten role decisions and string-shaped classification. |
| 2 | They are duplicate-authority and SOURCE-ZERO debt. |
| 3 | The duplicate in-tree LSP/highlighter and its corpora were deleted on 2026-08-17; they are historical evidence only and must not be ported. |
| 4 | Durable semantic tokens wait for graph-owned source spans and generated grammar roles in the sibling `idol-native` LSP. |

| # | directive |
|---|---|
| 1 | Closure requires one authority edit to regenerate every consumer, production use of the immutable token view, an adversarial control that changes the authority and observes every affected projection, and failure when any consumer reconstructs a role from spelling. |
