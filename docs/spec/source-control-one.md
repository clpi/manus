# SOURCE-CONTROL-ONE

| # | directive |
|---|---|
| 1 | **Idol has a small set of familiar control faces but ONE semantic control algebra.** Every familiar and canonical face reduces to the same semantic graph facts *before* optimization. |
| 2 | Therefore source syntax can never narrow the realization space — while a higher-density face may reveal stronger demand, refinement, recurrence and iteration facts EARLIER. |

| # | directive |
|---|---|
| 1 | if / else / match -> REFINEMENT while -> RECURRENCE for / each / map / ... -> ITERATION return / break / continue -> exact region exits |

| # | directive |
|---|---|
| 1 | Physical control flow is never sacred. |
| 2 | A source `for` need not remain a loop. |
| 3 | A source `while` need not iterate. |
| 4 | A source `if` need not branch. |
| 5 | A source `match` need not exist after parsing. |
| 6 | A relation chain need not allocate an intermediate collection. **The only invariant is the required observation.** |

| # | directive |
|---|---|

## §0 THE INVARIANTS THIS SITS ON

| # | directive |
|---|---|
| 1 | @ current-world access / qualification . exactly ONE static projection : semantic subject orientation () universal application = binding / place update == equality |

| # | directive |
|---|---|
| 1 | `:` also spells the explicit binding-descriptor constraint, `x: descriptor = value`. |
| 2 | It is NEVER iterator punctuation, method lookup, namespace search, or a control delimiter. `=` NEVER attaches a control body. |
| 3 | So these are INVALID: |

| # | directive |
|---|---|
| 1 | if(cond) = body while(cond) = body for(xs) = body x:for(xs) x:while(xs) |

| # | directive |
|---|---|
| 1 | APPLICATION-ONE remains absolute: source category, spelling, AST kind, file path or "looks like a control construct" may not reconstruct semantic meaning downstream. |

## §1 THE HIERARCHY — there is NO single preferred spelling per shape

| # | directive |
|---|---|
| 1 | This is the correction that governs every other section. |
| 2 | Rank by MEANING: |

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

| # | directive |
|---|---|
| 1 | **Canonical means the smallest spelling that preserves actual domain meaning — not the fewest characters.** An explicit `for` body carrying three effects is clearer than a forced `:each`, and §31 keeps it. |

## §2 CONTROL-HEAD BINDINGS

| # | directive |
|---|---|
| 1 | Fresh lexical bindings may appear in control heads. |
| 2 | They are BINDINGS, never assignment-as-expression, and never storage. |

| # | directive |
|---|---|
| 1 | if(user = lookup(id)) while(line = stream:read()) else(x = fallback()) for(users = load()) (user) |

| # | directive |
|---|---|
| 1 | Head grammar is `binding* predicate?`. **A comma is not boolean AND** — write `if(a and b)`, not `if(a, b)`. |
| 2 | The comma only separates head bindings from the optional final predicate. |

| # | directive |
|---|---|
| 1 | **Truthiness rule.** Binding-only means predicate = truthiness of the binding. |
| 2 | Binding + explicit predicate means the EXPLICIT predicate is authoritative — do not secretly conjoin the truthiness test. |

| # | directive |
|---|---|
| 1 | **Safety law.** A bare-name head binding must be FRESH in the surrounding lexical scope, and heads may not hide observable place mutation. |
| 2 | Reject `if(x = other())` when `x` already exists, and reject `if(table[key] = value)`, `if(@state = value)`, `if(obj.field = value)`, `while(table[key] = next())`. |

| # | directive |
|---|---|
| 1 | **Scope.** A head binding lives in the remainder of that head plus that alternative's body — not in later alternatives, not after the construct. |
| 2 | So `if(x = first()) … else(x = second()) …` is valid and clean; each `x` is a distinct binding. |
| 3 | No maybe-initialized outer variable, no forced stack slot. |

## §3 REFINEMENT — `if`, `else(pred)`, `else`, match

| # | directive |
|---|---|
| 1 | if(a) if a result = if(cond) one() one() a else(b) else if b else two() two() b else four() |

| # | directive |
|---|---|
| 1 | There is **no `elseif` identity and no `ElseIf` graph kind** — one ordered refinement application with alternatives. `else(expr)` ALWAYS means a conditional alternative, so `else(action())` is not an unconditional else; write `else` on its own line. |

| # | directive |
|---|---|
| 1 | **There is no canonical independent match system.** Familiar `match` / `switch` / `case` may be accepted at ingress and must become the exact same refinement graph. |
| 2 | No `PatternIR`, `CaseIR`, `MatchNode`, `SwitchNode` as semantic authorities. |
| 3 | Exhaustiveness is a descriptor/refinement-domain fact — successive alternatives refine the remaining domain — and works identically whichever face was written. |

| # | directive |
|---|---|
| 1 | An `if` may realize as: compile-time selection, nothing (result unused), conditional select, predication, an ordinary branch, a jump table, a binary decision tree, a perfect hash, a bit test, a SIMD mask, or a GPU predicate. |

## §4 RECURRENCE — `while`

| # | directive |
|---|---|
| 1 | while(cond) while cond while(line = read(), line != "quit") body body process(line) |

| # | directive |
|---|---|
| 1 | The head is re-evaluated per iteration; head bindings are scoped to that iteration. |
| 2 | No persistent mutable place is implied, and the binding normally realizes as a register or disappears. |

| # | directive |
|---|---|
| 1 | **Condition and body are DELAYED semantic regions.** Conceptually `while(() cond)(() body)` — with physical representation normally *none*. |
| 2 | No closure allocation unless something genuinely escapes. |

| # | directive |
|---|---|
| 1 | A `while` may become: an ordinary loop, an early semantic exit, an unrolled loop, a lawful SIMD recurrence, a finite-state quotient, an orbit jump, binary relation powering, a closed form, a compile-time answer, or zero work. |

| # | directive |
|---|---|
| 1 | **Tail recursion is an equivalent recurrence.** A domain-meaningful recursive definition must NOT be rewritten to `while` merely because it eventually loops physically — `fib` carries algebraic structure worth keeping, and its physical realization may be entirely non-recursive. |

## §5 ITERATION — `for`, and the relation chain

| # | directive |
|---|---|
| 1 | for(source) (item) for item in source for(entries) (key, value) body body consume(key, value) |

| # | directive |
|---|---|
| 1 | The canonical face exposes the true structure `iteration(source)(body-relation)` — **control-boundary currying**, not general currying, and normally with partial-application object 0, closure object 0, environment 0. |

| # | directive |
|---|---|
| 1 | `for(users = load()) (user)` binds the SOURCE; the yielded item is not the whole source, so `for(user = users)` is invalid as yield syntax. `for(events) tick()` consumes zero yielded values, and their production should be zero where lawful. |

| # | directive |
|---|---|
| 1 | **Prefer the strongest meaningful relation** — `xs:each/map/filter/fold/any/all/ find`, `users:map(.score)` where `.field` stays exactly one static projection. |
| 2 | Chains must not mandate intermediate collections: the graph sees iteration, refinement, projection, reduction, and may emit one scalar loop, one NEON reduction, an indexed query, a compile-time result, or nothing. |

| # | directive |
|---|---|
| 1 | **Do not force all `for` into chains** (§31), and do not auto-transform loops into map/filter/fold unless equivalence is PROVEN. |

| # | directive |
|---|---|
| 1 | `pairs`/`ipairs` are not canonical — the table/shape/world determines lawful iteration. |
| 2 | If ordering is semantically demanded, that must be explicit through the relation, descriptor or world, never hidden in a helper name. |

## §6 EXITS — `return`, `break`, `continue`

| # | directive |
|---|---|
| 1 | return(value) return value break continue |

| # | directive |
|---|---|
| 1 | **CORRECTED 2026-08-16 — `break()` / `continue()` ARE NOT CANONICAL.** An earlier draft of this section had it backwards. **Bare `break` and bare `continue` are the canonical zero-result exits.** `()` on a zero-payload region exit carries NO information, and the parenthesized face falsely suggests ordinary APPLICATION-ONE behaviour — which is exactly why the compiler refuses `break()` as `expr-unhandled:func_expr`. §12 measured that refusal and the first reading was "a canonical face is broken"; the correct reading is **the compiler was right, and the parenthesized face was the wrong design.** Under SOURCE-MINIMUM a `()` that carries no information is debt. |
| 2 | Revisit only if region exits are ever established as ordinary applicable semantic VALUES, and that architecture proves useful elsewhere. |

| # | directive |
|---|---|
| 1 | **`return` IS DIFFERENT and keeps both faces.** `return(value)` carries a result pack, so the parentheses carry real structure — `return(a, b)` is a pack. |
| 2 | That is a genuine asymmetry with `break`/`continue`, not an inconsistency. |

| # | directive |
|---|---|
| 1 | Tail expression IS the result; no explicit `return` needed. |
| 2 | All tail faces must publish equivalent tail-result demand, so TCO depends on graph position and effects, never spelling. |

| # | directive |
|---|---|
| 1 | `break`/`continue` publish an EXACT region exit once — no downstream "find the nearest loop" AST walk. |
| 2 | The graph meaning is structural, never a mandatory machine branch: |

| # | directive |
|---|---|
| 1 | region exit target exact iteration/recurrence exit (break) exact iteration STEP boundary (continue) result pack empty |

| # | directive |
|---|---|
| 1 | `continue` does NOT mean "jump to the loop header" — that would encode realization. |
| 2 | It means *exit the remainder of this iteration body and proceed to the iteration application's next semantic step*. |
| 3 | Realization may then be a branch, predication, a filtered iteration, **a SIMD lane mask**, or no instruction at all. |
| 4 | That distinction is what keeps a scalar source `continue` from blocking vectorization. |

| # | directive |
|---|---|
| 1 | Where the meaning is really search, prefer the relation: break-on-first-truth is `any`, break-on-first-false is `all`, break-at-first-match is `find`. |

## §7 DEMAGICKING — the keyword ontology shrinks

| # | directive |
|---|---|
| 1 | local/let/var/const -> x = value \| x: descriptor = value function/fun/fn -> add = (a, b) a + b then / do / end -> nothing (grammar already bounds the body) else if -> else(cond) for x in xs -> for(xs) (x) table[key] -> canonical computed projection (same face; parentheses remain ordinary application) string.find(s, p) -> s:find(p) type/struct/class/enum/concept/trait/interface/impl -> descriptors, able(...) module/namespace/import/require -> filesystem-originated static homes, . and @ comptime -> a stage fact, NOT a namespace |

| # | directive |
|---|---|
| 1 | Mutability is determined by whether a semantic place is demanded, not by a declaration keyword. |

## §8 EQUIVALENCE IS A GRAPH CLAIM, NOT A SYNTAX CLAIM

| # | directive |
|---|---|
| 1 | Canonical/familiar pairs must compare IDENTICAL on: application relation, subjects, operands, bindings, regions, results, descriptor facts, range/refinement facts, effects, world, authority, demand, control targets, yield packs, carried state. |
| 2 | Ignore only spelling provenance and formatting spans. |

> **A compiler that produces identical ANSWERS but different semantic GRAPHS for
> familiar and canonical spellings is still WRONG.**

| # | directive |
|---|---|
| 1 | Explicit iteration converges with a chain ONLY IF yield ordering, effects, body relation, results, break/continue behaviour and world observations are equivalent. **Do not assert equivalence because both "look like loops."** |

| # | directive |
|---|---|
| 1 | **Negative controls are required.** Make an effect observable and branch elimination must stop. |
| 2 | Make iteration count observable and recurrence deletion must stop. |
| 3 | Break an algebraic law and the closed-form candidate must vanish. |
| 4 | Introduce alias/effect/order dependence and fusion must stop. |

## §9 ORDERING

| # | directive |
|---|---|
| 1 | Normalize control BEFORE lowering to an opaque CFG — never lower first and try to reconstruct the laws. |
| 2 | Expose opportunities in ladder order: observation, demand, refinement/quotient, recurrence/iteration law, algorithm, representation, movement, parallel, SIMD, ABI, instruction selection, microarchitecture. |

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

| # | directive |
|---|---|
| 1 | **Compatibility is ingress, never authority** — a familiar face may live forever without docs, formatter, graph or backend preserving it. |

## §11 STOP CONDITION

| # | directive |
|---|---|
| 1 | canonical/familiar syntax parity 100% downstream control AST authority 0 spelling-based control resolution 0 duplicate match/switch semantic IR 0 iterator-object requirement 0 forced control-body closure allocation 0 forced loop representation 0 source-form performance divergence 0 |

| # | directive |
|---|---|

## §11.5 CONTROL-ALGEBRA-NOT-METHODS

| # | directive |
|---|---|
| 1 | **Refinement, recurrence and iteration are semantic application ALGEBRAS — not magic relation names projected onto every value.** `if`, `while`, `for`, `else` and familiar `match` are source/control faces that establish regions and publish graph facts, then DISAPPEAR. |
| 2 | They do not imply universal relations named after themselves. |
| 3 | Therefore these are noncanonical and REJECTED: |

| # | directive |
|---|---|
| 1 | value:if(...) source:while(...) source:for(...) value:else(...) |

| # | directive |
|---|---|
| 1 | Each would create a parallel relation ontology for a meaning the algebra already owns. `value:if(action)` would need either a fake relation `if` duplicating refinement, or pure parser sugar — and the latter weakens the invariant that `:` always denotes a real subject-oriented relation. `:else` is worse still: it has no independent subject, so it must either search for an open refinement (a downstream syntax walk, forbidden) or invent a relation. `users:for(body)` says strictly LESS than `users:each(body)`, which at least names the question. |

| # | directive |
|---|---|
| 1 | **This is the exact analogue of PROTOCOL-PROJECTION-ONE §3.1.** Just as *iteration facts ≠ "has a method named `next`"*, so: |

| # | directive |
|---|---|
| 1 | refinement facts != "has a method named `if`" recurrence facts != "has a method named `while`" |

| # | directive |
|---|---|
| 1 | **The algebra is stronger than the face.** A descriptor participates by supplying FACTS — truthiness, transition, termination — never by implementing a control-named method. |
| 2 | A user may not override refinement or iteration by defining `MyType:if` / `MyType:for` / `MyType:while`. |

| # | directive |
|---|---|
| 1 | **THE ONE LEGITIMATE CASE, and its criterion.** A subject-oriented spelling that shares a control word is lawful only if it denotes an **independently meaningful semantic relation whose identity survives without reference to control syntax**: |

| # | directive |
|---|---|
| 1 | text:match(pattern) LAWFUL if `match` genuinely means matching — application { relation: match, subject: text, operand: pattern, result: bool } user:match( … ) FORBIDDEN as conditional dispatch. |
| 2 | Same spelling, categorically different graph. |

| # | directive |
|---|---|
| 1 | The test is never "is this also a control word?" It is "does this relation mean something without the control construct?" Control-`match` is familiar ingress and must disappear into refinement; it may never be inferred FROM the relation. |

| # | directive |
|---|---|
| 1 | **`until` needs no semantic form.** `repeat body until p` is a recurrence whose body runs once before the continuation `!p` is tested. |
| 2 | Retain it as ingress if useful; do not add `state:until(p)`. |

| # | directive |
|---|---|
| 1 | **NO SPELLING-BASED CONTROL RESOLUTION, EVER.** Control parsing is grammar-owned ingress; relation resolution is graph-owned semantics. |
| 2 | A user-defined relation named `while`, or a lexical binding named `if`, must NEVER cause control syntax to dispatch dynamically. |
| 3 | Reserve control words from ordinary relation naming rather than overload parsing on semantic lookup. |
| 4 | After publication neither is reconstructed from source spelling — that is §11's stop condition. |

| # | directive |
|---|---|
| 1 | **THE CANONICAL HIERARCHY:** |

| # | directive |
|---|---|
| 1 | independently meaningful domain relation users:any(.active) |

        >
| # | directive |
|---|---|
| 1 | generic control algebra for(users) (user) |

        >
| # | directive |
|---|---|
| 1 | familiar compatibility face for user in users |

        >
| # | directive |
|---|---|
| 1 | syntactic mimicry users:for(...) REJECTED |

## §12 MEASURED BASELINE — 2026-08-16, idol `06723d39`

| # | directive |
|---|---|
| 1 | Probed by running one program per face and reading its answer, not by reading the parser. |

| face | ruling | today |
|---|---|---|
| `if(cond)` | canonical | **answers** |
| `if cond` | familiar | **answers** |
| `else(pred)` | canonical | **answers** |
| `else if` | familiar, normalize | **NOW PARSES** — §12.2 |
| `while(cond)` | canonical | **answers** |
| `while cond` | familiar | **answers** |
| `for(source) (item)` | **canonical** | **NOW PARSES** — converges with `for x in xs`, §12.2 |
| `for x in xs` | familiar | parses, backend refuses `gen-for-dynamic-iter` |
| `return(v)` / `return v` | both | **answer** |
| `break` | familiar | **answers** |
| `break()` | **canonical** | parses, refused `expr-unhandled:func_expr` |

| # | directive |
|---|---|
| 1 | **THE RULING IS INVERTED ON EXACTLY THE TWO FACES IT NAMES AS CANONICAL.** `for(source) (item)` does not parse at all, and `break()` is misread as an ordinary function application (`func_expr`) — which is §1.5's fake-relation confusion appearing in the compiler rather than in the source. |
| 2 | Meanwhile both familiar counterparts work. |
| 3 | So the formatter cannot yet migrate toward canonical (§10.8) because canonical is the face that does not exist. |

| # | directive |
|---|---|
| 1 | `else if` not parsing is a smaller gap of the same kind: §3 requires it accepted at ingress and normalized to `else(cond)`. |

| # | directive |
|---|---|
| 1 | **Not yet measured:** whether the faces that DO answer publish identical graphs. |
| 2 | Answer parity is not graph parity (§8), and no equivalence gate exists yet. |

### §12.1 `else if` — CORRECTED TWICE, and the real defect is narrower than either reading

| # | directive |
|---|---|
| 1 | The first table entry said `else if` "DOES NOT PARSE". |
| 2 | A lane then reported the opposite — that it parses and emits code byte-identical to `else(pred)`. **Both were wrong, and the truth is a sharper defect than either.** Isolated at idol `1408da4c`, identical programs differing in ONE clause: |

| # | directive |
|---|---|
| 1 | else if WITH a terminating bare `else` answers (rc 2) else if WITHOUT one REFUSED (rc 1) else(pred) WITH a terminating bare `else` answers else(pred) WITHOUT one ANSWERS plain if, no else at all answers |

| # | directive |
|---|---|
| 1 | Indentation is NOT the variable — 2-space and 4-space behave identically on both sides. **The variable is the trailing `else`.** The failure is `this block opened at column N is still open at the file edge`, so the familiar chain never closes unless an unconditional alternative terminates it. |

| # | directive |
|---|---|
| 1 | **THE FAMILIAR FACE CARRIES A CONSTRAINT THE CANONICAL FACE DOES NOT.** That is a direct §3 violation — familiar ingress must normalize to the same refinement, and here `else if` admits a strictly smaller language than `else(cond)`. |
| 2 | A three-alternative chain ending in a bare `else` hides it completely, which is exactly why both earlier readings were confident and wrong: the lane's probe had a terminating `else` and mine did not. |

| # | directive |
|---|---|
| 1 | **Method note, because this is the second time today a control-face claim was wrong in both directions.** Neither reading was reproduced against the other's program before being written down. |
| 2 | The fix that found it was to run BOTH programs, then vary one clause at a time — indent width, then trailing `else` — until a single variable separated them. |
| 3 | A face that "does not parse" and a face that "parses" can both be true of the same construct under different terminations, and a one-program probe cannot tell the difference. |

### §12.2 CLOSED — both faces landed, and the real finding is underneath them

| # | directive |
|---|---|
| 1 | At `f5ed4404` + `src/parser.zig` (434 insertions, 0 deletions): |

| # | directive |
|---|---|
| 1 | else if, NO trailing else answers 2 (was REFUSED — §12.1's defect) else(pred), NO trailing else answers 2 for(source) (item) PARSES, converges with `for x in xs` |

| # | directive |
|---|---|
| 1 | **A §8 VIOLATION WAS FOUND AND CLOSED ON THE WAY, and it is the reason §12.1's defect existed.** At base the two refinement faces built DIFFERENT TREES while answering identically: |

| # | directive |
|---|---|
| 1 | else if -> elseifs=0 else_body=true nested_if=true else(cond) -> elseifs=1 else_body=true nested_if=false |

| # | directive |
|---|---|
| 1 | `else if` was being desugared into a NESTED `if` inside an else body rather than into an alternative — which is exactly why it needed a terminating `else` to close. |
| 2 | Both are now `elseifs=1`, and `else if` additionally emits **byte-identical `__text` and `nm` T-symbols** to `else(cond)`. |

| # | directive |
|---|---|
| 1 | `for(source) (item)` has no bytes to compare from either face: `gen_for` is refused by every live backend (direct `gen-for-dynamic-iter`, wasm `refused at: gen_for`). |
| 2 | Both faces produce **byte-identical diagnostics and bail sites**, which is convergence honestly stated rather than a proxy dressed as proof. |

| # | directive |
|---|---|
| 1 | Verified: `zig build test` 1626/1627 -> 1632/1633 (+6); corpus compile differential 1015/1015 and 142/142 IDENTICAL; run differential 142/142 and 1014/1015 (the one row is `examples/shc/cwd.id`, which prints the cwd); `design`/`edge`/`any`/`obseq`/`selfhost` identical on both compilers, `any` still 5145, `selfhost` still 9/17. |

| # | directive |
|---|---|
| 1 | **THE FINDING THAT OUTRANKS BOTH PARSE FIXES.** `ast.Stmt.brk` is a `Loc` — **a location and nothing else. |
| 2 | No target, no result pack.** The exit target is rebuilt at `src/dnir_lower.zig:2705` from `ctx.loop_breaks[len-1]`, a stack pushed and popped during a recursive AST descent: literally *find the nearest enclosing loop*. |
| 3 | And `semantic_graph.zig`'s `NodeKind` has **no iteration, recurrence, refinement, region or exit kind at all.** |

| # | directive |
|---|---|
| 1 | So §11's stop condition pins `downstream control AST authority` and `spelling-based control resolution` at 0, and both are currently **TOTAL**. §10.3 — *the semantic graph owns normalized control facts* — has not started. |
| 2 | One immediate consequence: **`break` cannot name a target, so multi-level exit is inexpressible.** |

| # | directive |
|---|---|
| 1 | **FALSIFIER, as given by the lane that found it:** give the graph a control node kind and publish the exit target at parse; if the faces still converge and `loop_breaks` can then be deleted, the finding holds. |
| 2 | If some consumer needs the AST nesting that stack provides, the characterisation is incomplete. |
