# Pass 100 — DUO 0.1: THE SPECIFICATION

**Epoch 2 · Supersedes Pass 79 as the living authority (S17) · Every code block
is a conformance fixture · §22 marks everything described-but-undemonstrated —
this document does not confuse the two.**

Duo is a Lua-shaped, graph-semantic, agent-native systems language built on one
bet: **that a single mechanism — facts about values, flowing through relations,
realized by demand, proven by witnesses — can absorb everything other languages
ship as features, and outperform them because it knows more.**

Amended in place by Pass 101: guard chains (§6), the discharge ladder (§8), the
byte idiom (§15), `os.args`/`os.program` (§16), the toolchain host (§19), and
the `token` slot correction (§20).

---

# PART I — FOUNDATIONS

## 1. Axioms

```
A1  HPLS         maximum leverage, power, surface, and clarity per token;
                 a character that changes no meaning does not exist
A2  NNS          the grammar is CLOSED; capability = semantics of existing
                 forms, descriptors, values, edges, recognition
A3  ONE EDGE     every relationship is one graph fact; every spelling,
                 orientation, operator, and foreign form is its projection
A4  DEMAND       nothing physical without consumption — no table, closure,
                 pack, adapter, string, or return unobserved; demand carries
                 OBLIGATIONS (failures must be discharged)
A5  WITNESS      no optimization and no claim without an inspectable witness
A6  BRIDGES      open decisions carry provisional contracts all outcomes honor
A7  NATIVE-FIRST Duo semantics canonical; all foreign forms are projections
                 with provenance and trust; heritage is never a reason
A8  DESCENT      no ladder rung without its way back down
A9  ORDINARY     relations, worlds, protocols, lenses, namespaces, layers,
                 archetypes, rules: ordinary first-class values
A10 SELF-PROOF   the self-hosted compiler is the style guide and truth test
```

## 2. The Laws (final forms)

**LAW-CALL / FACE-CALL** — *Declarations are edges; calls are projections.*
Declare at the trie, operation-first: `read(number) = (lx, b) …`. Call at the
value, subject-first, mandatorily and auto-rewritten: `lx:read(number)(b)`,
`v:to(str)`, `xs:sort(cmp)`. Operation-first at call sites exists only as:
callable-as-value (`r = read[b] … r(lx)`), pass position (`map(to(str))`,
`fold(0, add)`), and world actions (`sh(cmd)`, `file.open(path)`, `print(x)` —
the world is the ambient subject). Operators outrank explicit relations
(`a == b`). *If you are holding the first argument, you are holding the
receiver.*

**LAW-STRATA (+2, +OP)** — Application groups are single-kind; each independent
decision is its own level (`map(symbol)(u32)`; litmus: *if the prefix means
something, it's a level*); same-kind grouping only for one-axis sets
(`any(i64, f64)`). *Comma = stratify; operator = select*: infix operand kinds
address realization edges (`i64 | f64` union, `u16 & positive` refinement,
`150 * ms` united value); no registered edge ⇒ diagnostic, never coercion.

**LAW-ROLE** — A descriptor is a level iff it is a choice operands cannot
determine; recoverable descriptors are roles — discovered, never spelled
(`len(s)`, `eq(a, b)`: zero levels). Relation families ARE the generics;
call-shape caching is the monomorphization; `<T>` never exists.

**LAW-SCOPE** — Assignment targets the nearest binding, else introduces
locally; no `local`. Worlds are lexical scope. Bare names never resolve to
receiver fields.

**LAW-ONE** — Every binding names exactly one concept; every boundary is
structural. **Identifiers are single lowercase words** (acronyms count: `json`,
`utf8`); the multi-word qualifier moves to a **LEVEL** (`read(number)`,
`skip(space)`, `any(i64, f64)`), a **HOME** (`wire.header`, `utf8.valid`,
`token.kind`), or **CONTEXT** (`limit`, where the scope says shift). No `_`
prefixes (privacy is scope, protocol face, or topology — names carry zero
semantics); no `_` discards (don't bind what you don't use); no case semantics
(no `Point`, no `MAX_N` — type-ness and frozen-ness are the axis's and
sealing's); no accessor prefixes (`get_`/`set_` — demand and lenses made them
lies); no companion descriptors (`*_kind`/`*_type` — inline at the field); no
axis words (`_by/_while/is_` — operand kinds select; predicates are bare
nouns). Nouns for pure values; verbs for effects; plurals for collections.
`grep [a-z]_[a-z]` outside numerals = 0.

**THE ANCHOR (S14 completed)** — Parens APPLY, brackets RETRIEVE — on tables
and callables alike. The anchor is one concept in three stances: **bare `@`
NAMES it** (the enclosing descriptor: `@{0,0}`, `next: @`), **leading `.` WALKS
from it** (three anchor contexts: method scope → my field `.pos`; argument
position → each element `map(.x)`; descriptor-expected position → the case
`tok.kind == .eof`), **postfix `X@rel` MOVES it and retrieves** (never
invokes). There is no prefix `@`: **directives do not exist** — the compiler is
values (`graph.descriptors`), worlds, facts (manifests), and queries (`why`),
reached like everything else. `:` is operator polymorphism under STRATA-OP:
shape-space operand = the IS edge (`name: shape`); callable-member = the INVOKE
edge (`a:m(x)`, leading `:m()` on the ambient subject).

**MOD-1** — The accumulator-module wrapper is erased: members hoist, tail
deleted, witnessed. A file IS the module; top level IS the surface, unmarked.

**DEMAND-RETURN / -ROUTE** — A body is an expression sequence; its value is its
final expression's; call-site demand alone materializes; `return` = early exit
or contract only; a void realization in `:`-chain position yields its receiver
(chain threading). Failures obey the doctrine of §8.

**CANONICAL LAYOUT** — The graph is truth; layout is a verified rendering (§3).
Fighting the formatter means the form is wrong.

---

# PART II — THE LANGUAGE

## 3. Lexical structure & layout — and the settlement of `end`

**Layout doctrine.** Duo does not have meaningful whitespace; it has
**canonical layout**: whitespace renders structure that lives in the graph, and
the toolchain *verifies rather than trusts* hand input. **Blocks close by
dedent (offside).** The settlement, with its reasons:

1. **`end` never existed in the graph** — block structure is edges; a closer
   token is a rendering choice, and rendering choices are the formatter's.
2. **The failure mode that justifies closer tokens is structurally unreachable
   here**: Python's sin is *writer-inferred* structure (a mis-indent silently
   means something else); Duo's ceilings (100 cols, ≤2 call depth, 0 nested if,
   no one-liner nesting) deny the deep shapes where offside fails, so
   indentation matching no legal shallow shape is a **diagnostic, never an
   alternate parse**, and the mandatory canonicalizer repairs input on ingest.
3. **The precedent was already set**: newlines have terminated one-liners since
   the endless rule — either layout is structure or every statement needs a
   terminator, and the second is strictly worse.
4. **Transition is measured, not asserted**: a written `end` is accepted and
   deleted (a human resync anchor for editing outside tooling); the token
   leaves the writing dialect when resync usage measures ~0.

Mechanics: statements end at newline except inside open `( [ {` (no
trailing-operator continuation; the formatter introduces groups to wrap);
tabs/widths normalized to 4-space canonical; blank lines insignificant; `else`
binds by column.

**Tokens with zero semantics, by design and exhaustively**: inter-token
whitespace (rendering), `_` inside numerals (visual grouping), comments (`--`;
but see docs-as-fixtures — canonical example blocks compile). Everything else
on the page changes meaning; that is the A1 audit and it now passes.

**Literals**: numbers need a leading digit (`0.5`); `1_000_000`, `0xff_ff`,
`0b1010`; `150 * ms` (units are descriptors; no unit literals); strings
interpolate — `"{expr}"` holes are full expressions (`"{fixed(2)(x)}"` — format
specs are sections in holes); raw `[[…]]` means raw; `'a'` byte literals.

## 4. The character catalog

```
.    walk from the anchor (leading: my field .pos / each's map(.x) / the
     case == .eof, by position) · data access a.b · a.m = bound member value
:    IS (shape-space operand: name: shape) · INVOKE (a:m(x); leading :m()
     = sibling on ambient subject) — operand space selects, position-total
@    the anchor: name it (bare), move it (postfix X@rel — retrieval only)
( )  APPLY (functions, dispatch tables, descriptors=construction, levels)
     · grouping · parameter slots
[ ]  RETRIEVE (index t[k], trie to[str][point], gap[23]) · raw strings
{ }  tables: data (=), descriptors (:), constructors desc{…}, brace-call
     named args, destructuring {a, b} = x, world/bundle literals
=    HOLDS (value binding; slot defaults; case payload) — vs : IS
|    union edge (descriptor operands: i64 | f64, t | nil, "a" | "b") ·
     bor (integer operands)
&    refinement edge (u16 & positive, str & utf8.valid) · band (integers)
..   string join (existing string bindings ONLY) · spread {..base, x = 1}
     · pack params (..xs) and spread f(..xs)
#    len operator face (#s; bare len = value face; s:len() normalizes)
+ - * / % ^ << >> ~    arithmetic/shift roots (operand-selected; * with a
     unit descriptor = united value)
== != < <= > >=        eq/cmp projections (derived structural for sealed
     records; identity for anonymous data tables)
and or not   operands returned (or IS nil-coalescing; facts narrow); not
     → bool; mixed and/or parenthesize
--   comment   ;  one-line induction tail (the only ; in the language)
"    interpolating string   '  byte   [[ ]]  raw
```

## 5. Bindings, callables, parameters, contracts

```
x = expr                      nearest-binding assignment; else local intro
total: f64                    statement-position shape (checked when held)
f = (x) g(x)                  THE CALLABLE — one concept (the realization
                              edge). Method = position anchors a subject
                              (lens context; no self param). Constructor =
                              the descriptor's call edge. Closure = a
                              callable whose WORLD-FRAGMENT is non-empty:
                              capture is a world fact (bundle — queryable
                              f@world, injectable, serializable, erased
                              when empty). "Closure" is a measurement.
connect = (host: str, port: u16 = 443, tls: bool = true)
                              params are SLOTS: shape + default; brace-call
                              supplies by name; positional fill is canon
gather = (..xs) xs:sum()      pack param; f(..xs) spreads
parse = (lx): ast | error     the return contract: a DEMAND DESCRIPTOR —
                              CDR (B-13) realizes the last expression
                              through ONE direct edge (x:to(T) restating it
                              is erased); DEMAND-ROUTE (B-15) routes
                              unbound failures to it. Bare positions never
                              coerce and never route; transitive search is
                              illegal everywhere, forever.
```

A one-expression body IS one line (mandatory); a multiline body that is one
expression plus ceremony (once-used temp, contract-restating conversion,
trailing return) collapses mechanically (TMP-1 + CDR-erasure + demand-return).

## 6. Control

```
if cond ... else ...                     multiline: offside closes
if count == 0 return nil, error.empty    one-liner: newline terminates
if v = f() use(v) else report(err)       binding condition IS the pattern match
if v, err = parse(s) use(v) else log(err)   correlated refinement
if t = f() and valid(t) and u = g(t) ...     GUARD CHAINS (Pass 101): `and`
                                             after a binding = correlated
                                             guard; bindings and guards
                                             interleave; failure of any link
                                             selects else; `or` never chains
kind = if tok.keyword keyword else name  expression-if IS the ternary
while b = cursor:next() mix(b)           consumption loop
while (i += 1) <= n consume(i)           clause-embedded induction
while more(s) consume(s); i += 1         the one ;-tail
for i, v in items visit(v)               iter packs; no pairs/ipairs ever
for i in range(0, n) f(i)                ranges own counting
for x in iterate(seed, step):take(alive) use(x)   init-and-step as pipeline
for a, b in zip(xs, ys) ...
```

Clauses are self-delimited (no top-level parenless application in clause
position); one-line body = one statement (+1 induction tail); no nesting;
dispatch tables replace elseif ladders always.

## 7. Data & shape

```
span: {                          ":" = semantic identity: sealable, hierarchy,
    start: u32                   satisfaction, derivation, projection
    stop: u32                    X8: ≥2 named fields → one per line, always
    width = () .stop - .start    (named fields are independent facts)
    contains = (p) .start <= p and p < .stop
    format(sink) = (out) out:write("[{.start}, {.stop})")
}                                eq/hash/to(str)/cmp/clone DERIVED; = false blocks
handlers = { ... }               "=" table = data (identity eq)
t = token{ kind, span, text }    same-name shorthand mandatory; positional
                                 fill canon: point{ 3, 4 }, lexer{ src, "x" }
node: { value: i64, next: @ }    recursion = the named anchor
n2 = { ..base, x = 1 }           spread: one pack edge, right-biased
{ name, age } = user             destructuring = shape projections = imports
kind: { name, number, eof }      enum: inline nominal case-set is the default;
tok.kind == .eof                 cases INFER from descriptor-expected position
token{ kind = .eof, ... }        (==, construction, dispatch keys, contracts,
@{ [.eof] = finish }(tok.kind)   payload construction .circle(3.0)) — NEVER
                                 in argument position (map(.eof) is a lens);
                                 no expected shape ⇒ diagnose: qualify
                                 token.kind.eof. NO companion descriptors.
method: "get" | "post"           literal unions for wire-string domains
body: str | nil                  the optional; never t?
digit = (b) b >= '0' and b <= '9'    predicates: bare nouns, four roles —
port = u16 & digitish            filter take(digit) · guard if digit(b) ·
                                 refinement u8 & digit · generator constraint
```

Matching without match: dispatch tables (`@{ [.circle] = (c) pi*c.r^2,
[.rect] = (r) r.w*r.h }(s)` — exhaustive, virtualized), descriptor-keyed type
switch (`@{ [str] = f, [i64] = g }(v)`), narrowing (`if c = to(shape.circle)(s)`),
payload lenses. Representation is demand-selected (interned tag / niche nil /
tag+payload / erased; niches compose).

## 8. The failure doctrine (complete)

```
DECLARE   : t | error            B-12: failure descriptors imply the pack;
                                 the structural nil is UNWRITTEN. | nil only
                                 when nil is a SUCCESS; all three when both.
PRODUCE   nil, error{ code, span, detail = "…{ctx}" }
                                 own block; construction is cold-path
CONSUME   if v, err = f(x) use(v) else report(err)
ROUTE     inside a declared failure contract, an UNBOUND failure position
          routes (early-exits with the pack): tok = lx:token() — no
          forwarding plumbing exists in Duo. Callee failures ⊆ contract's
          or diagnostic; binding takes precedence; why(return) explains.
OBLIGE    B-14: an unconsumed failure position is a DIAGNOSTIC — bind it,
          route it, or drop it by name. Silent loss is unexpressible.
LADDER    discharge precedence (Pass 101): (1) explicit binding of the
          failure = the handler; (2) a binding CONDITION is itself a
          discharge (failure selects else — routing never fires inside
          conditions); (3) declared contract ⇒ ROUTE; (4) else DIAGNOSE.
WRAP      judgment stays explicit: else return nil, error{ cause = err, span }
CHAIN     spread + cause; report renders the chain via format(sink)
```

## 9. Relations, the trie, protocols, the algebra

Declare at the source or any trie place; `false` blocks, `nil` removes;
subtrees are tables; enumeration is demand (`for src, conv in to[str]`).
**Join-keyed edges**: descriptor-space keys accept unions and refinements —
`to(str)(u8 | u16 | u32) = digits`, `to(hex)(int & unsigned) = hexdigits`;
precision: exact > refinement > union > family. Exact layers: `meta(level)` —
ordinary curried values; writes capability-gated by world facts.

Protocols are constraint tables; **anchoring is the homomorphism**:
`point@ordering → (bundle, nil) | (nil, missing)`; distributes over `&` (merge;
missing unions), `|` (first success + witness); implication is a lazy memoized
preorder; **modus tollens prunes**; modules satisfy protocols
(`backend@driver`); namespaces anchor as populations (`shc@wire`); negative
requirements (`{ io = false }`) make architecture one expression
(`ward@allocation_free`). Bundles are world fragments — injectable,
spreadable, demand-erased.

The algebra is user-writable edges: `implies(cmp)(eq)`, `lift(seq)` (functor
lifting: element edges give container edges, witnessed, overridable),
`orient(encode)(decode)` (printer↔parser duality), `weight(cost) = additive`
(the closure is a semiring; `paths(a)(b)` ranked, discovery ≠ application,
written composition joins provenance), `derive`, `rewrite`, `lower(target)`,
`canon` (quotient descriptors). Optics = one projection identity: lenses
(product) · prisms (narrowing edges) · traversals (`fields(int)(@)` selectors)
— composed paths lower to fused loops, zero optic objects.

## 10. The family registry (complete; no `__` name ever)

*Application/construction*: `call` (descriptors included — construction; `init`
deleted) · *places*: `place` (one keyed-place edge; load/store/update/borrow/
observe project; `get set has` over it) · *identity*: `eq cmp hash len default`
· *lifecycle*: `clone copy share ref deref release` (release IS drop; gc/close
= tiers 3/2) · *meta*: `meta(level)` · *rendering/data*: `format(style) to from
encode decode scan` · *iteration*: `iter(variant)` · *operator roots*: `add sub
mul div mod pow neg band bor bxor bnot shl shr concat eq cmp len` ·
*concurrency (spec'd)*: `suspend resume` · *system*: `lower validate
canonicalize realize rewrite derive observe measure migrate lift implies orient
weight archetype equiv stage gen add why todo`. **Non-families (structural,
never hookable, with reasons)**: truthiness (readability at a distance),
resolution (scope poisoning), assignment form, identity, demand. Weak refs: GAP
against the memory bridge. New customization points arrive as a row here or
nowhere.

## 11. The semantic model

**Resolution** (8 rungs): lexical shadow → instance layer (capability-gated) →
exact descriptor relation → hierarchy → package extension → authorized foreign
→ generated → dynamic → structured failure; exact > refinement > union > family
within rungs; `false` blocks below. **Sealed-world collapse**: sealed ∧ frozen
∧ no shadow ∧ instance-off ∧ frozen world ⇒ rung-3 proof — hot paths live here,
and the **sealed-collapse rate** (call sites at rung ≤3 in SHC/Ward) is a
tracked metric with a floor, or the predictability claim retires.

**Knowledge**: correlated packs; path-sensitive facts; guard discharge and
**fact upgrading** (sorted/unique/dense flow → binary search, merges,
dedup-skip: asymptotics from facts); demand descriptors with obligations;
virtualization (table syntax ≠ table identity unless observed). **The closure
is a query engine** — memoized by witness dependencies, persistent, budgeted
with tombstones; demand reachability tree-shakes optimization itself.

**THE CALLABLE = the edge**; closure = non-empty world-fragment;
specialization = fact-flow on constant fragments; durability ships fingerprint
+ bundle. **Enumerability is the table/function axis**: a table is an
enumerable callable, a function a non-enumerable table; apply/retrieve/anchor
shared; `x@iter` answers the type question; the boundary crosses
(dispatch→apply, gen→sample, orient→invert). Scope = table = world.

**Memory** (bridged): non-moving E1 until the GC record; drop ladder via
`release`; `ref/deref` proven-fast or safe-slow, explained; `copy` ⇒ memcpy;
ownership-driven mutation (`xs:sort()` in-place under uniqueness — linearity
makes it observationally sound — persistent under sharing); effect-region
arenas. **Effects/concurrency**: effect-conditioned realization (no colors);
task scopes ARE lexical scopes; cancellation/deadlines = world facts at
suspension points; virtual time = clock-in-world; metered worlds; atomics =
place ops with ordering facts; layout facts (`& packed & le & at(a) &
volatile`) — parse-by-casting, registers-as-places; location explicit forever.

## 12. Concluded boundaries

```
B-1  0-based, half-open; s[i, j] = [i, j); no negative wrapping
B-2  truthiness: false/nil falsy; all else truthy — never hookable
B-3  and/or return operands (or IS nil-coalescing; slot defaults deleted
     the abuse; facts narrow the result shape); not → bool
B-4  division operand-selected: i64/i64 truncates (overflow regime); any
     float ⇒ float; % matches; no //
B-5  .. strict strings; repair = interpolation
B-6  == resolves eq: structural for sealed records; identity for data tables
B-7  membership: :has (operand-selected); `in` iteration-only
B-8  t[k] = nil removes; absence over sentinels
B-9  (..xs)/f(..xs); #pack = arity = static fact
B-10 print/min/max ordinary; min/max cmp-derived, binary + fold faces
B-11 string cmp byte-lexicographic; locale is injected
B-12 result unions imply the pack; structural nil unwritten
B-13 CDR: declared shapes realize through ONE direct edge, per position
     (failure positions never convert); literals are the special case;
     bare positions never coerce; numeric str-edges tolerate whitespace
B-14 OBLIGATION: unconsumed failure = diagnostic (bind / route / named drop)
B-15 DEMAND-ROUTE: declared contracts route unbound failures; ⊆ or diagnose;
     no contract, no routing
LEN  a family: # operator face, len value face; units per descriptor
TEXT str = bytes & utf8.valid; iteration explicit by unit; no default iter
OVFL overflow = realization dimension: checked default; wrap/saturate by
     policy fact; proven away under range facts
TAIL proper tail calls guaranteed
```

## 13. The performance doctrine — why ≥ C is the design target

**C's optimizer is bounded by what C can know; Duo's by what is true.** Every
mechanism below converts information C discards into speed, and every one
terminates in machine code with no runtime between — and **the descent is DUO
TO THE BYTE** (Pass 103, NO FOREIGN WAIST): graph -> realize -> flow ->
lower(target) -> encode(target) -> encode(elf/macho/pe/wasm) -> link, all DNIR
transformed by family edges; the ISA is descriptors with layout facts (encoding
= the codec matrix pointed at silicon); registers are places; the linker is
graph merge. C is never an intermediary, LLVM never a dependency; foreign
toolchains are CI ORACLES only; C/TS/Rust emission is an interop EXPORT at the
edge:

**The compression law (Pass 104)** — why owning the descent is weeks-class and
not decades-class:

```
incumbent ≈ (passes × invariant coupling) × targets × dialects × legacy
            + semantics archaeology + serial lore accumulation
duo       ≈ Σ independent checked edges + data-described targets
            + 0 (archaeology deleted) + parallel mined lore / gate throughput
```

Their optimizer INFERS; ours READS. Alias analysis, UB reasoning, loop-idiom
recognition and devirtualization are archaeology for facts the source discarded
— Duo never discards them, so the hardest half of optimization is not solved
faster, it is not a task. Mutable-IR pass coupling becomes admission of
independent checked rewrites (legality is data, not folklore). The dialect /
flag / legacy-target museum is not built. Serial human lore becomes search under
gates: a peephole is an edge-shaped, law-bounded, oracle-checkable unit, and
Duo is an admission gate with a language attached.

1. **Sealed collapse** makes hot-path dispatch static (rung-3 proofs), erasing
   the "dynamic language" tax where it matters; the collapse *rate* is a public
   metric.
2. **Demand erasure** deletes what C programmers must hand-avoid: unobserved
   tables, packs, adapters, closures (empty fragments), format machinery — not
   optimized, *never built*.
3. **Fact-upgraded asymptotics**: sortedness, uniqueness, density, and range
   facts select algorithms and drop checks C cannot drop without unsafe
   folklore (bounds under range proofs, overflow under interval proofs,
   branchless niches).
4. **Fusion as law**: pipelines, traversals, and composed edges lower to single
   loops (rewrite edges, witnessed) — the abstraction penalty is a theorem with
   the manifest as proof object.
5. **Layout facts** give C's control of representation (packed, endian,
   at-address, volatile, arenas, memcpy-by-`copy`) *plus* proof-carrying views.
6. **Ownership-driven mutation** gets in-place performance with persistent
   semantics where sharing exists — the fast path C takes and the safe path C
   skips, one name.
7. **Whole-graph knowledge**: join-keyed specialization, closed-world enum
   collapse of bundles, cross-module inlining by edge identity, PGO ingested as
   facts — link-time optimization is the *resting state*, not a flag.
8. **The honest floor**: every fallback (dynamic rung, safe-slow deref, checked
   overflow) is *witnessed and explained* (`why`), performance regressions are
   *bisected by fact-diff* (blame is a query, promoted to a launch
   requirement), and **every claim in this section pays the fixture toll** —
   the benchmark suite is part of the conformance corpus, and §22 lists all of
   it as owed, not owned.

Anticipated objection, answered in place: *"a language with a dynamic rung
cannot beat C"* — the rung exists to be *measured out of hot paths* (G6 gates
them at rung ≤3), and the counter-question is the design: what does C do with
the facts it cannot express? It discards them. Duo compiles them.

---

# PART III — PRACTICE

## 14. The pattern book (P1–P16)

**P1 module** — a file; top level = surface, unmarked; contracts via protocol
faces; bodies use bare names (destructure at top) and receiver faces; dotted
std paths in bodies are denied. **P2 descriptor** — fields then slots, X8
lines; write `format(sink)`; derive the rest; block with `false`. **P3 errors**
— the §8 doctrine; construction cold-path, own block. **P4 iteration** —
pipelines first (`vs:filter(active):map(score):sort()`, `vs:max(.score)`,
`vs:fold(0, add)`); pinned surface, one name per op, operand-selected: `map
filter fold each find any all count take drop until sort max min group join
push pop sum zip windows chunks bump iterate`; loops for cursors/effects/exit
protocols. **P5 dispatch** — keys → callable table (cases `.eof`, literals,
descriptors); never elseif. **P6 conversion** — declare `to(t)` at the source or
join; consume `x:to(t)`; compose explicitly. **P7 options** — brace call +
options descriptor. **P8 bundles** — anchor and inject (`run(task,
point@ordering)`); never dicts or op-params. **P9 predicates** — bare nouns,
four roles. **P10 hooks & codegen** — edges (`lower(t)(op)`); bulk via `for d in
graph.descriptors if d@wire to(json)(d) = gen(d)`. **P11 script** — shebang;
top-to-bottom; `os.args`; final pack = exit code. **P12 checks** — `check(…)`
anywhere: test = assert = contract = doc = optimizer evidence = generator seed;
stage = where the proof lands. **P13 state machines** — `next(state)(event) =
handler` tries; exhaustiveness and diagrams free. **P14 chaining** — TMP-1 and
the subject-run collapse; name a value only if used twice, re-read, or the name
explains. **P15 edge-first** — converts/renders/parses/encodes/validates/
varies-by-target ⇒ RELATION; a named function is a dead end. **P16 selector
bodies** — per-field work is `fields(shape)(@)` traversal folds, never hand
loops.

## 15. The anti-canon

**Deny (grep the diff; all rows absent):** interior `_` in identifiers (outside
numerals) · any uppercase identifier · `_` prefixes and discards · companion
`*_kind/*_type` · `get_/set_/compute_` · axis names (`sort_by take_while
is_digit`) · prefix-`@` anything · `.new( new = .create( make_` · `string.byte
string.char string. table. std.string std.script require local function fn def
let const var class impl trait interface enum match switch try catch -> => ?.
?: T? |> <T> type X = type( pairs( ipairs( pcall tostring( tonumber(
setmetatable getmetatable _G gmatch gsub` · module aliases and
`alias.fn(subject, …)` · `" .."` beside literals · `end`-reliance (accepted,
deleted) · single-use next-line temps · same-subject void runs unchained ·
elseif kind-ladders · sentinels · per-field hand loops · failure-forwarding
plumbing (`if err return nil, err` — routing exists) · mixed-kind and
two-decision groups · trailing `return expr` · wrappers · any non-`.duo` file.

**The graveyard (load-bearing absences):** function/class/import/match/try/
trait/macro/ternary syntax · `local self type req new init end`(retiring) ·
`__` names and the metatable API · regex and Lua patterns · pipe operator ·
named-arg/default syntax (slots and brace-calls instead) · generics syntax ·
lifetime syntax · trait objects (bundles → enums) · implicit conversions and
transitive search · `?`/`?.`/`//` · slice syntax (`all` is a value) ·
`satisfies/refine/has` primitives · operation namespaces (`std.string`) and
activity junk drawers (`std.script`, `util`) · **C-as-intermediary,
LLVM-as-dependency, runtime-hosted execution** (Pass 103) · visitor/pass-pipeline compiler
architecture · plugin/macro hook APIs (edges) · test/build/logging frameworks ·
directive surfaces (`@comp`, `@assert`, `@why`, `@descriptors`) ·
visibility-by-naming · closure-as-a-kind · location transparency · uppercase.

**Byte idiom (Pass 101):** `s[i]` IS the byte; `string.byte(s, i)` → `s[i]`;
`string.char(b)` → `str{ b }`; ranges → `s[i, j]:bytes()`. There is no string
library — there is a string descriptor, and you are holding one of its values.

## 16. The standard environment

Descriptors carry their surfaces (`str view bytes seq map set` sealed, with
curated miss-repairs); **no operation namespaces, no junk drawers** —
subjectless residents are families (`range zip scan gen min max len print
iterate why add todo …`) and genuinely subjectless worlds (`std.math std.fs
std.io std.mem std.os units graph`). Strings: `split trim starts ends find
replace take until join chars bytes graphemes to has` + `#` + `s[i, j]` views;
extraction ladder: predicates → `scan(grammar)(s)` → cursor loops; **no regex
ever**. `os.args` = the argument list, 0-based; the program path is
`os.program`. Processes: `sh(cmd)` → `proc{ out, err, code }` with
demand-selected observation (consuming `.out` IS the capture; unobserved
streams never buffer). Collections: fact-selected realizations
(`why(realization)` explains); order/uniqueness facts flow; views everywhere;
relational families fuse columnar.

## 17. Metaprogramming & leverage

The ladder, run before writing anything (stopping early is the violation): edge
exists? → derivable? → liftable? → a hook? → a projection? → a bundle? → a
section/lens? → a dispatch table? → graph iteration? → erased by demand anyway?
Staging is structural (folding = facts; placement = demand); the compiler
surface is ordinary at every stage: `check`, `why(question)(subject)`,
`graph.*`, the `add` family (`add(module)(…) add(slot)(…) add(case)(…)
add(check)(…) add(gap)(…)`), `todo(gap[23])`, `lower[arm64]` — browsable,
extendable, never wrapped. Templates are tables with lens-addressed holes;
archetypes are edges; negative edges are architecture; checks are optimizer
facts; sandbox = shadowed world roots.

## 18. Cross-language & monoglot

Authored source is 100% Duo; the bootstrap ledger is the sole exception and
only shrinks; foreign code lives only there and in gap exhibits. The IR is a
descriptor family; projection pairs are INTEROP EXPORTS + ingestion — **never
the compile path** (Pass 103; emission `lower(target)` IS the native backend,
and C/TS emission is a product for consumers; ingestion: C headers / Rust
metadata / TS types → rung-6 descriptors with provenance and trust);
zero-adapter ABI on proven layout
equality; protocols ⇄ trait bounds; schemas round-trip with `migrate(v1)(v2)`;
one conformance suite runs differentially across targets. Rosetta in one line
each: Lua keep the feel, lose the library; Rust traits→protocols, `?`→routing,
`dyn`→bundles→enums, macros→graph iteration; TS types erase, facts compile;
Python comprehensions→pipelines, dunders→slots; C/Zig headers ingested never
authored, comptime→facts, inline asm never (`lower` is the door); Go's fmt
culture completed by the canonicalizer.

## 19. Enforcement

**The host (Pass 101):** one graph service, N protocol front-ends — a single
`duo` toolchain owning the graph store, query engine, witnesses, canonicalizer;
LSP = queries (hover=why, references=dependents, diagnostics=the audit), MCP =
the same queries + the `add` family (the agent surface IS the emission API),
tree-sitter = a generated grammar projection (output, never authored), fmt =
the canonicalizer's face, Ward = the in-repo proof application. Sequencing:
graph core → fmt → LSP read-only → MCP → tree-sitter → Ward, each stage
dogfooding the last.

**Epoch protocol**: this document + the regenerated context file are the law;
archives excluded from sweeps; objections citing superseded rules are void;
genuine conflicts cite the rule ID and proceed canonically; every ruling
regenerates the context file in the same commit or is unshipped.

**The stack**: L1 grammar+firewall → L2 structural erasure (MOD-1, faces, arg-1
rewrite, subject-run collapse, `end`/ceremony deletion — applied, not reported)
→ L3 archetype-first → L4 semantic emission → L5 adaptive hot-list.

**AUDIT v3** ships with every diff (lexical/case/directive/deny greps at zero;
face+arg-1, constructor, alias, concat, stdlib, result, enum,
obligation/routing, end, temp, field, return, edge, strata, per-field scans;
shape match; RUNG REPORT; gap row; fixture row) or the diff is rejected unread.

**Descent**: four exits; stubs are `todo(gap[nn])` or bodiless declarations; the
gap register dedupes by frequency with `-- gap[nn]` citations. **Gates** G1–G11;
**metrics**: native ratio · monoglot census · gap velocity · deny-rows-to-
structure · sealed-collapse rate · blocks-passing/blocks-total.

## 20. The golden corpus 0.1 (pattern-match only from these)

```
-- ward/leb128.duo
{ error } = wire.failure

decode(u64) = (cursor): u64 | error
    value = 0
    shift = 0
    while b = cursor:next()
        if shift > 63 return nil, error.overflow
        value = value | ((b & 0x7f) << shift)
        if b & 0x80 == 0 return value, cursor
        shift += 7
    nil, error.truncated

encode(u64) = (v, out)
    while v >= 0x80 out:write((v & 0x7f) | 0x80); v >>= 7
    out:write(v)
```

```
-- shc/lex.duo
token: {
    kind: { name, number, string, symbol, eof }
    span: span
    text: view
    format(sink) = (out) out:write("{.kind} {.span} '{.text}'")
}

lexer: {
    src: view
    pos: u32
    here = () span{ .pos, .pos }
    peek = () if .pos < #.src .src[.pos] else nil
    next = ()
        b = :peek()
        if b .pos += 1
        b
    skip = (p) while b = :peek() and p(b) .pos += 1     -- guard chain
    token = (): token | error
        :skip(space)
        while b = :next()
            if digit(b) return :read(number)(b)
            if r = read[b] return r(@)                   -- callable-as-value
            return :read(symbol)(b)
        token{ kind = .eof, span = :here(), text = "" }
}

digit = (b) b >= '0' and b <= '9'
```

```
-- shc/parse.duo (demand-route shown)
parse = (lx: lexer): ast | error
    tok = lx:token()                             -- failure ROUTES
    node = grow(tok)                             -- failure ROUTES
    if t2, err = lx:token() attach(node, t2)     -- handled by choice
    else return nil, error{ cause = err, span = node.span }
    node
```

```
-- wire/json.duo — leverage by absence
wire = { encode(json), decode(json) }
user: {
    id: i64
    name: str
    tags: seq(str)
}
encode(json)(secret) = false
send = (out, u: user) u:encode(json):each(out.write)
```

```
#!/usr/bin/env duo
-- tool/wordcount.duo
{ lines } = std.fs
counts = {}
for line in lines(os.args[0]) for w in line:split(" ") counts:bump(w)
for e in counts:sort(.value):take(10) print("{e.key}: {e.value}")
```

## 21. Anticipated objections, answered or owned

*Silent error loss under laziness* → unexpressible (B-14/15). *Orphan edges
across packages* → bridged with a binding contract: detected at composition,
provenance names claimants, world-local shadowing resolves (full law owed,
§22). *Non-local performance under demand* → true, and priced: `why` +
fact-diff blame are launch requirements. *Reading requires shape knowledge* →
true tax of LAW-ONE's economy; ambiguous-operand lint + near-miss table
mitigate; sealed-collapse metric keeps "predictable" honest. *Offside will
misnest* → structurally unreachable (ceilings + verification, §3). *Mutation
duality is spooky* → linearity; no alias exists to observe it. *Dynamic can't
beat C* → §13; the rung is gated and measured. *Unfamiliarity tax* → a declared
bet with a falsifier (fire-count telemetry retires rules that convict
themselves). *Nothing runs* → correct: §22.

## 22. Status ledger & open bridges (described ≠ demonstrated)

**Running: nothing.** The audit artifact is the interim pipeline. **Spec'd,
owed**: **BACKEND MATURITY** — the marquee item, reframed by Pass 104 as **the
mining loop's throughput**, metered by G-D1..G-D6: days/weeks-class to baseline
(evaluator fixed point, flow differential, generated ISA fidelity, end-to-end
oracle parity), worklist-shaped past it, with REWRITES-ADMITTED-PER-WEEK as the
standing falsifier — if that number is low the Compression Thesis is wrong and
this ledger says so — plus **the Duo evaluator** (bodies are tables; evaluation
is a fold); the graph service + toolchain front-ends (LSP/MCP/tree-sitter
projection); canonicalizer + L2 rewrite set; archetypes; the add family;
hot-list telemetry; witness store + `why`; `scan`; the differential harness;
the benchmark corpus of §13. **Open decisions (bridged)**: memory management
(E1 bridge holds) · concurrency memory model · cross-package edge coherence
(orphan law) · weak references (against the memory bridge) · overflow
measurement · grammar formalization + resolution-cost analysis (metered by the
sealed-collapse floor) · the graph's concrete schema. **The toll**: every claim
herein pays one running fixture as the corpus lands; blocks-passing/
blocks-total is the project's first honest number, and §13 is not exempt.
**Owed (Pass 106) — the artifacts a trained reader checks in the first five
minutes, none blocked on implementation, all blocked on being written**: the
FORMAL GRAMMAR + generated parser + ambiguity argument (the first credibility
artifact) · the COST MODEL (strict evaluation order as small-step semantics;
demand governs MATERIALIZATION, never evaluation order; the guaranteed-erasure
list separated from best-effort optimization) · the SOUNDNESS PAGE (three-state:
proven / runtime-checked / diagnostic — no silent fourth state) · the NUMERICS
PAGE and the TEXT PAGE (the boring tables experts check first) · the DIAGNOSTICS
SPEC (to a newcomer the first error message IS the language) · the BORING CORPUS
(twenty everyday programs — the golden corpus is expert-flavoured) · the
RELATED-WORK PAGE (Unison, Koka, Zig, Hylo, Mojo, Lean, Erlang, Lua — publishing
it converts every "have you heard of X" into "yes, section 5") · the GOVERNANCE
PAGE + license + NAME RESOLUTION. **Release sequencing: the evaluator ships
first** (G-D1 is days-class by our own claim), with the REPL as its face —
running-thing → spec → thesis, inverting how it was built, because a hundred
specs lose to two hundred running lines.

**Owed (Pass 105)**: the PUBLIC CLAIMS DASHBOARD — blocks-passing/blocks-total,
oracle-parity tables, admission velocity, sealed-collapse rate, ledger size.
The pitch deck and the CI dashboard are the same artifact, and a release
without its numbers is unshipped.

> **Repository note (2026-08-08).** "Running: nothing" is the spec's
> conservative stance and is now inconsistent with observed reality in this
> repository: build gates, unit tests, a benchmark suite and a direct-native
> differential corpus all execute. The correct replacement is a GENERATED
> capability table — described → parsed → semantically checked → C path →
> direct-native → differentially proven → canonical — populated from the
> native differential corpus rather than asserted.
>
> **That table now exists: `zig build capability-table`**
> (`scripts/capability_table.duo`). It runs the compiler once per rung per
> fixture over the same corpus `native-differential` gates, so no cell is a
> claim someone maintains. Do not paste its numbers here — read them from a
> run, because a number transcribed into prose is exactly the drift this
> section was written about. Two things the first runs established, which are
> properties of the method rather than the status of the day:
>
> - `canonical` came out **59**, and `scripts/native_differential.duo`
>   independently reports **59 agree**. Two derivations, one number, neither
>   reading the other. That agreement is what makes the table evidence; if the
>   two ever disagree, one of them is lying and the disagreement says which
>   rung to look at.
> - The `described` rung — does the fixture say what it proves — is the one
>   the corpus is worst at, and it is the first rung. Evidence that runs but
>   does not speak is how a corpus decays into folklore.
>
> The table's own first version was wrong, and the way it was wrong is the
> lesson: its `parsed` rung ran `duo fmt` on the fixture, `duo fmt` rewrites in
> place, and `duo fmt` deletes comments (gap[048]). One run reformatted all 68
> corpus files, which broke 13 of them and stripped the `-- expect: N` headers
> `native_only/` depends on — and the table then reported 46 instead of 59 and
> `described` 0 instead of 16, confidently, from evidence it had destroyed
> itself. **A measurement must not be able to write to what it measures.** It
> now copies first.

## 23. Entailments (the theorems 0.1 owes)

One discriminator · dynamism is un-proven-ness · the anchor (name/walk/move) ·
worlds are the universal dependency mechanism · the trie is every registry ·
zero-cost abstraction is a theorem with the manifest as proof · one engine
wears every tool's badge · one assertion, five roles · the language is defined
by its deletions · homoiconic from the table side · build/run is one stage
tower · the language is its own agent harness · floor and ceiling are one
subset · large-scale change is graph surgery with proofs · scope = table =
world, and enumerability is the axis · the callable is one thing · routing
composes from demand.

## 24. Version discipline

**Release gates (Pass 105 §4)** — strategic invariants as anchored protocols on
the toolchain itself, red in CI until true: `std@{ ambient = false }` (U1,
capability scan — the measured baseline is gap[061]) · `build@deterministic`
(U2) · `dnir@migratable(v_prev)` (U3) · `graph@{ colored = false }` (U4) ·
`registry.open = gate(coherence.closed)` (U5 — the registry opens AFTER the
coherence law closes; ecosystem splits are forever) · `std@deprecation_only`
(U6) · `release@published(metrics)` (U7) · `toolchain@{ foreign = ledger |
oracle }` (U8). The unretrofittable list is chosen by one test: has any
language ever successfully added this after release? The answer under each is
no.

0.1 means: the semantic surface of Parts I–III is frozen against everything
except (a) the bridged decisions of §22, which land through their contracts,
and (b) rules that convict themselves by telemetry (the empirical-design loop),
which retire with a recorded post-mortem. Any change regenerates the context
file in the same commit; any claim lands with its fixture; any new
customization point arrives as a family-registry row or not at all.

---

*The closing sentence of Duo 0.1: one character where meaning changes and none
where it doesn't; one word per name and one concept per word; choices in
levels, values in roles, boundaries in structure, failures routed or held but
never lost; nothing built that nobody asked for, nothing named that navigation
could reach, nothing claimed that a fixture won't collect — and nothing above
the graph but renderings of it.*
