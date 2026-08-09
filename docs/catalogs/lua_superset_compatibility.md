# Lua Superset Compatibility Matrix

> **Pass 24 P1 contract.** Every grammar change must update this matrix.
> Classifications are permanent policy — `LUA_CANONICAL` is **not** temporary.

## Syntax classification key

| Class | Meaning |
| --- | --- |
| `DUO_CANONICAL` | Preferred Duo form; formatter may emit by default |
| `LUA_CANONICAL` | Valid Lua syntax Duo accepts but may not emit by default |
| `LUA_AND_DUO_CANONICAL` | Fully accepted in both styles; no deprecation planned |
| `DUO_EXTENSION` | Duo addition; not in Lua |
| `LEGACY_DUO_EXPERIMENT` | Old Duo experiment; migration path documented |
| `ACTUALLY_DEPRECATED` | Documented superset exception; compatibility mode where practical |
| `INVALID` | Rejected by Duo parser or semantics |

## Deprecation threshold (all must be true)

1. Genuine semantic or grammatical conflict
2. Contextual disambiguation cannot solve reliably
3. Preserving it materially blocks higher-value Duo capability
4. Migration is exact and automatic
5. Compatibility mode remains available where practical
6. Decision documented as a superset exception

Token reduction, formatter preference, or aesthetics alone are **insufficient**.

---

## Compatibility matrix

| Lua construct | Accepted | Same semantics | Duo extension interaction | Formatter behavior | Test coverage | Class |
| --- | --- | --- | --- | --- | --- | --- |
| Long strings `[[ ]]`, `[=[ ]=]`, … | ✅ | ✅ | Shell raw boundaries use matching delimiter level when content contains `]]` | Preserve delimiter level | `lexer.zig`, `control_defaults_mem.duo`, gate | `LUA_AND_DUO_CANONICAL` |
| Long comments `--[[ ]]`, `--[=[ ]=]`, … | ✅ | ✅ | None | Preserve | `lexer.zig`, gate | `LUA_AND_DUO_CANONICAL` |
| Ordinary quoted strings | ✅ | ✅ | Interpolation extensions in `.duo` | Preserve escapes | `lexer.zig` | `LUA_AND_DUO_CANONICAL` |
| `local function f()` | ✅ | ✅ | Bare/assign forms preferred in new `.duo` | May omit in `.duo` output | parser tests | `LUA_CANONICAL` |
| Bare/assign functions | ✅ | ✅ | Typed params, implicit return | Prefer in `.duo` | pass23 gate | `DUO_CANONICAL` |
| `local x = …` | ✅ | ✅ | Implicit `local` in `.duo` | May omit `local` in `.duo` | sema | `LUA_CANONICAL` / `DUO_CANONICAL` |
| Table constructors `{ k = v }` | ✅ | ✅ | Descriptor `@{}` is separate | Preserve Lua keys | parser | `LUA_AND_DUO_CANONICAL` |
| Metatables / metamethods | ✅ | ✅ | Protocol registry canonical names | N/A | pass23 gate | `LUA_AND_DUO_CANONICAL` |
| Multiple returns | ✅ | partial | Return-pack native dataflow open | N/A | partial | `LUA_AND_DUO_CANONICAL` |
| Varargs `...` | ✅ | ✅ | None | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| Generic `for k,v in pairs(t)` | ✅ | ✅ | Direct `for v in values` extension | Preserve Lua form | partial | `LUA_CANONICAL` |
| Numeric `for` | ✅ | ✅ | `@parallel for` (future) | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| Coroutines | ✅ | partial | Task graph specialization (future) | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| Labels / `goto` | ✅ | ✅ | None | Preserve | open | `LUA_CANONICAL` |
| `if … then … end` | ✅ | ✅ | If-expression without `then` | Prefer omit `then` in `.duo` | parser | `LUA_AND_DUO_CANONICAL` |
| `do … end` blocks | ✅ | ✅ | Omit where parser allows | May omit in `.duo` | partial | `LUA_CANONICAL` |
| `elseif` | ✅ | ✅ | `else if` chain in if-expr | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| `repeat … until` | ✅ | ✅ | None | Preserve | open | `LUA_CANONICAL` |
| Method `:` declarations / calls | ✅ | ✅ | Colon method assign in `.duo` | Preserve | pass23 gate | `LUA_AND_DUO_CANONICAL` |
| Parenthesized call `f(a, b)` | ✅ | ✅ | Parenless calls extend, never replace | Preserve when needed | partial | `LUA_AND_DUO_CANONICAL` |
| Bare identifier value `f` | ✅ | ✅ | Must not auto-invoke; Pass 24 §4 | N/A | Pass 24 constitution | `LUA_AND_DUO_CANONICAL` |
| Parenless invoke `f x`, `obj:method x` | ✅ | ✅ | Duo extension; distinct from value ref | Prefer in `.duo` | partial | `DUO_EXTENSION` |
| Concatenation `..` | ✅ | ✅ | Interpolation preferred in new `.duo` | Preserve | parser | `LUA_AND_DUO_CANONICAL` |
| Length `#` | ✅ | ✅ | None | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| Bitwise / integer ops | ✅ | ✅ | `@comp.bit.*` at comptime | Preserve | partial | `LUA_AND_DUO_CANONICAL` |
| `require` / modules | ✅ | ✅ | `req` shorthand | Prefer `req` in `.duo` | partial | `LUA_CANONICAL` / `DUO_CANONICAL` |
| `_ENV` | ✅ | open | None | Preserve | open | `LUA_CANONICAL` |
| Lexical scoping | ✅ | ✅ | Implicit local in `.duo` | N/A | sema | `LUA_AND_DUO_CANONICAL` |
| Error behavior | ✅ | partial | `@comp.hint.trap` etc. | N/A | partial | `LUA_AND_DUO_CANONICAL` |
| Close variables (Lua 5.5) | open | open | None | N/A | open | `LUA_CANONICAL` |
| Dynamic loading | partial | partial | `@comp.embed.*` | N/A | open | `LUA_CANONICAL` |

**Legend:** ✅ proven in tests; partial = asserted/partial coverage; open = not yet corpus-proven.

---

## Documented superset exceptions

| Construct | Class | Reason |
| --- | --- | --- |
| `@const`, `@comptime` as directives | `INVALID` | Use `@(expr)` and `@comp.*` instead (GR-007) |
| Pipeline `\|>` | `LEGACY_DUO_EXPERIMENT` | Prefer calls; compat warning in `.duo` mode |
| `[[ ... ]]` as shell conditional | `INVALID` | Never was valid; Bash uses long-string boundary |
| Bare callable auto-invocation (`f` means `f()`) | `INVALID` | Breaks first-class functions; Pass 24 §3 |

---

## Audit checklist (per grammar change)

1. Update this matrix row.
2. Add or extend lexer/parser/sema test.
3. Run `zig build lua-superset-gate`.
4. If claiming Lua compatibility, extend differential corpus (`P1`).
5. For call/concurrency changes, update `(archived, deleted — git history)`.
