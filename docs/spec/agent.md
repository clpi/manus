# Idol — Authoritative Language and Architecture Specification

**STATUS:** SOLE NEW-AGENT BOOTSTRAP  
**PURPOSE:** LANGUAGE LAW + COMPILER LAW + REPOSITORY LAW + CONVERGENCE LAW  
**MODE:** FAIL CLOSED

This document describes the intended language and architecture, not merely the
current implementation. Implementation conflicts are implementation defects.
Historical source, old examples, migration code, stale documentation, host
language patterns, agent output, and repository accidents do not override this
specification.

Conflict rule: `docs/spec/law.md` is the SUPREME one-page law and is
authoritative over every document. `docs/spec/constitution.md` (C0) is the
structured long-form expansion of `docs/spec/law.md` and the home of the `law.*`
identities. This file is constitutional interpretation for new agents. If this
file conflicts with `docs/spec/law.md` or C0, the higher authority wins and this
file must be repaired; where C0 itself diverges from `docs/spec/law.md`, C0 is
corrected to match `docs/spec/law.md`.

## I. Primary Principle

Idol is:
    ordinary semantic values progressively becoming more precisely known.
The specialization ladder is:
    dynamic
    → inferred
    → guarded
    → sealed
    → representation selected
    → target specialized
The programmer should normally not rewrite a program merely to move upward on
this ladder.
The compiler learns.
The program remains semantically the same.
Fundamental invariant:
    SEMANTIC IDENTITY PERSISTS.
    REPRESENTATION CHANGES.
Every language feature must strengthen this progression rather than introduce a
parallel system.

## II. Priorities

Optimize in this order:
    runtime performance
    semantic architecture
    compile-time performance
    syntax density
    semantic expressiveness
    metaprogramming power
    agent comprehensibility
    future extensibility
Do not improve superficial familiarity by sacrificing optimization or semantic
convergence.
Prefer:
    one mechanism → many capabilities
over:
    many mechanisms → one capability each
Canonical convergence targets:
    one id system
    one graph
    one descriptor/fact system
    one table/home model
    one application algebra
    one projection algebra
    one conversion relation
    one staging model
    one transformation model
    one world/universe algebra
    one realization model

## III. Identity

There is exactly one semantic identity concept:
    id
Do not create semantic identity kingdoms such as:
    StableId
    SemanticIdentity
    EntityId
    ModuleId
    TypeId
    ValueId
    CallId
    RegionId
    InstructionId
when they mean independent semantic identity.
Dense graph indexes, slots, handles, machine ranges, and internal integers may
physically encode/reference ids.
They are representations of identity, not new identities.
The following never establish semantic identity:
    name
    path
    source spelling
    span
    hash
    fingerprint
    pointer
    address
    intern slot
    opcode
    symbol
    linkage name
    declaration order
Distinct semantic occurrences retain distinct ids even if all visible facts are
equal.
Cross-edit or cross-build continuity is an explicit correspondence relation
between ids.
It is never guessed from path/name/hash equality.

## IV. Fact Ownership

Each authoritative semantic fact has exactly one producer.
Examples:
    lexical identity        lexical authority
    syntactic structure     grammar/parser
    home provenance         source projection
    relation                semantic resolution
    subject                 semantic resolution
    application             semantic graph producer
    world requirement       resolved relation/application
    world witness           authority satisfaction
    demand                  demand analysis
    representation          realization
    selected machine target realization
    machine range           machine producer
A downstream stage must never reconstruct an upstream fact from:
    source text
    function name
    path
    AST shape
    opcode
    method flag
    host type
    string
    symbol
If the fact is missing:
    fix the producer or edge
    OR fail closed
Never rediscover it.
One fact with multiple authoritative producers is a language fork.

## V. Unknown

Unknown compiler knowledge is not a language value.
Never represent unknown with:
    0
    false
    ""
    nil
    empty pack
    fake id
    placeholder enum
    default relation
    default world
Distinguish:
    unknown compiler fact
    nil language value
    false
    zero
    empty string
    empty table
    absent demand
    not applicable
Unknown remains unknown until proven.

## VI. Nil

Nil is Idol's native ordinary absence value.
Do not create wrapper ontologies:
    absent
    present
    maybe
    option
    none
    some
for ordinary lookup/search absence.
Example:
    home = env("HOME")
may produce:
    text | nil
Missing:
    nil
Present but empty:
    ""
These remain distinct.
Do not collapse:
    nil → ""
    nil → false
    nil → 0
Language refinement may narrow:
    text | nil
to:
    text
inside a branch proving non-nil.

## VII. Naming — General

A project-owned semantic identity must name exactly one irreducible semantic
thing.
Canonical semantic names are:
    lowercase
    singular
    one irreducible word
Do not encode in the identity name:
    cardinality
    protocol satisfaction
    ability
    representation
    transformation
    target
    stage
    provenance
    demand
    optimization state
    world authority
    implementation strategy
    pipeline phase
    historical state
    evidence state
Do not use:
    underscores
    camelCase
    PascalCase
    kebab-case
    mashed compounds
    numeric taxonomy
    arbitrary abbreviations
Delete before rename.
Decompose before rename.
Rehome before rename.
A lowercase one-token spelling is NOT enough.
Examples of still-invalid names:
    scanfiles
    canonicalid
    tokenview
    arm64check
    perfledger
because they contain more than one semantic axis.

## VIII. SINGULAR-ONE

Grammatical plurality never encodes semantic identity.
A table already represents zero, one, or many members.
Therefore:
    gates       invalid → gate
    tests       invalid → test
    fixtures    invalid → fixture
    relations   invalid → relation
    descriptors invalid → descriptor
when the plural merely means "a collection of X."
Cardinality belongs in facts:
    count(table)
    pack cardinality
    member count
    union cardinality
Never in the name.
Do not evade this with collective nouns merely meaning "many X":
    collection
    bundle
    suite
    catalog
    group
    set
    container
    pool
    family
unless the collective behavior is genuinely the independent semantic concept.
Do not blindly rename:
    scripts → script
    examples → example
    tools → tool
    docs → doc
First determine whether the organizational root should exist at all.
Prefer semantic rehoming.

## IX. IDENTITY-IRREDUCIBILITY TEST

For every new binding, table, file, directory, function, descriptor, or compiler
object ask:
    What independently observable entity does this identify?
    Which facts qualify it?
    Would the identity still exist if one of those facts changed?
    Is the name describing a fact rather than an entity?
    Does Idol already have machinery that owns the implied behavior?
If the identity disappears merely because a qualifying fact changes, the name
probably encoded the fact.
Example:
    an application witness
disappears when the subject no longer admits that relation application.
Therefore *able protocol names are not identities — they illegitimately encode
relation satisfaction. Canonical representation is the application/relation fact.

## X. PROTOCOL-NAME-ZERO

Never create identities encoding "can do X."
Presumptively invalid:
    callable
    readable
    writable
    iterable
    indexable
    hashable
    comparable
    equatable
    serializable
    encodable
    decodable
    parseable
    printable
    formattable
    executable
    runnable
    cloneable
    copyable
    movable
    awaitable
    seekable
and generally project-owned:
    *able
    *ible
when they mean relation/application satisfaction.
Replace with the actual fact:
    admits application
    admits read
    admits write
    admits iter
    admits to(format)
No adjective protocol object.
Exception: the bare boundary keyword `able(...)` is NOT an adjective identity —
it is the ONE explicit protocol/requirement boundary (`docs/spec/law.md` §9),
e.g. `able(eq)`, `able(read)`, `able(to(str))`. It is normally inferred and
spelled only at a real boundary; it mints no trait, dictionary, or vtable. A
name ending in `able`/`ible` (`readable`, `iterable`) remains forbidden.

## XI. ROLE-NOUN-ZERO

Banning adjectives is insufficient.
Also distrust role nouns that merely mean "thing that performs relation X":
    reader
    writer
    runner
    parser
    encoder
    decoder
    serializer
    formatter
    validator
    checker
    builder
    emitter
    generator
    renderer
    collector
    walker
    scanner
    evaluator
    interpreter
    provider
    consumer
    producer
    receiver
    sender
Such a noun is valid only if the domain contains a genuinely observable entity
with that identity.
Otherwise:
    subject + relation
already expresses the semantics.

## XII. QUALIFIER-ZERO

Do not mint identities from qualifiers or states such as:
    active
    ready
    valid
    invalid
    resolved
    unresolved
    known
    unknown
    sealed
    dynamic
    static
    native
    foreign
    cached
    dirty
    clean
    pending
    partial
    complete
    mutable
    immutable
    shared
    local
    global
    pure
    impure
    hot
    cold
    used
    unused
    materialized
    boxed
    unboxed
    inlined
    folded
    vectorized
These are facts about something else.
Never:
    nativevalue
    dynamiccall
    boxedvalue
    validtype
    specializedfunction
as separate semantic identity classes.

## XIII. REDUNDANT QUALIFIER ZERO

Avoid prefixes such as:
    semantic*
    idol*
    native*
    meta*
when the underlying concept is already inherently semantic/native/Idol.
Examples:
    semanticgraph
should normally just be:
    graph
Likewise:
    semanticcontext
    semanticalgebra
    semantictransaction
must prove irreducibility or be decomposed.
"Application algebra" may be an explanatory phrase.
It does not imply an Algebra object.

## XIV. META-NOUN-ZERO

Architectural explanatory words do not automatically deserve program identities:
    algebra
    calculus
    lattice
    framework
    system
    model
    mechanism
    architecture
    subsystem
    layer
    schema
Use them in prose when useful.
Do not create semantic subsystems merely because the architecture can be
described with that word.

## XV. ORGANIZATIONAL-ESCAPE-ZERO

Do not hide unclear semantic ownership under generic organizational names:
    core
    base
    common
    shared
    util
    utility
    helper
    support
    misc
    internal
    foundation
    platform
    system
    default
    general
    generic
A name like "helper" means ownership has not been resolved.
Rehome to the actual semantic owner.

## XVI. COLLISION-ZERO

Never create a semantic object whose role duplicates Idol's native machinery.
Presumptively forbidden when used as compiler/language architecture:
    router
    gateway
    dispatcher
    registry
    manager
    factory
    adapter
    broker
    mediator
    controller
    coordinator
    orchestrator
    handler
    executor
    runner
    engine
    pipeline
    scheduler
    loader
    bridge
    shim
    proxy
    wrapper
    frontend
    backend
    context
    session
    service
    provider
    framework
    container
The ROLE is forbidden, not only the spelling.
Renaming:
    router → broker → manager → service
does not fix it.

## XVII. Existing Machinery Owns These Responsibilities

Routing:
    application resolution
Dispatch:
    application resolution + realization selection
Registration:
    anchored facts
Adaptation:
    foreign/realization projection
Context:
    current fact/reachability set
Execution selection:
    demand + realization
Protocol satisfaction:
    relation/application facts
Transformation selection:
    transformation dependencies + demand
Therefore no second owner object is required.

## XVIII. KEY→HANDLER ZERO

A structure equivalent to:
    name → function
    kind → callback
    opcode → handler
    directive → implementation
    type → implementation
    format → encoder
is presumptively a second semantic dispatcher.
Meaning belongs in anchored graph facts.
A physical lookup index may exist only as acceleration.
Deleting the index must not alter semantic behavior.

## XIX. RESPONSIBILITY-BAG ZERO

An object that owns several of:
    relation selection
    world selection
    target selection
    source reachability
    stage
    transformation
    diagnostics
    runtime state
is presumptively wrong.
Do not create Context/Session/Manager objects that make facts true merely by
containing them.
Split facts by their real owners.

## XX. Filesystem Semantics

Filesystem has exactly one language job: **at ingestion**, paths establish
initial stable names and home/member topology for source bodies. After that,
paths are **provenance only** — not scope, not module identity, not lookup.

Every admitted directory implies an ordinary table/home. A same-name root
`.id` file is optional.

Example:
    test/
        smoke.id
initially tells the compiler:
    home test
    member smoke

Then the filesystem is forgotten except as origin/provenance.

No language operation means:
    go to parent directory
    look in sibling file
    search root
    import module
    load package

Prefer ordinary qualification when a binding is not ambient:
    gate.census
    test.smoke
    app.limit

The textual qualifier resolves **once** at source resolution. The graph sees
ids. Filesystem does not survive into graph resolution or realization.

If both exist:
    test.id
    test/
they contribute to the SAME test table/home. The file contributes root-body
semantics; the directory contributes members. No file/module distinction.

## XXI. File Is Body

For:
    gate/census.id
filesystem already supplies:
    home gate
    member census
Inside the file do NOT repeat:
    census = ...
    census: {...}
    gate.census = ...
    gate = { census = ... }
The file contents are the member body.
Home/member identity is supplied exactly once.

## XXII. Root Execution

There is no canonical:
    main
    entry
    init
    start
wrapper merely to execute a file.
A file's root expression sequence IS its execution/result.
Example scriptlike body:
    value = compute()
    value:print()
    0
No main.
If a file is root-callable:
    (x)
        y = transform(x)
        y
No same-name function wrapper.

## XXIII. Child Relations

A callable child file is normally a relation on its parent table when the parent
is its semantic subject.
Given:
    gate/idiom.id
with root:
    (diff)
        ...
canonical invocation:
    gate:idiom(diff)
not:
    gate.idiom(diff)
Graph:
    relation = idiom
    subject = gate
    operands = diff
    home = gate
    origin = gate/idiom.id
Nested example:
    test/compiler/smoke.id
canonical:
    test.compiler:smoke(...)
`.` projects compiler statically.
`:` invokes smoke on compiler.

## XXIV. DOT-STRICT

`.` means static named member projection only.
A call:
    x.y(...)
is canonical only if:
    y is genuinely a static projected callable/accessor VALUE
    x is not the semantic subject of relation y
Example allowed:
    env("HOME")
if `env` is uniquely reachable and human-obvious.
Keep static qualification only when it disambiguates actual semantic identity:
    os.env("HOME")
Example forbidden:
    gate.idiom(diff)
when gate is the subject.
Use:
    gate:idiom(diff)
Never use dot merely because another language would call something a static
method/module function.

## XXV. SUBJECT-FIRST

If an operation belongs semantically to a possessed value, orient the relation
on that value:
    source:read()
    path:open()
    stdout:write(text)
    command:run()
    text:find(pattern)
    text:sub(a,b)
Avoid:
    read(source)
    open(path)
    write(stdout,text)
    find(text,pattern)
unless the relation genuinely has no natural semantic subject.

## XXVI. APPLICATION-ONE

All ordinary application participates in one semantic algebra:
    relation
    projection facts
    subject
    operand pack
    result demand
    descriptor
    law
    world requirement
    world witness
    effect
    stage
    origin
    provenance
    demand
Parser preserves structure.
Resolver determines semantic application.
Do not create independent semantic call kingdoms for:
    function call
    method call
    accessor call
    protocol call
    generic call
    projected call
after resolution.

## XXVII. PAREN-ONE

`()`
is the ordinary canonical application/accessor delimiter.
The resolver determines whether:
    f(x)
is:
    callable application
    keyed access
    ordinal access
    place-producing access
    another admitted application shape
Punctuation itself does not mint semantic identity.

## XXVIII. HUMAN-UNAMBIGUOUS ELISION

Do NOT hide meaningful actions merely because the compiler could infer them.
Relation-name elision requires BOTH:
    compiler uniqueness
    human obviousness
Good:
    f(x)
    env("HOME")
    args(1)
    row(column)
because the application/access intent is obvious.
Normally prefer explicit:
    source:read()
    path:open()
    command:run()
    stdout:write(text)
    text:parse(json)
rather than:
    source()
    path()
    command()
    stdout(text)
    text(json)
when the omitted relation would force a human reader to guess.
Syntax density must not reduce semantic clarity.

## XXIX. ACCESS-ONE

Canonical ordinary access:
    env("HOME")
    args(1)
    table(key)
    row(column)
Do not canonically use:
    env["HOME"]
    args[1]
    table[key]
when normal application/access semantics suffice.
Do not use:
    x:get(k)
    x:set(k,v)
    x:call(...)
These duplicate application/place semantics.
Long-term place-producing application may support:
    x(k) = value
when `x(k)` resolves to a place.

## XXX. BRACKET-ZERO

Canonical Idol does not use `[]` for ordinary access, including when the key is
computed. Use `table(key)`; whether the application yields a value or place is
resolved from demand and facts rather than punctuation. A foreign source law may
recognize foreign bracket syntax only inside that law-qualified source
projection. The spelling remains source provenance and never becomes Idol
grammar or semantic authority.

## XXXI. HAS-ZERO

Do not reify presence into:
    has
    contains
    exists
    includes
    present
    member
when ordinary lookup/search already returns value-or-nil.
Bad:
    if table:has(key)
Prefer:
    value = table(key)
    if value
        ...
Bad:
    code:has(pattern)
Prefer an irreducible search:
    pos = code:find(pattern)
    if pos
        ...
Boolean presence should exist only if the bool itself is genuinely demanded.

## XXXII. TO-ONE

There is one semantic descriptor-conversion relation:
    to
Do not create generic conversion synonyms:
    char
    cast
    coerce
    convert
    stringify
    into
    as
    encode
when the actual semantics are descriptor conversion.

## XXXIII. Conversion Inference (SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE)

No source spelling should survive merely to restate a semantic fact the compiler
can already recover uniquely. This applies uniformly to bindings, relation/method
names, static projections, conversion, target descriptors, protocol/world
satisfaction, capture, and projection/injection composition.

Every source token must contribute semantic information not already uniquely
recoverable from: subject; operands; result demand; descriptor demand;
reachable exact facts; relation constraints; world/effect requirements; stage;
provenance; control-flow refinement.

If a spelling contributes no new information: omit it. If omission leaves
multiple lawful solutions: spell the minimum disambiguating fact. If omission is
compiler-unique but human-ambiguous: retain the irreducible meaningful relation
(`source:read()` may remain; `source()` alone does not).

FACT-COMPOSITION-INFER-ONE: projection, injection, capture, protocol/world
satisfaction, and target selection are graph facts — normally zero source syntax.
Usage derives dependencies (`stdout:write(env("HOME"))`, not `@{ os.env
io.stdout }`).

Case A — satisfaction:
    c: char = 10
If exact literal facts already satisfy char, no conversion exists.
Case B — inferred conversion:
    c: char = value
If the unique lawful path requires conversion, graph records:
    value:to(char)
without source spelling.
Case C — explicit target:
    value:to(char)
only if the target is not otherwise recoverable from demand/context.
There is no canonical `value:to()` rung.

Preference (source-density order):
    omit redundant binding
    → omit redundant relation/projection/conversion/world composition
    → value:to(target) only when target is not inferable
    → retain minimum spelling for uniqueness + human meaning

Never:
    string.char(10)
    char(10)
    10:char()
If the desired value is simply newline text:
    "\n"
Use the literal.

INTERMEDIATE-ZERO: chain relations directly when identity is preserved. Retain a
named intermediate only when the name contributes semantic information the chain
does not (multiple consumers, or human-clarity place identity).

## XXXIV. Satisfaction / Conversion / Parse / Realization

These are distinct:
SATISFACTION
    value already obeys demanded descriptor
CONVERSION
    semantic domain/law transformation through to
PARSE
    interpretation under syntax/format law, possibly failing
REALIZATION
    same semantic value receives another physical representation
Do not use conversion to model machine width/layout.
Do not use parse as a synonym for conversion.
Do not use realization as semantic conversion.

## XXXV. ENCODE-ZERO

`encode` and `decode` are presumptively noncanonical generic bindings.
Likewise:
    encoding
    codec
    encoder
    decoder
    serialize
    deserialize
    serializer
    deserializer
    marshal
    unmarshal
    transcode
must prove irreducible semantics.
For each site determine whether it is actually:
    satisfaction
    to(format)
    parse(format)
    emission/output
    foreign realization
Formats themselves may survive as descriptors:
    json
    cbor
    protobuf
    pem
    varint
if they represent irreducible observable format laws.
Do not create:
    encoding/json
    codec/json
    jsonencoder
    encodable
hierarchies.
A format is a descriptor.
The transformation is a relation.

## XXXVI. Format Examples

If JSON representation is semantically conversion:
    out: json = value
or explicitly:
    out = value:to(json)
If text must be interpreted as JSON syntax:
    value = text:parse(json)
If emission has independently observable semantics distinct from `to`, an
explicit relation may survive only after proof.
Never invent `encode` merely because ecosystem libraries use that vocabulary.

## XXXVII. @ — Current-world accessor

`@` IS THE CURRENT-WORLD ACCESSOR (`docs/spec/law.md` §4).
Canonical meanings:
    bare @
        the current world value
    @member
        access a static member of the current world: @target  @env
        (@ is the accessor itself; @member.child is one access then one
        ordinary static projection)
    @member = v
        mutate a current-world member place, when it is a place
    thing@world
        interpret/project thing in world (postfix); thing@ is current-world
        qualification, normally redundant
    @{ k = v }
        derive the current world by injection (exact fact deltas);
        thing@{ k = v } is scoped interjection;  @( … ) is eval
INVALID: @.member and @:member — @ already accesses, so there is no `@.`
projection step and no `@:` subject dispatch.
Prefix compiler-namespace directives are denied.
Never:
    @comp.*
    @host.*
    @runtime.*
    @ffi.*
as generic source APIs.
`@` does not mean import.
`@` does not mean generic injection.
`@` does not call compiler implementation.

## XXXVIII. @{}

`@{ k = v }`
derives the current world by **injection** — a new closed world with exact
fact deltas over the enclosing world. `thing@{ k = v }` is **interjection**:
`thing` evaluated under that derived world. `@{}` is the single face for world
derivation; it is **not** a descriptor sigil.

A **descriptor is an ordinary table** whose values are descriptor constraints —
no sigil is required:

    point = {
        x: f64
        y: f64
    }

It is **not**:
    import
    use
    include
    universe declaration
    scope declaration
    a descriptor literal

**`@{}` is world derivation, never import/dependency ceremony.** Injection
normally has **zero** source syntax — usage derives exact world/protocol
dependencies. Writing:

    @{
        os.env
        io.stdout
    }

just to use environment variables and stdout is forbidden surface plumbing.
Source names what it uses; execution supplies authority witnesses. Explicit
`@{ k = v }` injection exists only when fact composition is not uniquely
inferable from use.

When projected fact/table expressions occur in an anchored descriptor body,
their normalized fact closure contributes coherently to that anchor. The
compiler may describe that algebraically as fact composition. There is no
`inject` language construct and no user-facing `interjection` syntax.

## XXXIX. Descriptors

Descriptors unify constraints/facts traditionally represented as:
    types
    concepts
    enum-like domains
    protocols
    schemas
    build targets
    stages
    hardware descriptions
    runtime descriptions
Do not reintroduce separate:
    type
    concept
    trait
    interface
    impl
    class
    struct
    protocol-object
kingdoms.
A descriptor is semantic facts/constraints.
Physical representation is not chosen merely because a descriptor exists.

## XL. TABLE-ONE

Ordinary tables remain the foundational semantic aggregation mechanism.
A table can play roles such as:
    home
    descriptor
    structured value
    world
    universe
    source root
    compile-time value
without changing semantic kind.
Role is a fact.
Do not create a separate object model for each role.

## XLI. World

World is an ordinary closed semantic table (`docs/spec/law.md` §3 + World+projection
add-on), not a class/kind/keyword. `@` is the current world.
A world may contain values, relations, descriptors, other worlds, stage/target
facts, and authority facts. Authority is ONE class of fact within a world — a
world is not synonymous with authority. An ordinary table/value plays the world
role when facts reachable from it satisfy the authority requirements of effectful
applications.
World means:
    a closed semantic table whose facts (including, but not limited to,
    authority facts) resolve meaning
not:
    authority object
    namespace
    service
    API module
    runtime object
Do not define:
    World
    FileWorld
    ReadWorld
    SandboxWorld
    readonly
    writable
    privileged
    restricted
merely to group permission sets.
Presence/absence of actual authority facts is sufficient.

## XLII. OS World

A platform may provide an ordinary world-role table:
    os
        env
        args
        cwd
These semantic values are supplied by execution ingress/realization.
Canonical ambient access:
    env("HOME")
    args(1)
when uniquely reachable and human-obvious.
Explicit static projection only when qualification disambiguates:
    os.env("HOME")
    os.args(1)
`env` and `args` are accessors.
Do not implement them in canonical Idol source using:
    getenv
    @comp.host.env
    host.env API
    runtime.env
Physical realization belongs below the graph.

## XLIII. IO World

A platform may provide:
    io
        stdin
        stdout
        stderr
These are ordinary endpoint values.
Meaningful operations orient on the actual endpoint:
    stdin:read()
    stdout:write(text)
Never:
    io.read()
    io.write()
because io is not the true subject.

## XLIV. USER-DEFINED FIXTURE TABLES

A fixture is an ordinary table whose bindings can satisfy authority at the
execution boundary:

    mock = {
        env = {
            HOME = "/tmp/idol"
        }
        stdout = output
    }

Nothing marks it as a `world`. At run/compile configuration, the caller
chooses projected bindings from it — conceptually:

    run program with
        env    = mock.env
        stdout = mock.stdout

Do not rush source syntax for this. It may initially be a compiler/run
descriptor or API operation (deployment configuration, not application
semantics). If Idol source eventually expresses it, use ordinary table
construction — not a world DSL.

Explicit qualification in source remains valid when ambiguity must be avoided:
    mock.env("HOME")

## XLV. ESSENTIAL MODEL

**Universe** is compiler vocabulary for the closed fact set used while resolving
one body or application. Users write programs; they do not define universes in
source. Injection/interjection are internal terms for adding fact edges — not
user syntax.

For users, three things matter:

    value
    relation
    authority

Everything else is compiler bookkeeping.

Example source:

    home = env("HOME")
    text = path:read()
    stdout:write(text)

The compiler already knows the complete semantic requirements:

    env accessor
    file read relation
    stdout write relation

Source must **not** redundantly declare:

    inject os.env
    project io.stdout
    include filesystem

**Rule (INFER-ONE for world):** if a dependency can be uniquely inferred from
an actual semantic use, never require a declaration of that dependency.

## XLVI. RESOLVE ONCE — NEVER SEARCH LATER

Each name and reference resolves **exactly once** to a semantic id and facts.

Lexical structure and layout-projected home topology may assist that initial
resolution. After resolution:

```text
no parent scope lookup
no filesystem lookup
no global fallback
no namespace lookup
no module lookup
```

Free lexical references become explicit **capture** edges — not runtime
parent-environment lookup.

```id
outer = 4
f = (x)
    x + outer
```

The resolver binds `outer` to one exact id. The graph records `f capture → outer-id`.
From that point forward, no parent scope exists semantically.

Prefer ordinary static qualification:

```id
if x > app.limit
    ...
```

Local naming is ordinary binding: `limit = app.limit`. Do not require `@{}`
projection blocks or import ceremony for sibling/home members the layout model
already makes referable.

## XLVII. FILESYSTEM INGEST ONLY

Filesystem semantics narrow to one job:

**At ingestion**, paths establish initial stable names and home structure. After
that, paths are **provenance only**.

```text
test/smoke.id  →  test · test.smoke  →  filesystem forgotten except origin
```

No language operation means: parent directory walk, sibling file search, root
search, import module, load package.

## XLVIII. @{} IS WORLD DERIVATION, NOT CEREMONY

`@{ k = v }` is the single face for world derivation by injection; `thing@{ k
= v }` is interjection. It is **not** a descriptor sigil — descriptors are
ordinary tables `{ x: f64 }`. It is **not** import/dependency ceremony.

Injection normally has **zero** source syntax — usage derives exact world
authority, inferred from use and supplied at execution. Never write:

```id
@{
    os.env
    io.stdout
}
```

just to use environment variables and output. Dot, colon, call, binding, and
ordinary tables already supply projection. Explicit `@{ k = v }` injection
exists only when fact composition is not uniquely inferable from use.

Forbidden source ceremony (non-exhaustive):

```text
import · require · use · include
universe declaration · world declaration · scope declaration
```

## XLIX. WORLDS AS EXECUTION INPUTS

Programs run under different worlds **without changing source**.

Real execution supplies platform `env` and `stdout`. Test execution supplies
fixtures and captured output. Same source — no `@{ mock.os.env }` inside the
program.

World composition at the run/compile boundary is ordinary table data:

```id
world = {
    env = mock.env
    args = os.args
    stdout = io.stdout
}
```

Cross-origin selection (args from platform, env from mock) is a **configuration**
fact at execution — not source-level `@{ os.args mock.os.env }` blocks.
Origin/authority lineage is preserved in graph witnesses; no CombinedWorld object.

## L. World Ambiguity

If two observably distinct witnesses could satisfy the same authority demand,
unqualified `env("HOME")` is **ambiguous** — fail.

Never choose by declaration order, nearest declaration, test preference, default
world, path, or namespace priority. Select explicitly:

```id
mock.env("HOME")
```

or supply a unique execution configuration. Rejecting OS/IO is witness omission at
the boundary — not a negative-capability language in source.

## LI. Projection Algebra

For a table/world T:
    F(T) = normalized semantic fact closure
Static projection (one static step, always):
    T.member
selects member facts. `@` is the current world and is itself the accessor;
`@member` accesses it (never `@.member` or `@:member`).
World qualification:
    T@world
evaluates/projects T under world — postfix `@` carries a world, never a
relation. Subject-relation orientation is the colon face `T:relation`
(`law.at.one`); `T@relation` anchoring is superseded.
Injection / interjection:
    @{ k = v }      derive the current world with exact fact deltas
    x@{ k = v }     scoped interjection x@(@{ k = v })
Projection:
    P(T,S) ⊆ F(T)
preserves ids and origin.
Projection does not clone meaning.

## LIII. Injection (internal)

For a destination world D and projected fact set P, coherent composition is
internal algebra:

```text
F(D)' = coherent(F(D) ∪ P)
```

Same fact unifies; compatible facts conjoin; incomparable distinct witnesses
→ ambiguity. Never last-wins.

This is how the compiler records inferred authority and context facts. It is
**not** a separate source-language operation. Do not expose `inject` or
`interject` as user syntax.

## LIV. Protocol

A protocol is a projection/constraint over required relation/application facts.
Example:
    source:read()
on unknown source establishes:
    source must admit read with the demanded shape
Do not create:
    readable
    Readable
    reader protocol
    interface
    trait
    impl
The relation/application constraint IS the requirement.

## LIV. Protocol ≠ World

Protocol satisfaction does not grant authority.
These may all satisfy `read`:
    memory
    file
    socket
But:
    memory:read()
        may require no external authority
    file:read()
        may require file/path authority
    socket:read()
        may require network/socket authority
Same relation.
Different subject/world facts.
Never merge into a generic "io capability."

## LV. Conditional Authority

For unresolved:
    file | socket
and relation:
    read
retain alternative-specific authority requirements.
After refinement to file:
    network requirement disappears.
Do not eagerly combine authority into generic world categories.

## LVI. Union

Union means remaining semantic alternatives.
It does not imply a boxed tagged runtime object.
For:
    a | b
representation is chosen later.
If refinement leaves one live alternative:
    runtime tag cost should disappear
unless the tag itself is independently observable.

## LVII. Value ≠ Place

A semantic value is not automatically storage.
A binding is not automatically a stack slot.
A table field is not automatically memory.
Place exists only if observable semantics demand:
    mutation
    aliasing
    address
    lifetime identity
    ABI
    persistent state
No place requirement:
    no mandatory load/store/materialization.

## LVIII. REPRESENTATION-NOUN-ZERO

Do not turn physical storage choices into semantic identities:
    buffer
    box
    slot
    cell
    register
    stack
    heap
    lane
    bucket
    block
    page
    node
    handle
    pointer
unless they are genuinely observable domain entities.
Representation belongs to realization.

## LIX. PACK-ONE

One pack model covers:
    operands
    results
    projections
    multiple returns
    ABI argument/result shapes
Preserve:
    pack id
    value ids
    position/label
    descriptor
    demand
    provenance
Do not invent separate:
    ArgList
    ReturnTuple
    ProjectionArgs
semantic kingdoms.

## LX. Multiple Returns

Multiple returns are native semantic result packs.
Do not materialize a tuple merely because a backend representation prefers one.
If caller consumes values separately, realization may keep them separately in
registers.
Unconsumed result slots should disappear physically.

## LXI. Closures

A closure has semantic facts:
    callable identity
    captures
    escape
    lifetime
    demand
Possible realization:
    inline
    constant substitution
    direct specialized function
    registers
    stack
    heap
Heap closure is last resort.
Source closure syntax never mandates heap allocation.

## LXII. Curry

Currying is genuine only when an application returns a callable value.
Example:
    scale = (k) (x) x * k
    double = scale(2)
Missing arity does not magically curry arbitrary functions.
Projection forms are not currying.

## LXIII. Functions

Canonical compact function form:
    add = (a, b) a + b
Multi-line:
    normalize = (value) value:validate():normalize()
Tail expression returns.
No Nim-style `result`.
No named return binding solely for return machinery.
No mandatory `function`, `fun`, `fn` keyword.
No `end`.
No canonical `do`.
No canonical `then`.

## LXIV. Methods / Relations

There is no independent method object model.
Colon is subject relation orientation.
A relation whose semantic subject is a table/value uses:
    subject:relation(...)
Do not introduce:
    method kind
    method registry
    method reference ontology
    impl block
Relation identity remains relation identity.

## LXV. DESCRIPTOR-LOCAL RELATIONS

Relations naturally associated with a descriptor/home should be defined within
that home's semantic topology rather than as operation-first free functions.
A relation can still be globally identified while its home supplies declaration
context.
Home membership does not mint a new relation identity.

## LXVI. Home

Home is:
    declaration/reachability/context anchor
It is NOT:
    namespace
    module
    protocol grant
    world grant
Moving among equivalent homes must not change relation identity.
Path is provenance after source projection.

## LXVII. MODULE-ZERO

There is no native:
    module
    namespace
    import
    require
    req
    include
    package-loader
semantic system.
Filesystem tables/homes + reachability already organize source.
Do not reconstruct module semantics later from paths.

## LXVIII. STD-ZERO / LIB-ZERO

No canonical:
    std.*
    lib.*
semantic hop.
Standard functionality is simply ordinary reachable/admitted relations,
descriptors, values, and laws.
Repository directories named `lib` must not become semantic roots merely
because they exist physically.
Do not repair:
    std.*
by changing it to:
    semantic.*
    core.*
    lib.*
Delete the organizational semantic hop.

## LXIX. META-ZERO

Compile-time/staged behavior is ordinary Idol semantics plus stage/anchor facts.
Do not create a parallel `meta` namespace/system unless the value is genuinely
external metadata.
No:
    metadispatch
    metaregistry
    metaobject system
for ordinary staging.

## LXX. Staging

Compile-time execution operates on ordinary Idol semantics.
No separate macro language.
No derive DSL.
No build DSL if ordinary staged Idol can express it.
Stage is a fact.
Compile-time values are ordinary values.

## LXXI. ARBITRARY COMPILE-TIME EXECUTION

Compile-time execution may perform ordinary Idol computation subject to world,
stage, and determinism constraints.
Cache by:
    semantic dependencies
    world observations
    target facts
    demand
not merely timestamps.

## LXXII. DERIVE-ZERO AS SUBSYSTEM

Do not build:
    derive registry
    derive evaluator kingdom
    derive bundle ontology
when behavior is expressible as:
    relation/descriptor facts
    stage
    transformation
A physical lookup index may remain if nonauthoritative.

## LXXIII. TRANSFORM-ONE

One transformation model covers:
    constant folding
    specialization
    inlining
    vectorization
    fusion
    staging
    dead-code elimination
    target lowering
Every transform records:
    input ids
    prerequisite facts
    produced facts
    eliminated alternatives
    provenance/lineage
    physical consequence
No rewrite engine/transform engine semantic kingdom.

## LXXIV. TRANSFORMATION-NAME-ZERO

Do not turn generic transformation families into arbitrary semantic homes:
    encoding
    decoding
    conversion
    normalization
    canonicalization
    lowering
    rewriting
    expansion
    optimization
    generation
    emission
unless the domain contains an independently observable entity with that name.
Usually these are relations/transformation records.

## LXXV. Transformation Lineage

Optimization does not erase semantic lineage.
Preserve:
    source
    → semantic id
    → application
    → relation
    → values
    → transformation
    → realization
    → instruction
    → byte range
Constant folding does not erase the application.
Inlining does not erase call provenance.
Vectorization does not erase scalar relation identity.

## LXXVI. GRAPH-ONE

There is one primary semantic graph.
Secondary:
    call graph
    region graph
    dependency graph
    control graph
may exist only as derived indexes/views.
They cannot own semantic facts unavailable from the primary graph.

## LXXVII. AST Boundary

AST owns syntax/provenance.
Parser may recognize:
    delimiters
    source home
    declared parameter shape
    spans
    syntax forms
Parser does NOT authoritatively decide:
    subject
    world
    demand
    application role
    semantic projection
    relation identity
Those belong to semantic resolution/graph.
Do not create hidden syntax bindings to manufacture semantic roles.

## LXXVIII. DNIR

DNIR is a realization projection.
It is not a second semantic language.
It must carry/consume graph facts such as:
    application id
    relation id
    selected target id
    subject id
    operand/result packs
    descriptors
    world/effect
    demand
    provenance
Do not reconstruct semantics from:
    callee name
    source path
    symbol
    opcode
    host type
    method flag
DNIR operation tags are physical encodings, not new semantic relation identities.

## LXXIX. Relation ≠ Target

One relation may have multiple lawful implementations.
Relation:
    validates semantic meaning
Selected target:
    chooses a concrete implementation/realization
Never assume:
    relation → exactly one physical function
Carry selected target separately where needed.

## LXXX. TARGET-ONE

Do not create semantic target-qualified relation identities:
    armadd
    wasmadd
    gpuadd
    simdadd
Semantic relation remains:
    add
Target is a realization fact.
Architecture names such as:
    arm64
    wasm
    macho
may survive only where they genuinely identify foreign/target representation
domains.
They must not qualify native semantic identities unnecessarily.

## LXXXI. Foreign Boundary

Foreign representations normalize exactly once.
Examples:
    C ABI
    Wasm
    OS handles
    foreign strings
    Lua compatibility
    process exit status
Ingress:
    foreign facts → canonical semantic facts
Egress:
    canonical semantic facts → required foreign representation
No permanent adapter/bridge semantic ontology.

## LXXXII. BRIDGE-DEATH

A temporary physical bridge requires:
    exact responsibility
    exact facts crossing
    semantic authority classification
    replacement owner
    deletion prerequisite
    positive control
    negative control
No deletion condition:
    invalid bridge.
Once replacement exists:
    delete bridge.
Never rename:
    bridge → adapter → gateway
and preserve the same architecture.

## LXXXIII. ZERO-COPY

Zero-copy interop requires proof of:
    layout
    alignment
    ownership
    lifetime
    mutation law
    alias law
    encoding
    ABI compatibility
Pointer compatibility alone is insufficient.

## LXXXIV. WASM

Wasm is a target/foreign realization over the same semantic graph.
No independent Wasm semantic universe.
Same semantic relation ids.
Same values where meaning persists.
Same application algebra.
Target-specific representation comes later.
Goal:
    Idol Wasm faster than Wasmtime
    smaller binaries
    faster startup
    equal semantic correctness
But claims require evidence.

## LXXXV. Numbers

Compact source faces may remain:
    i8 i16 i32 i64
    u8 u16 u32 u64
    f32 f64
But they decompose semantically into facts:
    width
    signedness
    format
    precision
    overflow law
    rounding law
Unannotated integer literals retain exact mathematical integer value until
demand forces a narrower descriptor.
Physical register/lane width belongs to realization.

## LXXXVI. Effects

Do not reduce effects to a single pure/impure boolean.
Retain enough facts to determine:
    may reorder?
    may duplicate?
    may eliminate?
    may speculate?
    may fail?
    may allocate?
    may observe mutation?
    which world required?
    may fuse?
    may parallelize?
Optimization consumes effect facts.

## LXXXVII. Order

Source order is semantically binding only when observable dependencies/effects
require it.
Independent work may:
    reorder
    fuse
    parallelize
    vectorize
    stage
when facts prove equivalence.

## LXXXVIII. Concurrency

Do not create semantic kingdoms merely from concurrency strategy:
    Task
    Future
    Promise
    Actor
    AsyncFunction
unless independently irreducible.
Semantic facts:
    dependency
    ordering
    sharing
    ownership transfer
    lifetime
    cancellation
    communication
    world
Realization may choose:
    inline
    coroutine
    thread
    task
    SIMD
    GPU
    process
Native coroutines should be first-class realization capability.

## LXXXIX. Synchronization

Do not introduce:
    lock
    atomic
    barrier
    refcount
cost unless sharing/order semantics require it.
Isolation should remove synchronization costs.

## XC. Ownership

Do not import Rust's surface ownership model.
Keep semantic facts:
    alias
    lifetime
    unique
    escape
    mutation
    transfer
    address observation
Representation follows those facts.
No ownership syntax required merely for compiler optimization.

## XCI. Iteration

One iteration semantic mechanism.
Do not create unrelated iterator kingdoms:
    pairs
    ipairs
    Iterator
    Enumerator
    Generator
    Range object
unless a returned state machine itself is semantically observable.
Realization may choose:
    counted loop
    pointer walk
    hash walk
    SIMD
    coroutine/generator

## XCII. Fusion

Source chains such as:
    xs:map(f):filter(p):sum()
should not force intermediate collections.
When facts allow:
    one fused loop
    zero intermediate allocation
is preferred.
Semantic relation composition remains visible to graph/tooling.

## XCIII. Vector

SIMD is realization.
Infer vectorization from:
    independent iteration
    descriptor
    alias freedom
    alignment
    reduction law
    target capabilities
Do not require a separate SIMD language.

## XCIV. SHAPE-ONE

Known table shape drives:
    field offsets
    scalar replacement
    register allocation
    stack layout
    hash elimination
    iteration strategy
    ABI layout
    vector layout
Once shape is known, downstream may not forget it and fall back to generic hash
semantics.

## XCV. COST-ONE

Every physical cost must identify the unresolved semantic possibility forcing
it.
Audit:
    allocation
    copy
    box
    tag
    guard
    hash lookup
    indirect call
    heap closure
    materialized pack
    runtime descriptor
    runtime world object
    ABI shuffle
    spill
    lock
    atomic
    buffer
    conversion
If no semantic uncertainty/observable law requires the cost:
    delete it.

## XCVI. REQUIRED ZERO-COST CASES

Known shape:
    generic hash lookup = 0
Sealed target:
    indirect call = 0
Nonescaping closure:
    heap allocation = 0
Singleton union:
    runtime tag = 0
Unused result:
    materialization = 0
Static protocol witness:
    runtime witness object = 0
Statically unique world witness:
    runtime world object = 0
Direct descriptor satisfaction:
    conversion = 0

## XCVII. Specialization

Specialization accumulates facts over existing semantic applications.
Potential facts:
    subject
    relation
    descriptor
    exact value
    table shape
    result demand
    world
    stage
    target
    profile
Do not create a separate generic/template semantic system.

## XCVIII. Specialization Budget

Semantic specialization does not imply code cloning.
Clone a physical implementation only when expected runtime benefit exceeds:
    compile time
    code size
    I-cache cost
    startup cost
    memory cost
Profile may influence this decision.
Profile does not establish semantic truth.

## XCIX. Guards

Every speculative guard records:
    assumed fact
    evidence
    guard
    dependent realization
    failure/invalidation path
No hidden assumptions.
No profile observation promoted directly to truth.

## C. Runtime

There is no mandatory monolithic Idol runtime.
A sealed native program that needs no:
    GC
    scheduler
    reflection
    dynamic tables
    coroutine machinery
    world adapter
should link none.
Startup should approach:
    OS loader → entry
with minimal language initialization.

## CI. GC

GC is a realization strategy.
A value may realize as:
    register
    stack
    static
    region
    arena
    isolated heap
    GC heap
according to lifetime/escape/alias facts.
GC is not mandatory table semantics.

## CII. COMPILE-TIME PERFORMANCE

Semantic richness must not imply heap-object explosion.
Prefer:
    dense ids
    arenas
    contiguous fact storage
    bitsets
    packed facts
    compact spans
    lazy indexes
Avoid:
    heap object per semantic fact
    string-key semantic maps everywhere
    duplicated complete IRs
Derive secondary facts only when demanded or profitable to cache.

## CIII. Cache

Cache is acceleration.
Deleting all caches must preserve correctness.
Cache candidates may be found by:
    fingerprint
    path
    timestamp
but semantic reuse must be verified by authoritative dependencies/facts.
A cache can never select meaning.

## CIV. Incrementality

Invalidation is fact-based:
    changed semantic fact
    → dependent semantic slice
    → dependent realization slice
Do not make:
    file changed → rebuild module
the fundamental architecture.
File is provenance partition, not semantic identity.

## CV. Determinism

Same:
    semantic source
    universe
    world observations
    target
must produce deterministic semantic meaning.
These may not choose meaning:
    filesystem order
    hash iteration
    task scheduling
    pointer addresses
    agent order
    source discovery order
Ambiguity must fail rather than resolve accidentally.

## CVI. Source Syntax — Blocks

Canonical blocks are offside/indentation-based.
No canonical:
    end
    then
    do
    semicolon
Outdent closes the block.
Whitespace is syntactic layout but semantic identity must not depend on
formatting details beyond the parsed structure.

## CVII. Comments

Canonical line comment:
    # comment
Do not reintroduce Lua `--`.
Block-comment machinery should not create a second complex comment language
unless independently justified.
Current source and tooling should consistently teach `#`.

## CVIII. Strings

Canonical ordinary text:
    "text"
Interpolation:
    "hello {name}"
Prefer interpolation over explicit concatenation.
Do not use Lua `..` as canonical concatenation.
Historical long-string syntax is not canonical.
Quote/byte semantics must remain consistent with the final lexical authority;
do not invent additional string literal kingdoms ad hoc.

## CIX. `!`

Canonical boolean negation should use the compact native negation face where
the grammar admits it.
Do not regress into stale Lua-style `not` patterns in canonical source if the
current lexical authority has retired them.
This is surface syntax; semantic boolean negation remains one relation/law.

## CX. Table Keys

Prefer ordinary static member syntax for statically known keys.
Do not write computed bracket keys merely because Lua historically required
them.
Use explicit computed projection only when the key genuinely is computed or
the place semantics require it.

## CXI. Generics

Do not introduce bracket generic syntax:
    Slice[Byte]
    Foo[T]
Types/descriptors are first-class semantic values.
Generic behavior comes from:
    ordinary parameters
    compile-time/stage facts
    descriptors
    application specialization
No separate generic language.

## CXII. Casts

No C-style cast system.
Conversion:
    to
Demand may eliminate source spelling entirely.
Representation reinterpretation is not necessarily semantic conversion and may
require a view/realization law rather than `to`.
Do not conflate bit reinterpretation with semantic conversion.

## CXIII. Shell

Shell is interpretation law.
Command is a semantic value.
Process execution is authority/effectful relation.
Do not create:
    shell namespace
    process service
    command runner
    capture subsystem
Canonical meaningful execution may be:
    command:run()
Output capture is usually:
    run + output demand
not a second relation.
Avoid textual shell pipelines for native compiler/gate logic when structured
semantic operations can express the work.
Bootstrap shell use must have deletion debt.

## CXIV. Status / Outcome

Foreign process status is not automatically native semantic outcome.
Distinguish:
    process status
    transport completion
    semantic result
    evidence verdict
Do not infer:
    status == 0 → semantic truth
without an admitted boundary law.

## CXV. PREDICATE-ZERO

Be suspicious of boolean helpers:
    is*
    has*
    can*
    exists
    valid
    supported
    enabled
when they merely rebox richer semantic facts.
Prefer direct refinement/consumption of the richer result.
A bool exists only when bool itself is demanded.

## CXVI. MODE-ZERO

Do not collapse independent semantic dimensions into:
    mode
    kind
    flavor
    style
    class
    category
    tag
if those are merely discriminators selecting behavior.
Decompose into actual facts.
Example:
    mode = readonly
is usually inferior to simply omitting write authority.

## CXVII. KIND-TAXONOMY CAUTION

Classification enums may exist as physical compact representations.
They may not replace decomposed semantic facts.
Dangerous:
    kind = callable
    kind = native
    kind = world
    kind = reader
Prefer direct fact relations.

## CXVIII. PROVENANCE-NAME-ZERO

Do not create distinct semantic identity classes:
    generatedvalue
    sourcevalue
    nativevalue
    importedvalue
    syntheticvalue
    inferredvalue
    derivedvalue
because origin/provenance differs.
Provenance is a fact on the same semantic identity where meaning persists.

## CXIX. DEMAND-NAME-ZERO

Do not mint identities from:
    used
    unused
    required
    optional
    consumed
    discarded
    retained
    requested
These are demand facts.
Demand drives realization.
It does not rename the semantic value.

## CXX. EVIDENCE-NO-AUTHORITY

These may represent evidence records, but never independently establish
semantics:
    status
    verdict
    proof
    report
    audit
    census
    metric
    benchmark
    profile
    trace
    log
    ledger
Evidence validates claims.
It does not make language facts true.
Profile guides optimization only.

## CXXI. PHASE-NO-AUTHORITY

Implementation may be organized into phases such as:
    lexer
    parser
    resolver
    lowerer
    codegen
but phase does not become semantic ownership merely because code runs there.
Facts remain owned according to semantic responsibility.
"Frontend" and "backend" must not become parallel semantic kingdoms.

## CXXII. Source Order / File Path

Filesystem topology supplies initial home/member projection.
After resolution, path becomes provenance.
Path never chooses:
    relation
    world
    target
    conversion
    protocol
    realization
Move/rename with semantic correspondence must not silently change meaning.

## CXXIII. LSP

Every language feature must support:
    formatting
    completion
    hover
    semantic highlighting
    diagnostics
    navigation
    refactoring
LSP consumes compiler semantic graph.
Do not create a second LSP semantic model.

## CXXIV. MCP

MCP should become the semantic API for agents.
Prefer stable semantic ids and graph queries over text search.
Useful queries:
    what relation is this?
    what is the subject?
    why this world?
    why this representation?
    what blocks scalarization?
    what prevents direct call?
    what transformation produced this instruction?
    what unknown fact caused this allocation?
Avoid text-based semantic workflows whenever graph facts are available.

## CXXV. Repository Corpus

Canonical agent training/reference source must contain only current canonical
Idol.
Historical/negative/foreign syntax must not masquerade as canonical corpus.
Prefer:
    generated transient negative fixtures
over permanently storing large searchable noncanonical source corpora.
If negative fixtures remain stored, their role must be mechanically explicit and
excluded from canonical training/search projections.

## CXXVI. ZERO-HISTORY

Git is the history archive.
Active current-project source/docs should not preserve:
    old project names
    old syntax history
    Pass N
    migration chronology
    deprecated wording
    legacy architecture explanations
unless required to describe a currently executed foreign/bootstrap boundary.
Current comments explain current truth.
Do not write:
    formerly...
    used to...
    release 0.1...
    migration from...
into canonical source.

## CXXVII. Current Identity

Project/language:
    Idol
Canonical source suffix:
    .id
New canonical `.id` is admitted.
Retired suffixes `.duo`, `.duon`, `.idsem` are forbidden in the active tree.
Canonical executable/tool spelling:
    idol
Do not reintroduce retired project identities or suffixes into active project
source, paths, caches, generated files, or current teaching.

## CXXVIII. Gate

`gate` is singular.
C0/constitution owns law.
Gate members verify/projection-test the law.
Gate files must not independently invent or manually maintain a second copy of
the language rules.
Generated verification from C0/graph is preferred.
Any temporary lexical detector must have a deletion condition once graph
authority exists.

## CXXIX. Manual Vocabulary Tables

Do not maintain hand-authored tables such as:
    admitted words
    relation→world
    namespace map
    respelling map
    global map
    protocol registry
when those facts already exist in grammar/C0/graph.
Gate queries the authoritative fact source.
It does not duplicate it.

## CXXX. SELF-HOSTING

Self-hosting means actual executed semantic authority moved into Idol.
It does not mean:
    .id file count
    source-line percentage
    wrappers around host APIs
    renamed foreign code
Ask:
    what earliest production semantic fact is still owned outside Idol?
Move that authority.
Then delete the old owner/fallback.
Priority frontier:
    lexical identity
    → grammar role
    → parser recognition
    → semantic resolution
    → graph
    → demand
    → realization
    → machine

## CXXXI. No Silent Fallback

After semantic authority moves, old path may not silently answer.
Unsupported native behavior:
    diagnose/fail closed
Do not silently:
    emit C
    call Lua
    invoke host helper
    use textual builtin
    query stale registry
    reconstruct from path
unless explicitly performing an admitted foreign realization.

## CXXXII. C Backend

Generated C is an explicit orthogonal physical realization, not semantic
authority and not a tier beneath direct native. It consumes the same graph facts
as every other backend. Do not shape Idol semantics around ease of C emission.

Direct native remains the default, self-host, release, correctness, and
performance path. It never emits C, invokes a C compiler, depends on a C
artifact, or falls back to C. `auto` never selects C. C-backend evidence proves
only the C feature; it cannot certify direct native. The `c` foreign world is an
independent interop capability and does not select a backend.

## CXXXIII. FTCFTW

Goal:
    faster than C across equivalent semantics
and:
    Idol Wasm faster than Wasmtime
    smaller binaries
    faster startup
Claims require evidence.
Optimization principle:
    unresolved semantic possibility → physical cost
As semantic uncertainty disappears:
    physical cost should disappear
Track unknowns that force:
    allocation
    box
    tag
    hash
    indirect call
    guard
    copy
    runtime descriptor
    lock
    spill
    materialization

## CXXXIV. Performance Evidence

Every performance claim binds:
    exact revision
    dirty state
    exact input
    semantic result
    target
    CPU/features
    competitor version
    compile time
    startup
    execution time
    peak memory
    artifact size
    sample count
    variance
Timing with incorrect/different semantics is invalid evidence.

## CXXXV. Performance Damage Control

Every benchmark must contain a positive observability control.
Intentionally worsen the measured dimension:
    add delay
    force allocation
    force hash
    force indirect call
    force copy
    disable vectorization
The benchmark must measurably worsen.
Otherwise the measurement path is not trusted.

## CXXXVI. FTCFTW DIMENSIONS

Do not optimize runtime alone.
Track jointly:
    runtime
    startup
    compile time
    compiler memory
    runtime memory
    binary size
    linked runtime bytes
    I-cache impact
No benchmark victory purchased by catastrophic size/startup/compile regressions
without explicit tradeoff evidence.

## CXXXVII. Agent Work Rule

Before adding any language/compiler concept:
    identify existing semantic owner
Before adding a name:
    prove identity irreducibility
Before adding a wrapper:
    prove the wrapped relation cannot already express it
Before adding a registry:
    prove graph facts cannot own it
Before adding a module:
    stop; module semantics are denied
Before adding *able:
    stop; protocol satisfaction is a fact
Before adding encode/decode:
    classify satisfaction/to/parse/realization first
Before adding plural table/root:
    stop; cardinality is a fact
Before adding router/gateway/context/engine:
    stop; find the actual existing semantic machinery
Before reconstructing information downstream:
    stop; fix the producer edge

## CXXXVIII. Hard Stop Conditions

Do not continue implementation when:
    semantic owner is unclear
    relation identity is unclear
    subject is unclear
    world authority is ambiguous
    application role is ambiguous
    upstream fact is missing
    easiest solution is a registry/context/router
    solution requires path/name semantic lookup
    solution requires semantic fallback
    new concept duplicates an existing mechanism
Record the exact missing semantic fact/boundary.
Do not invent architecture to unblock yourself.

## CXXXIX. Required Review For Every New Name

Every new project-owned name must answer:
    What semantic entity exists independently of this spelling?
    Is it singular?
    Is the word irreducible?
    Is it a noun for a real entity rather than an ability/role/state?
    Does it encode cardinality?
    Does it encode protocol satisfaction?
    Does it encode transformation direction?
    Does it encode representation?
    Does it encode implementation phase?
    Does it encode target?
    Does it encode provenance?
    Does it encode demand?
    Does it collide with application/world/projection/realization machinery?
    Would a fact change require renaming it?
Any bad answer:
    reject/decompose.

## CXL. Required Review For Every Application

For each application determine:
    relation
    subject
    operands
    result pack
    descriptor facts
    demand
    world requirement
    world witness
    effect
    stage
    origin
    provenance
    selected target when realized
Then ask:
    which facts need source spelling?
    which are uniquely inferable?
    would elision confuse a human reader?
No spelling is omitted merely because compiler inference can guess it.

## CXLI. Required Review For Every Compiler Structure

Ask:
    Is this semantic or physical?
    What authoritative fact does it contain?
    Who produced that fact?
    Is the fact duplicated elsewhere?
    Can deleting this structure change semantics?
    Is it an acceleration index?
    Does it reconstruct from names/paths?
    Does it create a second taxonomy?
    Does representation leak upward into meaning?
If deleting a supposed cache/index changes meaning:
    it was illegally authoritative.

## CXLII. Required Review For Every Physical Cost

For:
    allocation
    copy
    box
    tag
    branch
    indirect call
    hash
    runtime metadata
    world object
    closure environment
    temporary pack
    synchronization
answer:
    Which unresolved semantic possibility requires this?
No answer:
    delete the cost.

## CXLIII. Required Review For Every Pr/Workstream

Report:
    revision
    dirty state
    semantic boundary owned
    authority before
    authority after
    fact producer changed
    consumers changed
    ids preserved
    facts added
    facts removed
    reconstruction removed
    new concepts
    deleted concepts
    naming debt introduced
    naming debt removed
    bridges remaining
    bridge deletion condition
    SHC frontier before
    SHC frontier after
    physical delta:
        allocation
        copy
        box
        tag
        hash
        indirect call
        runtime bytes
    compile-time delta
    startup delta
    runtime delta
    memory delta
    size delta
    positive control
    negative control
    integrated result
No "done" without this.

## CXLIV. Negative Controls For Naming

Must reject attempts to create semantic architecture called:
    callable
    reader
    serializable
    encoding
    codec
    router
    broker
    service
    registry
    manager
    context
    engine
    pipeline
    collection
    container
    nativevalue
    validtype
    semantictransaction
when each merely reifies an existing fact/role.
Renaming to a synonym must still fail.
The gate is semantic-role based.
Not a word blacklist.

## CXLV. Positive Domain Exceptions

A normally suspicious word may be valid when it literally denotes an external
observable domain entity.
Examples:
    network router
    HTTP gateway
    hardware driver
    external codec identifier
But such a domain word may NOT be reused as compiler semantic machinery.
Likewise:
    json
    cbor
    protobuf
    wasm
    macho
may identify real observable format/foreign domains.
Their associated operations still follow the common semantic algebra.

## CXLVI. Current Canonical Style Examples

Descriptor/table (ordinary table — no sigil):
    point = {
        x: f64
        y: f64
    }
Compact function:
    add = (a, b) a + b
Tail-return body:
    normalize = (value) value:validate():normalize()
Accessor:
    home = env("HOME")
    first = args(1)
Meaningful relation:
    stdout:write(source:read())
Search + nil refinement:
    position = text:find("idol")
    if position
        print(position)
Conversion inferred:
    count: i64 = text
only when the compiler can prove the unique lawful to(i64) conversion and
that conversion is actually the intended semantic operation.
Conversion explicit when necessary:
    count = text:to(i64)
Static projection followed by accessor:
    home = mock.os.env("HOME")
Parent relation from child file:
    gate:idiom(diff)
No:
    gate.idiom(diff)
No:
    env["HOME"]
No:
    source()
when source() would obscure "read."
No:
    code:has(pattern)
No:
    encode(value)
without proving encode is independently irreducible.

## CXLVII. Current Canonical Topology Example

    gate/
        census.id
        idiom.id
    test/
        smoke.id
    mock/
        os.id
        input.id
        input/
            read.id
        output.id
        output/
            write.id
No root gate.id/test.id/mock.id is required for the directories to imply those
tables.
If same-name root files exist, they contribute to the same homes.

## CXLVIII. THINGS THAT MUST TREND TO ZERO

    retired project identities
    historical syntax
    pass-number source/comments
    module/import semantics
    std namespace
    lib semantic namespace
    semantic.* replacement namespace
    plural cardinality names
    *able/*ible identities
    role-noun protocol identities
    encode/decode generic systems
    codec systems
    router/gateway/dispatcher systems
    registry systems
    manager/factory systems
    context/session responsibility bags
    engine/pipeline systems
    bridge/shim/proxy layers
    main/entry wrappers
    redundant file self-bindings
    relation invocation through dot
    operation-first possessed-subject calls
    bracket ordinary access
    has/presence reboxing
    conversion synonyms
    explicit to when uniquely inferable
    world classes
    universe classes
    adjective capability worlds
    relation→world string maps
    protocol-granted authority
    host API wrappers
    compiler API namespaces
    downstream semantic reconstruction
    target-qualified semantic relations
    DNIR semantic duplication
    known-shape hash lookup
    sealed indirect calls
    nonescaping heap closures
    singleton-union tags
    undemanded result materialization
    undemanded runtime witness objects
    unexplained physical cost
    silent host/C/Lua fallback
    stale committed session state
    historical gap archive

## CXLIX. Final Compression

ONE MEANING → ONE ID.
FACTS QUALIFY IDENTITIES.
FACTS DO NOT BECOME EXTRA IDENTITIES.
CARDINALITY IS A FACT.
ABILITY IS A FACT.
ROLE IS A FACT.
STAGE IS A FACT.
TARGET IS A FACT.
PROVENANCE IS A FACT.
REPRESENTATION IS A FACT.
DEMAND IS A FACT.
AUTHORITY IS A FACT.
DIRECTORIES ARE TABLES.
FILES ARE TABLE/MEMBER BODIES.
ROOT EXPRESSIONS EXECUTE.
THERE IS NO MAIN.
DOT PROJECTS STATIC MEMBERS.
COLON ORIENTS MEANINGFUL RELATIONS.
PARENTHESES CALL/APPLY/ACCESS WHEN THAT IS HUMAN-OBVIOUS.
DO NOT HIDE MEANINGFUL READ/WRITE/OPEN/RUN/PARSE INTENT.
NIL IS ORDINARY ABSENCE.
DO NOT REIFY ABSENCE AGAIN.
HAS DOES NOT REBOX PRESENCE.
TO IS THE ONE CONVERSION RELATION.
TO DISAPPEARS WHEN SATISFACTION OR DEMAND MAKES IT REDUNDANT.
ENCODE/DECODE ARE NOT PRESUMED SEMANTIC RELATIONS.
FORMATS MAY BE DESCRIPTORS.
@ IS THE CURRENT WORLD — NOT A COMPILER/HOST DIRECTIVE.
@{} IS WORLD DERIVATION BY INJECTION — DESCRIPTORS ARE ORDINARY TABLES.
SOURCE NAMES USE; EXECUTION SUPPLIES WITNESSES — INFER-ONE FOR WORLD.
RESOLVE ONCE: LEXICAL/HOME ASSISTS INITIAL BINDING; NO LOOKUP AFTER RESOLUTION.
CAPTURE EDGES REPLACE RUNTIME PARENT SCOPE.
FILESYSTEM: INGEST TOPOLOGY ONLY — THEN PROVENANCE ONLY.
UNIVERSE IS COMPILER-INTERNAL — NOT USER SYNTAX.
FACT COMPOSITION IS INTERNAL — NOT inject/interject SOURCE CEREMONY.
WORLD IS EXECUTION INPUT — ORDINARY TABLES AT THE BOUNDARY.
PROJECTION IS `.` `:` AND APPLICATION — NO PROJECTION DSL.
PROTOCOL IS AN APPLICATION/RELATION CONSTRAINT.
PROTOCOL DOES NOT GRANT AUTHORITY.
MODULES DO NOT EXIST NATIVELY.
STD DOES NOT EXIST NATIVELY.
LIB DOES NOT EXIST SEMANTICALLY.
ROUTERS DO NOT OWN ROUTING.
REGISTRIES DO NOT OWN MEANING.
CONTEXT OBJECTS DO NOT MAKE FACTS TRUE.
ENGINES DO NOT OWN EXECUTION SEMANTICS.
BRIDGES MUST DIE.
THE GRAPH OWNS MEANING.
DEMAND OWNS NECESSITY.
REALIZATION OWNS PHYSICS.
EVERY PHYSICAL COST MUST IDENTIFY THE SEMANTIC UNCERTAINTY OR OBSERVABLE LAW
THAT REQUIRES IT.
OPTIMIZATION IS THE DISAPPEARANCE OF PHYSICAL COST AS SEMANTIC UNCERTAINTY
DISAPPEARS.
SELF-HOSTING IS EXECUTED SEMANTIC AUTHORITY TRANSFER.
FTCFTW CLAIMS REQUIRE SEMANTIC-EQUIVALENCE EVIDENCE.
IF A NAME MERELY RESTATES A FACT:
    DELETE THE NAME.
IF A NEW OBJECT DUPLICATES EXISTING LANGUAGE MACHINERY:
    DELETE THE OBJECT.
IF A DOWNSTREAM STAGE RECONSTRUCTS A FACT:
    FIX THE PRODUCER/EDGE.
IF A FALLBACK CAN SILENTLY REGAIN AUTHORITY:
    DELETE THE FALLBACK.
IF A PHYSICAL COST CANNOT EXPLAIN WHY SEMANTICS REQUIRE IT:
    DELETE THE COST.
THE TARGET END STATE IS:
    ONE LANGUAGE
    ONE GRAPH
    ONE APPLICATION ALGEBRA
    ONE FACT SYSTEM
    ONE SEMANTIC AUTHORITY
    ZERO SHADOW ONTOLOGY
    ZERO HISTORICAL DRIFT
    ZERO UNEXPLAINED PHYSICAL COST
    100% IDOL SELF-HOSTED SEMANTIC AUTHORITY
    FTCFTW PROVEN BY EVIDENCE

FTCFTW is not a checklist. It is the whole frontier `R(S,W,T,E,P)` — every
physically lawful realization preserving the required observations — searched to
a verified Pareto frontier (`docs/spec/law.md` §107 OPTIMIZATION-SPACE-COMPLETE;
C0 `law.optimization.space`). It rests on:

    OBSERVATION-ONE (§104, law.observation.one)
        a program is required observable relationships, not steps; semantic time
        is not physical time; observability is world-dependent
    OBSERVATION-MINIMUM (§103, law.observation.minimum)
        preserve only what is observable; every accidental observable is a
        permanent optimization barrier
    PHYSICAL-SPACE-OPEN (§102, law.physical.open)
        realization is any physical strategy across the whole machine/OS/hardware
        stack, not code generation
    BOUNDARY-ONE (§105, folded in law.observation.one)
        representation is free except at irreversible boundaries; foreign
        representation has finite extent
    OBLIGATION-ONE (§109, law.obligation.one)
        semantics is allowed observations + required obligations (positive,
        negative, temporal, safety/liveness, progress, fairness, causality,
        noninterference); equivalence preserves hyperproperties over SETS of
        executions, not one trace — "same output" is not equivalence
    NINE-UNIVERSE (§110, law.realization.universe)
        the structural (non-enumerative) closure: meaning · observation ·
        knowledge · demand · equivalence · realization · resource · search+proof
        · change; the supreme R equation; monotonic frontier (no knowing Pareto
        regression); value-of-information and contract-weakening debt; optimality
        gap = best-known − proven-lower-bound

The frontier factors into the 24 axes of §107/§108 over these nine universes
(§106/§110), with the foundational algebras law.equivalence.observation,
law.demand.derivative, law.relation.property, law.change.delta,
law.uncertainty.algebra, and law.optimizer.economy. A candidate realization is
admitted iff it preserves demanded observations under the current world,
satisfies authority/effect/resource constraints, is verifiable, and improves the
chosen Pareto frontier. Individual optimizations are instances discovered inside
`R`, never additions to the constitution. The frontier is **machinery, not a
list**: five graphs — A observation, B demand, C law, D frontier, E debt — feed a
mechanical loop (measure → largest debt → classify cause → implement → validate →
ratchet), with every case carrying a status in `{win, bound, open, unknownbound}`
and no aggregate permitted to hide a loss. Catalogue: `docs/performance.md`;
obligations: `gaps/GAP-169.md`, `gaps/GAP-170.md`, `gaps/GAP-171.md`,
`gaps/GAP-172.md` (frontier machinery / FTC-001…020).

The most important instruction for the new agent is the one that prevents recurrence of nearly every recent mistake:

Do not ask “what should I call this new thing?” until first proving that there is actually a new semantic thing. Most apparent new types, protocols, managers, helpers, encoders, readers, registries, contexts, states, wrappers, and categories should instead disappear into existing relation/descriptor/fact/application/world/realization semantics.

That is the difference between merely making the repo look Idollic and actually converging to the architecture.
