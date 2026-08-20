# Idol source, home, reach, and world projection

This file is a **non-authoritative projection** of `docs/spec/law.md` (supreme compact
law) and `docs/spec/constitution.md` (structured expansion). It exists to orient
source-layout and resolution work. When this projection diverges from the compact law
or its structured expansion, the compact law wins. It may never mint semantic
vocabulary or become an independent grammar/module/package law.

The exhaustive predecessor is preserved in Git history through
`a2986997a12857d10bd76c9e8eb1efff772eee17` and the research ancestry merges on
`main`. Its useful findings remain provenance; contradictions do not remain law.

## Identity and boundaries

The project and language are **Idol**. Canonical source uses `.id` and the
compiler executable is `idol`.

Keep these boundaries distinct:

```text
source       bytes, spans, source law, provenance
grammar      generated recognition projection of the selected source law
world        reachable bindings, authority, stage, target, observers
graph        exact semantic identities, applications, values, facts, witnesses
demand       what may be observed or must be produced
realization  physical representation and execution
```

The flow is:

```text
recognize(source, law)
→ resolve(syntax provenance, world)
→ publish exact graph facts
→ project demand
→ choose lawful realization
→ machine/evidence
```

No later phase reconstructs meaning from filenames, paths, token spelling,
AST shape, local enums, opcodes, or host-language types.

## Delimiter law

Delimiter identity is permanent and non-overloaded:

```text
()  ordinary relation application / grouping / operand and result packs
[]  computed or indexed projection
{}  structured pack, table, descriptor structure
.   named/static projection
:   subject-oriented relation or constraint face
@   current-world access, injection, and qualification (law.md §5)
```

Canonical computed projection is indexed projection: `table[key]`.
Parentheses remain ordinary relation application. A compatibility parser may
accept historical spellings only by publishing their exact provenance and
canonicalizing them before semantic consumption; compatibility never changes the
meaning of a delimiter.

## Files and directories

A canonical `.id` file is a source partition, not a module. A directory may
supply discovery and home provenance, but it is not a namespace object and does
not grant authority.

```text
main/
  main.id
  parser.id
  lexer.id
```

may project ordinary reachable homes/bindings such as `main`, `parser`, and
`lexer`. After resolution, semantic continuity is carried by graph identity and
witnesses rather than path spelling.

Do not add native concepts or source ceremony corresponding to:

```text
module namespace import require req include package-loader registry std
use using open expose inject admit provide service-locator dependency-container
```

Existing occurrences are migration debt or exact foreign-law provenance. They
are not templates for new Idol code.

## Home, reach, subject, and world

Never conflate:

| question | graph answer |
|---|---|
| where does meaning live? | home/provenance facts |
| can this scope resolve it? | reach/binding facts |
| what value or place is operated on? | subject/value/place identity |
| what authority may the application exercise? | world grant + witness |

Absolute invariants:

```text
home != subject
home != world
path != identity
package provenance != world grant
value != place
binding != place
projection witness != semantic identity
```

A world grants authority. A relation/protocol demands facts. A witness proves
satisfaction. Filesystem position, dependency possession, a host global, or an
organizational home never grants a world.

## Subject orientation and projection

When `source` is the semantic value being parsed, canonical orientation is:

```id
tree = source:parse()
tokens = source:scan()
```

When `table` is an aggregate value and `key` is computed:

```id
value = table[key]
table[key] = replacement
```

When `user` has a statically named projection:

```id
name = user.name
```

Bare and qualified faces may resolve to the same semantic identity when an exact
witness proves equivalence. The witness may differ; the relation/value identity
does not. Ambiguity fails closed—never first/last/load/path/hash order.

## Dependency and distribution

A resolved reference contributes its own semantic dependency. Build/distribution
configuration may establish acquisition, version, provenance, trust, and which
roots are reachable. Source does not repeat that fact with an import operation.

A package is distribution provenance for ordinary graph content. Native Idol has
no runtime package object, package registry, module table, or standard namespace
unless observation and demand independently require an ordinary value with that
shape.

## Canonical vocabulary

Canonical vocabulary is compiler-owned initial reachability of admitted semantic
identities such as `len`, `iter`, `read`, `write`, `run`, `to`, and `from` only
where current law admits them. It is not a `std` object and not a second registry
for the compiler, formatter, LSP, MCP, shell, or documentation.

## Inference and minimum source

Source contributes only information not uniquely recoverable from graph-visible
subject, operands, result demand, descriptors, reachable facts, world/effect
requirements, stage, target, provenance, and control-flow refinement.

Omit a conversion/application face when unique; spell the shortest form that
resolves exactly when it is not. Never bulk-delete syntax without an identity
witness, and never preserve redundant syntax merely because inference is not yet
implemented—record the implementation gap instead.

One-use intermediates disappear when the chain preserves semantic identity.
Names remain when they add semantic information, multiple consumers, observable
place identity, or human-facing provenance.

## Foreign source

Lua, C, shell, Wasm, or another admitted source partition keeps its exact foreign
source law and provenance at ingress. Foreign module/import/package concepts may
be represented as foreign facts, then projected onto existing Idol identities
only where equivalence is witnessed. They do not extend native Idol ontology.

Never try several grammars and choose one that accepts, switch source law from
command-looking text, or infer authority from source syntax.

## Realization and FTCFTW

The target path is:

```text
.id → semantic graph → demand → realization → machine
```

For equivalent semantics, Idol pays no runtime cost for source partitions,
homes, package provenance, statically settled worlds, canonical vocabulary,
unused values, or unused places. Demand and observation delete work before
representation selection.

A performance mechanism is admitted only with observation equivalence, exact
negative controls, current-revision evidence, and a measured Pareto improvement.
A non-performance change must preserve the strongest available performance
baseline and may not claim an improvement.

## Migration and deletion

Legacy mechanisms remain searchable in Git and in
`research/archive/pass-2/`; they do not govern current code. Each bridge must
have a named consumer and deletion condition. High-priority deletion targets
include:

- call-shaped indexing and any parser/lowering branch that confuses call with projection;
- path/name/AST-pointer reconstruction after graph resolution;
- runtime module/namespace/`std` machinery;
- duplicate grammar, descriptor, result, builtin, world, or optimization registries;
- semantic decisions encoded only in DNIR/local opcodes;
- consumer-zero production analysis modules;
- stale session-state and branch-local authority documents.

Unimplemented findings remain exact gaps or research lineage until closed by
code, controls, and evidence. Consolidation never means silent deletion.