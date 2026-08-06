# Duo Grammar Specification (canonical)

Cross-session grammatical evolution ledger. **All agents** working on syntax MUST read this at session start and append when adding or deprecating surface forms.

MCP: `duo_grammar_spec_read` / `duo_grammar_spec_update` (duo-lsp server). Comptime index: `@comp.agent.grammar()` / `std.agent.grammar_index()`.

## Status legend

| Status | Meaning |
| --- | --- |
| **preferred** | Canonical style for new `.duo` code |
| **accepted** | Parses and type-checks; may emit deprecation hints |
| **deprecated** | Still parses; do not use in new code |
| **removed** | No longer accepted |

## Rules

### GR-001 — Bare function declarations (preferred)

**Status:** preferred (2026-07-30)

`.duo` functions may omit `fun` / `function`:

```duo
add(x: i32, y: i32) -> i32
    x + y
end

add = (x: i32, y: i32) -> i32
    x + y
end
```

- Bare form: `name(params) [-> ret] body end` at statement start (duo_mode only).
- Assign form: `name = (params) [-> ret] body end`.
- `fun` / `function` remain **accepted** for backward compatibility but are **deprecated** in `.duo` files.
- **Untyped bare functions require `fun`.** `add(x, y) body end` (no type annotations) is ambiguous with the call statement `add(x, y)` and is rejected by the parser. The disambiguator is `startsFuncParamList` (`src/parser.zig`): at least one param must carry a type annotation (`name: type`) or be `...`. This is deliberate — supporting untyped bare forms would require lookahead speculation on every `name(...)` call statement to locate a matching `end`, risking quadratic parse time. Use `fun add(x, y) body end` for untyped params, or annotate at least one param (`add(x: i64, y) body end`) to drop `fun`.

### GR-002 — If-expressions (preferred)

**Status:** preferred (2026-07-30)

`if` may appear in expression position; arms are expressions terminated by `end`:

```duo
x = if a < b value
    else if b < c value * 2
    else value * 3
    end
```

- Optional `then` after each condition (same as statement `if`).
- **`else if`** (two tokens) and **`elseif`** (Lua) are both accepted for intermediate arms.
- Statement `if … then block … end` is unchanged.
- AST: `Expr.if_expr`; lowers to a C statement-expression with unified branch type.

### GR-003 — Implicit `local` (preferred)

Omit `local` in `.duo` files; bindings are file/module locals unless `global` (see `AGENTS.md`).

### GR-004 — Table keys without brackets (preferred)

**Status:** preferred (2026-07-31)

Hash keys in table literals use the shortest form:

| Key shape | Syntax | Example |
| --- | --- | --- |
| Identifier | `key = val` | `{ x = 1, y = 2 }` |
| Quoted string (non-identifier) | `"key" = val` | `{ "unit-test" = "a" }` |
| Expression / non-literal | `[expr] = val` | `{ [k .. "_suffix"] = v }` |

For **access**, prefer field syntax for identifier keys: `t.x` not `t["x"]`. Bracket form remains for dynamic or non-identifier keys.

### GR-005 — Boolean negation and inequality spelling (preferred)

**Status:** preferred (2026-08-01)

Use `not` for logical negation and `!=` for inequality in new `.duo` code:

```duo
ok = value != 0 and not disabled
```

- `not expr` is the canonical logical negation operator.
- `!=` is accepted as an alias for the existing inequality operator and lowers to the same AST node as Lua-compatible `~=`.
- `~=` remains accepted for Lua compatibility, but new Duo code should prefer `!=`.

### GR-006 — Table literal key forms (accepted)

**Status:** accepted (2026-08-05, P26-D11)

Three key forms; use the shortest unambiguous form:

| Form | Syntax | Meaning |
| --- | --- | --- |
| Identifier | `name = value` | Literal field/key name `name` |
| Quoted string | `"literal-key" = value` | Literal string key (non-identifier) |
| Computed | `[expr] = value` | Evaluate `expr`; use result as key |

```duo
table = {
    name = value
    Red = handle_red
    ["literal-key"] = value
    [Color.Red] = handle_red
    [expr] = value
}
```

Rules:

- `name = value` is **not** computed — it binds the literal identifier `name`.
- `[expr] = value` is computed — evaluate `expr` and use its value as the key.
- Do **not** invent another computed-key operator; Lua's `[ ]` form is canonical.
- Canonical Duo examples avoid `[]` for simple identifier-like keys.
- Formatter preserves `[]` when semantically necessary or intentionally explicit.

### GR-007 — No @const/@comptime surface syntax (implemented)

**Status:** implemented (2026-08-01)

`@const` and `@comptime` are NOT valid user-facing directives. Compile-time evaluation is expressed through:
- `@(expr)` — inline comptime eval
- `@comp.*` combinators at module scope
- Type annotations triggering static lowering
- `@inline`, `@hot` function attributes

The parser rejects `@const`, `@comptime`, `@comptime_expr`/`@comptimeexpr`, and
`@compile_time`/`@compiletime` (in both statement and expression position) with a
directed error + hint pointing to `@(expr)` or `@comp.*`. Rejection lives in
`src/parser.zig` (`Parser.bannedAtDirectiveSuggestion`), checked at the top of the
`.at` statement dispatch and at the top of `parse_macro_call_expr`, so keyword
token spellings (`const`/`comptime`) are caught before a generic parse cascade.

**Note:** `@constexpr` is intentionally NOT banned — it is a working directive that
folds pure expressions through the comptime evaluator (`__constexpr`).

### GR-008 — No `fun`/`function` in new .duo files (preferred)

**Status:** preferred (2026-08-01)

All new .duo code uses bare function syntax (GR-001). `fun`/`function` are accepted for backward compat but deprecated in .duo files. AGENTS.md already reflects this; editors/LSP should hint.

### GR-009 — Method-call colon inside argument lists (implemented)

**Status:** implemented (2026-08-01)

A `:` inside a call's argument list is a method call (`obj:method(`), not a
parameter type annotation (`a: i32`). Without this, `print(red:to_string())`
was mis-detected as a bare function declaration (GR-001), because the
`red:to_string` colon set the `typed_or_vararg` signal in
`scan_func_header_signal` (the prior `prev == .name` guard was insufficient —
a method colon also follows a name).

The disambiguator (`Parser.colon_is_method_call`, `src/parser.zig`) looks
ahead: a depth-1 colon counts as a type annotation only when it is NOT
`: name (`. This mirrors the existing return-type-colon rule
(`(params): ret` vs `(expr):method()`). Keeps GR-001 bare declarations
working while ordinary method-call statements parse as calls.

Related fix: `@c.export("name")` (and `@c.type`/`@c.ffi`/`@c.call`/`@c.link`)
now ATTACH to the following `fun`/decl as attributes instead of becoming a
standalone `.directive` statement — they are decl-attaching C-interface
attributes, not standalone module directives, even though they are cataloged
in the `@comp.*` table (`isMetaAttribute` returns true for them, so they had
to be special-cased in `parse_attributed_decl` before that check).

### GR-call-001 — Value reference vs explicit invocation (Pass 24)

**Status:** preferred (2026-08-05)

| Form | Meaning |
| --- | --- |
| `a` | Retrieve callable **value** — never auto-invoke |
| `a()` | Zero-argument invocation |
| `a x`, `a x, y` | Parenless invocation with arguments |
| `obj:method()`, `obj:method x` | Receiver calls |

First-class functions must remain passable without invocation:

```duo
items:each print
callback = print
handlers.Save = save
```

Bare-auto-call is **rejected** (P24-R01). Command tails (`pwd`, `git status`) use explicit command invocation context only — not global identifier semantics.

### GR-call-002 — Parenless call argument precedence

**Status:** implemented (2026-08-05)

Parenless call arguments bind tighter than binary `+` / `-`:

```duo
f x + y     -- parses as (f x) + y
f (x + y)   -- passes one combined argument
```

Implementation: `parse_parenless_call_arg` uses `parse_prec(18)`; trailing infix completes via `finish_prec` (`src/parser.zig`). Gate: P24-A02.

## Changelog

| Date | Rule | Change |
| --- | --- | --- |
| 2026-08-05 | GR-call-001, GR-call-002 | Pass 24 call model: value vs invoke; parenless precedence; P24-A02 gate |
| 2026-08-01 | GR-009 | Method-call colon in arg lists no longer mis-read as param type; `@c.export`/`@c.type`/`@c.ffi`/`@c.call`/`@c.link` attach to decls. `Parser.colon_is_method_call` ahead-look in `scan_func_header_signal`; C-interface decl-attaching attrs accumulate before isMetaAttribute check |
| 2026-08-01 | GR-006, GR-007, GR-008 | Table keys proposed; @const/@comptime rejected; fun/function deprecated in new .duo |
| 2026-08-01 | GR-007 | **Implemented** parser rejection of `@const`/`@comptime`/`@comptime_expr`/`@compile_time` with directed `@(expr)`/`@comp.*` hint (statement + expression position); 2 parser tests added (`Parser.bannedAtDirectiveSuggestion`) |
| 2026-08-01 | GR-005 | Preferred `not` + `!=`; `~=` remains accepted for Lua compatibility |
| 2026-07-31 | GR-004 | Quoted string table keys without `[ ]`; field access preferred over `["id"]` |
| 2026-07-30 | GR-001, GR-002 | Bare func decl, assign-form func, if-expressions; `fun` deprecated in `.duo` |
