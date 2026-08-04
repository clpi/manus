# Keyword Catalog

> **Pass 3 canonical reference.** Machine-readable inventory of every lexer keyword.
> Generated from `src/lexer.zig` audit (2026-08-04). 53 keywords total.

## Classifications

| Status | Meaning |
| --- | --- |
| CORE | Semantically indispensable; no replacement |
| READABILITY | Retained for clarity; optional in some contexts |
| TYPE | Primitive type annotation keyword |
| LUA_COMPAT | Required for Lua 5.4/5.5 compatibility |
| CONTEXTUAL | Used only in specific parser contexts |
| DEPRECATE | Safe to deprecate; canonical replacement exists |
| EXPERIMENTAL | Not yet stable; may change or be removed |
| REMOVE | Should not exist in canonical .duo |

---

## Full Inventory

### Control Flow (CORE — 13 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `if` | `kw_if` | CORE | Conditional; also expression (GR-002) |
| `else` | `kw_else` | CORE | Branch |
| `elseif` | `kw_elseif` | CORE | Chained conditional |
| `for` | `kw_for` | CORE | Numeric and generic loop |
| `while` | `kw_while` | CORE | While loop |
| `in` | `kw_in` | CORE | For-in iterator |
| `return` | `kw_return` | CORE | Function return |
| `break` | `kw_break` | CORE | Loop break |
| `continue` | `kw_continue` | CORE | Loop continue (Lua 5.5) |
| `end` | `kw_end` | CORE | Block closer |
| `and` | `kw_and` | CORE | Logical AND |
| `or` | `kw_or` | CORE | Logical OR |
| `not` | `kw_not` | CORE | Logical negation |

### Values (CORE — 3 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `true` | `kw_true` | CORE | Boolean literal |
| `false` | `kw_false` | CORE | Boolean literal |
| `nil` | `kw_nil` | CORE | Null value |

### Scoping (2 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `global` | `kw_global` | CORE | Only way to create module global in .duo |
| `local` | `kw_local` | LUA_COMPAT | Implicit in .duo (GR-003); required in .lua |

### Declaration (DEPRECATE — 2 keywords)

| Keyword | Token | Classification | Replacement |
| --- | --- | --- | --- |
| `function` | `kw_function` | LUA_COMPAT | Bare function syntax (GR-001) |
| `fun` | `kw_fun` | DEPRECATE | Bare function syntax; needed only for untyped .duo fns |

### Type Keywords (TYPE — 13 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `i8` | `kw_i8` | TYPE | 8-bit signed |
| `i16` | `kw_i16` | TYPE | 16-bit signed |
| `i32` | `kw_i32` | TYPE | 32-bit signed |
| `i64` | `kw_i64` | TYPE | 64-bit signed |
| `u8` | `kw_u8` | TYPE | 8-bit unsigned |
| `u16` | `kw_u16` | TYPE | 16-bit unsigned |
| `u32` | `kw_u32` | TYPE | 32-bit unsigned |
| `u64` | `kw_u64` | TYPE | 64-bit unsigned |
| `f32` | `kw_f32` | TYPE | 32-bit float |
| `f64` | `kw_f64` | TYPE | 64-bit float |
| `bool` | `kw_bool` | TYPE | Boolean |
| `void` | `kw_void` | TYPE | Void/unit |
| `str` | `kw_str` | TYPE | String (`const char*`) |

### Lua Compatibility (READABILITY/LUA_COMPAT — 6 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `then` | `kw_then` | DEPRECATE | Omit in .duo (style preference, not enforced) |
| `do` | `kw_do` | DEPRECATE | Omit in .duo where parser allows |
| `repeat` | `kw_repeat` | LUA_COMPAT | Repeat-until loop |
| `until` | `kw_until` | LUA_COMPAT | Repeat-until terminator |
| `goto` | `kw_goto` | LUA_COMPAT | Jump to label |
| `const` | `kw_const` | CONTEXTUAL | Module-level constants; `@const` banned (GR-007) |

### Duo Contextual / Experimental (14 keywords)

| Keyword | Token | Classification | Notes |
| --- | --- | --- | --- |
| `enum` | `kw_enum` | CONTEXTUAL | Enum declaration; target: descriptor syntax `@{}` |
| `match` | `kw_match` | CONTEXTUAL | Pattern matching block |
| `concept` | `kw_concept` | CONTEXTUAL | Type constraints; target: descriptor syntax |
| `alias` | `kw_alias` | CONTEXTUAL | Type alias declaration |
| `extends` | `kw_extends` | CONTEXTUAL | Concept extension; target: descriptor `+` |
| `try` | `kw_try` | EXPERIMENTAL | Error handling |
| `catch` | `kw_catch` | EXPERIMENTAL | Error handling |
| `defer` | `kw_defer` | EXPERIMENTAL | Deferred execution |
| `async` | `kw_async` | EXPERIMENTAL | Async function |
| `await` | `kw_await` | EXPERIMENTAL | Await result |
| `private` | `kw_private` | EXPERIMENTAL | Visibility; target: `_` prefix convention |
| `macro` | `kw_macro` | REMOVE | Not implemented; use `@comp.*` |
| `comptime` | `kw_comptime` | REMOVE | Not valid in .duo; use `@(expr)` |
| `let` | `kw_let` | REMOVE | Unnecessary; implicit local + `const` |
| `by` | `kw_by` | EXPERIMENTAL | For-loop step syntax |

---

## Retirement Summary

| Category | Count | Keywords |
| --- | --- | --- |
| **CORE** (keep) | 16 | if, else, elseif, for, while, in, return, break, continue, end, and, or, not, true, false, nil |
| **CORE** (scoping) | 1 | global |
| **TYPE** (keep) | 13 | i8–u64, f32, f64, bool, void, str |
| **LUA_COMPAT** (keep for .lua) | 5 | local, function, repeat, until, goto |
| **DEPRECATE** (remove from canonical .duo) | 4 | fun, then, do, let |
| **CONTEXTUAL** (migrate to descriptors) | 5 | enum, match, concept, alias, extends |
| **EXPERIMENTAL** (pending design) | 6 | try, catch, defer, async, await, by |
| **REMOVE** (should not be keywords) | 3 | macro, comptime, private |

**Target canonical .duo keyword count:** 30 (16 core + 1 scoping + 13 type)
**Current total:** 53
**Retirement candidates:** 23

---

## Pass 3 Keyword Retirement Priorities

1. **Immediate:** `macro`, `comptime`, `let` — no semantic role in current .duo
2. **Short-term:** `then`, `do` — enforce omission in formatter
3. **Medium-term:** `enum`, `concept`, `alias`, `extends` — replace with `@{}` descriptor syntax
4. **Long-term:** `fun` — remove once bare syntax handles all cases
5. **Compatibility:** `function`, `local`, `repeat`, `until`, `goto` — keep for .lua files
