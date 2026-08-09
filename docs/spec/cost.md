# duon 0.1 — The Cost Model

**Owed by Pass 100 §22 · commissioned by Pass 106 §1 · normative.**

Pass 106 states the problem exactly: *"Fifty years of 'sufficiently smart
compiler' burns — Haskell's space leaks specifically — mean DEMAND triggers a
trained allergy. The answer cannot be 'trust the witnesses'."*

So this document does not ask for trust. It states an evaluation order, proves
what demand is allowed to touch, publishes a short list of erasures that are
guaranteed and a longer list of optimizations that are not, and gives the
worst-case table an embedded or realtime engineer needs before adopting
anything. §7 then says which of it this repository does today, measured.

**The one sentence.** Duo is strict. **Demand governs MATERIALIZATION, never
evaluation order.**

---

## 1. Strict evaluation, as small-step semantics

Values and expressions:

```
v ::= number | byte | str | bool | nil | table | callable | pack
e ::= v | x | e.n | e[e] | e(e,…) | e:n(e,…) | e op e | not e
    | { field,… } | "…{e}…" | if e then e else e | fn | e@rel
```

Evaluation contexts — the shape of "the next thing that reduces":

```
E ::= []
    | E.n | E[e] | v[E]
    | E(e,…) | v(v,…, E, e,…)          -- callee first, then arguments L→R
    | E:n(e,…) | v:n(v,…, E, e,…)      -- receiver first
    | E op e | v op E                   -- left operand first
    | not E
    | { f = v,…, f = E, f = e,… }       -- fields L→R
    | "…{v}…{E}…{e}…"                   -- holes L→R
    | E@rel
```

Reduction:

```
(ctx)    e → e'                                     ⟹  E[e] → E[e']
(app)    ((p,…) body)(v,…)                          →  body[p := v]
(bind)   x = v ; k                                  →  k          (store updated)
(seq)    v ; k                                      →  k
(if-t)   if v a b   → a        when v is truthy
(if-f)   if v a b   → b        when v is falsy      (B-2: false and nil are falsy)
(and-t)  v and e    → e        when v is truthy
(and-f)  v and e    → v        when v is falsy
(or-t)   v or e     → v        when v is truthy
(or-f)   v or e     → e        when v is falsy
(route)  under a declared failure contract, if a call's failure position
         reduces to a non-nil failure and that position is unbound:
         E[f(v,…)] → return (nil, err)               -- B-15, §4.4
```

**The non-strict positions are exhaustive, and there are five.** The right
operand of `and`; the right operand of `or`; the unselected arm of `if` in
statement or expression position; the body of a callable before it is applied;
and the body of a loop before its condition or iterator admits it. Nothing else
in the language delays a reduction. There is no lazy binding, no thunk, no
`delay`, no implicit stream, no promoted-to-lazy field, and no
sufficiently-smart-compiler clause that could introduce one.

Short-circuit is **control flow**, not demand. `v and e` does not reduce `e`
because rule `(and-f)` says so, exactly as in C — not because nobody observed
it.

### 1.1 The materialization lemma — what demand is allowed to do

> **LEMMA.** Demand is a quotient on `v`. It is not a rewrite on `E`.
>
> Demand may change the representation of a value — inline it, split it into
> registers, choose a niche, or delete it entirely when no remaining reduction
> projects from it. Demand may **not** change the number, the order, or the
> identity of reductions that have an **effect**.
>
> Effects are: calls into the world (`print`, `sh`, `file.*`, `os.*`), writes to
> a place observable outside the current world fragment, and routed failures.

Two corollaries, and they are the whole point of the page.

**A Haskell-class space leak is unexpressible.** A space leak is a *retained
thunk*: an unevaluated redex kept alive because nobody demanded it. Duo has no
unevaluated redexes — `E` is reduced eagerly and demand acts only on `v`. The
failure mode that trained the allergy has no representation here.

What Duo *can* have is a retained **value**: an ordinary memory leak, with an
ordinary remedy (§6), diagnosed by ordinary means. That is a different bug with
a different shape, and conflating the two is how this argument usually gets lost.

**Erasure cannot make a program's output depend on the optimizer.** If a
construct has an effect, the effect happens; if it has none, its absence is
unobservable by definition. A witness that claims otherwise is reporting a
compiler defect, not a trade-off.

### 1.2 What demand does govern

- whether a heap object exists for a table, pack, descriptor, or closure
- which representation a value takes (interned tag, niche nil, tag+payload,
  registers, stack slots, heap)
- whether an intermediate collection exists between two pipeline stages
- whether a stream is buffered (`proc.out` unread is never captured)
- whether a formatting apparatus is instantiated

None of those is an evaluation-order question. Every one of them is a question
about the *shape of a value*, and the lemma is what keeps the two apart.

---

## 2. The guaranteed-erasure list

A **guarantee** is a statement about what the compiler MUST NOT BUILD. An
**optimization** is a statement about what it MAY improve. The first is checked
by inspecting output; the second can only be benchmarked. Only the first may
appear in a worst-case budget.

The list is deliberately short. A short guaranteed list is worth more than a
long aspirational one, and every row below is a MUST NOT with an inspectable
artifact.

| id | guarantee — the compiler MUST NOT build this | witness obligation |
| --- | --- | --- |
| E1 | zero-semantics tokens: `end`, comments, inter-token whitespace, `_` inside numerals (§3) | none needed — lexical |
| E2 | a closure object for a callable whose world fragment is empty | `why(realization)` names the fragment as empty |
| E3 | a table, pack, or descriptor value that no remaining reduction projects from | `why(free)` has nothing to explain, because nothing was built |
| E4 | a conversion edge whose target is the position's declared contract (CDR, B-13) | the edge does not appear in the manifest |
| E5 | a name lookup or hash for a field read on a **sealed** descriptor — it is a constant offset | layout fact in the manifest |
| E6 | an optic object for a composed lens, prism, or traversal (§9) | the composed path appears as one access |
| E7 | a buffer for a `proc` stream that is never read (§16) | absence of the capture |
| E8 | a string for a `format(sink)` that is never rendered | absence of the builder |
| E9 | a pack for the receiver threaded out of a void `:`-chain position | chain threading is a rename |

**Best-effort, and therefore excluded from every budget.** Inlining · sealed
collapse to rung ≤3 at any *given* call site · pipeline fusion into one loop ·
fact-upgraded algorithm selection (sortedness, uniqueness, density) ·
constant folding · monomorphization and call-shape caching · niche and tag
representation choice · register allocation quality · bounds-check removal ·
overflow-check removal under interval proofs · scalar replacement of an
*observed* aggregate · cross-module inlining by edge identity · PGO ingestion.

Every item in that paragraph is a genuine design goal and several are load-
bearing for the §13 performance claim. None of them is a guarantee, and a
realtime budget that assumes any of them is wrong. **Assume the best-effort
column is OFF when you compute a bound.**

The dividing test, stated so it can be applied to a construct that does not
appear above: *can a conforming compiler emit the artifact and still be
conforming?* If yes, it is best-effort. If no, it is a guarantee and belongs in
the table.

---

## 3. Worst-case behaviour, one page

`n` is the size of the operand. `k` is a key. "unwind" means the construct can
raise a **fault** that unwinds the world (Pass 107 §3) — never the process by
default. Allocation counts are **worst case**, with the best-effort column
assumed off.

| construct | worst-case time | worst-case allocation | unwind |
| --- | --- | --- | --- |
| binding `x = v` | O(1) | 0 | no |
| integer arithmetic `+ - * / % << >> & \| ~` | O(1) | 0 | overflow / divide-by-zero (OVFL, §12) |
| float arithmetic | O(1) | 0 | no (IEEE, no traps) |
| comparison `== != < <= > >=` on scalars | O(1) | 0 | no |
| `==` on a sealed record | O(fields), structural | 0 | no |
| `and` / `or` / `not` | O(1) | 0 | no |
| `if`, expression-`if` | O(1) branch | 0 | no |
| `while`, `for` | O(iterations × body) | per body | per body |
| guard chain `a = f() and p(a)` | O(links) | per link | per link |
| index `t[k]`, dense array part | O(1) | 0 | out of range (§12 B-8: absence, not fault) |
| index `t[k]`, hash part | O(1) expected, **O(n) worst** | 0 | no |
| field `.a`, sealed descriptor | O(1) constant offset | 0 | no |
| field `.a`, open table | as hash index | 0 | no |
| call `f(v,…)`, statically resolved | O(1) + callee | frame only | callee |
| call, rung ≤3 sealed collapse | O(1) + callee | frame only | callee |
| call, dynamic rung | O(rungs) resolution + callee | boxed argument vector | callee, plus resolution failure |
| construction, anonymous table | O(fields) | **1 heap object** | allocation fault |
| construction, sealed descriptor | O(fields) | 0 if it stays in registers or a stack slot; 1 if it escapes | allocation fault |
| spread `{ ..base, x = 1 }` | O(fields of base) | 1 heap object | allocation fault |
| string literal | O(1) | 0 (static) | no |
| view `s[i, j]` | O(1) | 0 | no |
| interpolation `"…{e}…"` | O(total length) | **1 per hole + 1 for the result** | allocation fault |
| `..` join | O(la + lb) | 1 | allocation fault |
| `#s`, `s:len()` | O(1) | 0 | no |
| `to(t)` / `from(t)` edge | edge-defined | edge-defined | edge-defined |
| dispatch table `@{…}(k)` | O(1) after collapse; O(cases) if not collapsed | 0 | no matching case |
| pipeline stage producing a collection | O(n) | **1 per unfused stage** | allocation fault |
| pack `(..xs)` / spread `f(..xs)` | O(arity), a static fact (B-9) | 0 if it does not escape | no |
| failure pack `nil, err` | O(1) + construction of `err` | 1 if `err` is a table | allocation fault |
| DEMAND-ROUTE (B-15) | O(1) — an early exit | 0 | no |
| callable value, empty world fragment | O(1) | **0** (E2) | no |
| callable value, non-empty fragment | O(captures) | **1 heap object** | allocation fault |
| `release` (tier 1 proven drop) | O(1) at a static point | 0 | no |
| `release` (tier 3 managed RC) | O(1) per count; cycle collection only on cycle-possible shapes | 0 | no |
| tail call | O(1), constant stack (TAIL) | frame reused | no |
| non-tail recursion | O(depth) stack | frame per level | metered `error.depth`, routed (Pass 107 §3) |

Two rows carry the honest bad news and are here on purpose. **Hash indexing is
O(n) worst case**, not O(1) — the guarantee is expected-time with a keyed,
SipHash-class function whose key is a world fact (§12 HASH). **An unfused
pipeline allocates once per stage**, because fusion is best-effort.

**This table is the specification. Seven of its rows are wrong about this tree
today**, and §7 gives each one a measurement: integer arithmetic does not
unwind on overflow or divide-by-zero, the tail-call row is false and fails as a
segmentation fault, the interpolation row undercounts nothing but omits that
nothing is freed, the two `release` rows describe machinery that does not
exist, the sealed-descriptor construction row is untestable because the
constructor does not compile, and the anonymous-table row is a hashed table
rather than a struct. Do not budget from this table against the current
binary. Budget from §7.

---

## 4. Where allocation can occur

The list is closed. If a construct is not below, it does not allocate.

```
A1  constructing a table, descriptor, or pack value that escapes or is observed
A2  growing a collection past its current capacity
A3  producing a `str` that is neither a literal nor a view — interpolation,
    `..`, `to(str)`, `format(sink)` rendering
A4  a callable value whose world fragment is non-empty
A5  opening a region or arena (memory tier 2)
A6  a foreign call that allocates — rung-6, provenance-tagged, never implicit
```

**Where allocation provably cannot occur.** Literals. Views (`s[i, j]`,
`bytes`, `chars`). Field reads and writes on an existing value. Arithmetic,
comparison, and bit operations. Iteration over a view. A sealed-descriptor value
that stays in registers or a stack slot. Chain threading. Every erasure in §2.
`ref(weak)` reads. A routed failure (B-15) — routing is an early exit, and the
failure value was already constructed by the producer.

**The structural claim `ward@allocation_free`** (§9, negative requirements) is
this list turned into an anchored protocol: a module satisfies it when its
reachable graph contains no `A1`–`A6` edge. That is a proof over the graph, not
a runtime counter, and it is what makes an allocation-free steady state
*provable* rather than measured.

---

## 5. Cost of the resolution ladder

The 8-rung ladder of §11 is the one place where a *name* costs time.

```
rung ≤3  lexical shadow / instance layer / exact descriptor relation
         — resolved at compile time; the call site is direct. O(1), 0 alloc.
rung 4-5 hierarchy walk, package extension — compile time; O(depth of hierarchy)
         at compile time, O(1) at run time.
rung 6   authorized foreign — compile time, provenance-checked.
rung 7   generated — compile time.
rung 8   dynamic — RUN TIME. Boxed argument vector, dynamic dispatch.
```

**Sealed-world collapse** (sealed ∧ frozen ∧ no shadow ∧ instance-off ∧ frozen
world) proves a site to rung 3. The **sealed-collapse rate** is a tracked metric
with a floor precisely because the difference between rung 3 and rung 8 is the
difference between a direct call and a boxed one, and a language that cannot
report that ratio cannot claim predictability. It is a metric, not a guarantee:
no individual call site is promised rung 3.

---

## 6. Memory cost, per tier

From Pass 107 §2, which is decided and permanent:

```
tier 1  PROVEN DROPS   free inserted at a static point. Runtime cost: ZERO.
                       The majority of sites under demand.
tier 2  REGIONS        bulk free at region close. Per-object cost: ZERO.
                       Allocation-free steady states provable (§4).
tier 3  MANAGED RC     one count per shared reference edge, elided by borrow
                       proofs; Perceus-class reuse means uniqueness gives
                       in-place update with no count traffic. Cycles:
                       deferred trial-deletion, confined to cycle-POSSIBLE
                       shapes — acyclic descriptors never pay.
never   tracing stop-the-world. Latency is a language property.
```

The honest open question, ledgered by Pass 107 and repeated here so a budget
does not have to go find it: **RC-with-elision versus tracing on share-heavy
graph workloads is unmeasured**, and it enters the benchmark corpus by name.

---

## 7. Status in this repository

Everything above is the specification. This section is what the tree does on
**2026-08-08**, branch `canonical-to-relation`, `zig build` debug binary at
`zig-out/bin/duo`. Every row was produced by running a probe and reading a
value or generated artifact — never by reading source and inferring. Identifiers
quoted from generated output are **C**, not Duo.

### Specified and implemented

- **Strictness holds, demonstrated.** A binding whose value is never read still
  runs its callee's effect: a program binding `x = noisy(n)` and returning `7`
  prints `evaluated` then `7`, exit 0. Demand did not elide the reduction. This
  is the document's central claim and it is the one that is demonstrated rather
  than asserted.
- **E3 holds for anonymous tables (C backend), demonstrated by artifact.** A
  two-field table constructed and never projected from compiles to
  `void* t = NULL; return (n * 2);` — the constructor is absent, and the boxed
  runtime prelude is not emitted at all (10 allocation sites in the generated C,
  all string helpers, against 107 for the escaping variant of the same program).
- **E2 holds, demonstrated by artifact.** A callable with an empty world
  fragment passed as a value compiles to a plain function-pointer box; the
  closure allocator appears in the generated C only as a definition, never as a
  call site. The capturing variant does allocate, which is the correct contrast:
  the closure is a measurement, and here the measurement is right.
- **Sealed descriptors get flat layout.** A two-field sealed descriptor becomes
  a C struct of two `int64_t`, returned by value, with field reads compiled as
  direct member access. E5's layout half is real.
- **The direct ARM64 backend has no heap opcode.** Its only allocation
  instruction is `alloc_slots`, and that arm lowers to a stack-pointer offset
  (`src/native_backend.zig`). The only fixed runtime symbols it can branch to
  are `printf` and `puts`; every other branch target is a user callee name, so
  a program that reaches an allocator does so by calling one, never implicitly.
  Read the result carefully: the backend's allocation-freedom is **partly
  attainment and partly refusal** — programs that would need a heap are
  refused, not compiled without one. See the bail note below.

### Specified and NOT implemented

- **TAIL is not implemented, and the failure mode is a SIGSEGV.** A textbook
  tail call compiles to a real call: the direct backend emits a 48-byte frame,
  `bl` to itself, restore, `ret`. Positive control at depth 1000 prints `1000`;
  at depth 5,000,000 the binary exits **139**. Pass 107 §3 says "No SIGSEGV as
  an API" and there is no depth metering and no routed `error.depth` today.
- **No deallocation is emitted, at any tier.** Zero `free` call sites appear in
  the user region of the generated C (0 below line 5900 of a 6039-line output;
  the 45 in the file are all inside the runtime's own rehash and string-pool
  helpers). A capturing closure's heap object initializes a `refcount` field to
  1; across the whole generated file that field is written twice and decremented
  **zero** times. Tier 1 is described as the only tier this tree has (Pass 107
  §4); measured, the tree has none of the three.
- **Interpolation costs two allocations and leaks both.** `"value {n}"` compiles
  to an integer-to-string allocation feeding a concat allocation, and nothing
  frees either. The §3 table's row is right about the count and optimistic about
  the lifetime.
- **OVFL is not checked.** `i64` maximum plus one prints `-9223372036854775808`,
  exit 0. §12 says checked is the default.
- **Integer division by zero is not a fault and not a truncation.** `7 / 0` with
  both operands `i64` prints **9218868437227405312** — the bit pattern of IEEE
  `+inf` read as an integer. B-4 says `i64/i64` truncates; measured, the operands
  went through the float path and the result was reinterpreted. This is a wrong
  answer with a green exit code, and it is the worst row on this page.
- **`range` does not exist**, so `for i in range(0, n)` is a parse-clean
  `call to undeclared function`. **`check`, `why`, and `todo` do not exist**
  either — every witness obligation in §2 is therefore unenforceable today,
  which is the honest reason the guarantee list has no fixtures.
- **Pipelines do not compile.** `xs:filter(odd):map(dbl):sum()` fails in the C
  backend with a type error. The fusion row of §3 is untestable, not merely
  unfused.
- **Descriptor construction does not compile, in either spelling.**
  `pair{ n, n + 1 }` and `pair{ a = n, b = n + 1 }` both emit a call to a
  nonexistent C function wrapping a boxed table into a struct-returning
  function; the direct backend refuses the same construct at `lowerExprCons()`
  (`src/dnir_lower.zig`, DNB001). So the flat-layout result above is measured
  through *field access on a value the compiler produced*, and the constructor
  cost row in §3 is **SPECIFIED, NOT DEMONSTRATED**.

### Implemented differently

- **An escaping anonymous table is a hashed heap table, not a struct.** It
  compiles to a table allocated with zero array capacity and two hash slots,
  with the two fields stored by hashed literal key. §3's "1 heap object" is
  right; the constant factor is a hash store per field, not a struct write.
- **Out-of-range index answers `nil`, not a fault** — consistent with B-8's
  absence-over-sentinels, and worth stating because the §3 table's "unwind"
  column would otherwise be read as promising a check.
- **The two backends disagree, and asm success is not run success.** A program
  reading two fields of an anonymous table emits correct scalarized ARM64 under
  `--backend=direct --emit asm` (exit 0, arithmetic verified by hand) and
  **fails to build** under the default path, because the C backend calls an
  undeclared table getter. Anyone measuring cost from `--emit asm` alone will
  measure a program that does not run.
- **Native coverage is 103 of 139 reachable programs** (`zig build
  native-census`, exit 0; 36 bail, 16 unreachable C-emitter fixtures). The
  heap-free property of the direct backend applies to those 103 and to nothing
  else.

### A note on measuring this yourself

The C backend writes its intermediate to a fixed path derived from the source
stem, in a shared temporary directory. Two concurrent runs of differently-named
sources are fine; two runs of the same stem race, and a stale file reads exactly
like a fresh one. Give probes unique stems, and read exit codes **without a
pipe** — a pipe reports the last command's status and has produced false greens
in this repository before.
