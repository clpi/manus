> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 41 — Native-First Amendment

Amends: [`duo_universal_semantic_access.md`](duo_universal_semantic_access.md) (canon: Pass 36 algebra + Pass 40 surface),
[`duo_projection_calculus.md`](duo_projection_calculus.md) (Pass 38), and the
Pass 34 charter. **Supersession chain: S7.**

**Ruling.** Backwards compatibility is removed as a design constraint. Lua
interoperability is reclassified from *ecosystem invariant* to *foreign
projection family* — exactly the status Rust traits and Python dunders already
hold in the relation graph. Design inputs are now only: HPLS, power, surface
area, projection logic and algebra, semantic clarity, intuitiveness, elegance.

---

## 0. What does NOT change: the Pass 40 surface

Dropping compat does **not** reopen the postfix-`@` ruling. Pass 40's scorecard
was already scored on exactly the criteria now in force — composition over
grammar, ambiguity-class elimination, one access operator, `meta` as a curried
value. Compatibility was not a decisive input to any row. Re-scored under the
purified criteria the ruling stands, stronger:

```
.        the only access operator
@name    the only semantic marker
meta     the only hierarchy surface — an ordinary curried function
one edge the only truth
demand   the only reason anything is physical
```

What changes is everything *behind* that surface that existed only to mirror Lua.

---

## 1. The purification rulings

### A1 — Compat reclassified

Every clause across Passes 34–40 reading "Public Lua-compatible language behavior
never changes" or "standing ecosystem invariant" is amended to:

> **Duo semantics are canonical. Lua is a supported foreign projection with
> provenance, trust, and an adapter boundary — the same machinery as every other
> foreign target.**

Interop is `@lua`-target projection: `__eq`, `__index`, `__tostring` adapters are
emitted **on demand at the boundary only**, with provenance, exactly as a Rust
`Display` impl would be. Foreign Lua values enter through the foreign layer of
the resolution ladder, nowhere else.

### A2 — The `__` namespace is deleted from canon

There is now **one** semantic namespace: `@name`. The double-underscore names
cease to exist in the language. They survive solely inside the `@lua` adapter as
*emission targets* — spelling details of one foreign ABI, no more canonical than
`PartialEq`.

Consequence of real weight: the dynamic semantic layer becomes **ordinary Duo
data**. `meta(dynamic)(v)` returns a plain table whose keys are semantic
identities (`@eq`, `@get`, `@format`). No shadow key convention, no string-name
registry, no reserved-prefix rules. The meta system is made of the language's own
tables all the way down.

### A3 — The resolution ladder compacts: 10 → 8 rungs

Rungs 8 (Lua metamethod projection) and 9 (dynamic metatable fallback) were two
rungs only because Lua's lookup rules had to be replayed verbatim. Merged:

```
1  lexical override          (static)
2  instance semantic layer   (capability-gated)
3  exact descriptor relation
4  descriptor hierarchy projection
5  package/namespace extension
6  authorized foreign relation   ← Lua values enter HERE, like all foreign values
7  generated/derived relation
8  dynamic semantic layer    (Duo-defined: @get/@set/@call/@eq lookups in the
                              value's dynamic table — not Lua metatable walk rules)
→  structured failure (nil, err)
```

The sealed-world collapse condition gets *simpler* — two fewer rungs to disprove
— so more sites reach the rung-3 proof with less evidence. **A performance win
purchased purely by deleting inherited semantics.**

### A4 — One inheritance mechanism

Lua had metatable `__index` chaining; Duo had descriptor hierarchy projection;
canon carried both. Now: **descriptor hierarchy projection is the only
inheritance mechanism in the language.** `@get` on the dynamic layer is a lookup
operation, not a delegation chain — chained delegation, where wanted, is a
library pattern written *with* `@get`, never a semantic rule the compiler must
honor. One mechanism, one set of hierarchy facts, one thing to prove.

### A5 — Operator inventory chosen on merit

Operators remain a **closed, compiler-owned projection set** from semantic roots
(`@eq @cmp @add @sub @mul @div @concat @len @get @set @call @iter`) — no
user-defined operators; that guard is elegance, not compat. The inventory's
*contents* are now selected, not inherited:

- `!=` replaces `~=` (universal intuition beats inheritance);
- `== < <= > >= + - * / % ^ .. #` retained on merit;
- integer/float division and future operator questions decided by numeric
  speciation (L8), free of Lua precedent;
- the operator↔root mapping lives in `duo-b/spec.duo` as descriptor data.

> **Repo status (measured 2026-08-05).** `!=` **already parses** — both `1 != 2`
> and `1 ~= 2` pass `duo check`. A5 is therefore a **deletion** task, not an
> addition: `~=` must be removed from the lexer (`src/lexer.zig:163`,
> `.neq => "~="`) and the `duo fmt --canonical` migration must rewrite it. Per
> the convergence rule, A5 closes only when `~=` is gone.

### A6 — `:` retained, on merit

`value:method(args)` receiver-binding sugar for **ordinary members** stays — it
earns its place (binding at the call site with one character) independent of its
origin. It never touches semantic space: `value:@eq` remains in the graveyard.

### A7 — Errors are return packs, canonically

`nil, err` structured failure is the one canonical error surface of the semantic
system. `pcall`-style dynamic unwinding is demoted to the `@lua` boundary adapter
and the E3 bridge; it is not a semantic-layer concept. This finishes what L3
(non-nilness facts) started: the error idiom is native, zero-cost, and singular.

### A8 — `getmetatable` / `setmetatable`: deleted

Previously "supported but not canonical." Now not in the language.
`meta(dynamic)(v)` and assignment do everything they did; the adapter maps them
for foreign Lua code at the boundary.

---

## 2. The gains ledger

| # | Gain | Kind |
| --- | --- | --- |
| 1 | One semantic namespace (`@name`); `__` deleted | clarity |
| 2 | Dynamic layer is ordinary Duo data | elegance, power |
| 3 | Ladder 10 → 8 rungs; simpler sealed-world proof | performance, provability |
| 4 | One inheritance mechanism | clarity, provability |
| 5 | Operator set on merit (`!=`, future L8 freedom) | intuitiveness |
| 6 | Error surface singular (`nil, err`) | clarity, performance |
| 7 | Duo-B shrinks: no compat-replay semantics to freeze | self-hosting |
| 8 | Conformance shrinks: Lua-parity chapters move to the adapter suite | stabilization |
| 9 | Ward differentials become foreign-boundary tests, not identity requirements | measurement honesty |
| 10 | Every future design question loses one veto-holder | velocity |

---

## 3. Amendments to prior passes (normative diff)

- **Pass 34 charter** — guardrail "Public Lua-compatible language behavior never
  changes" replaced per A1. All barrier records marking Lua-compat as
  `semantically_required: true` are re-audited; several fallback-preservation
  requirements likely downgrade to adapter obligations.
- **Pass 35** (absent from repo) — Duo-B 1.0 scope drops compat-replay semantics;
  conformance gains an `@lua` adapter chapter. G4 differential-vs-S0 unaffected
  (self-consistency, not Lua-consistency).
- **Pass 36** (absent from repo) — "Lua metamethod projection" entries become one
  row of the foreign-projection family; §13.7 compat mapping moves to the adapter
  spec.
- **Pass 38** — §8.5's `@x ↔ __x` table relocated verbatim into the adapter spec;
  §8.4 operator projections re-point at A5's merit inventory.
- **Pass 40** — ladder replaced by A3's 8 rungs; guideline 10's `getmetatable`
  smell upgraded from "compat boundary only" to "does not exist"; graveyard
  extends with `~=`, `__` names, `getmetatable`, `setmetatable`, `__index`-chain
  inheritance.

---

## 4. Deliberately kept, though compat no longer demands it

Recorded so these survive future zealotry: tables as the one aggregate; `nil`;
1-based indexing *as the default realization of sequence descriptors* (revisitable
by L8/L5 evidence, not by taste); `..` for concat; the stateless iterator triple
as `@iter`'s canonical projection (it is genuinely the zero-allocation design,
independent of origin); `:` sugar (A6).

**Heritage is not a reason to keep anything — but neither is it a reason to
delete what independently wins.**

---

## 5. Measured purification surface (2026-08-05)

What A1/A2/A8 actually touch in this repository today. Counts are grep-level
inventory, not a fix estimate.

| Ruling | Surface | Measure |
| --- | --- | --- |
| A2 | Lua metamethod names in `src/*.zig` + `lib/std/*.duo` | 19 distinct names, 128 references — heaviest: `__tostring` 23, `__add` 16, `__index` 15, `__len` 10 |
| A8 | `getmetatable`/`setmetatable` sites | `src/codegen.zig` 14, `src/sema.zig` 6, `lib/std/meta.duo` 4 |
| A1 | Lua-as-invariant machinery to reclassify as adapter | `lua_superset_catalog.zig` 223, `compat_layer_projection.zig` 139, `lua_superset_gate.zig` 132, `lua_superset_corpus.zig` 131, `lua_readiness.zig` 101 = **726 lines** |
| A5 | `~=` deletion | `src/lexer.zig:163`; `!=` already parses |

Note that A1's 726 lines are **reclassified, not deleted** — the gate becomes an
adapter parity suite rather than a language-identity requirement. That is a
change of *meaning* on an existing gate, which per the convergence rule needs its
own supersession record rather than a silent edit.

---

## 6. Closing

The language stops carrying a second language inside it. Lua becomes what Rust
and Python already were: a projection target with an adapter, provenance, and a
test suite. The semantic model gets one namespace, one inheritance mechanism, a
shorter ladder, a simpler collapse proof, and a meta system built from its own
ordinary tables.

Same surface. Purer core. Every remaining rule now exists because it won on the
only criteria left: power, projection algebra, clarity, intuitiveness, elegance.
