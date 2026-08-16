# PROTOCOL-PROJECTION-ONE

**A programmer never implements a protocol. They state meaningful relations, and
the compiler computes the algebraic closure over those facts.** If the facts
uniquely satisfy an algebra, satisfaction is INFERRED. If satisfaction uniquely
implies another conventional relation, that relation may itself be PROJECTED —
without an independent declaration.

    RELATION FACTS  ->  ALGEBRAIC CLOSURE  ->  IMPLIED RELATION/APPLICATION FACTS

This is not "standardize magic methods." It is: **standardize semantic algebras,
then project their natural relation faces from exact graph facts.** The
programmer gets the ergonomics of *just define what this thing naturally does*;
the compiler gets far more information than an interface system, and therefore
far more freedom to erase, fuse, specialize, or replace the mechanism entirely.

---

## §1 `.` IS NOT `:` — AND A HOME IS NOT A SUBJECT

    lexer.next     statically project member `next` from the value/home `lexer`
    lexer:next()   apply semantic relation `next` WITH `lexer` AS SUBJECT

These are categorically different. If `next` means *advance this state and
produce the next item*, only the second is correct. So:

    source:lex()     tokens:parse()     stream:next()          CANONICAL
    lexer.lex(source)  parser.parse(tokens)  stream.next()     NOT behavioral

**HOME IS NOT SUBJECT.** `compiler/lexer.id` establishes provenance and reach for
what is declared there. It does NOT mean every relation under that home is called
through `lexer.` or `lexer:`. **An organizational home must not become a subject
merely because it appears before a relation.**

**APPLIED / RELATION / SUBJECT are THREE facts and must not collapse:**

    source:lex()   ->   relation = lex        (home: compiler.lexer — provenance only)
                        subject  = source
                        applied  = <the value applied, if distinct>

The home is **not part of the semantic calling convention**. `lexer:lex(source)`
is lawful only when the lexer VALUE is genuinely the subject. `lexer(source)` is
lawful only if an exact application fact for the value `lexer` uniquely resolves
to `lex` — **never** from filename, home name, one-member home, or spelling
similarity.

**FILESYSTEM-ONE.** `compiler.id` plus a sibling `compiler/` project ONE home;
children contribute child homes and bindings. There is no import/module/package
object. After resolution, path is provenance only.

## §2 SUBJECT-ONE — `self` is migration debt

Subject is a **semantic application fact**, never an implicit first-argument
convention. Canonical graph records `application --subject--> value`; canonical
source writes `value:relation(...)`. An explicit `self` parameter that merely
encodes relation orientation is debt, not design.

## §3 ITERATION-ONE — `for` does not mean `iter` then `next`

**THIS LOWERING IS FORBIDDEN AS A DEFINITION:**

    for(xs) (x)          cursor = xs:iter()
        body       ->    while(x = cursor:next())
                             body

That is ONE possible realization. It must never become the semantic definition.
The canonical graph is a single iteration application:

    iteration
        source         xs
        result pack    {x}
        body relation  B
        ordering       facts
        termination    facts
        effects        E
        demand         D
        world          W

Realization may then choose: direct indexed traversal, cursor + `:next()`, SIMD,
hash traversal, tree traversal, closed-form reduction, parallel partition,
compile-time, or **nothing**. A fixed array may iterate with index arithmetic and
no `next` relation existing physically; a range with an induction recurrence; a
database query with a cursor advance — all satisfying the same demand.

**This is the same reason high-level Idol can beat hand-written C: the source
does not commit to iteration mechanics.**

### §3.1 Iteration is NOT "has a relation named `next`"

    WRONG   user defines Foo:next() -> compiler sees a member named "next"
            -> Foo is iterable

That makes the SPELLING `next` semantic authority — exactly what Idol exists to
eliminate. Correct in both directions, neither depending on the string:

- **Facts prove the algebra.** A meaningful `cursor:next()` plus sufficient
  transition, result and termination facts may PROVE iteration applicability.
- **The algebra projects the face.** Where `iteration(D)` is already known, a
  demand for one step resolves `next` as the **uniquely projected one-step face**
  — no handwritten interface slot.

The second direction is the stronger one, and it reverses the usual dependency:
`cursor` does not become iterable by implementing `next`; `cursor:next()` is a
projection of the iteration algebra `cursor` already participates in.

### §3.2 Worked shapes

    for(tree) (node)    walk admits traversal, yields node, order known
                        -> unique iteration projection. NO next() ceremony.
                        Realization: DFS stack / BFS queue / threaded walk /
                        recursion / SIMD chunk / compile-time.

    for(1..n) (i)       NOT a RangeIterator with next(). The law IS
                        {start 1, step 1, limit n} -> induction variable,
                        or NO LOOP if demand algebra removes it. This is what
                        makes recurrence closure reachable.

    for(tokens) (token) tokenstream carries {result token, ordering source-order,
                        termination end-of-input}. The programmer implements
                        neither Iterator<Token> nor necessarily tokens:next().

## §4 NO PROTOCOL REGISTRATION, AND NO PROTOCOL OBJECT

Forbidden outright:

    trait   interface   impl   Iterable   Iterator   Hashable   Readable
    impl iter for sequence      implements iterable      @iter
    register(sequence, iteration)      iter = { next = ... }

`able(r)` remains the rare explicit open-boundary requirement; it does **not**
create a protocol object. **Relation is protocol** — use actual relations, never
adjective interfaces.

## §5 THE ALGEBRA GENERALIZES FAR BEYOND ITERATION

This is the larger missing architecture, and each row is the same shape:

| meaningful relation the user wrote | facts may imply | forbidden ceremony |
|---|---|---|
| `a < b` | `eq`, `le`, `min`, `max`, sort eligibility | `Comparable` |
| `value:hash()` + equality law | hash-table representation applicability | `Hashable` |
| `source:read()` | satisfies consumers demanding `able(read)` | `Readable` |
| `to` + descriptor facts | downstream conversions | explicit `:to(...)` everywhere |
| iteration algebra | `next` / `for` / `each` faces | `Iterator` |

**Inference must be EXACT and FAIL CLOSED on ambiguity.** If several incompatible
laws could result, that is an ambiguity, and the programmer states only the
smallest missing distinction — never a conformance declaration.

## §6 THIS MUST CREATE OPTIMIZATION INFORMATION, NEVER RUNTIME MACHINERY

    conventional          Idol, sealed
    value                 exact descriptor
    -> interface desc     + exact iteration algebra
    -> vtable             + exact relation
    -> next pointer       -> direct specialized realization
    -> indirect call

    protocol object 0   iterator object 0   vtable 0   indirect dispatch 0
    unused result fields 0                  generic shape lookup 0

And the derived algebra must feed **demand, recurrence, representation
selection, SIMD, parallelization and target realization** — not merely type
checking. A sequence with iteration + known cardinality + contiguous
representation + pure body + associative reduction lets the graph conclude
scalar, SIMD, parallel and tree reduction are ALL lawful, and pick the cheapest.
The programmer never writes `RandomAccessIterator` / `ContiguousIterator` /
`ParallelIterator` — **that would be exposing compiler facts as user taxonomy.**

## §7 MANDATORY NEGATIVE CONTROLS

Each must be executable. A protocol-inference system without these infers
nothing trustworthy.

1. same relation name on two incompatible descriptors -> **ambiguity, never
   first-match**
2. a relation named `next` with NO iteration laws -> **must NOT become iterable**
3. an iteration law with NO explicit `next` -> **`for` must still work**
4. a static member named `next` that is not subject behavior -> **`.` stays a
   static projection**
5. remove the result/termination law -> **inferred iteration must disappear**
6. move a relation to another home, identity preserved -> **semantics unchanged**
7. same answer, altered application subject/relation graph -> **the
   graph-equivalence gate must FAIL**

Control 7 is the link to SOURCE-CONTROL-ONE §8: identical answers from different
graphs is still wrong.

## §8 IMPLEMENTATION DEBT — DO NOT CLAIM ANY OF THIS CLOSED

    host-owned parser / binding / sema / resolution   (executed authority is S0)
    explicit-self compiler source
    behavioral dot-shaped migration code
    token ordinal / catalog authority
    incomplete protocol implication closure
    incomplete cross-home structured-result facts
    recurrence body grammar rejecting 92% of candidates
    graph sovereignty incomplete

**Build a gate for each rather than rewriting spelling.** A task that only
renames an abstraction is rejected.

---

## §9 MEASURED BASELINE — 2026-08-16, idol `23a24179`, 1,015 tracked `.id`

    x:foo()   subject-oriented calls          9,606
    x.foo(    dot-shaped calls                6,449   in 467 files
    (self …)  explicit self parameters          123   in  29 files

    lib/compiler/lexer.id     self 27   dot 22    1,130 lines
    lib/compiler/parser.id    self  4   dot 263   1,792 lines
    lib/compiler/token.id     self  0   dot 0       130 lines

**Subject orientation is ALREADY THE MAJORITY — 60% of call sites.** The
migration is a minority correction, not a rewrite of the corpus.

**THE 6,449 IS AN UPPER BOUND ON THE VIOLATION, NOT THE VIOLATION COUNT, AND NO
REGEX CAN NARROW IT.** §1 requires a three-way classification — static
projection of a callable (retain `.`), semantic relation on a subject (migrate to
`:`), or home qualification (resolve once, then erase) — and only the second is a
violation. A real instance of the first appears in this very corpus:
`agent.scaling_ladder()` projects a callable from a home and is LAWFUL. This is
the same honesty `canonical.md` §26 already applies to mashed compounds:
*regex alone cannot prove them.* Any lane reporting a violation COUNT rather than
a classification distribution is reporting a number it did not measure.

`parser.id` carries 263 dot-shaped calls in 1,792 lines and is the densest
single site. `token.id` is already clean of both forms.

**Not measured:** whether any protocol implication closure exists at all, and
whether `for` currently lowers through an `iter`/`next` convention — §3's
forbidden definition. Both are the first questions a lane must answer, and
neither is answerable by grep.
