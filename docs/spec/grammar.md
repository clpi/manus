# Idol grammar projection

The supreme compact law is [`docs/spec/law.md`](law.md); [`docs/spec/constitution.md`](constitution.md)
is its structured expansion. This page is a human projection of closed
source-face decisions; it is not a grammar authority and must not be used to
hand-build parser tables.

The repository does not yet contain the complete machine-readable grammar that
the production parser, formatter, canonicalizer, Tree-sitter, LSP, MCP, tests,
and documentation must share. `GAP-134` owns that missing authority and its
generated roles. `GAP-145` owns the distinct lexical identities and immutable
token view required to consume it. Until they close, compiler acceptance is not
proof that a spelling is canonical.

## Lexical law

- canonical project-owned source uses `.id`;
- names are one lowercase semantic word;
- double quotes delimit text;
- single quotes delimit bytes;
- `#` begins a line comment;
- backtick is reserved and never executes a process;
- blocks use offside layout;
- `end`, semicolons, `then`, `do`, Lua long strings/comments, and prefix
  directives are not canonical Idol.

Compatibility recognition preserves its foreign or historical lawset and
provenance. It never shares canonical token identity and never supplies a
pattern for new `.id`.

## Delimiter roles

The lexer identifies delimiters, the grammar assigns roles, the parser consumes
roles, and resolution assigns meaning. Punctuation contributes no semantic
identity or physical representation choice after normalization.

- `()` is ordinary application and grouping only — never aggregate indexing:
  `f(a, b)`, `(x + y)`; computed projection is `[]`, e.g. `values[i]`;
- `{}` bounds structured packs, descriptor application, and descriptor homes;
- `.` is only statically named projection after an explicit subject:
  `user.name`; leading `.name` and bare `.` are noncanonical;
- `:` carries only its admitted descriptor, subject, and home roles:
  `text:len()` for an explicit subject and `:normalize()` for the ambient
  subject;
- `@` IS THE CURRENT-WORLD ACCESSOR (`docs/spec/law.md` §4 + World+projection
  add-on): bare `@` is the current-world value, `@member` accesses a static
  current-world member (`@` is the accessor itself, so `@member.child` is one
  world access then one ordinary static projection), `value@world` evaluates
  `value` under `world`, `@{ k = v }` derives a world with injected facts
  (injection), `thing@{ k = v }` evaluates a subtree under that derived world
  (interjection), and `@member = v` mutates a world member place. INVALID:
  `@.member` and `@:member` — `@` already accesses, so there is no `@.` step and
  no `@:` dispatch. It never introduces a compiler directive
  (`@comp`/`@host`/`@runtime`/…).

Canonical structured faces include:

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

An ordinary callable uses parentheses. A descriptor applies to structured
content with braces. A statically known field or key uses a named projection or
structured label. A computed aggregate key is a computed projection; it does
not introduce an indexing-application or semantic kingdom:

```id
user.name
table[key]

{
    name = value
}
```

Parentheses remain ordinary application and never aggregate indexing; a foreign
source law may recognize its own bracket or call indexing inside that law's
grammar projection, but the source form remains provenance and cannot become
canonical Idol application semantics.

None of these faces implies a table, record, object, allocation, place, nested
container, hash lookup, boxing, or dispatch.

## Update face

Compound update is the canonical face only when an equivalence witness proves
that `place op= value` and `place = place op value` request the same update.
The face adds no semantic operation: normalization retains the base relation
`op`, the exact place, its read, write, and update facts, the incoming value,
result demand, effects, and provenance. There is no `addassign` relation family
and no `++` face. When the witness exists, the compound form is the canonical
shortest face and the expanded form is migratable.

The witness must prove all of the following:

- the read and write designate the exact same place;
- a computed place and every expression that establishes it are evaluated
  exactly once;
- evaluation order and observable effects are unchanged;
- custom relation law, overflow, failure, aliasing, and result demand are
  preserved.

For example, `step += 1` may be canonical when those facts prove it equivalent
to `step = step + 1`. A different right-hand place, a repeated computed key, or
an update whose relation law or observations differ is not mechanically
rewritable.

The authoritative formatter and gate must decide from graph facts and the
equivalence witness. That implementation remains blocked by the distinct
lexical identities in `GAP-145`, generated grammar roles in `GAP-134`, and the
graph-derived semantic canonicality service in `GAP-124`. Any current text
ratchet, including the added-line check in `gate/idiom.id`, is
non-authoritative migration pressure and may not claim equivalence.

<!-- grammar:begin -->
## Grammar facts (generated)

<!-- Generated from lib/compiler/token.id via src/grammar_role_table.zig.
     Regenerate: idol run lib/compiler/token.id, then sh gate/grammar/spec.sh.
     Every row is an owner fact; the prose around it is authored law. -->

One grammar-fact owner (law.grammar.one): lib/compiler/token.id.

  name name
  int_lit integer
  float_lit float
  kw_false false
  kw_function function
  kw_fun fun
  kw_if if
  kw_nil nil
  kw_not not
  kw_true true
  kw_i8 i8
  kw_i16 i16
  kw_i32 i32
  kw_i64 i64
  kw_u8 u8
  kw_u16 u16
  kw_u32 u32
  kw_u64 u64
  kw_f32 f32
  kw_f64 f64
  kw_bool bool
  kw_void void
  kw_str str
  kw_match match
  kw_await await
  kw_comptime comptime
  lparen (
  lbrace {
  minus -
  hash #
  pipe |
  tilde ~
  colon :
  dot .
  at @
  bang !
  dots ...
  hash_hash ##
  text_lit text
  bytes_lit bytes
  compat_text_lit compat_text
  compat_long_text_lit compat_long_text

Total: 42 identities.
### Operator precedence and associativity

Highest number binds tightest (Pratt binding power from the owner):

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
<!-- grammar:end -->

## Parser boundary

Parser output records the minimum source structure and provenance needed for
resolution. It does not mint relation, subject, application, value, world,
demand, failure, or representation identity. Subject roles, descriptor facts,
semantic cases, and transitions belong to the resolver and graph.

The missing machine grammar must generate token roles, expression and binding
starts, descriptor-member roles, delimiter capabilities, prefix/postfix roles,
precedence, associativity, block/offside behavior, and compatibility status.
No consumer may maintain a punctuation list, keyword list, expression-start
chain, or source-text fallback beside that authority.

## Authority pipeline

The closed recognition chain is:

```text
source → lexer → grammar → parser → semantic resolver → graph → demand → realization → machine
```

Each stage preserves the strongest fact already known. No stage reconstructs an
earlier stage from text, names, hashes, or backend shape.

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

Foreign source faces enter only through explicit foreign import with provenance.
They do not share native token identity or supply patterns for new `.id`.

Until `GAP-145` (lexical identities) and `GAP-134` (generated grammar roles)
close, any hand-maintained keyword table, punctuation list, or text classifier
is bootstrap debt — report `IMPLEMENTATION-BLOCKED`, not a workaround parser
kingdom.

Tools, gates, LSP, MCP, formatter, and canonicalizer consume graph facts and
admitted projections. They do not infer meaning from formatted text or
substring detectors.
