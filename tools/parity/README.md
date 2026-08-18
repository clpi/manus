# parity — projection agreement reporters (Pickle Mission E)

Report-only tools. They compare existing projections of a shared authority
by identity, report drift, and never choose a side or rewrite a role.

## grammar

`tools/parity/grammar` compares, by token ordinal:

- `src/lexer.zig` `TokenKind` field count — the canonical ordinal space
- `lib/token/grammar_role.id` (ROLE_COUNT / KIND_EOF / BEGIN_EXPR)
- `lib/token/grammarrole.id` (ROLECOUNT / KINDEOF / BEGINEXPR)
- `ext/tree-sitter-idol/src/grammar.json` rule count (context only)

Output: a count matrix, the first divergent BEGIN_EXPR ordinal, and a
DRIFT list. Exit is always 0 — this is measurement, not a gate.

### First measurement (2026-08-17, HEAD fa2805ef) — since closed

```
canonical TokenKind        114
lib/token/grammar_role.id  110   stale by 4; no emitter writes it
lib/token/grammarrole.id   114   count-correct; live target of
                                `idol token-tables emit` (main.zig:901);
                                old dialect + retired regen banner
tree-sitter idol rules     127   context (rules include non-token rules)
BEGIN_EXPR divergence at ordinal 3
```

Consumer census: `lib/compiler/token_view.id` reads `token.grammarrole.*`
(the 114 projection). `tools/emit_grammar_role.zig` writes a third,
dead `lib/std/token/...` path. See `.agents/MOP_HANDOFFS.md` H7.

### Update (same day, post-reconciliation)

The stale `lib/token/grammar_role.id` (110, undriven, unconsumed) and the
spent `tools/emit_grammar_role.zig` (dead `lib/std` target) were deleted;
the live generator's retired regen banner was corrected and
`idol token-tables emit` regenerated `lib/token/grammarrole.id` (114,
current generator format). Parity now reports: **all projections agree**.
