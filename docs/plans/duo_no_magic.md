# Duo — No Magic (canonical)

**Ruling:** `satisfies` — and everything shaped like it — is deleted as a
primitive. Nothing in the standard environment may be a binding with private
compiler behaviour.

**The de-magicking test (standing gate, G3):**

> For every name in the standard environment, either (a) a user could define it
> with public machinery, or (b) it is a relation family on the one graph whose
> compiler-populated edges are inspectable, overridable, and blockable exactly
> like user edges. Anything failing both is a side registry.

## 1. Satisfaction is the anchoring homomorphism

`@` distributes over constraint tables. For a table `P` whose entries are
requirements, `X@P` anchors each entry at X and yields `(bundle, nil)` — a table
of resolved implementations, entry-for-entry — or `(nil, missing_set)`. Laws are
checked as evidence facts on the resolved edges; a failed law lands in
`missing_set` with its counterexample.

```
ordering = { cmp, laws = { antisymmetric, transitive, total } }

if impls = Point@ordering
    sort_with(items, impls.cmp)        -- the proof IS the bundle
else
    report(impls, missing)
end

ordered = descriptors:filter((d) d@ordering)   -- selection: just a predicate
run(task, Point@ordering)                       -- injection: a world fragment
n = { ..number, ..(int@ordering) }              -- spread the bundle
```

Three faces of one graph fact, each already in the language:

| Face | Spelling | Mechanism |
|---|---|---|
| static | `items: seq(ordering)` | the shape axis, verified at compile time |
| dynamic | `if x = to(P)(v) ...` | narrowing — a derived conversion edge |
| reflective | `if b = X@P ...` | the homomorphism — proof as data |

Sealed anchor plus frozen protocol makes the whole test a compile-time constant
and folds the bundle to direct references — zero tables, zero dictionaries.

## 2. The former magic, respelled

Anything that *answers a question about semantics* is a relation family — edges,
so ownable, derivable, blockable. Anything that *merely computes* is an ordinary
function. No third category.

| Was | Is |
|---|---|
| `satisfies(d, P)` | `d@P` — an operator law, not a function |
| `has(user, .name)` | `has(.name)(user)` — a family; presence is semantics a descriptor owns |
| `try_get(user, .a.b)` | `get(.a.b)(user)` — family, pack `(value,nil)\|(nil,missing_at)` |
| `range`, `meta`, `load.module` | ordinary values — always were |
| `compare` | projection of the `cmp` family |
| `derive` | a trie — the hook system itself |

## 3. Hooks are edge contributions

Override, derive, inject and observe all reduce to contributing edges to tries.
The compiler's own behaviours are pre-populated edges, no more privileged than
a user's:

```
derive(eq)(record) = structural_eq       -- ships with the compiler; overridable
derive(eq)(Secret) = false               -- block
rewrite(fuse)(map_map) = fuse_maps
lower(arm64)(add_op) = lower_add_arm64
observe(specialized)(on_spec) = log_spec
```

The algebra is inherited, not designed: **override** = a more precise edge or a
higher layer; **block** = `false`; **remove** = `nil`; **inject** = spread a
bundle or shadow a scope; **stage** = the family's parameter; **conflict** = the
same nine classes, never last-write-wins; **provenance** = every hook edge is
witnessed; **inspection** = trie reflection, so `derive[eq]` and `lower[arm64]`
are enumerable and the compiler is browsable as data.

Plugin APIs, callback registries and macro systems are the graveyard shapes this
replaces. A hook mechanism that is not edge contribution is a side registry.

## 4. The functional closure

Constraint tables and bundles form a monoid under spread (right-biased,
conflict-classified), and anchoring is a homomorphism over it:

```
X@(P union Q) = (X@P) union (X@Q)        missing-sets union on failure
```

Currying gives sections everywhere (`to(str)`, `get(.name)`, `derive(eq)`,
`lower(arm64)`); lenses compose; packs are the product side. That is the entire
type-class and module-system story, held by two operators and a table.

Laws attached to edges license `rewrite` fusion — `xs:map(f):map(g)` becomes
`xs:map(compose(g, f))`, pipelines become single loops — all witnessed, all
suppressible, all subject to demand.

**Idioms:** sections over lambdas (`items:map(to(str))`); lens composition over
access lambdas; bundles over function-parameter lists (`run(task, impls)`);
anchored bundles over hand dictionaries (`Point@ordering`, never
`{ cmp = Point@cmp }`); the clear pipeline over the hand-fused loop. The
point-free boundary stands: implicit-parameter lambdas remain rejected.
