# Idsem grammar projection

The sole language law is [`docs/spec/constitution.md`](constitution.md). This
page is a human projection of closed source-face decisions; it is not a second
grammar authority and must not be used to hand-build parser tables.

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
  directives are not canonical Idsem.

Compatibility recognition preserves its foreign or historical lawset and
provenance. It never shares canonical token identity and never supplies a
pattern for new `.id`.

## Delimiter roles

The lexer identifies delimiters, the grammar assigns roles, the parser consumes
roles, and resolution assigns meaning. Punctuation contributes no semantic
identity or physical representation choice after normalization.

- `()` is ordinary callable application and grouping: `f(a, b)`;
- `{}` bounds structured packs, descriptor application, and descriptor homes;
- `[]` is genuinely computed or indexed projection: `values[i]`;
- `.` after an explicit subject is statically named projection: `user.name`;
  bare `.` denotes the ambient subject value and never abbreviates `.name`;
- `:` carries only its admitted descriptor, subject, and home roles:
  `text:len()` for an explicit subject and `:normalize()` for the ambient
  subject;
- `@` supplies a semantic anchor only: bare `@` names the enclosing descriptor,
  `value@relation` selects that relation anchored at `value`, and `@{...}` is
  the ambient descriptor applied to structured content. It never introduces a
  compiler directive.

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
structured label. Brackets remain only when evaluating an expression supplies
the key:

```id
user.name
table[key]

{
    name = value
    [key] = computed
}
```

None of these faces implies a table, record, object, allocation, place, nested
container, hash lookup, boxing, or dispatch.

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
