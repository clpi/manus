# Grammar Compactness Catalog

> **Pass 3 canonical reference.** All compact syntax forms: accepted, proposed, rejected.
> Tracks one-line expressiveness, keyword retirement, and grammar wins.

## Status Key

| Status | Meaning |
| --- | --- |
| ✅ ACCEPTED | Implemented, tested, in canonical grammar |
| 🔄 PARTIAL | Parser supports; not all contexts or tooling ready |
| ⬜ PROPOSED | Designed; not yet implemented |
| ❌ REJECTED | Evaluated and declined (with reason) |
| 🔮 FUTURE | Long-term direction; blocked on prerequisites |

---

## Accepted Compact Syntax (implemented)

| ID | Form | Example | Since | Notes |
| --- | --- | --- | --- | --- |
| GS-001 | Bare function decl | `add(x: i32, y: i32): i32 x + y end` | GR-001 | Requires ≥1 typed param |
| GS-002 | Assign-form function | `add = (x: i32, y: i32): i32 x + y end` | GR-001 | Named binding to anon fn |
| GS-003 | If-expression | `x = if a < b val else val2 end` | GR-002 | Chainable with else if |
| GS-004 | Implicit local | `x = 42` (no `local`) | GR-003 | .duo files only |
| GS-005 | Omit `then` | `if ready run() end` | AGENTS.md | Duo-preferred; `if ready then run() end` remains `LUA_AND_DUO_CANONICAL` |
| GS-006 | Omit `do` | `while active tick() end` | AGENTS.md | Where parser allows |
| GS-007 | `req` over `require` | `json = req "std.json"` | — | Short import |
| GS-008 | String-literal calls | `print 'hi'` | — | Single string arg |
| GS-009 | `!=` inequality | `a != b` | GR-005 | Alias of `~=` |
| GS-010 | `@(expr)` comptime | `size = @(64 * 1024)` | — | No keyword needed |
| GS-011 | Bare `@name` directives | `@hot`, `@inline`, `@popcount` | — | Tier 1/2 aliases |
| GS-012 | Implicit return | `add(a, b) a + b end` | — | Tail expression |
| GS-013 | `_` private prefix | `_helper()` not exported | — | Convention, not keyword |
| GS-014 | One-line if-expr | `mode = if debug "debug" else "release"` | GR-002 | No `end` when single-expr |
| GS-015 | Newline field sep | `{ a = 1\n b = 2 }` | GP-013 | Commas optional between fields |
| GS-016 | Lua long strings | `[[text]]`, `[=[text]=]`, … | Lua | `LUA_AND_DUO_CANONICAL`; never shell conditionals |
| GS-017 | Lua long comments | `--[[text]]`, `--[=[text]=]`, … | Lua | Same delimiter rules as strings |

---

## Proposed Compact Syntax (designed, not yet implemented)

| ID | Form | Example | Prerequisite | Score |
| --- | --- | --- | --- | --- |
| GP-001 | Field projections | `users:map(.name)` | ~~Parser `.name` in call context~~ | ✅ DONE |
| GP-002 | Method references | `items:each(:close)` | ~~Parser `:name` in call context~~ | ✅ DONE |
| GP-003 | Named destructuring | `{ name, age } = user` | Sema field-match | ✅ DONE |
| GP-004 | Table spread | `{ ..source, x = 1 }` | ~~Parser `..expr` in tables~~ | ✅ DONE |
| GP-005 | Descriptor spread | `User: @{ ..Named, id: i64 }` | Descriptor algebra | ✅ DONE |
| GP-006 | Binding conditions | `if file = open(path) ... end` | Parser assign-in-cond | ✅ DONE |
| GP-007 | Short-circuit control | `ready or return` | Already works (Lua semantics) | Free |
| GP-008 | Direct iteration | `for v in values ... end` | Iterator protocol | ✅ DONE |
| GP-009 | Keywordless enum | `Color: @{ Red, Green, Blue }` | ~~`@{}` descriptor parser~~ | ✅ DONE |
| GP-010 | Keywordless record | `Point: @{ x: f64, y: f64 }` | ~~`@{}` descriptor parser~~ | ✅ DONE |
| GP-011 | Payload variants | `Result: @{ Ok(v), Err(e) }` | Variant grammar in `@{}` | 🔄 PARTIAL |
| GP-012 | Descriptor composition | `User: @{ ..Named, id: i64 }` | Descriptor algebra ops | ✅ DONE |
| GP-013 | Compact separators | Newline instead of comma in `@{}` | ~~Parser newline-as-sep~~ | ✅ DONE |
| GP-014 | Failure propagation | `file = open(path) or return` | Already works | Free |
| GP-015 | `@export` visibility | `@export run(args) ...` | Parser attribute-on-decl | ✅ DONE |
| GP-016 | Storage directives | `buf = @stack [1024]u8` | Representation selection | Future |
| GP-017 | Selective import | `{ encode, decode } = req "std.json"` | Destructuring + req | ✅ DONE |
| GP-018 | Dispatch tables | `handlers[color](value)` | Pattern recognition transform | Future |
| GP-019 | Descriptor methods | `Point: @{ x: f64, length(self) ... end }` | Descriptor grammar | Future |
| GP-020 | Positional init | `point: Point = { 3, 4 }` | Known-shape mapping | Medium |

---

## Rejected Compact Syntax (evaluated, declined)

| ID | Form | Reason |
| --- | --- | --- |
| GR-X01 | Arrow functions `(x) => x * 2` | Adds punctuation without semantic gain; ordinary `(x) x * 2` suffices |
| GR-X02 | `@const` directive | Conflicts with Lua `const`; `@(expr)` is more general (GR-007) |
| GR-X03 | `@comptime` directive | Same as above; banned by parser |
| GR-X04 | Indentation-based blocks | High ambiguity cost; conflicts with `end`-based grammar |
| GR-X05 | Significant whitespace | Formatter instability; Lua heritage conflicts |
| GR-X06 | `match` as expression sugar | Ordinary table dispatch + `if` chains suffice; keep `match` as block |
| GR-X07 | `impl` blocks | Use methods directly (`Type:method()`) |
| GR-X08 | `trait`/`interface` keywords | Use descriptor syntax `@{}` |
| GR-X09 | `new` keyword | Construction via `Type { fields }` or plain calls |
| GR-X10 | `import` keyword | `req` is shorter and sufficient |

---

## Deprioritized symbolic operators (compat only — not canonical)

These forms parse and may lower natively, but **must not** appear in new `.duo` code,
stdlib, docs, or agent-generated examples. Prefer the canonical alternative.

| ID | Form | Example | Canonical alternative | Notes |
| --- | --- | --- | --- | --- |
| GR-DP01 | Pipeline `\|>` | `data \|> f` | `f(data)` | Parser warns in `.duo` mode |
| GR-DP02 | Chained `\|>` + projection | `p \|> .x \|> .y` | `p.x.y` | Legacy fuse only; do not teach |
| GR-DP03 | Infix tensor `@` | `a @ b` | `duo_tensor_matmul(a, b)` | Conflicts mentally with `@comp.*` |
| GR-DP04 | Method-chain as `\|>` | `xs \|> map \|> filter` | `filter(map(xs, f), p)` | Use calls, not F#/Elixir pipe mimicry |

**Agent rule:** When suggesting data transforms, use **function call syntax** and
**field projections in argument position** (`map(items, .name)`), never `|>` chains.

---

## Scoring Rubric (0–5 each)

| Dimension | Weight |
| --- | --- |
| Semantic density | High |
| Visual clarity | High |
| Lua familiarity | High |
| Grammar regularity | Medium |
| Formatter stability | Medium |
| Lowering simplicity | Medium |
| Optimization value | Medium |
| Dynamic fallback | Medium |
| LSP quality | Low |
| MCP quality | Low |
| Agent parseability | Medium |
| Migration feasibility | High |

---

## One-Line Design Exemplars

These demonstrate the target aesthetic:

```duo
-- Functions
add(a, b) a + b
abs(x) if x < 0 -x else x
clamp(x, lo, hi) math.max(lo, math.min(x, hi))
double = (x) x * 2

-- Descriptors (proposed)
Point: @{ x: f64, y: f64 }
Color: @{ Red, Green, Blue }
Vec4f = @(Vector(f32, 4))

-- Pipelines
users:filter(.active):map(.score):each(print)

-- Control flow
ready or return
config = parse(file) or return

-- Compile-time
size = @(64 * 1024)
codec = @(make_codec(Packet))
```

---

## Implementation Priority

1. **Free wins (already Lua semantics):** GP-007, GP-014
2. **High leverage, bounded scope:** GP-001 (projections in **call position**), GP-008, GP-004
3. **Architectural (descriptor grammar):** GP-009, GP-010, GP-012, GP-013
4. **Medium scope:** GP-003, GP-006, GP-017
5. **Future (blocked):** GP-011, GP-016, GP-018, GP-019
6. **Do not expand:** GR-DP01–04 (`|>`, infix `@`) — compat warnings only
