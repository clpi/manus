# SOURCE-CONTROL-ONE

**Idol has a small set of familiar control faces but ONE semantic control
algebra.** Every familiar and canonical face reduces to the same semantic graph
facts *before* optimization. Therefore source syntax can never narrow the
realization space — while a higher-density face may reveal stronger demand,
refinement, recurrence and iteration facts EARLIER.

    if / else / match       ->  REFINEMENT
    while                   ->  RECURRENCE
    for / each / map / ...  ->  ITERATION
    return / break / continue -> exact region exits

Physical control flow is never sacred. A source `for` need not remain a loop. A
source `while` need not iterate. A source `if` need not branch. A source `match`
need not exist after parsing. A relation chain need not allocate an intermediate
collection. **The only invariant is the required observation.**

---

## §0 THE INVARIANTS THIS SITS ON

    @   current-world access / qualification
    .   exactly ONE static projection
    :   semantic subject orientation
    ()  universal application
    =   binding / place update
    ==  equality

`:` also spells the explicit binding-descriptor constraint, `x: descriptor =
value`. It is NEVER iterator punctuation, method lookup, namespace search, or a
control delimiter. `=` NEVER attaches a control body. So these are INVALID:

    if(cond) = body        while(cond) = body      for(xs) = body
    x:for(xs)              x:while(xs)

APPLICATION-ONE remains absolute: source category, spelling, AST kind, file path
or "looks like a control construct" may not reconstruct semantic meaning
downstream.

## §1 THE HIERARCHY — there is NO single preferred spelling per shape

This is the correction that governs every other section. Rank by MEANING:

1. **If the operation has an independently meaningful relation, use the
   relation/chained form.** `xs:any(p)` states *existence*; the explicit
   flag-and-break loop states *scan and mutate a flag*, and forces the compiler
   to rediscover the question.
2. **If the operation is fundamentally refinement, recurrence, or generic
   iteration, use `if` / `while` / `for`.** These stay canonical when no
   stronger domain relation exists.
3. **Familiar legacy spellings are ACCEPTED where useful, and normalized
   immediately.**
4. **Every equivalent face publishes the same semantic graph facts.** Source
   choice cannot constrain realization.
5. **Never invent `:if`, `:while`, `:for`, `:call`, `:get`, `:set`, iterator
   objects, or fake relation names merely to make syntax look uniform.** A
   relation exists only if it has independently meaningful semantic identity. A
   boolean does not inherently own a relation named `if` or `then`.

**Canonical means the smallest spelling that preserves actual domain meaning —
not the fewest characters.** An explicit `for` body carrying three effects is
clearer than a forced `:each`, and §31 keeps it.

## §2 CONTROL-HEAD BINDINGS

Fresh lexical bindings may appear in control heads. They are BINDINGS, never
assignment-as-expression, and never storage.

    if(user = lookup(id))          while(line = stream:read())
    else(x = fallback())           for(users = load()) (user)

Head grammar is `binding* predicate?`. **A comma is not boolean AND** — write
`if(a and b)`, not `if(a, b)`. The comma only separates head bindings from the
optional final predicate.

**Truthiness rule.** Binding-only means predicate = truthiness of the binding.
Binding + explicit predicate means the EXPLICIT predicate is authoritative — do
not secretly conjoin the truthiness test.

**Safety law.** A bare-name head binding must be FRESH in the surrounding
lexical scope, and heads may not hide observable place mutation. Reject
`if(x = other())` when `x` already exists, and reject `if(table(key) = value)`,
`if(@state = value)`, `if(obj.field = value)`, `while(table(key) = next())`.

**Scope.** A head binding lives in the remainder of that head plus that
alternative's body — not in later alternatives, not after the construct. So
`if(x = first()) … else(x = second()) …` is valid and clean; each `x` is a
distinct binding. No maybe-initialized outer variable, no forced stack slot.

## §3 REFINEMENT — `if`, `else(pred)`, `else`, match

    if(a)          if a              result = if(cond)
        one()          one()             a
    else(b)        else if b         else
        two()          two()             b
    else
        four()

There is **no `elseif` identity and no `ElseIf` graph kind** — one ordered
refinement application with alternatives. `else(expr)` ALWAYS means a
conditional alternative, so `else(action())` is not an unconditional else; write
`else` on its own line.

**There is no canonical independent match system.** Familiar `match` / `switch`
/ `case` may be accepted at ingress and must become the exact same refinement
graph. No `PatternIR`, `CaseIR`, `MatchNode`, `SwitchNode` as semantic
authorities. Exhaustiveness is a descriptor/refinement-domain fact — successive
alternatives refine the remaining domain — and works identically whichever face
was written.

An `if` may realize as: compile-time selection, nothing (result unused),
conditional select, predication, an ordinary branch, a jump table, a binary
decision tree, a perfect hash, a bit test, a SIMD mask, or a GPU predicate.

## §4 RECURRENCE — `while`

    while(cond)        while cond        while(line = read(), line != "quit")
        body               body              process(line)

The head is re-evaluated per iteration; head bindings are scoped to that
iteration. No persistent mutable place is implied, and the binding normally
realizes as a register or disappears.

**Condition and body are DELAYED semantic regions.** Conceptually
`while(() cond)(() body)` — with physical representation normally *none*. No
closure allocation unless something genuinely escapes.

A `while` may become: an ordinary loop, an early semantic exit, an unrolled
loop, a lawful SIMD recurrence, a finite-state quotient, an orbit jump, binary
relation powering, a closed form, a compile-time answer, or zero work.

**Tail recursion is an equivalent recurrence.** A domain-meaningful recursive
definition must NOT be rewritten to `while` merely because it eventually loops
physically — `fib` carries algebraic structure worth keeping, and its physical
realization may be entirely non-recursive.

## §5 ITERATION — `for`, and the relation chain

    for(source) (item)     for item in source     for(entries) (key, value)
        body                   body                   consume(key, value)

The canonical face exposes the true structure `iteration(source)(body-relation)`
— **control-boundary currying**, not general currying, and normally with
partial-application object 0, closure object 0, environment 0.

`for(users = load()) (user)` binds the SOURCE; the yielded item is not the whole
source, so `for(user = users)` is invalid as yield syntax. `for(events) tick()`
consumes zero yielded values, and their production should be zero where lawful.

**Prefer the strongest meaningful relation** — `xs:each/map/filter/fold/any/all/
find`, `users:map(.score)` where `.field` stays exactly one static projection.
Chains must not mandate intermediate collections: the graph sees iteration,
refinement, projection, reduction, and may emit one scalar loop, one NEON
reduction, an indexed query, a compile-time result, or nothing.

**Do not force all `for` into chains** (§31), and do not auto-transform loops
into map/filter/fold unless equivalence is PROVEN.

`pairs`/`ipairs` are not canonical — the table/shape/world determines lawful
iteration. If ordering is semantically demanded, that must be explicit through
the relation, descriptor or world, never hidden in a helper name.

## §6 EXITS — `return`, `break`, `continue`

    return(value)   return value              break        continue

**CORRECTED 2026-08-16 — `break()` / `continue()` ARE NOT CANONICAL.** An earlier
draft of this section had it backwards. **Bare `break` and bare `continue` are
the canonical zero-result exits.** `()` on a zero-payload region exit carries NO
information, and the parenthesized face falsely suggests ordinary
APPLICATION-ONE behaviour — which is exactly why the compiler refuses `break()`
as `expr-unhandled:func_expr`. §12 measured that refusal and the first reading
was "a canonical face is broken"; the correct reading is **the compiler was
right, and the parenthesized face was the wrong design.** Under SOURCE-MINIMUM a
`()` that carries no information is debt. Revisit only if region exits are ever
established as ordinary applicable semantic VALUES, and that architecture proves
useful elsewhere.

**`return` IS DIFFERENT and keeps both faces.** `return(value)` carries a result
pack, so the parentheses carry real structure — `return(a, b)` is a pack. That is
a genuine asymmetry with `break`/`continue`, not an inconsistency.

Tail expression IS the result; no explicit `return` needed. All tail faces must
publish equivalent tail-result demand, so TCO depends on graph position and
effects, never spelling.

`break`/`continue` publish an EXACT region exit once — no downstream "find the
nearest loop" AST walk. The graph meaning is structural, never a mandatory
machine branch:

    region exit
        target       exact iteration/recurrence exit  (break)
                     exact iteration STEP boundary    (continue)
        result pack  empty

`continue` does NOT mean "jump to the loop header" — that would encode
realization. It means *exit the remainder of this iteration body and proceed to
the iteration application's next semantic step*. Realization may then be a
branch, predication, a filtered iteration, **a SIMD lane mask**, or no
instruction at all. That distinction is what keeps a scalar source `continue`
from blocking vectorization.

Where the meaning is really search, prefer the relation: break-on-first-truth is
`any`, break-on-first-false is `all`, break-at-first-match is `find`.

## §7 DEMAGICKING — the keyword ontology shrinks

    local/let/var/const  ->  x = value  |  x: descriptor = value
    function/fun/fn      ->  add = (a, b) a + b
    then / do / end      ->  nothing (grammar already bounds the body)
    else if              ->  else(cond)
    for x in xs          ->  for(xs) (x)
    table[key]           ->  table(key)          (place demand: table(key) = v)
    string.find(s, p)    ->  s:find(p)
    type/struct/class/enum/concept/trait/interface/impl -> descriptors, able(...)
    module/namespace/import/require -> filesystem-originated static homes, . and @
    comptime             ->  a stage fact, NOT a namespace

Mutability is determined by whether a semantic place is demanded, not by a
declaration keyword.

## §8 EQUIVALENCE IS A GRAPH CLAIM, NOT A SYNTAX CLAIM

Canonical/familiar pairs must compare IDENTICAL on: application relation,
subjects, operands, bindings, regions, results, descriptor facts,
range/refinement facts, effects, world, authority, demand, control targets,
yield packs, carried state. Ignore only spelling provenance and formatting
spans.

> **A compiler that produces identical ANSWERS but different semantic GRAPHS for
> familiar and canonical spellings is still WRONG.**

Explicit iteration converges with a chain ONLY IF yield ordering, effects, body
relation, results, break/continue behaviour and world observations are
equivalent. **Do not assert equivalence because both "look like loops."**

**Negative controls are required.** Make an effect observable and branch
elimination must stop. Make iteration count observable and recurrence deletion
must stop. Break an algebraic law and the closed-form candidate must vanish.
Introduce alias/effect/order dependence and fusion must stop.

## §9 ORDERING

Normalize control BEFORE lowering to an opaque CFG — never lower first and try
to reconstruct the laws. Expose opportunities in ladder order: observation,
demand, refinement/quotient, recurrence/iteration law, algorithm,
representation, movement, parallel, SIMD, ABI, instruction selection,
microarchitecture.

## §10 IMPLEMENTATION ORDER — never land syntax without graph convergence

1. grammar recognizes canonical + familiar faces
2. parser publishes explicit source regions, binders, targets
3. semantic graph owns normalized control facts
4. exact equivalence gates prove convergence
5. downstream AST-kind / name reconstruction DELETED
6. demand / refinement / recurrence / iteration consume graph facts
7. realization stays completely source-face independent
8. formatter migrates toward canonical surface
9. only then widen familiar compatibility

**Compatibility is ingress, never authority** — a familiar face may live
forever without docs, formatter, graph or backend preserving it.

## §11 STOP CONDITION

    canonical/familiar syntax parity        100%
    downstream control AST authority          0
    spelling-based control resolution         0
    duplicate match/switch semantic IR        0
    iterator-object requirement               0
    forced control-body closure allocation    0
    forced loop representation                0
    source-form performance divergence        0

---

## §12 MEASURED BASELINE — 2026-08-16, idol `06723d39`

Probed by running one program per face and reading its answer, not by reading
the parser.

| face | ruling | today |
|---|---|---|
| `if(cond)` | canonical | **answers** |
| `if cond` | familiar | **answers** |
| `else(pred)` | canonical | **answers** |
| `else if` | familiar, normalize | **DOES NOT PARSE** — block left open |
| `while(cond)` | canonical | **answers** |
| `while cond` | familiar | **answers** |
| `for(source) (item)` | **canonical** | **DOES NOT PARSE** — "write `name` at this token edge" |
| `for x in xs` | familiar | parses, backend refuses `gen-for-dynamic-iter` |
| `return(v)` / `return v` | both | **answer** |
| `break` | familiar | **answers** |
| `break()` | **canonical** | parses, refused `expr-unhandled:func_expr` |

**THE RULING IS INVERTED ON EXACTLY THE TWO FACES IT NAMES AS CANONICAL.**
`for(source) (item)` does not parse at all, and `break()` is misread as an
ordinary function application (`func_expr`) — which is §1.5's fake-relation
confusion appearing in the compiler rather than in the source. Meanwhile both
familiar counterparts work. So the formatter cannot yet migrate toward canonical
(§10.8) because canonical is the face that does not exist.

`else if` not parsing is a smaller gap of the same kind: §3 requires it accepted
at ingress and normalized to `else(cond)`.

**Not yet measured:** whether the faces that DO answer publish identical graphs.
Answer parity is not graph parity (§8), and no equivalence gate exists yet.
