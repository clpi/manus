# Pass 81 — The Family Registry: Every Protocol Point, Concluded

> **Status:** canon (supersedes Pass 79 §IV.1's accumulated list).
> **Measured against the compiler 2026-08-07** by `scripts/family_registry_census.duo`.
> **10 of 38 rows implemented, and five of those ten are controls or vestiges.**
> The family surface with any realization today is four rows.

The registry is the spec. The census is the compiler. This document carries
both, because Pass 64 Part VIII settled that a spec is *allowed* to run ahead of
its compiler and that what is not allowed is an agent discovering the gap by
writing broken code. Every row below says which state it is in.

---

## 0. The small question — `#.src`

`#.src` is the `len` operator applied to the applied lens — `#(.src)`, "the
length of *my* `src`." Operators compose with anchored-scope lenses like any
primary expression; no ambiguity exists (`.src` cannot be a numeral — numbers
need a leading digit) and the spelling is canonical.

**Measured: the parse is exactly as ruled; the lowering is not.** `.src` becomes
a closure and `#` is applied to *the closure itself* rather than composed into a
lens, so the backend emits `strlen(<closure>)` and the C compiler rejects the
type. `#p.src` on a named subject works. Filed as **GAP-022** — the rule is
right, the realization is missing, and today the form does not compile.

## 1. The completeness principle

> **Every point where a value's descriptor can customize behavior is a relation
> family — ownable, derivable, blockable, anchorable, witnessed. Every point
> where it deliberately cannot is listed with its reason. There is no third
> state, and no `__` name ever.**

## 2. The registry, organized

Legend: **LIVE** — measured working · **SPEC** — ruled, no realization ·
**BROKEN** — realization exists and is wrong.

### 2.1 Application & construction — `call` (and the deletion of `init`)

`call` is the family behind application of non-function values: dispatch tables,
callable records, partial-application objects. And the unification that deletes
`init` as a concept: **construction is the descriptor's own `call` edge.**
`point{ 3, 4 }` is the descriptor applied to a literal; the default realization
is shape-directed fill + slot defaults + refinement checks (`& positive` verified
here); a descriptor that needs invariants, derived fields, or resource
acquisition **overrides its `call` edge** — no post-construction hook, no
two-phase init, no partially-built object ever observable:

```
handle: {
    fd: i32 & valid_fd
    call = (spec) @{ fd = os.open(spec.path, spec.mode) }   -- construction owned
}
```

| Row | State | Measured |
| --- | --- | --- |
| `CALL-4` brace application against a **function** | **LIVE** | `srv{ port = 8080 }` dispatches |
| `CALL-1` descriptor shape fill | **BROKEN** | codegen emits `point(tbl)` and never defines `point` |
| `CALL-2` descriptor `call =` edge | **SPEC** | parse error at the `=` |
| `CALL-3` callable record | **SPEC** | `t(1)` yields nil |

The deletion of `init` is sound and costs nothing to adopt — there is no `init`
to retire. What does not exist is the **default** realization: a descriptor
declared `point: { x: i64, y: i64 }` has no shape-directed fill behind it, so
`point{ ... }` is a call to an undefined symbol rather than a construction. This
is the same row `spec_conformance.duo` records as `FF-13 t{...} shape` MISSING.

### 2.2 Places & indexing — `place` (Lua's `__index` + `__newindex`, collapsed)

Duo does not split read-hook from write-hook: the **`place` family** is a
descriptor's keyed-place implementation — one edge yielding the place, whose
load/store/update/borrow/observe are demanded projections:

```
sparse: {
    place(u32) = (self, i) sparse_slot(self, i)   -- one edge: read AND write
}                                                  -- AND += AND borrow AND diff
matrix[all, j]        -- strided place, same family
board.uart.baud       -- MMIO place: at()/volatile facts select realization
counts[w]             -- default: the table's own storage place
```

`get`/`set`/`has` (lens-guarded, correlated) are projections over `place`;
computed properties, views, sparse structures, registers, and journaled/durable
slots are all `place` edges; there is no separate newindex, no rawget/rawset (the
*exact layer* — `meta(descriptor)` — is the raw access, principled instead of
magical).

| Row | State | Measured |
| --- | --- | --- |
| `PLACE-2` default table place `t[2]` | **LIVE** | — |
| `PLACE-1` `place(T) =` edge | **SPEC** | parse error at `place(` |
| `PLACE-3` `get` projection | **SPEC** | `t:get("a")` yields nil |

Collapsing `__index`/`__newindex` into one edge is the right ruling and there is
no vestige fighting it. Note the cost of `PLACE-3` failing *silently* — it
returns nil rather than diagnosing, the LV-4 failure mode.

### 2.3 Identity, structure, sizing

`eq` · `cmp` · `hash` · `len` (with the per-descriptor unit semantics) ·
`default` (slot defaults at construction; **no read-miss auto-vivification** —
absence is absence).

| Row | State | Measured |
| --- | --- | --- |
| `LEN-2` `#s` on a builtin | **LIVE** | — |
| `EQ-1` `eq =` · `CMP-1` `cmp =` · `LEN-1` `len =` · `DEFAULT-1` slot default | **SPEC** | one parse rule — see below |
| `HASH-1` `hash` | **SPEC** | undeclared identifier |

**This is the single highest-leverage blocker in the registry.** Every one of
these is a `name = ...` member inside a descriptor body, and a descriptor body
accepts **type slots only**. `eq =` fails at the `=` with `expected '}', got
'name'`, identically to `cmp`, `len`, `hash`, `call` (2.1) and `place` (2.2). One
parse rule gates roughly twelve rows across five sections. Filed as **GAP-021**.

### 2.4 Lifecycle — and `release` IS drop

`clone` · `copy` (memcpy grant) · `share` · `ref` / `deref` (borrowed views) ·
**`release`** — the drop family, already tiered (proven last-use → lexical close
→ managed); Lua's `__gc` *and* `__close` are its tier-3 and tier-2 respectively,
one family, no finalizer/to-be-closed split.

| Row | State |
| --- | --- |
| `CLONE-1` · `COPY-1` · `REF-1` · `RELEASE-1` | **SPEC** — no name resolves |

### 2.5 The meta answer — `meta(level)` replaces get/setmetatable

Reading a layer is `meta(instance)(v)` — an ordinary curried value. Writing is
assignment into it, **capability-gated by world facts** (a sealed world forbids
it; a sandbox forbids it; the diagnostic says which fact). Lua's `__metatable`
protection field becomes a policy fact like every other authority question.
Nothing here is an API; it is layers + places + facts.

| Row | State | Measured |
| --- | --- | --- |
| `META-3` `setmetatable` vestige | **LIVE** | still resolves and runs |
| `META-1` `meta(instance)` · `META-2` `meta(descriptor)` | **SPEC** | undeclared |

Worth naming explicitly: the replacement has not landed *and the vestige has not
been retired*, so both ends live at once. `spec_conformance.duo`'s `G6` row
depends on `setmetatable` today. Retire the vestige only after `meta(level)`
lands, or that row goes red for the wrong reason.

### 2.6 Rendering, data, extraction

`format(style)` — the sink family, style-parameterized (`format(debug)`,
`format(display)` — one family, styles are descriptors, so the debug/display
split is an edge choice, not two protocols) · `to` / `from` (one edge, oriented)
· `encode` / `decode` (`orient`-paired) · `scan` (grammars).

| Row | State |
| --- | --- |
| `TO-1` `to(str)(42)` | **LIVE** |
| `FROM-1` `from` · `FORMAT-1` `format(style)` · `ENCODE-1` · `SCAN-1` | **SPEC** |

`to` and `from` are ruled **one edge, oriented**. Half of that edge exists. Until
`from` lands, the "one edge" claim is a spec property with a one-sided
realization — do not write `from` expecting the symmetry to hold.

### 2.7 Iteration

`iter` — parameterizable (`iter(reverse)` where the realization supports it, a
capability fact otherwise); consumed by `for`; `pairs`/`ipairs` remain dead
because arity flows from the iter pack identity.

| Row | State |
| --- | --- |
| `ITER-1` `for v in t` | **LIVE** |
| `ITER-2` `iter(reverse)` | **SPEC** — the family is not addressable by name |

`for` consumes the iter pack correctly; what is missing is `iter` as a *value*,
so there is nothing to parameterize.

### 2.8 Operator roots (the full enumeration, at last)

`add sub mul div mod pow neg` · `band bor bxor bnot shl shr` · `concat` ·
`eq cmp` (for `== != < <= > >=`) · `len` (`#`) — every operator token projects
from exactly one of these bindings; all are passable values (`fold(0, add)`); all
obey STRATA-OP operand selection (which is how `|` unions descriptors and `&`
refines them — the *same* `bor`/`band` roots with descriptor-operand edges).

| Row | State |
| --- | --- |
| `OP-5` the `+` **token** | **LIVE** |
| `OP-1` `add` as value · `OP-2` `fold(0, add)` · `OP-3` `concat` · `OP-4` `band` | **SPEC** |

The tokens all work. The *bindings behind them* are not nameable, so no root can
be passed anywhere and `fold(0, add)` has no surface. The enumeration is the
valuable half of this section today; the passability claim is unrealized.

### 2.9 Concurrency protocol point (spec'd direction, honestly marked)

`suspend` / `resume` — the awaitable point that scopes, cancellation facts,
virtual time, and durable continuations all address; recorded as the family they
will be, gated on the concurrency floor (§XV ledger). `CONC-1` is **SPEC** by
design; the row exists so the day it lands is dated.

## 3. The deliberate NON-families (hookability refused, with reasons)

```
truthiness      false/nil falsy, forever (B-2). Overridable truthiness makes
                every binding condition unreadable at a distance. STRUCTURAL.
scope/resolve   name resolution is the ladder; a __resolve hook is scope
                poisoning (the `with` disaster wearing a family). STRUCTURAL.
assignment      x = v is the scoping rule; no assignment hooks — places hook
                STORAGE (2.2), never the binding form itself.
identity        `rawequal`-style identity is meta(descriptor)-level fact
                access, not a family; identity is not customizable.
demand          materialization is the compiler's; no __demand hook — demand
                is observed, never performed.
```

**One of these is contradicted by the compiler today, and it is the one §3 calls
structural.** Measured: `if 0` does **not** take its branch. `if 1` and `if ""`
do, and `if false` does not, so the controls are sound and the reading is
unambiguous — **zero is falsy**. B-2 as written says only `false` and `nil` are
falsy. Either the compiler contradicts a structural rule, or B-2 means something
narrower than it says. Filed as **GAP-023**; it is a ruling, and rulings are the
author's, so the census asserts the rule as written and the row reads MISSING
until the ruling lands.

A registry that only tested what *should* exist could not have caught this — the
non-family rows earn their place.

## 4. The Lua rosetta for this registry (agents' mental map)

| Lua | Duo | State |
|---|---|---|
| `__index` + `__newindex` | **`place`** — one keyed-place edge, all four ops projected | SPEC |
| `__call` | `call` (including descriptor construction) | LIVE for functions |
| `__len` | `len` | SPEC |
| `__eq` `__lt` `__le` | `eq`, `cmp` (total order; `le` derived) | SPEC |
| `__add` … `__bxor` `__shl` | the operator roots (2.8) | tokens LIVE, roots SPEC |
| `__concat` | `concat` (strict, B-5) | SPEC |
| `__tostring` | `format` / `to(str)` | `to(str)` LIVE |
| `__gc`, `__close` | `release` tiers 3 and 2 | SPEC |
| `__pairs` | `iter` | `for` LIVE, `iter` SPEC |
| `__metatable` | authority facts on `meta(level)` writes | SPEC, vestige LIVE |
| `__mode` (weak tables) | **OPEN — GAP-024**: weakness is a `ref`-strength fact on places, gated on the memory decision (E2 bridge) | unruled |

The one honest hole the sweep found is the last row: weak references/ephemerons
have no ruling and *cannot* have one before the GC decision — so they enter the
gap register pointing at the memory bridge instead of getting a premature family.

## 5. Canon updates

Pass 79 §IV.1's accumulated list is replaced by this organized registry (2.1–2.9
+ §3's non-families); `init`, `__index/__newindex`-style split hooks, read-miss
vivification, overridable truthiness, and resolution hooks join the graveyard;
the `place` family enters the pattern book (computed properties, sparse, MMIO as
its worked examples); `format(style)` parameterization and `call`-as-construction
get fixtures; the weak-ref gap is filed against E2. The registry closes with its
own gate: **a new customization point proposed anywhere in the system must arrive
as a family row or a non-family row in this table — there is nowhere else for it
to live.**

## 6. What an agent should write today

The registry is canon. It is also, at 4 live family rows out of ~30, almost
entirely unrealized — so the interim advice matters more here than in most
passes.

- **Do not write descriptor member bindings.** `call =`, `place(T) =`, `eq =`,
  `cmp =`, `len =`, `hash =`, slot defaults — none parse. This is one rule
  (GAP-021), and when it lands most of §2 becomes writable at once.
- **Do not write `point{ ... }` against a declared descriptor.** It compiles to
  a call to an undefined symbol. Brace application against a *function* works.
- **Do not pass operator roots.** `add`, `concat`, `band` are undeclared
  identifiers; `fold(0, add)` has no surface. The tokens are fine.
- **Do not write `#.src`.** Use `#p.src` on a named subject (GAP-022).
- **`to(str)`, `for v in t`, `t[k]`, `#s` and brace-calling a function are the
  registry surface that works.** Everything else in §2 is spec.
- **Every family name is an ordinary undeclared identifier.** There is no
  reserved surface and no Duo-level diagnostic — `release` and `place` fail
  exactly like a name typed at random, at the C compiler. Nothing warns you that
  you wrote canon that does not exist yet. That is the whole reason this
  document carries a measured column.

Run `duo run scripts/family_registry_census.duo` before trusting any row.

## 7. Related

- `scripts/family_registry_census.duo` — the gate. Ratchet, floor pinned at the
  measured 10/38. Set `DUO_BIN` to an absolute path when running from anywhere
  but the repo root.
- `scripts/spec_conformance.duo` — the Pass 64 gate. `FF-13 t{...} shape` there
  is `CALL-1` here, measured independently and agreeing.
- `GAP-021` descriptor bodies accept no member bindings · `GAP-022` `#.src`
  mis-lowers · `GAP-023` zero is falsy, contradicting B-2 · `GAP-024` weak
  references, gated on E2.
