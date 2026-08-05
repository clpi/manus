# Directive Catalog

> **Pass 3 canonical reference.** Every registered `@` directive with semantic ID, tier, and status.
> Generated from `src/meta_module.zig` audit (2026-08-04).

## Tier Model

| Tier | Access | Stability | Example |
| --- | --- | --- | --- |
| **1 — Top-level** | `@name` | Stable; admission rubric required | `@hot`, `@inline`, `@sealed` |
| **2 — Short alias** | `@name` | Discoverable; may change | `@popcount`, `@prefetch` |
| **3 — Namespaced** | `@comp.*` | Complete API; always accessible | `@comp.why.shape`, `@comp.agent.gaps` |

---

## Tier 1 — Canonical Top-Level Directives

These pass the admission rubric: frequent, meaningful, cross-backend, stable, one primary meaning.

### Optimization

| Directive | Semantic ID | Category | Hardness | Status |
| --- | --- | --- | --- | --- |
| `@hot` | `comp.hint.hot` | optimization | preference | ✅ implemented |
| `@cold` | `comp.hint.cold` | optimization | preference | ✅ implemented |
| `@inline` | `comp.hint.inline` | optimization | preference | ✅ implemented |
| `@noinline` | `comp.hint.noinline` | optimization | preference | ✅ implemented |
| `@pure` | `comp.effect.pure` | semantic assertion | requirement | ✅ implemented |
| `@flatten` | `comp.hint.flatten` | optimization | preference | ✅ implemented |
| `@noreturn` | `comp.hint.noreturn` | semantic assertion | requirement | ✅ implemented |

### Representation

| Directive | Semantic ID | Category | Hardness | Status |
| --- | --- | --- | --- | --- |
| `@packed` | `comp.layout.packed` | representation | requirement | ✅ implemented |
| `@aligned` | `comp.layout.align` | representation | requirement | ✅ implemented |
| `@raw` | `comp.layout.raw` | representation | requirement | ✅ implemented |
| `@sealed` | `comp.shape.sealed` | shape assertion | requirement | ✅ implemented |

### Visibility / Linkage

| Directive | Semantic ID | Category | Hardness | Status |
| --- | --- | --- | --- | --- |
| `@export` | `comp.c.export` | visibility | requirement | ✅ implemented |
| `@ffi` | `comp.c.ffi` | foreign interface | requirement | ✅ implemented |
| `@native` | `comp.compile.native` | compilation | requirement | ✅ implemented |
| `@deprecated` | `comp.deprecated` | semantic assertion | info | ✅ implemented |

### Generation

| Directive | Semantic ID | Category | Hardness | Status |
| --- | --- | --- | --- | --- |
| `@derive` | `comp.derive` | generation | transform | ✅ implemented (module-level) |

---

## Tier 2 — Discoverable Short Aliases

Useful but more specialized. Accessible as `@name` with canonical path under `@comp.*`.

### Bit Intrinsics

| Alias | Canonical Path | Internal | Status |
| --- | --- | --- | --- |
| `@popcount` | `comp.bit.popcount` | `__popcount` | ✅ |
| `@ctz` | `comp.bit.ctz` | `__ctz` | ✅ |
| `@clz` | `comp.bit.clz` | `__clz` | ✅ |
| `@bswap` | `comp.bit.bswap` | `__bswap` | ✅ |
| `@rotl` | `comp.bit.rotl` | `__rotl` | ✅ |
| `@rotr` | `comp.bit.rotr` | `__rotr` | ✅ |
| `@bitcast` | `comp.bit.bitcast` | `__bitcast` | ✅ |

### Branch Hints

| Alias | Canonical Path | Internal | Status |
| --- | --- | --- | --- |
| `@likely` | `comp.hint.likely` | `__likely` | ✅ |
| `@unlikely` | `comp.hint.unlikely` | `__unlikely` | ✅ |
| `@prefetch` | `comp.hint.prefetch` | `__prefetch` | ✅ |
| `@assume` | `comp.hint.assume` | `__assume` | ✅ |
| `@unreachable` | `comp.hint.unreachable` | `__unreachable` | ✅ |
| `@trap` | `comp.hint.trap` | `__trap` | ✅ |
| `@fence` | `comp.hint.fence` | `__fence` | ✅ |
| `@volatile` | `comp.hint.volatile` | `__volatile` | ✅ |

### Metaprogramming (Tier 2 — combinators with bare aliases)

| Alias | Canonical Path | Internal | Status |
| --- | --- | --- | --- |
| `@map` | `comp.map` | `__comptimemap` | ✅ |
| `@expand` | `comp.expand` | `__metaexpand` | ✅ |
| `@fixpoint` | `comp.fixpoint` | `__comptimefixpoint` | ✅ |
| `@fanout` | `comp.fanout` | `__comptimefanout` | ✅ |

### C Interface

| Alias | Canonical Path | Internal | Status |
| --- | --- | --- | --- |
| `@emit` | `comp.c.emit` / `c.emit` | `__emit` | ✅ |
| `@asm` | `comp.asm` | `__asm` | ✅ |

---

## Tier 3 — Namespaced Compiler API (`@comp.*`)

### Introspection (`comp.type.*`, `comp.why.*`, `comp.origin`)

| Path | Internal | Has Handler | Notes |
| --- | --- | --- | --- |
| `comp.type.name` | `__type_name` | ✅ | Type name string |
| `comp.type.id` | `__type_id` | ✅ | Stable type identifier |
| `comp.type.info` | `__typeinfo` | ✅ | Full type information |
| `comp.type.shape` | `__type_shape` | ✅ | Storage class label |
| `comp.type.is` | `__is_type` | ✅ | Type predicate |
| `comp.type.of` | `__typeof` | ✅ | C typeof (limited) |
| `comp.type.names` | `__moduletypenames` | ✅ | Module type list |
| `comp.shape` | `__type_shape` | ✅ | Alias of type.shape |
| `comp.why` | `__why` | ✅ | Explain compiler decision |
| `comp.why.shape` | `__why_shape` | ✅ | Explain storage class |
| `comp.origin` | `__origin` | ✅ | Provenance origin |
| `comp.satisfies` | `__satisfies` | ✅ | Concept satisfaction check |
| `comp.fields` | `__fields` | ✅ | Field list |
| `comp.methods` | `__methods` | ✅ | Method list |
| `comp.variants` | `__variants` | ✅ | Enum variant list |
| `comp.has.field` | `__has_field` | ✅ | Field existence check |
| `comp.has.method` | `__has_method` | ✅ | Method existence check |
| `comp.has.metamethod` | `__has_metamethod` | ✅ | Metamethod check |
| `comp.concepts.count` | `__concept_count` | ✅ | Number of concepts |
| `comp.concepts.methods` | `__concept_methods` | ✅ | Concept method descriptors |
| `comp.concepts.fields` | `__concept_fields` | ✅ | Concept field descriptors |

### Compile-Time Control (`comp.compile.*`, `comp.if`, `comp.for`)

| Path | Internal | Has Handler | Notes |
| --- | --- | --- | --- |
| `comp.if` | `__comptimeif` | ✅ | Compile-time conditional (canonical) |
| `comp.for` | `__comptimefor` | ✅ | Compile-time loop (canonical) |
| `comp.fold` | `__comptimefold` | ✅ | Compile-time fold |
| `comp.assert` | `__static_assert` | ✅ | Static assertion |
| `comp.compile.log` | `__comptimeprint` | ✅ | Compile-time log |
| `comp.compile.warn` | `__comptimewarn` | ✅ | Compile-time warning |
| `comp.compile.error` | `__comptimeerror` | ✅ | Compile-time error |
| `comp.constexpr` | `__constexpr` | ✅ | Constant expression |
| `comp.compile.only` | — | ✅ | Mark comptime-only callback |
| `comp.compile.cached` | — | ✅ | Persistent comptime cache |
| `comp.compile.native` | — | ✅ | Force native lowering |

### Exponential Combinators (`comp.map` through `comp.hyper`)

| Path | Budget | Has Handler | Notes |
| --- | --- | --- | --- |
| `comp.map` / `comp.sweep` | O(n) | ✅ | Type sweep |
| `comp.match` | O(n) | ✅ | Pattern-match codegen |
| `comp.tabulate` | O(n) | ✅ | Lookup table generator |
| `comp.interpolate` | O(n) | ✅ | String template interpolation |
| `comp.each` / `comp.chain` | O(n) | ✅ | Fragment iteration |
| `comp.zip` | O(n×m) | ✅ | Cartesian zip |
| `comp.product` | O(n²) | ✅ | Cartesian product of two concepts |
| `comp.tensor` | O(n³) | ✅ | Tensor sweep |
| `comp.nfold` | O(n^k) | ✅* | Wired 2026-08-04 |
| `comp.power` / `comp.powerset` | O(2^n) | ✅ | Powerset |
| `comp.choose` | O(n choose k) | ✅ | Combinations |
| `comp.permute` | O(n!) | ✅ | Permutations |
| `comp.burst` | derive+product | ✅ | |
| `comp.transcend` | 3-concept | ✅ | |
| `comp.infinity` | O(n⁴) | ✅ | |
| `comp.hyper` | O(n⁵) | ✅ | |

### Generative (`comp.template`, `comp.grammar`, `comp.weave`, `comp.scheme`)

| Path | Internal | Has Handler | Notes |
| --- | --- | --- | --- |
| `comp.template` | `__metatemplate` | ✅ | Parametric expansion |
| `comp.generate` | `__metagenerate` | ✅ | Cartesian generation |
| `comp.scheme` | `__metascheme` | ✅ | Declarative scheme |
| `comp.scheme.clauses` | `__metaschemeclauses` | ✅ | Named clause form |
| `comp.grammar` | `__metagrammar` | ✅ | EBNF expansion |
| `comp.weave` | `__metaweave` | ✅ | Cross-module sweep |

### Agent Discovery (`comp.agent.*`)

| Path | Internal | Has Handler |
| --- | --- | --- |
| `comp.catalog` | `__metacatalog` | ✅ |
| `comp.ladder` | `__metaladder` | ✅ |
| `comp.agent.catalog` | `__metaagentcatalog` | ✅ |
| `comp.agent.ladder` | `__metaagentladder` | ✅ |
| `comp.agent.hooks` | `__metaagenthooks` | ✅ |
| `comp.agent.dedupe` | `__metaagentdedupe` | ✅ |
| `comp.agent.gaps` | `__metaagentgaps` | ✅ |
| `comp.agent.grammar` | `__metaagentgrammar` | ✅ |

### String Intrinsics (`comp.str.*`)

| Path | Internal | Has Handler |
| --- | --- | --- |
| `comp.str.contains` | `__strcontains` | ✅ |
| `comp.str.countlines` | `__strcountlines` | ✅ |
| `comp.str.splitcount` | `__strsplitcount` | ✅ |
| `comp.str.starts.with` | `__strstartswith` | ✅ |
| `comp.str.ends.with` | `__strendswith` | ✅ |
| `comp.str.len` | `__strcomptelen` | ✅ |
| `comp.str.eq` | `__streq` | ✅ |
| `comp.str.join` | `__strjoin` | ✅ |

### Type Construction

| Path | Internal | Has Handler |
| --- | --- | --- |
| `comp.make.type` | `__make_type` | ✅ |
| `comp.as.type` | `__as_type` | ✅ |
| `comp.bitfield` | `__bitfield` | ✅ |
| `comp.union` | `__union` | ✅ |
| `comp.select` | `__select` | ✅ |

---

## Directive Categories

| Category | Count | Purpose |
| --- | --- | --- |
| `optimization` | 7 | Runtime performance hints |
| `representation` | 4 | Layout control |
| `visibility` | 4 | Export, linkage, deprecation |
| `generation` | 1 | Derive macros |
| `bit_intrinsics` | 7 | Hardware bit ops |
| `hints` | 8 | Branch/memory hints |
| `introspection` | 25+ | Type/shape/why queries |
| `compile_control` | 11 | Comptime evaluation |
| `combinators` | 20+ | Exponential codegen |
| `generative` | 6 | Template/grammar/scheme |
| `agent` | 8 | Agent discovery |
| `c_interface` | 7 | C/asm interop |
| `string` | 8 | Comptime string ops |
| `type_construction` | 5 | Type building |

**Total registered directives:** ~130+ (counting all aliases across comp/meta/compiler)
**Unique semantic operations:** ~85
**With codegen handlers:** ~65
**Registered but unwired:** ~20
