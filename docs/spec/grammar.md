| field | value |
|---|---|
| title | Idol grammar projection |

| # | directive |
|---|---|
| 1 | The supreme compact law is [`docs/spec/law.md`](law.md) |
| 2 | [`docs/spec/constitution.md`](constitution.md) is its structured expansion. |
| 3 | This page is a human projection of closed source-face decisions; it is not a grammar authority and must not be used to hand-build parser tables. |

| # | directive |
|---|---|
| 1 | The repository does not yet contain the complete machine-readable grammar that the production parser, formatter, canonicalizer, Tree-sitter, LSP, MCP, tests, and documentation must share. `GAP-134` owns that missing authority and its generated roles. `GAP-145` owns the distinct lexical identities and immutable token view required to consume it. |
| 2 | Until they close, compiler acceptance is not proof that a spelling is canonical. |

| section |
|---|---|
| Lexical law |

| # | directive |
|---|---|
| 1 | canonical project-owned source uses `.id`; |
| 2 | names are one lowercase semantic word; |
| 3 | double quotes delimit text; |
| 4 | single quotes delimit bytes; |
| 5 | `#` begins a line comment; |
| 6 | backtick is reserved and never executes a process; |
| 7 | blocks use offside layout; |
| 8 | `end`, semicolons, `then`, `do`, Lua long strings/comments, and prefix directives are not canonical Idol. |

| # | directive |
|---|---|
| 1 | Compatibility recognition preserves its foreign or historical lawset and provenance. |
| 2 | It never shares canonical token identity and never supplies a pattern for new `.id`. |

| section |
|---|---|
| Delimiter roles |

| # | directive |
|---|---|
| 1 | The lexer identifies delimiters, the grammar assigns roles, the parser consumes roles, and resolution assigns meaning. |
| 2 | Punctuation contributes no semantic identity or physical representation choice after normalization. |

| # | directive |
|---|---|
| 1 | `()` is ordinary application and grouping only — never aggregate indexing: `f(a, b)`, `(x + y)`; computed projection is `[]`, e.g. `values[i]`; |
| 2 | `{}` bounds structured packs, descriptor application, and descriptor homes; |
| 3 | `.` is only statically named projection after an explicit subject: `user.name`; leading `.name` and bare `.` are noncanonical; |
| 4 | `:` carries only its admitted descriptor, subject, and home roles: `text:len()` for an explicit subject and `:normalize()` for the ambient subject; |
| 5 | `@` IS THE CURRENT-WORLD ACCESSOR (`docs/spec/law.md` §4 + World+projection add-on): bare `@` is the current-world value, `@member` accesses a static current-world member (`@` is the accessor itself, so `@member.child` is one world access then one ordinary static projection), `value@world` evaluates `value` under `world`, `@{ k = v }` derives a world with injected facts (injection), `thing@{ k = v }` evaluates a subtree under that derived world (interjection), and `@member = v` mutates a world member place. INVALID: `@.member` and `@:member` — `@` already accesses, so there is no `@.` step and no `@:` dispatch. It never introduces a compiler directive (`@comp`/`@host`/`@runtime`/…). |

| # | directive |
|---|---|
| 1 | Canonical structured faces include: |

```id
{ x, y }

{
    x = a
    y = b
}

point{ x, y }

p: point = { x, y }

point: {
    x: f64
    y: f64
    len = ()
        (x*x + y*y):sqrt()
}
```

| # | directive |
|---|---|
| 1 | An ordinary callable uses parentheses. |
| 2 | A descriptor applies to structured content with braces. |
| 3 | A statically known field or key uses a named projection or structured label. |
| 4 | A computed aggregate key is a computed projection; it does not introduce an indexing-application or semantic kingdom: |

```id
user.name
table[key]

{
    name = value
}
```

| # | directive |
|---|---|
| 1 | Parentheses remain ordinary application and never aggregate indexing; a foreign source law may recognize its own bracket or call indexing inside that law's grammar projection, but the source form remains provenance and cannot become canonical Idol application semantics. |

| # | directive |
|---|---|
| 1 | None of these faces implies a table, record, object, allocation, place, nested container, hash lookup, boxing, or dispatch. |

| section |
|---|---|
| Update face |

| # | directive |
|---|---|
| 1 | Compound update is the canonical face only when an equivalence witness proves that `place op= value` and `place = place op value` request the same update. |
| 2 | The face adds no semantic operation: normalization retains the base relation `op`, the exact place, its read, write, and update facts, the incoming value, result demand, effects, and provenance. |
| 3 | There is no `addassign` relation family and no `++` face. |
| 4 | When the witness exists, the compound form is the canonical shortest face and the expanded form is migratable. |

| # | directive |
|---|---|
| 1 | The witness must prove all of the following: |

| # | directive |
|---|---|
| 1 | the read and write designate the exact same place; |
| 2 | a computed place and every expression that establishes it are evaluated exactly once; |
| 3 | evaluation order and observable effects are unchanged; |
| 4 | custom relation law, overflow, failure, aliasing, and result demand are preserved. |

| # | directive |
|---|---|
| 1 | For example, `step += 1` may be canonical when those facts prove it equivalent to `step = step + 1`. |
| 2 | A different right-hand place, a repeated computed key, or an update whose relation law or observations differ is not mechanically rewritable. |

| # | directive |
|---|---|
| 1 | The authoritative formatter and gate must decide from graph facts and the equivalence witness. |
| 2 | That implementation remains blocked by the distinct lexical identities in `GAP-145`, generated grammar roles in `GAP-134`, and the graph-derived semantic canonicality service in `GAP-124`. |
| 3 | Any current text ratchet, including the added-line check in `gate/idiom.id`, is non-authoritative migration pressure and may not claim equivalence. |

| # | directive |
|---|---|
| 1 | <!-- grammar:begin --> |

| section |
|---|---|
| Grammar facts (generated) |

| # | directive |
|---|---|
| 1 | <!-- Generated from lib/compiler/token.id via src/grammar_role_table.zig. |
| 2 | Regenerate: idol run lib/compiler/token.id, then sh gate/grammar/spec.sh. |
| 3 | Every row is an owner fact; the prose around it is authored law. --> |

| # | directive |
|---|---|
| 1 | One grammar-fact owner (law.grammar.one): lib/compiler/token.id. |

| # | directive |
|---|---|
| 1 | name name int_lit integer float_lit float kw_false false kw_function function kw_fun fun kw_if if kw_nil nil kw_not not kw_true true kw_i8 i8 kw_i16 i16 kw_i32 i32 kw_i64 i64 kw_u8 u8 kw_u16 u16 kw_u32 u32 kw_u64 u64 kw_f32 f32 kw_f64 f64 kw_bool bool kw_void void kw_str str kw_match match kw_await await kw_comptime comptime lparen ( lbrace { minus - hash # pipe \| tilde ~ colon : dot . at @ bang ! dots ... hash_hash ## text_lit text bytes_lit bytes compat_text_lit compat_text compat_long_text_lit compat_long_text |

| # | directive |
|---|---|
| 1 | Total: 42 identities. |

| section |
|---|---|
| Operator precedence and associativity |

| # | directive |
|---|---|
| 1 | Highest number binds tightest (Pratt binding power from the owner): |

```text
  4    and            left
  6    in             nonassoc
  9    not            none
  2    or             left
  17   +              left
  17   -              left
  19   *              left
  19   /              left
  19   %              left
  23   ^              right
  11   &              left
  7    |              left
  6    <              nonassoc
  6    >              nonassoc
  1    =              right
  9    ~              left
  10   .              none
  19   @              left
  9    !              none
  16   ..             right
  6    ==             nonassoc
  6    !=             nonassoc
  6    <=             nonassoc
  6    >=             nonassoc
  13   <<             left
  13   >>             left
  19   //             left
  1    |>             left
  1    +=             right
  1    -=             right
  1    *=             right
  1    /=             right
  1    %=             right
  1    ^=             right
```
| # | directive |
|---|---|
| 1 | <!-- grammar:end --> |

| section |
|---|---|
| Parser boundary |

| # | directive |
|---|---|
| 1 | Parser output records the minimum source structure and provenance needed for resolution. |
| 2 | It does not mint relation, subject, application, value, world, demand, failure, or representation identity. |
| 3 | Subject roles, descriptor facts, semantic cases, and transitions belong to the resolver and graph. |

| # | directive |
|---|---|
| 1 | The missing machine grammar must generate token roles, expression and binding starts, descriptor-member roles, delimiter capabilities, prefix/postfix roles, precedence, associativity, block/offside behavior, and compatibility status. |
| 2 | No consumer may maintain a punctuation list, keyword list, expression-start chain, or source-text fallback beside that authority. |

| section |
|---|---|
| Authority pipeline |

| # | directive |
|---|---|
| 1 | The closed recognition chain is: |

```text
source → lexer → grammar → parser → semantic resolver → graph → demand → realization → machine
```

| # | directive |
|---|---|
| 1 | Each stage preserves the strongest fact already known. |
| 2 | No stage reconstructs an earlier stage from text, names, hashes, or backend shape. |

| Stage | Owns | Must not own |
|---|---|---|
| Lexer | token identity, content, span, provenance | semantic roles inferred from punctuation spelling |
| Grammar | roles, precedence, associativity, block/offside | meaning, world, relation, or representation identity |
| Parser | minimum structure and provenance for resolution | relation, subject, application, demand, failure cases |
| Resolver | subject, binding, scope, home reachability | storage class, opcode, target, or schedule choice |
| Graph | semantic identity, facts, application lineage, witnesses | text spelling authority or parser-node ontology |
| Demand | observable necessity, effects, result requirements | premature materialization |
| Realization (DNIR) | target, ABI, linkage, placement, schedule, encoding | new semantic vocabulary or renamed graph meaning |
| Machine | instructions, objects, ranges, physical artifacts | recovered semantics from opcodes or names |

| # | directive |
|---|---|
| 1 | Foreign source faces enter only through explicit foreign import with provenance. |
| 2 | They do not share native token identity or supply patterns for new `.id`. |

| # | directive |
|---|---|
| 1 | Until `GAP-145` (lexical identities) and `GAP-134` (generated grammar roles) close, any hand-maintained keyword table, punctuation list, or text classifier is bootstrap debt — report `IMPLEMENTATION-BLOCKED`, not a workaround parser kingdom. |

| # | directive |
|---|---|
| 1 | Tools, gates, LSP, MCP, formatter, and canonicalizer consume graph facts and admitted projections. |
| 2 | They do not infer meaning from formatted text or substring detectors. |
