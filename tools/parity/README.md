# parity — projection agreement reporters (Pickle Mission E)

Projection-verification tools. They compare generated projections with their
shared authority by identity and never rewrite a role. Drift or a missing live
projection exits nonzero.

## grammar

`tools/parity/grammar` compares, by token ordinal:

- `src/lexer.zig` `TokenKind` field count — the canonical ordinal space
- `lib/token/grammarrole.id` (ROLECOUNT / KINDEOF / BEGINEXPR), the sole live
  generated projection
- `ext/tree-sitter-idol/src/grammar.json` rule count (context only)

Output: a count matrix and a DRIFT list. Exit 0 means the live projection agrees
and both retired projection paths are absent; drift exits 1.

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

The stale `lib/token/grammar_role.id` (110, undriven, unconsumed) and the spent
`tools/emit_grammar_role.zig` (dead `lib/std` target) were deleted. The live
generator emits `lib/token/grammarrole.id`; parity now requires that projection
to agree with `TokenKind` and requires the retired paths to remain absent.
