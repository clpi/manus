# Idsem durable project orientation

You are working on Idsem (idol .id).

Your task is not to translate an existing compiler into prettier syntax.

Your task is to converge a single semantic system whose governing principle is:

semantic identity persists; representation changes.

Canonical native source uses: .id

Historical Duo, Duon and .duo material is migration or provenance unless current
repository authority explicitly states otherwise.

Repository truth and current owner-active authority override historical
documents, stale examples, prior agent assumptions, and this prompt on
implementation-state details.

If current implementation contradicts an established architectural law, treat that
as migration debt rather than evidence that the law is wrong.

## first action

Before modifying anything:

1. Inspect current main, head, dirty state, active claims, and recent commits.
2. Read the repository authority chain: constitution, grammar/source authority,
   agent instructions, bootstrap/selfhost state, subsystem owners.
3. Identify the exact semantic boundary being changed.
4. Identify authoritative producers of required facts.
5. Identify downstream consumers of those facts.
6. Detect overlap with other active ownership.
7. Determine authority shifts and remove duplicates.
8. If conflicts exist, report one precise authority conflict. Do not invent a
   third interpretation.

Do not begin from conventional compiler design assumptions.

Begin from:

What semantic observation, relation, value, dependency, state, law, or effect is
required?

## identity

There is one semantic identity space.

Do not derive identity from:

* source spelling
* filename
* .id suffix
* namespace
* parser node type
* host enum
* backend opcode
* machine instruction
* local counters
* textual composites
* hashes alone

A hash may accelerate lookup only when it is provably collision-safe relative to
semantic identity.

A hash is evidence or acceleration, not identity.

Distinct occurrences of the same relation remain distinct application
identities with independent provenance and demand.

## one meaning

Each irreducible semantic meaning has:

* one identity
* one canonical native word
* zero parallel names

Prefer existing vocabulary:

relation, subject, value, pack, binding, descriptor, shape, place, world,
effect, demand, law, origin, stage, witness, provenance, realization, identity,
span, token, role, view, run, outcome, evidence

Do not encode qualification into relation names.

Facts qualify meaning. Realization carries physical choice.

## naming

Canonical vocabulary is lowercase.

Use one word for irreducible meaning.

Do not introduce names containing:

* underscores
* casing conventions
* host compiler jargon
* backend or OS jargon
* transport or ABI qualifiers
* representation qualifiers

Foreign identifiers may retain spelling only when required for provenance.

Foreign spelling does not become native vocabulary.

If no irreducible meaning remains after decomposition:

SEMANTIC-VOCABULARY-BLOCKED

## source

Canonical language: Idsem

Canonical source: .id

Historical .duo is compatibility or migration provenance.

There is exactly one source-family authority.

Do not duplicate suffix logic across compiler, formatter, LSP, MCP, or tooling.

Project branding is not ontology.

Do not create artificial namespaces like "idsem graph/value/relation" when the
concepts are simply: graph, value, relation

## source faces

Human syntax may differ while converging semantically.

Current delimiter model:

* () call / grouping
* {} structured packs / descriptors
* [] computed or indexed projection
* . named projection
* : subject/descriptor constraint

Do not collapse these into a single delimiter system.

Minimal grammar means minimal irreducible distinctions, not minimal characters.

## structured values

{} is neutral structure.

It does not imply object, class, heap, or record allocation.

Materialization is optional and demand-driven.

Only write what cannot be reconstructed.

## descriptor homes

A home organizes structure; it does not define ownership.

Relations declared in a home remain global semantic relations.

No method/class/member-function identity exists.

## subject

Subject is a semantic role, not argument position.

It is not inferred from syntax position, naming, or location.

Subject resolution must be explicit and preserved.

: form uses ambient subject when defined.

It must not be conflated with ordinary function calls.

## pack

Arguments and results are semantic packs.

A pack preserves:

identity, order, labels, values, descriptors, provenance, demand

Do not flatten into host tuples or reconstruct later.

Unknown, empty, zero, and false are distinct.

## value

A value is identity plus facts.

It is not a storage class.

Do not map to:

local, temp, stack, heap, register, record

Binding is not place unless demand requires it.

## place

A place exists only if semantically required.

Do not preserve storage artifacts from host compilers.

If no place is required, eliminate it entirely.

## control

Control syntax is not IR ontology.

After normalization, meaning is expressed as:

* conditions
* demands
* dependencies
* effects
* continuations

Not as syntactic categories.

## grammar

Authority chain:

source -> lexer -> grammar -> parser -> semantic resolver -> graph ->
demand -> realization

Each stage preserves strongest known fact.

No stage reconstructs earlier stages from text.

Lexer identifies tokens; grammar assigns roles; parser consumes roles;
resolver assigns meaning.

No handwritten keyword/punctuation tables.

If missing projection:

IMPLEMENTATION-BLOCKED

## lexical law

* " text
* ' bytes
* # comment
* len is relation, not syntax
* backtick reserved unless explicitly defined

Lua compatibility is historical only.

No implicit execution semantics.

## numbers

Numeric forms (i64, u32, f64) remain compact source faces.

Do not prematurely assign semantic or physical representation.

Separate:

* numeric meaning
* constraints
* realization

## foreign

Foreign systems retain their own laws until equivalence is proven.

Do not flatten C/Rust/Wasm/etc into native semantics.

Preserve:

origin, ABI, ownership, aliasing, failure semantics, uncertainty

## world

World authority is explicit, not namespace-based.

No std.* style implicit authority systems.

World facts grant capability, not imports.

## files and packages

Files do not define identity.

Paths do not define semantics.

No import system is assumed unless explicitly required by authority.

## dnir

DNIR is a realization layer only.

It does not introduce new semantic vocabulary.

It may define:

representation, target, ABI, linkage, placement, schedule, encoding

but not rename semantics.

## transformation

Transformations preserve lineage.

Even when folded or optimized, original semantic application identity remains
traceable.

## demand

Demand determines what must exist.

Do not materialize structures that are never demanded.

Eliminate unnecessary abstraction before construction.

## realization

Semantic graph defines meaning.

Demand defines necessity.

Realization defines physical execution.

Do not collapse realization choices prematurely.

## performance

Goal: FTCFTW

Maximize semantic knowledge, minimize compiler state.

Avoid unnecessary IR duplication or abstraction layers.

## selfhost

Self-hosting is measured by transferred semantic authority, not file count or
structure replication.

## host pattern zero

Do not inherit host compiler architecture patterns as semantic truth.

Translate only real semantic requirements, not implementation artifacts.

## evidence

Truth requires executed production evidence.

Not schema, not fixture, not file presence.

Only actual execution outcome counts.

## concurrency

Do not resolve conflicts by reintroducing removed authority.

Missing facts are preferable to shadow systems.

## no fallback authority

Never reconstruct missing semantic truth from text or inference.

Fail closed.

## relation admission

A new relation is allowed only if:

* no existing relation covers it
* it is irreducible after full decomposition
* it is not representable as descriptor, shape, or provenance

## tooling

Tools operate on graph identity, not text inference.

## canonical code

Canonical .id is stricter than compatibility code.

Correctness includes semantic authority, not just parsing.

## historical source

History is preserved but never authoritative over current grammar.

## unresolved grammar

Never resolve grammar from examples.

Only from current machine-authoritative grammar source.

## scope

Keep changes local.

Do not expand into unrelated subsystems.

## adversarial mindset

Every rule must survive a degenerate implementation test.

## completion standard

A change is complete only when:

* semantic boundary is uniquely owned
* no downstream re-derivation occurs
* authority is singular

Report:

boundary, authority, identity, facts, loss, bridges, world, realization,
evidence, performance, blocker

Then stop.

## absolute project law

Do not turn Idsem into another conventional compiler.

Do not turn semantics into syntax.

Do not turn representation into identity.

Do not turn naming into ontology.

One meaning. One identity. One word.
