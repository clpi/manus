# Duo — Sums, Protocols, and the Demand-Return Correction (canonical)

Three gaps closed with **zero new grammar**. Every construct below rides one of
six carriers that already parse: tables, bindings, calls, spread, anchors, demand.

## 1. Sums are tables

A sum is a descriptor whose slots are cases. Nullary cases are frozen distinct
values; payload cases are constructors. Both are ordinary slot forms.

```
token_kind: { name, number, string, symbol }
result: { ok(value), err(failure) }
shape:  { circle(r: f64), rect(w: f64, h: f64) }
```

`shape.circle` is simultaneously a descriptor (refining the union, hierarchy edge
recorded), a value, an anchor target and a dispatch key. Untagged alternatives
need no `|`: `any_of(i64, f64)` is an ordinary descriptor function. Case sets
enumerate as tables. Nothing about a sum is a new kind of thing.

### Consumption — no match construct exists or will

```
-- exhaustive branching: a callable dispatch table, lowering to a branch
area = @{
    [shape.circle] = (c) pi * c.r ^ 2
    [shape.rect]   = (r) r.w * r.h
}(s)

-- narrowing: a conversion edge consumed by a binding condition
if c = to(shape.circle)(s) use(c.r) else fallback(s) end

-- testing and destructuring
if kind == token_kind.string read_string(cursor) end
{ r } = c
```

Relations lift over cases and stay overridable per case at case depth:
`eq(shape.circle) = approx_circle_eq`. Correlated packs are the degenerate
two-case union, so `result: { ok(value), err(failure) }` *is* the return-pack
alternative structure — refinement, impossible-state elimination and tag-free
representation apply to every user sum identically. Representation is
demand-selected: niche-packed, tag+payload, branch-only, or erased entirely when
a case is observed only by identity.

## 2. Protocols are constraint tables

A protocol is an ordinary frozen table whose entries are requirements.

```
comparable  = { eq, hash }
ordering    = { cmp, laws = { antisymmetric, transitive, total } }
wire        = { encode(json), decode(json) }
opaque      = { format = false }              -- negative requirement
ordered_key = { ..ordering, ..comparable }    -- composition is spread
```

Four operations, all existing machinery:

- **Test** — `satisfies(Point, ordering)` returns a correlated pack
  `(proof, nil) | (nil, missing_set)`. Sealed descriptor plus frozen protocol is
  a compile-time constant.
- **Select** — protocols are values and `satisfies` curries:
  `descriptors:filter(satisfies(ordering))`.
- **Project** — satisfaction unlocks derived surface through the law-to-projection
  registry. Implication is graph algebra, so protocol hierarchy is subsumption
  with evidence, never nominal inheritance.
- **Inject** — an implementation bundle is also a table, injected by spread or
  scope at descriptor, lexical or argument level, and demand-erased.

Constraints at signatures are descriptor expressions: `sort = (items: seq(ordering), key)`.
Verification uses the usual three tiers — compile time where sealed, a guard
where stable, a structured failure at the dynamic rung. A violation carries the
missing set, the implication chain consulted, and repair candidates.

## 3. The demand-return correction

> A body is an expression sequence. The body's value is its final expression's
> value. Whether that value is materialized is decided entirely by call-site
> demand. Core logic implies its returns; source never adds result plumbing.

This supersedes Pass 48 §2.3, which made a *binding* special. Nothing is special:
assignment is already an expression, and `place.update` is already an expression
whose value is the stored value.

```
Point: {
    x: f64
    xpp = (self, amt) self.x += amt
}
```

- `point:xpp(2)` unconsumed — void realization; the update runs, no value is
  constructed, the ABI returns nothing.
- `nx = point:xpp(2)` — the same edge realizes with one return: the freshly
  stored value, read from the place with no second evaluation and no duplicated
  effect.
- `a, b = f(...)` — positions materialize per demand; unused positions'
  construction is deleted.

There is no `result =` idiom. Writing `result = compute(a, b)` then reading it is
a redundant binding, and the whole pattern is the smell — the canonical body is
`compute(a, b)`.

Where demand cannot propagate (exports past the closed world, foreign adapters,
the dynamic rung, escaping function values), the realization defaults to the
declared return descriptor or the full body value, and the manifest records
`return_shape: pinned(reason)`. That is the one place a return descriptor earns
its keep.

Demand never changes semantics, only materialization: a void realization of an
effectful body keeps every effect.
