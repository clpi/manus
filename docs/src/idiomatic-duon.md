# Idiomatic duon

**Precedence, so this file can never become a rival authority:** `CLAUDE.md` +
`docs/spec/` are THE LAW. `AGENTS.md` carries the mechanical deny list. **This
file teaches** — worked before/after pairs, and the reasoning that makes the
canonical form the obvious one. Where this file and the law disagree, the law
wins and this file has a bug.

The previous version of this document was titled *"The Zen of Duo"* and taught
`fun`, the File-as-`M` pattern, and `my_mod` naming. All three are denied now.
If you have it in context, it is VOID.

---

## The one rule under all the others

**Say the fact once, in the place that owns it.** Every canonical form below is
that rule applied to a different surface. Every denied form is a place where the
old spelling made you repeat something the compiler already knew.

---

## 1. Identifiers are ONE lowercase word

`grep [a-z]_[a-z]` outside numeric literals is **zero**, and there is no
uppercase in an identifier, ever.

```duo
-- denied
is_digit(c)          do_retry(n)        dt_pad2(x)        MAX_N        Point
-- canonical
digit(c)             retry(n)           date.pad(2)       max          point
```

The qualifier you wanted to bolt on with an underscore has three homes, and
picking the right one is the whole skill:

| the qualifier is… | it becomes a… | example |
|---|---|---|
| a *variant of the operation* | **LEVEL** — a paren | `read(number)`, `skip(space)`, `add(wrap)` |
| a *place the thing lives* | **HOME** — a dot | `wire.header`, `token.kind`, `utf8.valid` |
| already obvious from the receiver | **nothing** — delete it | `sort(cmp)` not `sort_by(cmp)` |

`sort_by`, `take_while`, `is_digit` are axis names: the axis is already the
argument, so naming it twice is the redundancy.

## 2. `end` is deleted, and so is `;`

A body is an offside expression sequence. Its value is its final expression's.

```duo
-- denied
scan(n: i64): i64
    s = 0
    i = 1
    while i <= n
        s = s + i
        i = i + 1
    end
    return s
end

-- canonical
scan(n: i64): i64
    s = 0
    i = 1
    while i <= n
        s = s + i
        i = i + 1
    s
```

No `end`, no `then`, no `do`, no trailing `return`, and **no `;` — the repair
for a semicolon is to press enter.** One-lining is free *while every clause
boundary carries a structural token*; two expression-starts side by side
(`if x < lo lo`) never separate, so that is a newline.

## 3. Call at the value, subject-first

If you are holding the first argument, you are holding the **receiver**.

```duo
-- denied: ALIAS-CALL
L.next(lex)          string.sub(s, 1, 3)      table.insert(xs, v)
-- canonical: FACE-CALL
lex:next()           s:sub(1, 3)              xs:push(v)
```

You *declare* operation-first at the trie (`read(number) = (lx, b) …`) and
**call** subject-first (`lx:read(number)(b)`). Operation-first survives at a call
site only as a callable value in pass position (`map(to(str))`) or as a world
action (`print(x)`, `sh(cmd)`).

There is no `string.` / `table.` / `math.` module and no `std.mem` / `std.fmt` /
`std.math`. Pure operations are **value edges** (`x:abs()`, `s:copy()`); **worlds
are the only namespaces**. `s[i]` IS the byte — a str is bytes.

## 4. There is no `self`

Every job `self` had was already done by ruled machinery. A parameter named
`self` is an audit finding, and parameter lists count TRUE ARGUMENTS ONLY.

| the job | denied | canonical |
|---|---|---|
| touch a field | `self.x` | `.x` |
| call on the receiver | `self:length()` | `:length()` — leading invoke |
| return the receiver | `…; self` | **nothing** — a void body in chain position yields its receiver |
| the receiver as a value | `self` | `.` — the zero-length walk |
| spread the receiver | `..self` | `...` |

```duo
scale = (k) @{ .x * k, .y * k }
```

`k` is the only true argument, so it is the only parameter.

## 5. Construct through the ladder

`.new`, `.create`, `make_*` and `init` are banned. Four rungs, in order:

```duo
point{ x = 1.0, y = 2.0 }        -- (a) descriptor application
v:to(str)                        -- (b) a conversion edge
p:from(polar)(r, t)              -- (c) a from(mode) LEVEL
file.open(path)                  -- (d) action-named acquisition
```

`from_polar`, `of_hex` and `new_ms` are LAW-ONE violations *and* ladder
violations at once.

## 6. Failure routes; it is never plumbed

The result union is `t | error`. Structural nil is unwritten.

```duo
-- denied — this shape does not exist in duon
v, err = thing()
if err
    return nil, err

-- canonical: inside a declared failure contract, an unbound failure
-- position ROUTES and early-exits with the pack
tok = lx:token()
```

An unconsumed failure position **diagnoses**: bind it, route it, or drop it BY
NAME. Silent loss is unexpressible. **Zero forwarding plumbing exists in duon.**

## 7. Strings interpolate

```duo
-- denied
"hello " .. name .. ", you are " .. age:to(str)
-- canonical
"hello {name}, you are {age}"
```

No concat chains, no `tostring`, no `string.format`. Multiline is the offside
string block.

## 8. Cases are inferred, and the set lives at the field

```duo
-- denied — a companion descriptor naming the kind
token_kind = { name, number, eof }
tok.kind == token_kind.eof

-- canonical — the case set is INLINE at the field
kind: { name, number, eof }
tok.kind == .eof
token{ kind = .eof }
s: shape = .circle(3.0)
```

Literal unions are for wire strings only: `method: "get" | "post"`.

## 9. Demand is the resting state, so there is no comprehension

```duo
xs:take(odd):map(f)
```

That fuses, streams, and never materializes unless demanded. Nested is join.
There is **no comprehension syntax and never will be** — laziness is already the
default, so a second spelling for it would be a second way to say one fact.

## 10. When you miss a keyword: NNS FIRST

The grammar is **CLOSED**. Capability is the semantics of existing forms. If a
repair seems to need new surface, you have not yet found the form it is hiding —
say so rather than annexing a token. Forty features from other languages were
absorbed by five concepts and **zero new grammar**:

| you wanted | it already is |
|---|---|
| pattern matching | dispatch tables + lens-path keys |
| generators / `yield` | demand streams |
| channels | stream places composed by `\|` |
| `?.` | a refinement proof, or `get(.y, default)` |
| overflow control | mode levels — `add(wrap\|sat\|checked)` |
| slices | `xs:view(2, 5)` (`..` stays spread) |
| a mutex | a place + an exclusive fact; the lock scope is a region |
| docs / doctests | `doc(slot)` edges; examples are `check(doc)` staged |

## 11. Output is graph data, never a string

Every emission — diagnostic, trace, manifest, debugger frame, REPL echo, MCP
response — is `(span, role, rule, why, dnir)` rendered through the one role
taxonomy. **Plain-string output is a finding**, and repair candidates are EDGES,
not prose.

---

## The corpus is not the law

**756 `.duo` files still contain bare `end`; 227 contain `string.`.** That is
migration debt. Do not imitate the file you are editing — check it against this
guide and repair what you touch.

Before you finish: `zig build idiom-gate`.
