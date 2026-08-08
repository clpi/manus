# Duo — Canonical Specification (SHC Edition)

The consolidation. Everything concluded in Passes 34–47 folded into one
authoritative language grammar, semantic model, idiom canon, and
self-hosted-compiler (SHC) contract.

**Authority rule.** Where any prior pass conflicts with this document, this
document wins and the conflict is a supersession to record. Where this document
is silent, the source pass remains normative.

Machine-readable form: `src/pass48_catalog.zig`. Proofs: `src/pass48_gate.zig`
(`zig build pass48-gate`).

---

## Part I — Axioms

| | | |
|---|---|---|
| **A1** | HPLS | maximum leverage, power, surface, projection algebra, clarity, elegance — per token of syntax |
| **A2** | NNS | the grammar is closed; capability arrives as semantics of existing forms, descriptor data, ordinary values, IR, or recognition — never as new tokens/keywords/productions (escape hatch: priced, evidenced, one-release rejection first) |
| **A3** | ONE EDGE | every semantic relationship has exactly one canonical graph fact; all spellings, orientations, operators, foreign forms and realizations are projections of it |
| **A4** | DEMAND | nothing is physical unless consumed — no table, closure, pack, descriptor, metatable, adapter, string or wrapper without an observed demand (IR invariant) |
| **A5** | WITNESS | no optimization without an inspectable witness: legality, enabling facts, fallback, dependents |
| **A6** | BRIDGES | nothing is blocked; every open decision carries a provisional contract every possible final decision can honor |
| **A7** | NATIVE-FIRST | Duo semantics are canonical; Lua, Rust, Python, C, schemas are foreign projections with adapters, provenance and trust |
| **A8** | DESCENT | no ladder rung ships without its way back down specified (deopt, unwind, invalidation, reclamation) |
| **A9** | ORDINARY | relations, namespaces, worlds, meta-layers, ranges, lenses, subtrees are ordinary first-class values in ordinary scope — no parallel universe of special things |
| **A10** | SELF-PROOF | the SHC is the style guide, benchmark and truth test; a correct but conventional compiler is a failure |

---

## Part II — Surface grammar (final)

### 2.1 Access and operators

```
.               the only data-access operator            point.x
.x  (leading)   a lens; in an anchored scope, applied to the ambient subject
                except in argument position — receiver field access is .x += amt
:               declaration = shape ("is"); call = receiver sugar
                x: f64   Point: { ... }   out:write(b)
=               value binding ("holds")                  x = 0, f = (x) g(x)
@               bare: the enclosing descriptor, uniformly — @{ ... },
                @{ ..self, x = nx }, next: @; not an identifier, never shadowable
X@rel           the anchor operator: rel resolved with X bound into its declared
                anchor role — pure retrieval, never invocation   Point@to(str)
[ ]             indexing (incl. relation-trie index dual)        to[str][Point]
```

Methods vs statics carry no annotation: a slot whose body applies lenses to the
ambient subject is a method; one that doesn't is static. The whole receiver, when
needed, is an ordinary named parameter (`(self, d)`). **Bare names never resolve
to receiver fields** — scope is lexical or it is nothing. Number literals require
a leading digit (`0.5`, never `.5`). `name: shape = value` composes shape and
value; statement-position `total: f64` introduces a shaped binding.

Operators — merit inventory, **closed**, compiler-owned, projected from relation
bindings:

```
==  !=  <  <=  >  >=      eq / cmp projections
+ - * / % ^               arithmetic family
& | ~ << >>               bitwise family (i64/u64 lane)
..                        concat        #  length
and  or  not              logic (mixed and/or requires parens)
```

Prefix `@` is the staging/directive namespace only: `@(expr)`, `@{ ... }`,
`@comp.*`. **Position disambiguates completely** — prefix `@` = staging,
postfix `@` = anchoring.

### 2.2 Bindings and scope

```
x = expr        assignment targets the nearest existing binding in an enclosing
                writable scope; otherwise introduces locally
```

No `local`. Frozen bindings (std namespaces, relation families) are non-writable,
so inner assignment shadows locally — announced by diagnostic when the name is
operator-linked or a namespace root. **Worlds are lexical scope**: a semantic
override is a shadow (`eq = approx_eq`); closures capture their world
frozen-by-stable-reference by default.

### 2.3 Functions and results (as amended by Pass 49)

```
f = (x) g(x)                       single expression: one line, mandatory
f = (a, b): result_desc            return descriptor = optional CONTRACT pinning
    effect_one(a)                  boundary ABI; absence = demand-polymorphic
    combine(a, b)                  the body's value IS its final expression
end
xpp = (self, amt) self.x += amt    void unless consumed; consuming sites receive
                                   the stored value (one update, never recomputed)
```

A body is an expression sequence; its value is its final expression's value;
**call-site demand alone decides materialization**. `return x, y` is early exit or
explicit pack; bare `return` is explicit void. Where demand cannot propagate
(exports, foreign, dynamic rung), the declared descriptor — or the full body
value — pins the shape, recorded in the manifest.

### 2.4 Control flow

```
if cond ... else ... end                        statement form
if cond a else b                                expression form (packs per branch)
if count == 0 return nil, Error.Empty end       guard: the one-line prefix-if
if v = f() use(v) else report(err) end          binding condition
if value, err = parse(text) ... else ... end    correlated binding
while item = it:next() consume(item) end        canonical consumption loop
for i, item in items ... end                    arity by iter pack identity
for i in range(0, n) ... end                    range descriptor value
```

Binding conditions evaluate once, bind visible in body only, succeed by the
return descriptor's success alternative else position-1 truthiness, and lower to
bind → refine → branch. **This is Duo's pattern matching.**

### 2.5 Tables, descriptors, destructuring, spread

```
point: {
    x: f64
    y: f64
    xpp = (amt) .x += amt                     method: lens context, no self param
    length = () sqrt(.x^2 + .y^2)
    origin = () @{ 0, 0 }                     static: @ = enclosing descriptor
    with_x = (self, nx) @{ ..self, x = nx }   whole receiver: named param
    eq = (a, b) a.x == b.x and a.y == b.y     symmetric: operands explicit
    format(sink) = (out) out:write("({.x}, {.y})")
}
token = token{ kind, span, text }       same-name shorthand mandatory
node: { value: i64, next: @ }           recursive descriptor via @
node2 = { ..base, inferred = facts }    spread = one pack-expansion edge
{ name, age } = user                    destructuring → shape projections
{ copy, fill } = std.mem                destructuring IS the import list
```

### 2.6 Relations (bare, first-class) and the trie

```
to(str)(bool) = (v) if v "true" else "false"    exact edge (place store)
eq(Point) = point_eq                            subject-level edge
to(str) = { [i32] = f, [Secret] = false }       subtree; false blocks region
to(str)(bool) = nil                             remove local decision
to_text = to(str)          ≡  to[str]           first-class subtree
render = Point@to(str)                          anchor: role-addressed edge
sort(items, cmp)                                injection: relations are values
for src, conv in to[str] ... end                enumeration demand
```

Std families: `to from eq cmp hash format iter release ref deref clone default
get set call len copy share encode decode`. SHC families by identical machinery:
`lower validate canonicalize realize rewrite measure`, plus the extension-point
families `derive` and `observe` (§2.8).

### 2.7 Namespaces

Ambient roots are `std` plus manifest dependencies; frozen bindings; static paths
fold to direct references at compile time. Dynamic loading is an explicit
effectful stdlib call (`plugin, err = load.module(p)`).

### 2.8 Lenses, places, extension points

```
names = symbols:map(.name)     bare projection path = lens
has(.name)(user)               presence: the `has` FAMILY (subject: container)
get(.address.city)(user)       guarded projection: (value,nil)|(nil,missing_at)
```

Places (IR category): binding, field, index, lens path, relation path, foreign
slot, atomic slot — one owner for load/store/update/borrow/move/CAS; `+=` is
`place.update`.

Extension points are relation families with compiler-populated edges (Pass 52):

```
derive(eq)(record) = structural_eq       rewrite(fuse)(map_map) = fuse_maps
lower(arm64)(add_op) = ...               observe(specialized)(handler)
```

Hook = edge contribution; override/block/remove/inject = the trie's own
operations; the compiler is browsable as data (`derive[eq]`, `lower[arm64]`).

### 2.9 Sums are tables (Pass 49)

```
token_kind: { name, number, string, symbol }      enum: frozen distinct cases
result: { ok(value), err(failure) }               tagged union
shape: { circle(r: f64), rect(w: f64, h: f64) }

area = @{ [shape.circle] = (c) pi * c.r ^ 2,      matching = dispatch tables
          [shape.rect] = (r) r.w * r.h }(s)
if c = to(shape.circle)(s) use(c.r) end           narrowing
if kind == token_kind.string ... end              equality
```

No match construct, no case syntax, no `|` operator. Variant lifting derives
`eq/hash/format` per case, overridable at case depth; correlated packs are
formally the two-case sum; representation is demand-selected (niche /
tag+payload / branch-only / erased).

### 2.10 Protocols are constraint tables (Passes 49, 52)

```
ordering = { cmp, laws = { antisymmetric, transitive, total } }
ordered_key = { ..ordering, ..comparable }         composition = spread (monoid)
if impls = Point@ordering ... end                  test: @ distributes → bundle
if x = to(wire)(v) ... end                         narrowing: derived edge
sort = (items: seq(ordering), key) ...             static face: the shape axis
descriptors:filter((d) d@ordering)                 selection: just a predicate
run(task, Point@ordering)                          bundles are world fragments
```

**No `satisfies` primitive exists** — satisfaction is the anchoring
homomorphism. De-magicking test (G3): every std name is an ordinary definable
value or a relation family with inspectable edges — no third category.

---

## Part III — Semantic model

### 3.1 Resolution ladder (final: 8 rungs)

```
1 lexical shadow (static)        within each rung: exact edge > subtree > family;
2 instance layer (gated)         explicit > generated; false blocks its covered
3 exact descriptor relation      region below; nil never blocks
4 descriptor hierarchy
5 package/namespace extension
6 authorized foreign relation
7 generated/derived
8 dynamic layer
→ structured failure: nil, err
```

**Sealed-world collapse:** no lexical shadow ∧ instance layer forbidden ∧
descriptor sealed ∧ namespace frozen ∧ world frozen-captured ⇒ the ladder
collapses to a rung-3 **proof**. SHC hot paths must live here (G6).

### 3.2 The relation graph

One edge = operation + application schema + descriptors + implementation + scope
+ evidence + provenance. Application schemas are graph data — curry groups, index
duality, symmetric operands, subject roles — never inferred from arity or
punctuation. Observation (enumeration, mutation, identity) is the only thing that
materializes a trie. Coherence: one implementation per (operation, descriptors,
parameters) per level; conflicts classify as equivalent / specific / authority /
mergeable / ambiguous / incompatible / blocked, **never last-write-wins**.

### 3.3 Knowledge and IR

Correlated packs `(T,nil)|(nil,E)` foundational; path-sensitive facts; guard
subsumption graph; semantic phi with deferred representation joins; absence as
fact; internal poison family (uninitialized/moved/dropped/unreachable — never
collapsed into nil); demand descriptors on every expression; proof-carrying
access; cold-path extraction; tail merging. **Virtualization invariant: table
syntax does not imply table identity unless observed.**

### 3.4 Memory, lifecycle, errors

E1 bridge (non-moving, pointers stable, safepoints at calls); E8 bridge
(sealed-immutable alias-free); E6 (isolate heaps, immutable sharing via `share`).
Drop ladder via `release`: proven last-use inline → lexical close → managed.
`ref`/`deref` yield borrowed views, proven-fast or safe-slow, always explained.
Errors are `nil, err` packs, singular.

---

## Part IV — Idiom canon

### 4.1 Layout law (binding)

One-line **required** when one semantic unit ∧ ceilings hold (100 cols, ≤2
paren/call depth, ≤1 binding, no nested if) ∧ parse obvious. Multiline
**required** for ordered effects, failure construction, explanatory bindings,
comments, stage boundaries, descriptor bodies. The formatter computes layout; no
configuration; orientation is authorship and never rewritten.

### 4.2 The ten idioms

1. Operators first (`a == b`, not `eq(a, b)` mid-expression).
2. Operation-first invocation; anchors for retrieval, never invocation.
3. Relations, subtrees, lenses, namespaces are values — pass them.
4. Declare at the source, in the descriptor; never both ends of an edge.
5. Let demand synthesize structural `eq/hash/clone`; block with `false`.
6. `format(sink)` primary; `to(str)` is its projection.
7. Binding conditions for every lookup/parse/consume; guards for every early exit.
8. Lenses over trivial lambdas; bound members over wrappers.
9. Semantic variation = lexical shadow in a well-named function.
10. Meta layers only when the layer matters.

### 4.3 The smells

Sigil archaeology (`__`, `getmetatable`, `req`, `pairs`); wrapper lambdas; result
objects where packs suffice; eager tables/metatables/adapters "just in case"; a
curry level carrying a static fact; hand dispatch where a trie exists; fighting
the formatter (the form, not the layout, is the bug).

---

## Part V — SHC contract

### 5.1 Architecture (binding)

**Forbidden by default:** visitor hierarchies, repeated enum switches, parallel
node universes, pass-pipeline-as-meaning, boxed uniform object models,
protocol/intrinsic/trait registries beside the graph.

**Required:** one semantic graph as truth; descriptors project all consumers
(token → lexer/precedence/formatter/Tree-sitter/docs/fuzz/tests; diagnostic →
every renderer; IR op → constructor/verifier/printer/lowering/tests; target
instruction → encode/decode/select/schedule; ABI descriptor →
classification/packs/unwind). Facts → legal transformations → demand →
candidates → schedule. Proofs expire with their dependencies.

### 5.2 SHC idiom floor

Hot paths (lexer, parser, binder, graph, queries, IR, lowering): sealed-world
resolution only; zero unexpected dynamic semantic calls, generic tables, boxes,
heap closures, iterator objects, materialized packs.

### 5.3 Gates

| | | | |
|---|---|---|---|
| **G1** | dialect containment | **G6** | hot-path staticity |
| **G2** | idiomatic compression | **G7** | witness integrity |
| **G3** | semantic ownership (no side registries) | **G8** | N-directional consistency |
| **G4** | projection reuse | **G9** | bootstrap fixed point (S2 ≡ S3) |
| **G5** | demand discipline | **G10** | density ratchet |

Build artifacts: representation manifest, idiom & leverage manifest, witness
store. Bootstrap: Duo-B versioned dialect; five-state lifecycle
(discovered → specified → implemented → validated → adopted); N-1 buildability;
two-stage landing; pinned recovery roots.

---

## Part VI — Graveyard (consolidated)

`req` · `local` · `pairs/ipairs/enumerate` · `getmetatable/setmetatable` ·
`__`-anything · `~=` · match/pattern syntax · traits/interfaces/impl
blocks/derive/protocol keywords · lifetime & ownership syntax · trait objects &
dictionary passing · receiver binding · postfix guards · `?` `?.` `or=` `<?=`
`..<` · implicit-parameter lambdas · implicit conversions · transitive cast
search · arity-inferred currying · parameter permutation · static facts as curry
levels · duplicate `to`/`from` storage · install/bind APIs · `within` helpers ·
visitor ownership of truth · last-registration-wins.

---

## Part VII — Proof corpus

```
-- wire/leb128.duo
{ Error } = wire.failure

decode(u64) = (cursor): (u64, cursor) | (nil, Error)
    value = 0
    shift = 0
    while byte = cursor:next()
        if shift > 63 return nil, Error.Overflow end
        value = value | ((byte & 0x7f) << shift)
        if byte & 0x80 == 0 return value, cursor end
        shift += 7
    end
    nil, Error.Truncated
end
```

```
-- syntax/span.duo
span: {
    start: u32
    stop: u32
    eq = (a, b) a.start == b.start and a.stop == b.stop
    cmp = (a, b) compare(a.start, b.start) or compare(a.stop, b.stop)
    format(sink) = (out, s) out:write("[{s.start}, {s.stop})")
}
```

```
-- diag/render.duo
report = (sink, diags) diags:each(sink@format)   -- anchored impl as value
labels = diags:map(.code)                        -- lens
```

```
-- semantic/convert.duo — the SHC's own lowering family, same machinery
lower(arm64) = { [add_op] = lower_add_arm64, [load_op] = lower_load_arm64 }
emit = (target, region) region.ops:each(lower(target))
if code = lower(target)(op) code(ctx, op) else nil, Error.NoLowering end
```

Every excerpt: sealed-world resolution, zero heap iterators, zero wrapper
closures, zero materialized tables, guards as one-liners, correlated packs, tail
demand. **The manifest for this corpus is the conformance test.**

---

## Part VIII — Closing

`.` for data, `:` for members, postfix `@` for anchoring, prefix `@` for staging,
bare first-class relations on a trie, one edge behind every spelling, lexical
scope as the only world, demand as the only materializer, witnesses behind every
disappearance. One character of ceremony where meaning changes; none where it
doesn't; and nothing physical that nobody asked for.
