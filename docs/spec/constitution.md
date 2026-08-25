# Idol constitution projection

`docs/spec/law.md` is the **sole supreme compact law**. This file is its
structured long-form expansion, stable `law.*` identity owner, and documentation
bridge — not a competing authority. When this file and the compact law differ,
the compact law wins and this projection must be repaired without minting an
amendment subsystem.

`CLAUDE.md`, other `docs/spec/*.md` pages, agent routers, tests, tools, and
implementation are further projections and may not contradict either authority
tier. Git history is the sole historical archive.

The fenced body is structured law notation retained while `GAP-145` closes the
canonical lexical and generated-role boundary. It is not executable canonical
Idol, not a source template, and its `#` notation must not be copied into
`.id`. The current law lives in the facts; the notation is a documentation
projection until the whole file can move truthfully to `constitution.id`.

```text
# C0 structured law notation. NON-SOURCE.

# ═══ §1 · the primary representation ═══════════════════════════════════════
#
# The first fact, and the one every other fact depends on: law lives in the
# graph, not in sentences.

law: {
    id: str
    kind: { invariant, objective, deprecated, boundary, protocol }
    holds: any
    binds: seq(str)
    fails: str
    # These fields describe the complete law record in the structured
    # documentation bridge. Canonical constitution source and generated
    # machine validation remain blocked by GAP-145.
    why: any
    deny: any
    canon: any
    keep: any
    ladder: any
    open: any
    proof: any
}

representation = law{
    id    = "law.representation"
    kind  = .invariant
    holds = .facts
    binds = {
        "prose explains, prose does not bind",
        "every normative rule exists in this graph",
        "a rule that exists only in prose is unshipped",
    }
}

authority = @{}

authority.constitution = law{
    id    = "law.authority"
    kind  = .invariant
    holds = .expansion
    binds = {
        "docs/spec/law.md is the sole supreme compact law",
        "this document is the structured long-form expansion and law-id owner only",
        "when compact law and this projection differ the compact law wins and this file is repaired",
        "every generated projection and implementation must trace its rule to the compact law through this expansion",
        "no implementation projection pass document router corpus or tool encodes an independent rule",
        "machine consumption remains blocked until canonical constitution id and generated projections replace the documentation bridge",
    }
    fails = "two encodings of one rule is two languages or a second supreme authority beside law.md"
}

# The structural goal. Note it is an OBJECTIVE, not an invariant: it states
# where the language is going, and it is measured, not asserted.
correctness = law{
    id    = "law.correctness"
    kind  = .objective
    holds = .unrepresentable
    binds = {
        "invalid syntax cannot be written",
        "invalid semantics is refused by the graph, not by a linter",
    }
}

# ═══ §2 · the constitutional stack ═════════════════════════════════════════

level: { rank: i64, name: str, role: str }

stack = {
    level{ 0, "compact_law", "docs/spec/law.md — supreme compact law" },
    level{ 1, "constitution", "structured expansion of compact law" },
    level{ 2, "grammar", "constraints derived from C0" },
    level{ 3, "verification", "corpus, diagnostics, roles, agent context" },
    level{ 4, "implementation", "execution" },
}

descent = law{
    id    = "law.descent"
    kind  = .invariant
    holds = .downward
    binds = { "C0 to C4 only", "no upward dependency" }
    fails = "an implementation that teaches the constitution is a fork"
}

conformance = law{
    id    = "law.conformance"
    kind  = .invariant
    holds = .implementation
    fails = "the implementation is invalid, never the constitution"
}

coherence = law{
    id    = "law.coherence"
    kind  = .invariant
    holds = .consistent
    fails = "the build stops BEFORE compiling anything"
}

# ═══ §3 · RULE-OWNER — precedence, and why it exists ═══════════════════════
#
# Agent output and historical pass material never outrank an owner directive
# reconciled into this constitution. A conflicting projection is void and must
# be repaired rather than treated as another authority.

precedence = {
    "directive",       # the owner, verbatim, until reconciled into law.md
    "compact_law",     # docs/spec/law.md — supreme executable wording
    "constitution",    # structured long-form expansion of compact law
    "projection",      # grammar, corpus, context and workflow views
    "implementation",  # what happens to be implemented
}

owner = law{
    id    = "law.owner"
    kind  = .invariant
    holds = .directive
    binds = {
        "a current explicit owner directive is reconciled into docs/spec/law.md before implementation continues",
        "docs/spec/law.md is the sole supreme compact law and this constitution is its structured expansion only",
        "pass documents summaries projections corpus patterns and implementation are never parallel law",
    }
    fails = "leaving a current directive beside contradictory repository law or treating historical pass text as authority"
}

# ═══ §4 · identity ═════════════════════════════════════════════════════════

language = @{
    name  = "idol"
    file  = ".id"
    binary = "idol"
    repository = "idollang/idol"
    epoch = 3
}

# Current identity — never list Idol in language.history.
# ZERO-HISTORY: no language.history table. Git is the sole historical archive.
language.current = @{
    names = { "Idol", "idol" }
    file  = ".id"
    binary = "idol"
    repository = "idollang/idol"
}

mnemonic = law{
    id    = "law.identity.mnemonic"
    kind  = .invariant
    holds = .explanation
    binds = {
        "identity model is an explanatory mnemonic only and never a semantic subsystem",
        "the project brand never qualifies an existing semantic concept",
        "idolgraph and idolrelation are denied because the concepts remain graph and relation",
        "graph relation id descriptor value demand world place and witness retain their unbranded names",
    }
    deny  = { "idolgraph", "idolrelation", "branded semantic compounds" }
    fails = "a project brand becoming semantic ontology"
}

id = law{
    id    = "law.id.one"
    kind  = .invariant
    holds = .graph
    binds = {
        "id is the one semantic identity concept and facts qualify every relation application value descriptor subject world provenance transformation demand realization and machine range",
        "graph rows slots array positions compact tags and dense integers are private physical representations of id and never create node kind edge or layer identity vocabularies",
        "public semantic boundaries use id directly and never expose node stable entity value call application relation region instruction ast source shape descriptor type module local fingerprint graph or incarnation identity wrappers",
        "name path span source spelling fingerprint hash and intern slot are projections provenance evidence or acceleration and never establish identity",
        "distinct occurrences and distinct graph incarnations retain distinct ids even when every compared fact matches",
        "downstream semantic use fails closed when the exact id and required facts are absent",
    }
    fails = "a second identity concept a semantic node or kind ontology or path hash fingerprint name source spelling pointer opcode slot or address selecting meaning"
}

continuity = law{
    id    = "law.identity.continuity"
    kind  = .protocol
    holds = .evidence
    binds = {
        "cross edit build snapshot and incarnation continuity is an explicit relation between ids",
        "provenance source span home relation descriptor transformation and graph correspondence facts may support that relation",
        "missing correspondence remains unknown rather than guessed from equal paths names or fingerprints",
    }
}

fingerprint = law{
    id    = "law.identity.fingerprint"
    kind  = .protocol
    holds = .acceleration
    binds = {
        "a fingerprint may retrieve a cache or correspondence candidate only and is never named or typed as identity",
        "authoritative facts verify every candidate before semantic reuse",
        "collisions and deleting every fingerprint index preserve semantic correctness",
        "fingerprints are computed only when caching persistence or tooling demands them",
    }
}

number = law{
    id    = "law.number.projection"
    kind  = .invariant
    holds = .composed
    binds = {
        "i8 i16 i32 i64 u8 u16 u32 u64 f32 and f64 remain compact canonical source faces",
        "fixed width signedness format precision overflow and rounding are descriptor facts or laws rather than unrelated primitive kingdoms",
        "an unannotated integer literal retains its exact integer value without a default fixed width",
        "width is semantic only where arithmetic range serialization abi memory foreign or other observable law demands it",
        "physical lane register immediate memory vector and target width belong to realization",
        "bool text bytes and integer remain semantic domains rather than machine width aliases",
    }
    fails = "a primitive kind tag selecting meaning or an inferred literal committing a machine representation without demand"
}

# ═══ §5 · syntax ═══════════════════════════════════════════════════════════

syntax.name = @{
    shape     = .word          # one lowercase word
    underscore = false
    uppercase  = false
}

# `docs/spec/law.md` §4–§5f: `@` IS THE CURRENT-WORLD ACCESSOR. Bare `@` is the
# current world value. `@` immediately followed by a static name accesses that
# world member: `@member` (`@target`, `@env`) — `@` already performs the access,
# so `@member.child` is one world access then one ordinary static projection.
# There is NO `@.` projection step and NO `@:` subject dispatch: `@.member` and
# `@:member` are INVALID; write `@member`. Postfix `thing@world` interprets
# `thing` in `world`; `thing@` is lawful current-world qualification (normally
# redundant). `@{ … }` is the injection literal only (apply the current world to
# a pack of `k = v` facts to derive a NEW closed world); an ordinary
# pack/descriptor is plain `{ … }` with no sigil. `thing@{ … }` is interjection
# — `thing@(@{ … })`. `@k = v` mutates a world member place. `@( … )` is eval. A
# prefix `@` directive that names a compiler namespace (`@comp`, `@host`,
# `@runtime`, `@c`, `@emit`, `@asm`) does not exist — that is a directive zoo,
# not a world member.
syntax.anchor = @{
    bare      = .world         # `@` is the current world value
    member    = .projection    # `@target` `@env` — access a static current-world member
    postfix   = .world         # `thing@world` interprets thing in world; `thing@` current
    eval      = .same          # `@( … )` evaluates in the current world
    inject    = .world         # `@{ k = v }` derives a closed world with exact deltas; an ordinary pack/descriptor is plain `{ … }`
    interject = .scope         # `thing@{ k = v }` evaluates thing under an injected world
    mutate    = .place         # `@k = v` mutates a world member place, when it is a place
    prefix    = false          # neither a prefix `@` directive namespace nor a `@.`/`@:` accessor step exists
}

# projection · injection · interjection · mutation are four uses of ONE
# table/world mechanism — not four subsystems, and no inject/scope/context/
# provider/registry/dependency framework is minted.
world.projection = law{
    id    = "law.projection.algebra"
    kind  = .invariant
    holds = .same
    binds = {
        "`.` is exactly one static structural projection — one filesystem child level or one static member — never dispatch, method/extension lookup, namespace/recursive search, or world/parent fallback",
        "a bare name infers as a static projection of the current world only when no lexical binding supplies the meaning and the projection is unique; lexical binding wins for a bare lexical name and `@member` accesses the world member explicitly",
        "injection `@{ k = v }` derives a NEW closed world: project(inject(w, k=v), k) = v and project(inject(w, k=v), q) = project(w, q) for every untouched q, established when the world is formed, never a runtime parent-world fallback",
        "empty injection is identity, injecting the exact existing fact is idempotent, a duplicate member in one injection literal is an error, and nested injection shadows by formation order not search",
        "interjection `thing@{ k = v }` is `thing@(@{ k = v })`; world qualification `thing@world` scopes to the evaluated subtree and threads its world through unresolved ambient dependencies without a runtime world argument, leaving the caller world unchanged",
        "mutation `@k = v` is ordinary place mutation, persistent and observed by every alias; a derived world is a distinct world; prefer interjection for scoped replacement",
        "after ingestion path is provenance and id/facts are authority; no component walks directories again, and when the world is statically known the realization keeps world object 0, lookup 0, and dispatch 0",
    }
    fails = "a second scope/context/provider/registry/dependency subsystem; `.`/`@` resolution that searches or falls back instead of selecting one exact fact; or a `@.member`/`@:member` accessor — `@` already accesses, so the only faces are `@member`, `@k = v`, `thing@world`, `@{ … }`, `thing@{ … }`"
}

# injection changes fact AVAILABILITY; it never bypasses satisfaction. authority
# is a fact whose value must be a valid witness — a label/boolean/string cannot
# manufacture it (`law.world.grant`, `law.able`).
world.authority = law{
    id    = "law.injection.authority"
    kind  = .invariant
    holds = .same
    binds = {
        "an injected authority fact must itself be a valid semantic witness; `@{ authority = true }` grants nothing",
        "relation applicability (`able(read)`) and world authority are separate facts; protocol satisfaction never grants authority",
        "a closure captures the smallest exact necessary world fact, not the whole world; the ambient world is not an automatic closure environment",
        "a world is named for its genuine scenario, never for the fact it injects",
    }
    fails = "world injection used as authorization magic, or an ambient world captured whole when one fact was required"
}

syntax.block = @{
    bound     = .offside
    close     = false
    semicolon = false          # the repair is "press enter"
}

# ═══ §5b · path and home names ═════════════════════════════════════════════
#
# A project-owned filename or directory that projects an Idol binding or home
# obeys the SAME name law as Idol source. There is no separate filename
# convention. The stem is the semantic table or home name; the path projects
# it. Physical path is provenance after resolution; it must not mint a second
# semantic identity.

path.name = law{
    id    = "law.path.name"
    kind  = .invariant
    holds = .same
    binds = {
        "canonical(path stem) equals the canonical semantic name of the table or home that source contributes",
        "one irreducible semantic meaning maps to one lowercase word in every path component that projects semantic home",
        "concatenated file and directory names never express qualification — decompose semantic units into nested homes and worlds through hierarchy, never mashed stems",
        "snake_case camelCase PascalCase SCREAMING_CASE kebab-case dot.compounds word concatenation invented abbreviations and numeric version suffixes used as taxonomy are forbidden in project-controlled semantic path components",
        "removing punctuation does not repair a compound name",
        "a slash expresses semantic home topology only when the enclosing component is an admitted home",
        "corpus role words such as test proof fixture example benchmark generated native foreign compat legacy migration and snapshot do not belong in semantic source-table identity unless they are the irreducible owner",
        "foreign generated and history classifications remain mechanically distinct and must not teach native naming",
    }
    fails = "filesystem name and language name maintained as two independent authorities"
}

path.gate = law{
    id    = "law.gate.path"
    kind  = .protocol
    holds = .ratchet
    binds = {
        "every added or renamed project-controlled path component is classified before admission",
        "separator and case violations fail immediately",
        "a stem decomposable into two or more established semantic words fails unless the whole stem is independently admitted as one irreducible word",
        "semantic_graph semanticGraph SemanticGraph semantic-graph and semanticgraph receive the same verdict",
        "old_thing to oldthing does not clear a compound finding merely because punctuation disappeared",
        "no filename allowlist becomes a second naming authority",
        "long-term validation belongs in the source graph; gate/path.id and gate/idiom.id are the staged lexical and compound firewalls until then",
    }
    fails = "a commit that adds canonical source inside an invalid new filename or introduces a mashed compound name token on an added line"
}

# ═══ §6 · semantic roles ═══════════════════════════════════════════════════

call.face = @{
    declare = .operation       # to(str) = (value) … — head parens PROJECT the relation
    invoke  = .subject         # value:to(str) · lx:read(number)(b) — subject : then projection then operands
}

# law.paren.one: () after a relation name in a declaration head is projection, not
# curry. to(str) = (value) does not produce a callable; value:to(str) supplies the
# subject. f(a)(b) is two applications only when f(a) is actually callable.

# `docs/spec/law.md` §5 and §9: ONE application algebra — `()` is ordinary
# application. Computed or indexed aggregate access is projection — `table[key]`
# — never `table(key)`, `table:get(key)`, or `get(table, key)`. When projection
# yields a place, `table[key] = value` is the assignment face; there is no
# setter ontology. Application and projection resolve from applied-value
# identity and facts; there is no "get first / call first / table first"
# precedence, and incomparable candidates are an ambiguity error. A foreign
# source law may recognize its own bracket/call indexing only inside that
# law-qualified source projection as provenance. `:get`/`get(t,k)` are
# noncanonical.
access = @{
    application = .application  # f(x) — ordinary application; never aggregate indexing via ()
    projection  = .indexing     # table[key] — computed aggregate projection
    place       = .assignment   # table[key] = value — no setter kingdom
    precede     = false         # no get/call/table-first precedence; ambiguity errors
    compat      = .foreign      # foreign-law provenance only; never canonical Idol access
}

# `docs/spec/law.md` §9: `able(...)` is the ONE explicit protocol/requirement
# boundary. It creates no trait, interface, protocol object, dictionary, vtable,
# or adjective type. `able(eq)` / `able(read)` / `able(to(str))` mean the unknown
# subject at this boundary must ADMIT the demanded relation/application shape.
# ABLE IS NORMALLY INFERRED — omit it when implementation/use already establishes
# the requirement; spell it only at a real boundary (public/open generic contract,
# implementation unavailable, higher-order boundary, ambiguous requirements, or a
# descriptor that explicitly exposes its admitted relation shape). Static
# satisfaction keeps runtime protocol object / dictionary / vtable = 0. Protocol
# satisfaction never grants authority. Adjective protocols (`readable`, `iterable`,
# `source: readable`, `trait`, `impl`, `concept`) remain forbidden — the relation
# constraint is `source: read` and the boundary word is `able`.
able = @{
    boundary = .protocol       # the one explicit requirement boundary
    shape    = .application     # able(eq) able(read) able(to(str)) — admitted shape
    default  = .inferred        # INFER ABLE FIRST; spell only at a real boundary
    runtime  = false            # object 0 · dictionary 0 · vtable 0; grants no authority
}

subject = @{
    implicit = true
    named    = false           # SELF-ZERO: there is no self
}

failure = @{
    result   = .union          # t | error; structural nil is unwritten
    obligate = true            # an unconsumed failure position diagnoses
    route    = .contract       # B-15 routes under a declared contract
}

# ═══ §7 · lua is hosted, not assimilated ═══════════════════════════════════
#
# Language origin is not merely metadata. A Lua table lookup and an
# Idol sealed-shape field lookup can have identical graph SHAPE and different
# semantic LAW. If origin were only provenance, an optimizer could prove a
# fact using Idol laws over a Lua node.
#
# So: the SUBSTRATE is shared, the LAWSET is not. Lua shares shapes,
# specialization, representation selection and witnesses without becoming
# almost-Idol.

lua = @{
    host   = .hosted
    law    = .lua              # lua semantics, exactly
    face   = .foreign
}

# ═══ §8 · passes become provenance ═════════════════════════════════════════
#
# Pass numbers stop being authority and become history. Supersession is a
# graph operation, not a numeric comparison — which is what let "higher pass
# wins" overrule a directive in the first place.

passes = law{
    id      = "law.pass"
    kind    = .deprecated
    holds   = false
    binds   = { "pass numbers are provenance", "supersedes is a graph edge" }
}

supersedes = @{
    old = .retired             # removed from the current view
    new = .active
}

# ═══ §9 · CLAUDE.md is a non-normative projection ══════════════════════════
#
# Generation is the target. Until that projection exists, a hand-maintained
# view must remain short, declare its source and fail closed on disagreement.

context = @{
    source = .constitution
    write  = .bootstrap
    target = .generated
    binds  = false             # non-normative
    parts  = {
        "identity", "invariants", "canon", "denied",
        "ownership", "gates", "gaps", "foreign",
    }
}

# ═══ §10 · the pattern lattice ═════════════════════════════════════════════
#
# A canonical pattern is not an example. It is five artifacts, and a pattern
# missing any of them is undefended.

pattern: {
    canon: str
    denied: str
    graph: str
    lowering: str
    diagnostic: str
}

selfzero.pattern = pattern{
    canon      = "scale = (k) { x * k, y * k }"
    denied     = "scale = (self, k) …"
    graph      = "scale(point, k)"
    lowering   = "param 0 is the subject; the surface names no receiver"
    diagnostic = "a parameter named self is an audit finding"
}

# ═══ §11 · source law, not dialect identity ════════════════════════════════

source.interpretation = law{
    id    = "law.source.interpretation"
    kind  = .invariant
    holds = .exact
    binds = {
        "every source position has exactly one explicit or ingress-derived source law",
        "source supplies bytes span origin and provenance while law supplies interpretation",
        "one grammar authority projects the selected law into token identity roles precedence and structural recognition",
        "world supplies semantic context and authority after recognition and never switches grammar",
        "source law grants no authority and selects no physical realization",
        "foreign grammar remains source provenance rather than a semantic node taxonomy",
        "foreign meaning remains an exact identity in the shared graph until a witness permits convergence",
        "ordinary thing@world is semantic interjection after recognition and never a parser-mode switch",
        "inline foreign source if admitted uses one neutral source-span capture whose punctuation is not yet frozen",
    }
    fails = "a dialect semantic identity hidden parser switch grammar union try-parser world-selected syntax or foreign syntax node surviving as semantic authority"
}

fact.marks = { "origin", "law", "provenance" }

# ═══ §12 · canonicalization ════════════════════════════════════════════════

canon = law{
    id    = "law.canon"
    kind  = .invariant
    holds = .idempotent
    binds = {
        "parse, resolve, canon, render, reparse, compare identity",
        "canon(parse(canon(parse(s)))) == canon(parse(s))",
    }
}

# ═══ §13 · corpora ═════════════════════════════════════════════════════════

corpus = @{
    canon   = "canonical id only"
    foreign = "structured generated external or explicit foreign lawset"
    denied  = "invalid by construction"
}

training = law{
    id    = "law.training"
    kind  = .invariant
    holds = .canon
    binds = {
        "agents learn project owned source patterns from canonical id only",
        "every tracked searchable file is canonical current teaching material or mechanically unmistakable foreign data",
        "git history rather than an in tree source archive preserves retired implementation",
        "foreign import tests use structured generated external or narrowly isolated machine owned input rather than ordinary stale programs",
    }
    fails = "a blind search autocomplete or nearest file analogy teaching retired architecture"
}

# ═══ §14 · the allowed semantic kinds ══════════════════════════════════════
#
# This list is CLOSED. A subsystem that is not one of these, and not one of
# the four allowed roles below, requires a constitutional amendment — which
# means editing this file, in the open, with the owner.

kinds = {
    "id", "descriptor", "relation", "binding", "place", "demand",
    "obligation", "effect", "world", "capability", "lifetime", "provenance",
    "trust", "origin", "realization", "witness",
}

roles = { "index", "cache", "projection", "bootstrap" }

subsystems = law{
    id    = "law.subsystem"
    kind  = .invariant
    holds = false              # no freeform subsystems
    fails = "needs a constitutional amendment, not a directory"
}

# ═══ §15 · the mechanism delta ═════════════════════════════════════════════
#
# What a change must NOT add. All zeros, and a nonzero is not a warning.

delta = @{
    kinds      = 0
    registries = 0
    syntax     = 0
    keywords   = 0
    operators  = 0
    authorities = 0
}

# ═══ §16 · the agent protocol ══════════════════════════════════════════════

agent.before = @{
    ask  = "what is the earliest host-owned production boundary?"
    gets = { "constitution", "source law", "revision", "dirty state", "claims", "gaps", "frontier", "gates", "denied" }
}

agent.steps = {
    "read the sole law and verify source provenance",
    "inspect current revision dirty state live claims gaps frontier and evidence",
    "claim exact disjoint paths before editing",
    "find the semantic owner and request cross owner facts rather than recreating them",
    "compute fact demand realization authority and physical state deltas",
    "produce positive negative differential performance and private run evidence demanded by the boundary",
    "commit and push each bounded admitted repair promptly so concurrent work remains publicly auditable",
    "release exact owned claims and hand off remaining blockers after the pushed revision is verified",
}

# The stop condition, and it is a STOP, not a fallback. An agent that cannot
# find an owner must record a gap rather than invent a home.
# `do` cannot name this field — it is a reserved word, and `noowner` would be
# two words jammed into one, which LAW-ONE forbids as surely as an underscore.
# `.orphan` is the one word that names the state: an entity with no owner.
agent.stop = @{
    when = .orphan
    act  = .gap
}

# ═══ §17 · the gate ════════════════════════════════════════════════════════

gate.agent = {
    "constitution consistent",
    "source law and canonicality classified",
    "path and home names classified",
    "layout resolution without req import loader or admission syntax; projection and scope reachability only",
    "current revision and dirty state bound",
    "ownership conflict absent",
    "graph valid",
    "law one",
    "one edge",
    "world requirements reachable",
    "provenance total",
    "failure obligated",
    "run outcome and evidence private",
    "architecture delta zero",
}

# ═══ §18 · what an agent reports ═══════════════════════════════════════════

report: {
    change: { owner: str, laws: seq(str), archetype: str, graph: str, realization: str }
    ownership: { claims: seq(str), conflicts: seq(str), release: bool }
    proof:  { positive: str, negative: str, differential: str, witness: str }
    run: { revision: str, tree: str, command: str, outcome: str, evidence: str }
    architecture: { kinds: i64, registries: i64, syntax: i64, authorities: i64 }
    boundary: { idol: str, lua: str, shared: str, foreign: str }
    debt:   { compat: bool, bootstrap: str, gate: str }
    blockers: seq(str)
    handoff: str
    result: { gates: seq(str) }
}

# ═══ §19 · why ═════════════════════════════════════════════════════════════

why.takes = { "syntax", "edge", "relation", "failure", "span" }

why.gives = {
    "canonical form", "semantic identity", "law", "graph fact",
    "origin", "resolution path", "witness",
}

# ═══ §20 · totality — THREE gates, not one ═════════════════════════════════
#
# The distinction the audit was right about: 100% role coverage is not 100%
# understood meaning. A token can be beautifully coloured while its binding
# resolution is wrong. These are separate dimensions and each gets its number.

total.role = "every span has ONE role"
total.meaning = "every semantic occurrence resolves to an id and facts or to an explicit error"
total.origin = "every non-source fact carries its chain"

# ═══ §21 · identity is one graph entity ════════════════════════════════════
#
# Equal content may share realization without replacing id.
# Incarnation, correspondence, provenance and content remain separate facts.

coordinate = "a private compact physical representation of id valid only within one exact graph incarnation"
content = "normalized semantic facts and relations, never identity"
incarnation = "the graph lifetime qualifying a private coordinate"

dedup = law{
    id    = "law.dedup"
    kind  = .invariant
    holds = .content
    binds = {
        "share realization and structurally transparent content",
        "never collapse id",
        "private storage deduplication never changes semantic facts or correspondence",
    }
    fails = "two counters becoming one object"
}

# ═══ §22 · lawsets ═════════════════════════════════════════════════════════

lawsets = @{
    native = { "idol" }
    foreign = { "lua", "c", "rust", "python", "wasm", "abi", "schema", "source", "build", "package" }
    closed = false
}

# ═══ §23 · the lua firewall ════════════════════════════════════════════════
#
# Exact source behaviour is non-negotiable. Representation may specialize
# arbitrarily; behaviour may not move. Each of these participates in guards,
# and each specialization owes a behavioural differential.

lua.holds = {
    "table semantics",
    "metatable identity and mutation",
    "multiple return adjustment",
    "numeric behaviour",
    "truthiness",
    "closure environments",
    "coroutines",
    "the error model",
    "iteration order",
    "global environment dynamics",
    "observable identity",
}

lua.adapt = law{
    id    = "law.lua"
    kind  = .invariant
    holds = .behaviour
    binds = {
        "representation specializes freely",
        "every speculation carries its deopt",
        "every specialization carries differential evidence",
    }
    fails = "a faster lua that is not lua"
}

# ═══ §24 · the shared substrate ════════════════════════════════════════════
#
# Shared REPRESENTATION. Not shared law — §7 and §22 are the firewall.

shared = {
    "values", "descriptors", "bindings", "places", "calls", "relations",
    "control", "effects", "demand", "lifetime", "provenance", "origin",
    "law", "trust", "representation", "realization", "witness",
}

# ═══ §25 · cross-language equivalence ══════════════════════════════════════

equiv = @{
    kind    = .edge
    form    = "equiv(a)(b)"
    witness = true             # A5: no claim without one
}

# ═══ §26 · effects touch resources ═════════════════════════════════════════
#
# NOT a total order. A per-function happens-before chain over-constrains and
# costs reordering, vectorization, commuting and parallelism. Effects name
# what they TOUCH and in what mode; ordering is DERIVED where dependence
# actually requires it.

effect: { on: str, mode: { read, write, alloc, io, state } }

effects = {
    effect{ "place", .read },
    effect{ "place", .write },
    effect{ "region", .alloc },
    effect{ "world.fs", .io },
    effect{ "world.net", .io },
    effect{ "runtime.lua", .state },
}

ordering = law{
    id    = "law.ordering"
    kind  = .invariant
    holds = .derived
    binds = { "order only where dependence requires it" }
    fails = "an effect chain that forbids legal reordering"
}

# ═══ §27 · ownership ═══════════════════════════════════════════════════════

ownership = {
    "native", "region", "rc", "borrowed", "pinned",
    "foreign.lua", "foreign.python", "foreign.jvm", "wasm.linear",
}

# ═══ §28 · what dnir is, and is not ════════════════════════════════════════

# `is` and `not` are both reserved, so the fields are `role` and `denies` —
# two more places the constitution had to obey itself to be written.
dnir = @{
    role   = "demand-selected realization, linearized"
    denies = { "the semantic graph", "the language definition" }
}

# dnir is a FAMILY of canonical realization facts with backend views, not one
# linear form serving every backend forever. These are FACETS of one graph, not
# independent IRs; a backend requests the facets it needs and the textual
# `.dnir` form is a deterministic projection of them.
dnir.facets = {
    "core",        # scalars, places, blocks, calls, packs, effects, control
    "mem",         # lifetime, retain/release, region operations
    "vector",      # lanes, masks, vector operations
    "concurrent",  # suspend, resume, atomic
    "machine",     # target-selected constraints
}

# Every dnir operation carries these. A physical temporary may be `%17`, and
# `%17` is NEVER semantic identity — that is what keeps backend-local numbering
# out of MCP, LSP, debugging and the persistent graph.
dnir.marks = { "meaning", "incarnation", "origin", "law", "witness" }

# Linearization need not be perfectly reconstructable — optimization destroys
# surface structure — but every instruction maps BACKWARD to its semantic
# nodes, source spans, transforms and witnesses. That route is what powers
# debugging, perf blame, why(realization), review and certification.
dnir.reverses = true

# ═══ §28a · what is persisted ══════════════════════════════════════════════
#
# "Persist meaning; derive mechanics." Not every compiler detail belongs in the
# persistent graph. Register allocation is not persisted merely because graphs
# are fashionable.

persist = law{
    id    = "law.persist"
    kind  = .invariant
    holds = .meaning
    binds = {
        "persist what matters to incrementality, identity, legality,",
        "tooling, provenance, integration, debugging or agent queries",
        "derive the rest locally",
    }
}

# ═══ §29 · realization candidates ══════════════════════════════════════════

realization = law{
    id    = "law.realization.candidate"
    kind  = .invariant
    holds = .open
    binds = {
        "each demanded value or application retains every lawful candidate compactly until facts demand and cost select one",
        "constant scalar vector direct bytecode gpu and foreign implementation are possible physical candidates rather than a closed kind list",
        "foreign origin guarded proof state and dynamic knowledge remain qualifying facts and never become realization identities",
        "expensive candidate analysis occurs only where candidates compete and the expected value justifies compiler work",
        "selection retains relation application value transformation implementation and machine provenance",
        "sealed selection leaves no runtime catalog registry package traversal or generic dispatch",
    }
}

# ═══ §30 · optimization is a witnessed rewrite ═════════════════════════════

rewrite: {
    pattern: str
    holds: seq(str)
    gives: str
    preserves: seq(str)
    cost: str
    witness: str
}

# ═══ §31 · frontends ═══════════════════════════════════════════════════════
#
# A foreign language lifts to the SUBSTRATE directly. Routing it through a
# Idol AST first would assimilate its semantics on the way in, which is §7.

frontends = @{
    native = { "idol" }
    foreign = { "lua", "c", "rust", "python", "wasm", "source" }
    closed = false
}

lifting = law{
    id    = "law.lifting"
    kind  = .invariant
    holds = .direct
    fails = "a foreign language wearing Idol's ast"
}

# ═══ §32 · a call across a boundary ════════════════════════════════════════

edge.call = {
    "caller law", "callee law", "abi", "ownership", "effects",
    "failure translation", "trust", "representation",
}

# ═══ §33 · the self-hosting sequence ═══════════════════════════════════════
#
# In SLICES, never all at once. At every rung: the old implementation is the
# ORACLE, the new one is the CANDIDATE, and the differential is the JUDGE.
# Do not rewrite from faith.

slice: { rank: i64, name: str, note: str }

selfhost = {
    slice{ 1, "lexer", "executed token production transfers before canonical lexical-role closure" },
    slice{ 2, "grammar", "must consume the GENERATED constitutional grammar" },
    slice{ 3, "identity", "binding + exact graph identity + witnessed cross-incarnation correspondence before optimizer migration" },
    slice{ 4, "relation", "the trie and resolution; retires concept/generic/method registries as authority" },
    slice{ 5, "demand", "makes B-13/B-14/B-15 real graph semantics" },
    slice{ 6, "representation", "including aggregate abi and packs" },
    slice{ 7, "linearizer", "self-hosted graph to the existing backend form" },
    slice{ 8, "backend", "then progressively retire the bootstrap" },
}

differential = law{
    id    = "law.differential"
    kind  = .invariant
    holds = .oracle
    binds = { "old is oracle", "new is candidate", "the differential judges" }
    fails = "a rewrite landed on faith"
}

# ═══ §33a · the orientation truths every agent gets first ══════════════════

# The structured documentation keeps one rule per string so every obligation
# remains independently reviewable. This notation is not canonical source.
agent.first = {
    "Do not design Idol. Idol is already designed.",
    "Identity is id; facts qualify it and no layer exposes a node kind edge or typed identity vocabulary.",
    "Discover the semantic owner, instantiate its canonical archetype, preserve its graph laws, prove the realization.",
    "If the constitution cannot express the change, STOP and record a constitutional gap. Never create a competing mechanism.",
    "Foreign languages are not Idol with strange syntax.",
    "Preserve their lawsets exactly; share representations and optimizations only where witnessed equivalence permits.",
    "Audit and correct useful old or unmerged work against current main before deleting its legacy carrier.",
    "Push each bounded admitted repair promptly so concurrent agents audit public revisions rather than private state.",
    "Optimization converges through sparse graph fact propagation, witnessed equivalence retained in that graph, and demand profile costed realization extraction rather than a fixed pass kingdom.",
    "A green test is not enough.",
    "A change is complete only when syntax, rendering, identity, ownership, effects, obligations, provenance, realization, differential and witnesses ALL agree.",
}

# ═══ §34 · the final architectural invariant ═══════════════════════════════

substrate = law{
    id    = "law.substrate"
    kind  = .invariant
    holds = .one
    binds = {
        "one representation layer",
        "independent lawsets",
        "equivalence by proof",
        "realization is its own layer",
    }
}

# ═══ §35 · topology ════════════════════════════════════════════════════════

layers = {
    "constitution", "grammar", "context", "tooling", "frontends",
    "graph", "specialized", "realization", "dnir", "backend",
}

# ═══ §36 · THE COMPILER'S OWN ARCHITECTURE IS IDOL-SHAPED ══════════════════
#
# The compiler should not merely COMPILE Idol this way. A host helper that
# owns a recoverable semantic distinction is evidence that the architecture
# has not internalized its own language.

archrelation = law{
    id    = "law.arch.relation"
    kind  = .invariant
    holds = .relation
    binds = {
        "a distinction recoverable from OPERANDS, LEVELS, HOMES, LAWSETS or CONTEXT",
        "may not be a separate host function name, enum case, registry or manager",
        "canonical is the ordinary relation specialized by its operands",
        "a bootstrap host function may implement it PHYSICALLY, never as authority",
    }
    fails = "addnode addedge addchild registertype registerprotocol emitwitness"
}

# These are not unrelated functions sharing a prefix. They are ONE open
# relation successively specialized: `add`, then the LEVEL, then the subject,
# then the value. Where the operand already names its kind, `g:add(n)` resolves
# through the descriptor of `n` and the level is unnecessary.
add.canon = { "g:add(n)", "g:add(mode)(n)" }   # level ONLY where mode is a real choice

factone = law{
    id    = "law.fact.one"
    kind  = .invariant
    holds = .one
    binds = {
        "two properties projecting one relationship may NOT be written independently",
        "scope and contains",
        "a reverse index and its forward edge",
        "ownership and release obligations",
        "origin and provenance references",
    }
    fails = "addChild writes n.scope = parent AND addEdge(.contains) — two mutations of one fact"
}

# `parent contains child` is the fact; child scope, parent children and
# ancestry are projections. A host helper may project that fact but does not
# create another semantic operation.
contains.canon = "parent:add(contains)(child)"

hostprojection = law{
    id    = "law.host.projection"
    kind  = .invariant
    holds = .projection
    binds = {
        "the bootstrap may look unlike Idol ONLY where the host requires it",
        "every such api NAMES the Idol relation it projects",
        "it carries authority false, its semantic owner, and its deletion gate",
    }
    fails = "a host abstraction made permanent because it was convenient in zig"
}

# `add` is an ORDINARY OPEN RELATION, not privileged compiler magic. The
# compiler ships well-known specializations; a graph world may authorize more
# under coherence. A hidden switch over kinds would fix forever what adding can
# mean.
#
# Closed host enums are compact indexes only. They may not freeze the set of
# relations or revive retired source concepts as graph ontology.
kinds.role = .index          # bootstrap acceleration, never ontology
kinds.authority = false

# A graph VALUE is immutable current truth. Authority to produce the next
# incarnation is a WORLD, so arbitrary code cannot mutate compiler truth by
# accident. G0 --transaction--> G1, never mutation in place — which is what
# buys incrementality, undo, replay, speculation, parallel agents and stable
# incarnation identity.
edit.canon = { "edit = world(graph)(g)", "parent:add(child)" }  # graph is AUTHORITY, not cargo

# The irreducible primitives. Everything else — descriptor, binding, place,
# effect, capability, lifetime, origin, trust, provenance, representation,
# realization — is a semantic FAMILY OF FACTS, not a separate graph object
# class. The graph must not look like an OO graph database implemented in Zig;
# it is Idol's relation calculus made persistent.
primitives = { "value", "relation", "fact", "world", "demand", "witness" }

# TRUST IS A LEVEL ON A FACT, never a mechanism standing beside one. The line
# above already names trust a FAMILY OF FACTS; these are its levels, in the
# ordinary Idol sense that `read(number)` is a level — no new object class, no
# new surface.
#
# An assertion must be recorded, attributable and invalidatable. An unlabelled
# assumption is never allowed to masquerade as proof.
trust = @{
    inferred = .derived      # the compiler derived it from the graph
    proven   = .witness      # A5 satisfied; the witness is inspectable
    observed = .sample       # profile-time; carries its sample and its expiry
    asserted = .author       # the author knows and the compiler cannot check
    foreign  = .lawset       # a foreign lawset guarantees it, trust-tagged
    guarded  = .runtime      # true under a check, which carries its descent
}

# Weakest last, and an unlabelled claim takes the WEAKEST level rather than the
# strongest. A default of `proven` is how six mechanisms became invisible.
trust.order = { "proven", "inferred", "observed", "guarded", "foreign", "asserted" }
trust.rest = .asserted

facttrust = law{
    id    = "law.fact.trust"
    kind  = .invariant
    holds = .level
    binds = {
        "every fact carries exactly one trust level",
        "asserted is attributable — it names its author and what invalidates it",
        "asserted has a spelling and therefore a census",
        "a realization trusts the MINIMUM over the facts it consumes",
        "no mechanism may carry trust that the fact does not",
    }
    fails = "a flag wearing the face of a proof: no companion check, no witness, no census"
}

# ABSENCE IS A FACT, AND ITS SPELLING ALREADY EXISTS. A2 NNS, checked against
# this document rather than assumed: a false-valued field in a descriptor is
# how absence has always been written here — `syntax.anchor` denies a prefix,
# `syntax.name` denies underscore and uppercase, `syntax.block` denies the
# semicolon, `subject` denies a name, `kinds` denies authority, `std` denies
# ambient reach. Nothing is owed at the SURFACE, and a proposal for `noalias`,
# `restrict` or an unsafe block is the signal that the existing form has not
# been found yet.
#
# What IS owed is the ENUMERATION. Optimization runs on negative facts — no
# alias, no re-entry, no failure edge, no observer — and the compiler spells
# none of them, so a flag stands in for "no alias exists" and hopes. Each
# negative below is an ordinary fact taking an ordinary trust level, which is
# the whole point: `alias = false` proven by an ownership witness and the same
# words asserted by an author are different claims, and only the census can
# tell them apart.
#
# The negative ownership fact is `sharing`; a reserved grammar word does not
# become a new fact identity merely because a proposal used it.
absence = @{
    sharing  = .ownership    # no other live place reaches this one
    reentry  = .world        # no foreign frame re-enters during this scope
    failure  = .contract     # no failure edge leaves this realization
    observer = .region       # no other thread observes this place
    effect   = .purity       # no world is touched
}

negative = law{
    id    = "law.fact.negative"
    kind  = .invariant
    holds = .fact
    binds = {
        "absence is a fact carrying a trust level, never a mechanism",
        "the spelling is a false-valued field in a descriptor — no new surface",
        "a negative fact names the witness that would falsify it",
        "an unspellable absence becomes a flag, which is how this was found",
    }
    fails = "noalias, restrict or an unsafe block proposed as new grammar"
}

# dnir is THE CANONICAL REALIZED RELATION STREAM — not nodes plus an operation
# taxonomy. This SUPERSEDES the earlier "family of facets" reading in §28:
# naming sub-ir families recreates ir kingdoms under a friendlier word.
# The `add` identity stays traceable at every rung, which a conventional opcode
# enum cannot promise:
#
#     semantic     x --add--> y, z
#     realized     add(i64)(register, register)
#     dnir         %3 = add.i64 %1 %2
dnir.stream = true

# ═══ the final invariant ═══════════════════════════════════════════════════

final = law{
    id    = "law.final"
    kind  = .invariant
    holds = .one
    binds = { "no competing semantic systems", "all meaning reduces to here" }
    fails = "a second place where meaning is decided"
}

# ═══ §36 · what the twenty-point review added, and nothing more ════════════
#
# Five rulings the adjudication produced that no fact above carries yet. Added
# rather than restated: every other point of that review was already law here.

# SELF-ZERO deletes a PARAMETER, not a PROOF. Unspecified, the ambient subject
# becomes a second borrowing mechanism by accident — `capture = () .` and a
# nested `f = () () .` have to answer reference vs copy vs view vs lifetime
# extension, and each answer touches closures, regions, ownership, aliasing and
# ABI. A surface cheaper than the binding it abbreviates is how implicit
# borrowing gets in.
escape = law{
    id    = "law.escape"
    kind  = .invariant
    holds = .ordinary
    binds = {
        "the ambient subject is an ordinary semantic value",
        "capture and escape take the same lifetime proof as any other place",
        "no implicit borrow, no implicit copy, no lifetime extension",
    }
    fails = "a second borrowing mechanism nobody declared"
}

# The memory ladder's load-bearing undefined term. `cycle-possible` is doing
# enormous work: dynamic tables, closures capturing tables capturing closures,
# foreign objects, weak refs, finalizers, resurrection, cross-thread graphs,
# detection latency, behaviour under memory pressure, per-object metadata.
# "Never a tracing collector" is a LATENCY PROMISE, so it is measured, not
# asserted — and lua hosting generates pathological cyclic graphs routinely,
# which makes the supremacy story and the memory doctrine ONE experiment.
cycle = law{
    id    = "law.cycle"
    kind  = .objective
    holds = .measured
    binds = {
        "cycle-possible is undefined and must be defined before it is relied on",
        "the no-tracing promise ships with latency and throughput envelopes",
        "the lua corpus is the designated adversary",
    }
    fails = "a mechanism list standing in for a latency guarantee"
}

# The wasm engine is one very large file BECAUSE compiler defects punish
# decomposition. An agent reading it could conclude giant modules are idiomatic
# high-performance Idol. THEY ARE NOT. Every such workaround is a gap with a
# removal fixture, and the engine is the primary language-design fuzzer: each
# ugly thing it needs is either inherent wasm complexity or an Idol defect, and
# it gets adjudicated as exactly one of the two.
workaround = law{
    id    = "law.wasm.workaround"
    kind  = .invariant
    holds = .gap
    binds = {
        "every compiler-forced workaround is a gap with a removal fixture",
        "the workaround count publishes and descends to zero",
        "a compiler limitation never becomes runtime architecture",
        "agent context must say the monolith is a defect, not a pattern",
    }
    fails = "an agent learning bad Idol from the best evidence Idol has"
}

# Fastest AND smallest AND most featureful are conflicting dimensions, so the
# WHOLE matrix publishes, losses included. The external reference runtime is a
# moving oracle and ceiling, never an ancestor: its performance is ITS claim,
# and this repository may publish only its own last reproducible measurement.
matrix = @{
    speed   = { "startup", "cold", "warm", "jit latency", "steady", "memory", "branch", "call", "simd", "wasi" }
    size    = { "binary", "stripped", "loc", "rss", "instance", "jit metadata", "code cache" }
    feature = { "core spec", "wasi one", "wasi two", "simd", "threads", "atomics",
                "exceptions", "tail calls", "memory64", "multi memory", "reftypes",
                "component", "wit", "embedding", "aot", "jit arch" }
    quality = { "conformance", "differential", "fuzzing", "determinism", "diagnostics", "provenance", "sandbox" }
    proof   = { "percent canonical Idol", "foreign loc", "workarounds", "native realization", "boxing", "allocation", "binary to source" }
}

release = law{
    id    = "law.wasm.release"
    kind  = .invariant
    holds = .total
    binds = {
        "every axis of the matrix publishes, losses included",
        "the external reference runtime is an oracle, never an ancestor",
        "our claim cites our own reproducible measurement, never the oracle's",
        "every runtime answers identically before any speed number is compared",
    }
    fails = "a correctness-free speed win, which this repository already paid for once"
}

# Package composition is a semantic exercise, not package-system detail owed
# after implementation.
# And compatibility does not reduce to graph shape: complexity, effects,
# allocation, determinism, the error set, precision, ordering stability, a
# sealed descriptor opening, and timing observable through a foreign interface
# all move while the edge set stands still. A COMPUTED number that misses an
# effect growth is worse than a declared one, because it is trusted.
package = law{
    id    = "law.package"
    kind  = .invariant
    holds = .owed
    binds = {
        "relation and descriptor ownership",
        "extension authority and version coexistence",
        "dependency-private extensions and local overrides",
        "conflicting implication chains",
        "semver is computed from contracts and witnesses, never from edges",
        "the contract is surface, effects, failure set, complexity, determinism, capability",
    }
    fails = "opening a registry before coherence closes"
}

# ═══ §37 · ORIENTATION. Semantic expressibility is not canonicality. ═══════
#
# Idol source may be semantically correct and still noncanonical. Orientation,
# compaction and idiom are LAW, not taste — and the compiler, formatter,
# agents, std, the self-hosted compiler, Idol Wasm, the docs and every piece of
# architectural pseudocode obey the same one.

# Declare from the relation. Work from the value. The two faces are different
# questions: the declaration answers "what relation exists?", the invocation
# answers "what can this value do or become?". Never collapse them into one
# spelling. Operation-first at a CALL SITE is canonical only when the relation
# itself is the value being held or passed — `xs:map(to(str))`.
face = law{
    id    = "law.face.subject"
    kind  = .invariant
    holds = .subject
    binds = {
        "if the first semantic operand is present as a value, IT IS THE RECEIVER",
        "declare operation-first, execute subject-first",
        "operation-first at a call site only for a relation held as a value",
    }
    fails = "to(str)(n) where n is in hand — the algebra described, not the work done"
}

# A level names a REAL CHOICE, never a category already recoverable. If removing
# a level leaves exactly one valid edge, the canonicalizer removes it. `x:to(str)`
# cannot collapse — `str` is the demanded destination and is an independent
# decision. `g:add(node)(n)` DOES collapse, because `n` names its own descriptor.
necessity = law{
    id    = "law.level.necessity"
    kind  = .invariant
    holds = .necessary
    binds = {
        "a level exists only for a choice the operands cannot recover",
        "removal leaving exactly one valid edge means the level was a tag",
        "explicitness is not automatically clarity",
    }
    fails = "a redundant semantic level, which is restatement and violates hpls"
}

# THE OBJECT THAT STORES THE DATA IS NOT NECESSARILY THE SEMANTIC SUBJECT.
# A host structure owning the memory does not make it the receiver. If the
# operation resolves a subject, canonical orientation is `subject:resolve(rel)`
# with the graph ambient — NOT `graph:resolve(relation)(subject)` merely because
# the index physically lives in a graph object. This is the law that stops
# pseudo-OOP drift, and it is the twin of law.face.subject: together they
# forbid both `compiler:everything(...)` and `lower(target)(value)`.
physical = law{
    id    = "law.owner.physical"
    kind  = .invariant
    holds = .semantic
    binds = {
        "physical storage owner is not the semantic subject",
        "value:lower(target), never compiler:lower(value, target)",
        "fact:derive(rule), never graph:derive(fact, rule) where graph is storage",
        "host method ownership leaking into semantic design is a finding",
    }
    fails = "an api perfectly named and incorrectly oriented"
}

# Ambient is earned, not assumed: a thing is ambient ONLY where exactly one
# valid contextual value exists. Otherwise it DIAGNOSES. No hidden global
# compiler graph — the dynamic global environment is a lua fact, not an Idol one,
# and it may not return as architecture.
ambient = law{
    id    = "law.ambient.one"
    kind  = .invariant
    holds = .unique
    binds = {
        "graph and world are authority, not syntactic cargo",
        "ambient requires exactly one valid contextual value",
        "ambiguity diagnoses rather than picks",
    }
    fails = "shortening source by hiding an independent choice"
}

# Canonical source is a FIXED POINT, semantically and not merely by formatting.
# The canonicalizer performs semantic REPAIRS — `to(str)(n)` becomes `n:to(str)`
# — and emits a witness naming the relation, subject, level and the unchanged
# graph identity, which is what makes the rewrite justified rather than a
# reformat. Idiom is checked across every dimension at once, not one grep:
# face, level, home, bind, return, route, subject, case, chain, convert.
idiom = law{
    id    = "law.idiom.total"
    kind  = .invariant
    holds = .fixpoint
    binds = {
        "canon(source) == source for every committed canonical file",
        "the canonicalizer repairs orientation and witnesses the repair",
        "agents report idiom counts COMPUTED, never self-declared",
    }
    fails = "semantically valid source that teaches the wrong idiom"
}

# Relation metadata carries the canonical face, so rendering is DERIVED rather
# than left to agent taste. An argument list is not `{ a, b, c }` — each operand
# carries a ROLE, and orientation follows from the roles automatically. This is
# also what stops a bootstrap host signature from teaching the renderer that its
# first parameter is the receiver.
role = law{
    id    = "law.relation.role"
    kind  = .invariant
    holds = .roles
    binds = {
        "every operand carries a role: subject, level, operand, world, demand",
        "canonical rendering derives from roles, not from source order",
        "a host signature declares which argument is the subject, and it need not be the first",
    }
    fails = "a generator emitting to(str)(x) because it had a signature and no subject role"
}

# DOCUMENTATION IS CORPUS. A code block in a normative document is a canonical
# corpus member and compiles under the same gate, because an architect writing
# `to(str)(x)` in a design note teaches every later agent the wrong idiom. A
# block is Idol, dnir, foreign or CONCEPTUAL — and if an idea cannot yet be
# expressed canonically it is marked conceptual and filed as a gap. Never invent
# near-Idol. Prose is lintable too: say "add fact" and "resolve relation", never
# "call addnode" or "the registry owns".
doc = law{
    id    = "law.doc.corpus"
    kind  = .invariant
    holds = .canonical
    binds = {
        "normative code blocks obey every canonical gate",
        "a block is Idol dnir foreign or conceptual — never rough pseudocode",
        "architecture prose uses Idol concepts so its wording is lintable",
    }
    fails = "a specification teaching an idiom its own gate would reject"
}

docteaching = law{
    id    = "law.doc.teaching"
    kind  = .invariant
    holds = .canonical
    binds = {
        "canonical documentation and normative examples must pass SUBJECT-ONE and OPERATION-ONE",
        "do not teach home package table class constructor or namespace receiver patterns unless the left-hand value is proven an ordinary semantic subject not organizational home",
        "do not use new in examples unless new is an admitted irreducible relation",
        "parser:parse(source) lexer:scan(source) and http.client:new() are anti-patterns in orientation unless explicitly decomposed to subject relation and admitted operands",
    }
    fails = "normative documentation that trains module api or constructor ontology"
}

sourcenotproof = law{
    id    = "law.source.not.proof"
    kind  = .invariant
    holds = .absolute
    binds = {
        "current repository source is not proof of canonical Idol merely because it is id or builds",
        "resolve every touched construct against current C0 plus current owner directives",
        "if shortest uniquely resolving form semantic fact ownership world authority relation identity or demand driven realization is not yet implemented classify existing spelling as bootstrap debt not the new pattern",
        "current fixtures disagreeing with C0 are wrong — never preserve fixture behavior against constitution",
        "agent retrieval must exclude foreign corpus unless explicitly requested — corpus role must be machine visible",
    }
    fails = "learning from bootstrap debt compatibility fixtures or stale canonicalization as if it were current law"
}

repairclass = law{
    id    = "law.repair.class"
    kind  = .protocol
    holds = .absolute
    binds = {
        "no agent may fix a surface specimen without proving the semantic class which produced it is now impossible to reintroduce under another spelling path helper namespace wrapper protocol name fallback or realization",
        "every error class repair adds positive and negative controls and derives gate checks from authoritative facts where possible",
    }
    fails = "specimen-only repair that leaves the producing class reintroducible under another face"
}

projectionpack = law{
    id    = "law.projection.pack"
    kind  = .invariant
    holds = .firstclass
    binds = {
        "every relation application carries projection pack subject operand pack and result pack as distinct first-class roles in resolver graph dnir and tooling",
        "read(number) = (lx, b) declares relation read projection pack number subject lx operand pack b — not a curry stage",
        "to(str) = (value) declares relation to projection pack str subject value — projection parameters are relation parameters not callable types",
        "projection pack facts must survive elision in source — omitted syntax does not erase projection pack in the graph",
        "must land before generic currying work or nested-call semantics that conflate projection with returned-callable application",
    }
    fails = "projection pack treated as curry operand intermediate callable or missing from graph facts"
}

identityprojection = law{
    id    = "law.identity.projection"
    kind  = .protocol
    holds = .current
    binds = {
        "current language identity is Idol idol only — per law.zero.history git is the sole historical archive",
        "current agent projection documents must not use retired project or language names as live identity",
        "gate target current projection count of retired names as identity outside foreign provenance equals zero",
        "retired names are not preserved in the active tree",
    }
    fails = "retired name appearing as live identity in agent projections or active tree"
}

# ═══ §37 · DISTRIBUTION IS NOT SEMANTICS (the stdlib reconciliation) ════════
#
# THE DEEPEST RULE, and everything below is a consequence:
#
#   Distribution boundaries must never become semantic boundaries unless the
#   semantics genuinely require it.
#
# Four distinctions follow:
#
#   1. A function does not become conceptually different because it arrived
#      from another package.
#   2. A standard operation does not need a package root because of where its
#      implementation file lives.
#   3. A package namespace is not a substitute for relation identity.
#   4. IMPORTING CODE IS NOT GRANTING CAPABILITY.

distribution = law{
    id    = "law.distribution"
    kind  = .invariant
    holds = .semantic
    binds = {
        "a distribution boundary is not a semantic boundary",
        "provenance is discoverable, never restated at every call",
        "package origin disambiguates candidate provenance while exact relation law and world facts decide meaning",
    }
    fails = "std.string.split(s, x) where s:split(x) names the same edge"
}

# The orthogonal facts that a conventional standard-library namespace blurs.
#
#   meaning    ordinary Idol descriptors, relations, values and laws —
#              relation, table, callable, failure, basic numerics and
#              sequences, reflection. Always present. No import, no prefix.
#   vocabulary standardized relation and descriptor IDENTITIES that are NOT
#              language axioms — sort, encode, json, time, format. Standard
#              MEANING; realization is replaceable.
#   package    a separately versioned GRAPH FRAGMENT contributing descriptors,
#              relations, implementations, worlds, laws, realizations. It does
#              NOT contribute a namespace.
#   world      AUTHORITY to perform effects, orthogonal to distribution.
distribution.projects = { "relation", "descriptor", "law", "world", "implementation", "realization", "origin", "trust" }

# Availability and authority remain orthogonal. A relation may be known while
# its required world refuses the application.
authority.grant = law{
    id    = "law.authority.grant"
    kind  = .invariant
    holds = .orthogonal
    binds = {
        "availability and authority are DIFFERENT relations",
        "a standard operation may resolve while the world refuses it",
        "installing a package grants NO capability",
    }
    fails = "import as permission"
}

# ═══ §37b · layout resolution (GAP-153) ═════════════════════════════════════
#
# Native dependency is NOT req, require, import, module, package, namespace,
# include, Lua require, or any newly invented loader or admission edge. Files
# contribute ordinary tables; directories may contribute enclosing homes; the
# reference is the dependency edge. Worlds grant authority; possession of a
# table never implies possession of a world.

layout = law{
    id    = "law.layout"
    kind  = .invariant
    holds = .topology
    binds = {
        "same-directory sibling references resolve without dependency syntax",
        "cross-home visibility uses anchored root tables supplied by build or project configuration rather than per-file loader declarations",
        "scope and enclosing home topology decide referability",
        "req and require remain compatibility provenance only and ratchet to zero in new canonical source",
        "reachability is scope and home projection not use using import inject admit open include or any admission syntax",
        "selective visibility is scope construction at owner boundaries not source ceremony",
        "native resolution never lowers through Lua require package traversal or runtime module tables",
        "visibility of a table never grants the worlds its relations may require",
        "world requirements remain ordinary application facts resolved by existing world law",
    }
    fails = "dependency possession treated as authority possession"
}

projection = law{
    id    = "law.projection"
    kind  = .invariant
    holds = .lexical
    binds = {
        "projection is ordinary table home and binding reachability not a module mechanism",
        "bare selective cross and algebraic projection preserve one semantic identity with distinct witnesses",
        "no native operation means add x to the current environment for visibility alone",
        "use using import inject admit open include bring provide register install mount and expose are not native admission faces",
        "after resolution projection facts are binding home relation world anchor and witness facts only",
        "projection has zero independent downstream ontology beyond admitted graph facts",
    }
    fails = "using edge use face module open object runtime namespace merge loader registry or hidden authority"
}

layout.gate = law{
    id    = "law.gate.layout"
    kind  = .protocol
    holds = .ratchet
    binds = {
        "new canonical use using import inject admit open include bring provide register install mount and expose admission sites are zero",
        "new canonical req require and import sites are zero",
        "new req-specific compiler authority is zero",
        "native dependency decisions keyed on req spelling are zero",
        "nearest-pattern-zero blocks filling a vacuum with req or Lua loader idioms",
        "docs/spec/source.md is the operative projection scope package and capability closure",
    }
    fails = "a new canonical line that reintroduces loader syntax module registry import-as-permission or admission-as-visibility as native architecture"
}

# ═══ §37c · host boundary (GAP-154) ════════════════════════════════════════
#
# Idol source sees semantic values. Host OS APIs are ingress/egress realization
# only. Renaming os.args → core.args without decomposition is forbidden.

host = law{
    id    = "law.host"
    kind  = .invariant
    holds = .boundary
    binds = {
        "Idol source does not call host operating system APIs as semantics",
        "args and env are ordinary tables under os world accessed as os.args[n] and os.env[k]",
        "environment is not a thing",
        "io read and write use io:read and io:write not io.read or io.write",
        "environment observation requires environment value facts and compatible world authority",
        "process execution requires structured command value and process world not popen or opaque shell strings",
        "endpoints are input output error values whose physical realization is embedding selected",
        "build world and program world remain orthogonal",
        "backend and target selection are realization facts not canonical source switches",
        "host APIs may exist only at classified bootstrap ingress or egress adapters with deletion gates",
    }
    fails = "host namespace authority in native semantic middle"
}

shell = law{
    id    = "law.shell.interpretation"
    kind  = .invariant
    holds = .law
    binds = {
        "shell is command interpretation law not a source law grammar home world authority mode bit keyword or global boolean",
        "a launcher may independently supply exact command provider reach process filesystem and environment authority and endpoints according to policy",
        "shell interpretation grants none of those facts",
        "bare external command resolution requires an exact reached command provider and execution independently requires process authority",
        "Idol lexical and ordinary home bindings resolve before command provider projection",
        "shell interpretation never changes source law grammar parser AST or compiler semantics",
        "raw shell text is an explicit opaque boundary and never fallback for an unresolved structured command",
    }
    fails = "shell interpretation selecting grammar granting authority constructing a privileged home or making shell string execution or popen a native relation"
}

core = law{
    id    = "law.core.vocabulary"
    kind  = .invariant
    holds = .vocabulary
    binds = {
        "core names canonical vocabulary authority not a runtime traversable namespace",
        "no runtime std core or prelude table is required for canonical resolution",
        "canonical relations are directly reachable from root projection",
    }
    fails = "core.len std table or prelude namespace as semantic authority"
}

host.gate = law{
    id    = "law.gate.host"
    kind  = .protocol
    holds = .ratchet
    binds = {
        "new canonical os.args os.getenv popen io.popen os.execute host argv and host getenv lookup are zero",
        "new canonical generic io proc ir process runtime system std core and environment namespace authority are zero",
        "no std namespace table prelude or spelling anywhere in Idol source",
        "std proc and ir are not things — vocabulary is layout and world projection only",
        "new shell string execution and backend string semantic switches in canonical source are zero",
        "docs/spec/host.md is the operative host boundary projection",
        "tools/node/dev/census/host classifies existing debt FOREIGN BOOTSTRAP MIGRATION VIOLATION BLOCKED",
        "lexical host detectors in idiomgate are temporary migration firewalls until graph enforcement",
    }
    fails = "new host API debt or host wrapper without semantic boundary and deletion gate"
}

# MEANING is standard and non-replaceable; REALIZATION is replaceable. A
# package may contribute a better `sort` realization — insertion, introsort,
# radix, simd, gpu — and the call stays `xs:sort()`. It may NOT redefine what
# standard `sort`, `eq`, `hash` or `to` MEAN, or ordinary code would change
# behaviour on installation.
vocabulary = law{
    id    = "law.vocabulary"
    kind  = .invariant
    holds = .meaning
    binds = {
        "packages contribute witnessed implementation candidates for exact relations and laws",
        "packages may not redefine standard MEANING",
        "one call site, many realizations, selected by demand and cost",
    }
    fails = "behaviour changing because a dependency was installed"
}

# REACHABILITY FOR LINKING AND REACHABILITY FOR RESOLUTION ARE DIFFERENT
# RELATIONS. `app -> orm -> driver` must not hand the app every edge the driver
# contributes; `orm` decides what it re-exports. Without this, a project with
# 400 dependencies has an unreasonable resolution universe and composition
# becomes spooky.
reach = law{
    id    = "law.reach"
    kind  = .invariant
    holds = .explicit
    binds = {
        "the transitive dependency graph is NOT the resolution universe",
        "a package chooses what it re-exports",
        "a private dependency is topology, not a naming trick",
    }
    fails = "a transitive dependency's extensions becoming candidate edges"
}

# Coherence under composition, which is the real pre-registry problem: two
# fragments may each imply a different edge for the same identity. "Latest
# import wins" is DENIED — it destroys semantic locality.
coherence.rule = "a package may freely define relations over identities it OWNS. extending a relation where it owns NEITHER side needs explicit extension authority or a local scope."

# Packages advertise PROVEN FACTS, not only apis — allocation-free, deterministic,
# no-network, native on a target, thread-safe, no-failure under a descriptor.
# Downstream optimization consumes them, which makes a package a fragment
# carrying realization knowledge rather than only code you can call.
package.publishes = { "origin", "version", "exports", "requires", "guarantees", "implementations", "provenance" }

# Build, dev, runtime and plugin dependencies are ONE system. The STAGE at
# which a fragment is demanded decides when it participates; separate
# dependency families are a mechanism duplicated four times.
depends = law{
    id    = "law.depends"
    kind  = .invariant
    holds = .stage
    fails = "build-dependency, dev-dependency and proc-macro as separate families"
}

# Feature flags are DEMAND, not package metadata booleans. If nothing demands
# tls, its fragment and realization disappear. A package with 50,000 semantic
# facts may contribute 17 machine realizations to a given program — which is
# what makes "more featureful AND smaller binary" expressible rather than
# contradictory.
features = law{
    id    = "law.features"
    kind  = .invariant
    holds = .demand
    fails = "a feature-configuration mini-language beside the language"
}

# ═══ §38 · THE PERFORMANCE CONSTITUTION ════════════════════════════════════
#
# NORTH STAR: Idol source states MAXIMUM SEMANTICS; the compiler emits MINIMUM
# MACHINERY.
#
# Performance, binary size, compile time, memory and specialization cost are
# REALIZATION OBJECTIVES, not benchmarks run afterwards. Every layer preserves
# enough semantic information for the compiler to optimize them JOINTLY rather
# than locally.

perf.demand = law{
    id    = "law.perf.demand"
    kind  = .invariant
    holds = .consumed
    binds = {
        "a descriptor, pack slot, iterator, error payload, closure environment,",
        "schema projection, package fragment, wasm feature, debug record,",
        "capability or intermediate collection EXISTS only if something consumes it",
    }
    fails = "materializing what nothing demanded"
}

perf.late = law{
    id    = "law.perf.late"
    kind  = .invariant
    holds = .late
    binds = {
        "never choose representation before facts require it",
        "descriptor identity, range, shape, lifetime, aliasing, target,",
        "alignment, call shape, world and demand decide it — not the parser",
    }
    fails = "boxed because the front end could not yet know better"
}

# Every dynamic mechanism carries the SAME ladder and an exact descent.
# Relation lookup, tables, closures, failures, packages, worlds, foreign
# values, wasm dispatch, lua metatables — one ladder, not one per subsystem.
perf.ladder = {
    "dynamic", "observed", "guarded", "sealed", "direct", "erased",
}

# Budgeted GLOBALLY, never greedily. A specialization justifies its code
# growth or it is refused, and `why(skip)` answers.
perf.worth = {
    "hotness", "expected cycles saved", "guard cost", "compile cost",
    "icache pressure", "binary growth", "duplication", "deopt probability",
}

# THE INVERSE OPERATION, and the tree has no mechanism for it. Without
# re-generalization the compiler can derive billions of variants and has no way
# to recover compactness.
perf.merge = law{
    id    = "law.perf.merge"
    kind  = .invariant
    holds = .bidirectional
    binds = {
        "identical or near-identical specializations MERGE",
        "cold paths differing under matching hot paths OUTLINE",
        "realizations sharing machine structure DEDUPLICATE",
        "speed and size are optimized together, never speed alone",
    }
}

perf.explain = law{
    id    = "law.perf.explain"
    kind  = .invariant
    holds = .why
    binds = {
        "why(realize) why(box) why(alloc) why(dispatch) why(inline)",
        "all derive from the ONE fact graph",
        "a retained cost the compiler cannot explain IS A GAP",
    }
}

# Three reusable engines replace a conventional procession of semantic passes.
# Their physical indexes are disposable projections; ids, facts, relations,
# witnesses and provenance remain the authority.
perf.propagate = law{
    id    = "law.perf.propagate"
    kind  = .invariant
    holds = .sparse
    binds = {
        "one dependency worklist propagates monotone graph facts and each fact family supplies its lattice rather than a pass local semantic store",
        "constant descriptor range case world effect stage shape escape alias demand profile target and realization legality update only affected ids",
        "strongly connected components condense recursive dependencies while dominators postdominators loop forests and bitsets remain derived control indexes",
        "memory and observable effects use graph owned version and dependency facts so repeated alias walks do not become another memory semantic universe",
        "exact dependencies drive invalidation reuse and agent tooling and unchanged facts require no repeated whole graph scan",
    }
    fails = "one full compiler pass and one shadow registry for every fact family"
}

perf.equivalence = law{
    id    = "law.perf.equivalence"
    kind  = .invariant
    holds = .witnessed
    binds = {
        "lawful equivalent expressions representations algorithms foreign implementations and machine forms remain alternatives attached to the same semantic graph",
        "equivalence persists across compiler levels where its expected reuse exceeds its retained graph and compiler cost",
        "saturation is bounded by demand profile expected machine gain reuse confidence compile work peak state and graph growth",
        "every admitted equivalence retains its law witness provenance and exact input output ids and extraction retains the chosen causal path",
        "an egraph index hash fingerprint or canonical form may accelerate candidates but never becomes a second semantic ir or selects meaning",
    }
    fails = "destructive rewriting that discards lawful choices or an unbounded second equality graph"
}

perf.summary = law{
    id    = "law.perf.summary"
    kind  = .invariant
    holds = .projection
    binds = {
        "modules and foreign units project compact exported descriptor relation world effect call constant escape shape cost and provenance facts",
        "global reasoning consumes summaries first and imports a full subgraph only when demand and expected value justify it",
        "summary indexes preserve exact owner correspondence and incremental invalidation and never mint module local semantic identity",
        "whole program knowledge does not require whole program materialization",
    }
    fails = "loading every module graph to rediscover a fact already present in an exact summary"
}

perf.extract = law{
    id    = "law.perf.extract"
    kind  = .invariant
    holds = .budgeted
    binds = {
        "optimization effort is assigned per semantic region from expected executions improvable cost confidence reuse and compile budget rather than one global optimization level",
        "cold and simple regions use cheap linear extraction while valuable regions may demand bounded equivalence search verified synthesis or integrated allocation and scheduling",
        "block and function layout cold splitting outlining identical folding register allocation scheduling and instruction selection consume shared profile demand and cost facts",
        "discovered peepholes and superoptimizations enter reuse only with an exact equivalence witness over their demanded laws",
        "native and wasm share propagation equivalence demand profile and extraction machinery while retaining their distinct observable target laws",
    }
    fails = "uniformly expensive optimization or a backend heuristic kingdom detached from graph facts"
}

# THE SIZE INVARIANT, and it is what makes "more featureful AND smaller" a
# statement rather than a contradiction:
#
#   FEATUREFULNESS is a property of the SEMANTIC GRAPH.
#   BINARY SIZE is a property of DEMANDED REALIZATION.
size.invariant = true

# Every emitted byte range is attributable to a semantic demand — the relation,
# what demanded it, its realization, and why it was retained. That is what
# `idol why size` reads, and it reports semantic causes rather than symbols.
size.ledger = { "relation", "demanded by", "realization", "retained because" }

# Multi-objective cost. The build's world chooses the objective; these are
# ordinary descriptors, NOT compiler-mode kingdoms, so one deployment may
# optimize a hot kernel for speed and everything else for size.
cost.facts = {
    "cycles", "bytes", "compile", "peak", "allocations",
    "misses", "footprint", "energy", "variance",
}
cost.objectives = { "speed", "size", "startup", "latency", "energy", "balanced" }

# These ratios are definitions. Current values belong to revision-bound
# evidence, never to the constitution.
perf.ratios = {
    "retention: realized facts / reachable semantic facts",
    "erasure: constructs erased / constructs used",
    "efficiency: measured speedup / added code bytes",
    "compression: semantic values / physical runtime objects",
    "density: demanded relations / binary kb",
    "reuse: realized capabilities / distinct mechanisms",
}

# ═══ §39 · THE PRIME DIRECTIVE (what every agent receives first) ════════════
#
# You are MODIFYING Idol. You are not designing a conventional compiler in Zig
# and you are not inventing language architecture. The job is to move the
# repository MONOTONICALLY toward 100% self-hosted canonical Idol with zero
# competing semantic mechanisms.
#
# THE CORE QUESTION, asked before adding anything:
#
#   Is this an irreducible NEW concept, or is it already a value, relation,
#   fact, world, demand, witness or realization — specialized by operands and
#   context?
#
# ASSUME THE LATTER UNTIL PROVEN OTHERWISE. Prefer one relation with many
# specializations over many functions, enums, registries, managers and systems.

directive = law{
    id    = "law.directive"
    kind  = .invariant
    holds = .monotone
    binds = {
        "the constitution is current law; repair the implementation, never the law",
        "history, archived code, old apis and compatibility syntax are NOT precedent",
        "if the constitution cannot express the task, RECORD A GAP — do not invent",
        "spelling changes do not fix architectural duplication",
    }
}

# For every semantic operation, name all eight. An operation that cannot name
# them is not understood well enough to land.
operation.names = {
    "canonical relation", "semantic subject", "semantic owner", "fact",
    "lawset", "witness", "physical projection", "deletion gate",
}

# What an agent must be able to show is ZERO before completion. A nonzero entry
# is not a warning; it needs a constitutional amendment.
delta.zero = {
    "semantic owners added", "competing registries added", "semantic enums added",
    "syntax added", "keywords or operators added", "string-based semantic cases",
    "unclassified semantic apis", "new silent fallbacks",
}

# THE FINAL TEST, and it is the strongest rule in this file because it is the
# only one that closes a class rather than an instance:
#
#   Could another competent agent look at this change and reasonably implement
#   the SAME semantic idea using another registry, enum, helper family, api
#   orientation, syntax or subsystem?
#
#   IF YES, DO NOT STOP. Find and enforce the missing constitutional invariant
#   so there is only ONE reasonable Idol-native direction.
#
# Restated as the rule it generalizes: any architectural mistake an agent can
# make TWICE is a missing machine-enforced invariant. The constitution evolves
# primarily by converting recurring review findings into executable
# impossibility.
final.test = law{
    id    = "law.final.test"
    kind  = .invariant
    holds = .impossible
    binds = {
        "a mistake reachable twice is a missing invariant, not a missing prompt",
        "close the CLASS, never the instance",
    }
    fails = "a stronger prompt where a gate was owed"
}

# THE OBJECTIVE, stated so it is not mistaken for code quality: not merely code
# that works, but a repository in which non-Idol architecture becomes
# IMPOSSIBLE TO WRITE, IMPOSSIBLE TO TEACH, IMPOSSIBLE TO MERGE, and
# UNNECESSARY TO REPRESENT.
objective = law{
    id    = "law.objective"
    kind  = .objective
    holds = .unrepresentable
    binds = {
        "impossible to write", "impossible to teach",
        "impossible to merge", "unnecessary to represent",
    }
}

# A lexical host scan can ratchet spellings but cannot close an architectural
# class. Different names can own the same shadow meaning, while a correctly
# named physical helper can still orient the semantic subject incorrectly.
#
# So the scan MEASURES the habit and does not CLOSE it. The invariant it is
# missing is declarative rather than lexical: every function that mutates or
# resolves semantic state DECLARES the relation it projects, and an unannotated
# semantic mutation is the finding. Then the question stops being "what is it
# called" and becomes "how many physical apis project `add`, and why".
scan.gap = "lexical rows cannot close an architectural class — projects= is owed"

# ═══ §40 · SYNTAX SUBTRACTION — leading dot is retirement debt ══════════════
#
# This law supersedes every earlier leading-dot reading.
#
# CANONICAL `.` HAS ONE MEANING: explicit postfix projection from an
# ALREADY-WRITTEN subject — `x.y`. Every other leading-dot form is retirement
# debt, and is not preserved merely because the parser accepts it.
#
# THE TEST, asked of every syntactic form and not only this one:
#
#   Does this token encode semantic information ALREADY UNIQUELY RECOVERABLE
#   from subject, expected descriptor, demand, relation identity or context?
#
#   If yes it is canonicalization debt. AND THE REPAIR IS NOT NEW SYNTAX.
#
# THE TARGET IS NOT FEWER CHARACTERS. It is FEWER SYNTACTIC SEMANTIC
# MECHANISMS. A shorter spelling that adds a mechanism is a loss.

subtract = law{
    id    = "law.subtract"
    kind  = .invariant
    holds = .postfix
    binds = {
        "canonical `.` is postfix projection from a written subject",
        "recoverable information is debt, not economy",
        "retired syntax is never replaced by new syntax",
    }
    fails = "preserving a form because the parser happens to accept it"
}

# FIVE OBLIGATIONS BEFORE ANY DELETION. Retirement is proven, not asserted.
#
# Replacement parsing is insufficient. The replacement must resolve, lower and
# preserve behavior by value before a source face is deleted.
subtract.proves = {
    "the replacement RESOLVES AND LOWERS, proven BY VALUE, on both backends",
    "every semantic role has a strictly SIMPLER EXISTING spelling",
    "resolution is deterministic",
    "canonical lowering is NO WORSE",
    "the canonicalizer migrates it mechanically",
    "lua and other foreign source laws are unaffected",
}

# SELF-ZERO requires implicit-subject fields to use ordinary bare identities.
# Leading-dot fields and bare dot are retirement debt; leading colon remains
# the admitted ambient-subject application face.
#
#   scale = (k) { x * k, y * k }
#
# Which collides with a local binding named `x`, so obligation 2 —
# DETERMINISTIC RESOLUTION — is the one that decides this form, and it is not
# yet proven either way. This is recorded as OPEN rather than resolved.
subtract.blocked = "self-zero's implicit subject: bare identity vs local binding"
subtract.free = { "case in construction", "argument lens", "inferred case" }

# ═══ §41 · SELF-ZERO, REDEFINED — the receiver disappears, not into dots ════
#
# This resolves the open SELF-ZERO question and supersedes every punctuation-
# receiver definition.
#
# THE MISTAKE THE OLD DEFINITION MADE: it defined SELF-ZERO as `.x` / `.y` /
# `:length()`, which makes `.` and `:` CARRY THE BURDEN OF SELF. The receiver
# did not disappear; it was respelled as punctuation.
#
# THE CORRECTED DEFINITION:
#
#   A subject-bearing scope contributes its subject's visible relations and
#   projections to ORDINARY NAME RESOLUTION. The subject has no user-visible
#   binding name.
#
# So this is the SELF-ZERO form:
#
#   point:scale = (k) { x * k, y * k }
#
# and this is not:
#
#   point:scale = (k) { .x * k, .y * k }

selfzero = law{
    id    = "law.selfzero"
    kind  = .invariant
    holds = .resolution
    binds = {
        "subject projections participate in BARE-NAME resolution",
        "there is no .field shorthand and no self",
        "the receiver disappears from source, it is not respelled as punctuation",
    }
    fails = "defining the implicit subject as a punctuation prefix"
}

# THE COMPLETE RECEIVER MODEL. Seven rows, and every one of them earns its
# spelling:
#
#   explicit field            p.x
#   IMPLICIT field            x
#   explicit relation         p:length()
#   IMPLICIT relation         :length()
#   explicit whole subject    p
#   passed field projection   map(name)
#   passed relation           map(to(str))
receiver.model = 7

# `:` IS KEPT BECAUSE IT CONTRIBUTES INFORMATION. `normalize()` could be an
# ordinary local or world function; `:normalize()` unambiguously says "invoke
# the normalize relation on the ambient subject". That earns its syntax.
#
punctuation = law{
    id    = "law.subject.punctuation"
    kind  = .invariant
    holds = .necessary
    binds = {
        "omitting the subject must not require restating it as punctuation",
        "leading colon marks ambient subject application while dot remains only statically named projection",
        "no bare punctuation token stands for the ambient subject value",
    }
}

# THE ONE RULE THAT REPLACES THREE PUNCTUATION ENCODINGS. `.case`, `.field`
# and `.lens` were three spellings for three contexts the graph already
# distinguishes:
#
#   BARE IDENTITY + SEMANTIC DEMAND + AVAILABLE HOMES -> ONE IDENTITY, OR A
#   DIAGNOSTIC.
#
#   law{ kind = invariant }     `invariant` resolves: kind demands a case
#   point:scale = (k) x * k     `x` resolves: the subject has one projection x
#   users:map(name)             `name` resolves: map demands a callable
resolution.rule = "bare identity plus demand plus homes yields one identity or a diagnostic"

# SHADOWING IS DIAGNOSED, NEVER SILENTLY RESOLVED. "Locals win" is DENIED:
# adding `x = 3` would silently change every later `x` from a subject
# projection to a local binding, which makes source meaning depend on a
# declaration the reader may not have reached yet.
shadow = law{
    id    = "law.shadow"
    kind  = .invariant
    holds = .diagnose
    binds = {
        "a lexical binding may NOT silently shadow an ambient-subject identity",
        "referenced in the same scope",
        "a collision that would depend on subtle precedence DIAGNOSES",
    }
    fails = "locals win, and every later x quietly changes meaning"
}

# Leading-dot fields retire to bare identity once deterministic resolution is
# implemented. Bare dot has no canonical role. Leading colon remains because
# it contributes the ambient-subject application fact.
subtract.resolved = "leading dot retires; bare dot is invalid; leading colon remains"

# ═══ §42 · SURFACE SUBTRACTION — the rules that keep it from becoming golf ══
#
# Canonical Idol encodes ONLY distinctions the compiler cannot
# recover from the explicit subject, the ambient subject, expected descriptor,
# relation identity, operand descriptors, demand, lexical scope, or
# world/lawset context. Syntax restating recoverable information is debt.
#
# ULTIMATE RULE: syntax exists to RESOLVE UNCERTAINTY, not to RESTATE
# CERTAINTY. The shortest form is not the one with the fewest characters — it
# is the one containing the FEWEST UNNECESSARY SEMANTIC DECISIONS.

minimum = law{
    id    = "law.minimum"
    kind  = .invariant
    holds = .irreducible
    binds = {
        "canonical source writes IRREDUCIBLE information",
        "plus what is deliberately retained for human semantic naming",
        "canonicalization is not minification",
    }
}

# THE CANONICAL-PERFORMANCE LAW.
# A canonical rewrite is INVALID if it lowers worse than the form it replaces
# without a semantic reason. Canonicality and performance CANNOT DISAGREE —
# and where they do, COMPILER CAPABILITY IS THE GAP, never the corpus.
#
# A canonical face that does not yet resolve or lower while a noncanonical
# fallback does is compiler-capability debt, not permission to canonize the
# fallback.
#
# In both the corpus looked like bad taste and was authors writing what
# compiles. This law inverts the repair order permanently: FIX THE CAPABILITY,
# THEN ENFORCE THE ORIENTATION.
canonperf = law{
    id    = "law.canon.performance"
    kind  = .invariant
    holds = .equal
    binds = {
        "canonical may never lower worse than the form it replaces",
        "if canonicality and performance disagree, the COMPILER is the gap",
        "track allocations, boxing, dispatch, lookup, copies, size, compile, fallback",
    }
    fails = "a law prescribing a spelling the compiler cannot produce"
}

# RESOLUTION ENTROPY CEILING. Every omitted token transfers work to semantic
# resolution, and that cost is MEASURED, not assumed away. A compaction is
# accepted only when resolution stays unique, diagnostics stay good, local
# reasoning stays predictable, and AGENT GENERATION ACCURACY DOES NOT REGRESS.
# If removing syntax causes a large nonlocal search, THE SYNTAX WAS EARNING ITS
# KEEP.
entropy.resolution = law{
    id    = "law.entropy"
    kind  = .invariant
    holds = .bounded
    binds = { "hpls includes compaction WITHOUT semantic-distance explosion" }
}

# SEMANTIC LOCALITY. Bare-identity resolution draws from a PREDICTABLE LOCAL
# LATTICE and nothing wider. Transitive dependency existence does NOT make an
# identity visible — no global graph soup.
locality.lattice = {
    "lexical", "ambient subject", "expected descriptor",
    "exact visible semantic identities", "admitted vocabulary",
}

# WHAT IS NOT COMPACTED, stated so subtraction does not become point-free code.
# Idol does not delete syntax merely because the graph can technically infer
# meaning. These carry irreducible or high-value HUMAN information:
keep = {
    "x.y", "x:f()", ":f() under self-zero",
    "if", "while", "for x in xs", "break", "continue",
    "arithmetic and comparison operator faces",
    "() ordinary application", "{} structured packs and descriptor homes",
    ". named projection", ": descriptor, subject and home roles",
    "ordinary interpolated strings", "offside layout",
}

# THE THREE TIERS. Retirement is not one list — it is a judgement per form.
retire = {
    "leading .field implicit projection", "leading .case", "leading .field lens",
    ".field constructor designation", "tail `return x`",
    "operation-first immediate to(t)(x)", "redundant relation levels",
    "redundant descriptor annotations", "repeated standard and package homes",
    "single-use pipeline temporaries adding no name",
    "manual failure forwarding where the contract routes",
}

audit = {
    "check(...) as its own grammar production", "raw [[...]] strings",
    "the special condition-binding grammar", "@{} where demand is already unique",
    "& refinement over bitwise", "| union over bitwise", "early return",
}

# LEVEL-ZERO, HOME-ZERO, TEMP-ZERO, ROUTE-ZERO, SUBJECT-ZERO, CASE-ZERO,
# CONVERT-ZERO. One test serves all seven: does removing it leave EXACTLY ONE
# valid reading? If yes it goes; if no it stays in its smallest existing form.
zero.test = "does removal leave exactly one valid edge"

# CONSTITUTION SOURCE MIGRATION. This Markdown document is structured law
# notation, not executable canonical source. It moves atomically to
# `constitution.id` only after GAP-145 closes lexical identity and generated
# grammar roles and the complete body passes all four canonical source layers.
migrate.first = "the constitution"
migrate.blocked = "gap[145] — canonical lexical identity and generated roles are incomplete"

# Grammar reconciliation: postfix `expr.name` is statically named projection;
# bare dot has no ambient-subject meaning. The formal grammar and this law must
# converge through one generated role projection.
grammar.owed = "remove bare dot primary; preserve postfix named projection; generate every role from one authority"

# ═══ §43 · DELIMITER CLOSURE — useful source distinctions survive ═══════
#
# Brace-zero and application-zero are closed.
#
# Source faces preserve useful human distinctions while semantic meaning
# converges immediately after resolution. One application architecture does
# not imply one delimiter. Parentheses carry ordinary callable operands and
# grouping; braces carry structured packs, descriptor homes and descriptor
# application; brackets carry computed or indexed projection. Parentheses
# never mean aggregate indexing. No source face selects a physical aggregate.

brace = law{
    id    = "law.brace"
    kind  = .invariant
    holds = .resolution
    binds = {
        "`{ … }` is a neutral structured pack and never implies allocation",
        "`name{ … }` is explicit descriptor application",
        "an expected descriptor may supply the same descriptor fact",
        "an ordinary callable uses `name( … )`, never braces",
        "the parser preserves the source face; resolution supplies descriptor and application facts",
    }
    fails = "letting a callable use braces or letting delimiter choice force representation"
}

# `@{ … }` IS WORLD INJECTION ONLY (§54, docs/spec/law.md; law.injection.only).
# It derives a NEW closed world from the current world with the stated k = v fact
# deltas. It is NOT name-elided descriptor construction: a descriptor is an
# ordinary table `{ … }`, and descriptor construction is `name{ … }` (or plain
# `{ … }` when the descriptor is demanded). `point = @{ x: f64, y: f64 }` is
# retired — strengthen tables, do not add a descriptor sigil.
anchor.recover = "@{ … } derives a world by injection; descriptor construction is name{ … } or plain { … }"

# The provisional brace-call is retired. Ordinary call and descriptor
# application converge semantically only after their distinct source facts
# have been recognized.
audit.braceresolved = "brace-call retired; callable uses parentheses; descriptor application uses braces"

# The resolution rule is §41's, unchanged and now doing a second job:
#
#   BARE IDENTITY + SEMANTIC DEMAND + AVAILABLE HOMES -> ONE IDENTITY, OR A
#   DIAGNOSTIC.
#
# Here the demand is a descriptor applicable to a structured pack. Callable
# resolution remains the ordinary parenthesized face. Both produce graph
# application facts without preserving a source delimiter as semantic truth.

# ═══ §44 · APPLICATION IS ONE MECHANISM ════════════════════════════════════
#
# Application unification is SEMANTIC, never punctuation unification. The
# recognizer retains the minimum source structure and provenance. Resolution
# supplies relation, subject, operand pack, result pack and descriptor facts.

apply = law{
    id    = "law.apply.one"
    kind  = .invariant
    holds = .one
    binds = {
        "Idol has ONE semantic application architecture",
        "parentheses are the ordinary callable source face",
        "braces are the structured pack and descriptor application source face",
        "descriptor application and ordinary call converge after resolution where facts permit",
        "the parser records syntax provenance and never assigns semantic relation or subject identity",
    }
    fails = "a delimiter becoming semantic identity or an ordinary callable accepting braces"
}

# Unification of the MECHANISM is not a claim that every application is
# observationally identical. These stay distinct EDGES — specializations of one
# relation, exactly as `add(node)` and `add(edge)` are specializations of `add`,
# never separate grammar or object models.
apply.edge = {
    "apply(descriptor)(fieldpack)",
    "apply(callable)(argpack)",
    "apply(staged)(argpack)",
}

construct = law{
    id    = "law.construct.zero"
    kind  = .invariant
    holds = .none
    binds = {
        "CONSTRUCTOR IS NOT A SEMANTIC CATEGORY",
        "a descriptor is an APPLICABLE VALUE",
        "applying one to a compatible structured argument yields a value it describes",
        "no constructor abstraction survives into machine code unless demanded",
    }
    deny  = { "constructdescriptor", "bracecall", "tablector", "recordinit" }
    why   = "same ruling as law.arch.relation: do not name in a function what subject and argument shape already determine"
    ladder = "dynamic application, descriptor known, field shape known, layout known, direct initialization, scalar replacement, registers or constant"
}

pack.shape = law{
    id    = "law.pack.shape"
    kind  = .invariant
    holds = .deferred
    binds = {
        "a STRUCTURED PACK NEED NOT MATERIALIZE A TABLE",
        "`{ … }` supplies structured pack facts",
        "`( … )` supplies callable operand pack facts",
        "both preserve slot order, labels, values, descriptors and provenance",
        "table realization happens only where demand requires it",
        "physical representation is selected AFTER semantic resolution",
    }
    deny  = [[defining f{...} as callable syntax or defining f({...}) as forced table materialization]]
    why   = [[point{ x = 1, y = 2 } must lower to two fields in registers. Allocating a table because the SURFACE has braces lets syntax decide representation, which law.demand.rest forbids]]
    keep  = "distinct source packs converge without implying runtime materialization"
}

# Unification must EXPOSE facts, not erase them. The application identity
# carries subject identity, argument labels and positions, operand descriptors,
# constants, world, demand and return pack — so `point{ x = 1, y = 2 }` is a far
# stronger fact than a generic dynamic call, and specializes accordingly.
apply.carries = {
    "subject identity", "argument labels", "argument positions",
    "operand descriptors", "constants", "world", "demand", "return pack",
}

# ═══ §44a · the traps, the surviving distinction, and the ladder ══════════
#
# The laws below extend the one application architecture without duplicating
# its identity, construction or pack owners.

# THREE TRAPS, each a plausible implementation that would regress this ruling:
#
#   1. PARSER-LEVEL OVERLOAD — the parser asking whether `point` is a type,
#      emitting a constructor node if so and a call node if not. That is the
#      split this law deletes,
#      relocated one layer down. My own reverted patch did this in codegen,
#      branching on `record_aliases`, and it was the same mistake at a third
#      layer.
#   2. BRACES AS CALL — accepting `f{…}` for an ordinary callable erases a
#      useful source distinction. Defining `f({…})` as a forced table operand
#      separately commits representation before demand.
#   3. LOST CALL SHAPE — application identity must PRESERVE subject identity,
#      argument labels, positions, descriptor identities, constants, world,
#      demand and return pack. `point{ x = 1, y = 2 }` must be strictly
#      STRONGER than a generic dynamic call, never equal to one.
apply.traps = { "parser overload", "braces as sugar", "lost call shape" }

# The distinction that SURVIVES, and it is not "constructor versus call":
#
#   { x = 1, y = 2 }         an ordinary anonymous structured value
#   point{ x = 1, y = 2 }    APPLICATION of `point` to that shape
#
# Different because one has a SUBJECT.
#
# Descriptor, callable and staged applications remain distinguishable through
# facts while sharing one application architecture. Computed indexing retains
# subject, key pack, place, value, descriptor and demand facts without becoming
# callable syntax.
apply.edges = { "descriptor", "callable", "staged" }

# The ladder this buys, which is why the unification is worth more than the
# collision it fixes:
#
#   dynamic application -> descriptor known -> field shape known -> layout
#   known -> direct initialization -> scalar replacement -> registers
#
# NO CONSTRUCTOR ABSTRACTION SURVIVES INTO MACHINE CODE UNLESS DEMANDED.
apply.ladder = 7

# ═══ §45 · DELETION CONTRACTS — relation.zig may not fossilize ═════════════
#
# `src/relation.zig` is a deletion-gated bootstrap projection of ordinary graph
# relation facts. None of its host object taxonomy is semantic authority, and
# cleaner host names do not make a parallel registry canonical.

relationdebt = law{
    id    = "law.relation.debt"
    kind  = .invariant
    holds = .projection
    binds = {
        "src/relation.zig projects `relation`, `fact` and `witness` and owns none",
        "authority = false; the deletion gate is gap[082]",
        "no object taxonomy in it may become a permanent semantic kind",
    }
    fails = "gap[084]'s registries returning under cleaner names"
}

# FOUR DEBTS NAMED, each with the condition that retires it:
#
#   string identities   relation resolution must not depend on textual
#                       descriptor names once exact graph relation identities exist —
#                       packages, renames, MCP, refactoring and multiple
#                       versions all break on text.
#   codegen legality    the lossy-composition REFUSAL happens at codegen, so
#                       `idol check` approves what compilation later refuses.
#                       Class algebra belongs in SEMANTIC RESOLUTION: legality
#                       above realization, always.
#   one hop             derivation is deliberately one hop. Before longer
#                       paths, a path-selection law must cover multiple valid
#                       paths, cost, loss, effects, ownership, failure, trust
#                       and ambiguity. **Adding BFS would be architecturally
#                       wrong** — search is not a coherence law.
#   `to` in codegen     four literal `"to"` comparisons remain, annotated
#                       non-authoritative. HARD GATE: once primitive
#                       conversions are authored std relation facts,
#                       `codegen.zig` must go NET NEGATIVE in conversion code,
#                       or the relation layer is a front-end feeding the same
#                       builtin emitter kingdom.
relation.retires = { "string identities", "codegen legality", "one hop", "to comparisons" }

# ═══ §46 · NOMINAL IDENTITY IS THE NEXT WALL ═══════════════════════════════
#
# A nominal value cannot participate in derived relations if the compiler
# collapses it into the descriptor of its physical initializer.
#
# That is not a conversion feature. It is REPRESENTATION POLYMORPHISM, and it
# is the milestone the algebra is waiting on: **a `feet` value may physically
# remain an f64 while being semantically distinct.** Expanding conversion
# machinery before this lands buys nothing, because there is nothing for the
# derived edges to act on.
nominal = law{
    id    = "law.nominal"
    kind  = .invariant
    holds = .independent
    binds = {
        "semantic descriptor identity is INDEPENDENT of physical representation",
        "a nominal descriptor over a primitive costs no boxing",
    }
    fails = "a descriptor that cannot inhabit a value"
}

# ═══ §47 · C-DOMINANCE — C is a CANDIDATE, not the ceiling ═════════════════
#
# THE HONEST QUALIFICATION FIRST, because the goal as usually stated cannot be
# met: no compiler can guarantee that EVERY Idol program beats EVERY
# hand-written C program on every machine and every metric. A human can write
# assembly, exploit undocumented behaviour, or choose a workload built to
# defeat one optimizer.
#
# What IS achievable, and is strictly stronger than benchmarking:
#
#   For every Idol program whose semantics are no stronger than an equivalent
#   C program, the compiler must be able to produce machine code NO WORSE than
#   the best C realization in its candidate set — while exploiting semantic
#   facts unavailable to C where they exist.
#
# THE MECHANISM. C stops being the ceiling and becomes ONE CANDIDATE
# REALIZATION. For any semantic fragment the compiler holds several: Idol
# native lowering, a C-equivalent scalar lowering, simd, an intrinsic, a
# generated sequence, a library call, a profile-guided version. It costs them
# and picks. If Idol-native is worse, IT PICKS THE C-EQUIVALENT ONE.
#
#   Idol semantic information   >=  C semantic information
#   candidate set              includes the C-equivalent realization
#   chosen                     = min cost over candidates
#
# Idol cannot lose, because it keeps the fallback. That is monotonicity rather
# than optimism, and it is why this is architecture and not a benchmark claim.

cfloor = law{
    id    = "law.c.floor"
    kind  = .invariant
    holds = .candidate
    binds = {
        "wherever a C-equivalent realization exists it is a BASELINE CANDIDATE",
        "native Idol must MEET OR BEAT that baseline before replacing it",
        "C is a candidate, never the optimization ceiling",
    }
    fails = "a native lowering that ships because it is native"
}

perffloor = law{
    id    = "law.perf.floor"
    kind  = .invariant
    holds = .retained
    binds = {
        "a conservative baseline realization is RETAINED",
        "until another candidate is proven or measured superior",
        "under the ACTIVE objective, never under a default one",
    }
}

perfdominance = law{
    id    = "law.perf.dominance"
    kind  = .invariant
    holds = .monotone
    binds = {
        "adding semantic facts may NEVER reduce the realization set",
        "it may only remove semantically INVALID candidates, or add stronger ones",
    }
    fails = "a fact that makes the compiler forget an option it had"
}

# Every rewrite carries these, and a candidate replaces another ONLY when
# correctness is proven AND cost does not rise for the chosen objective. Where
# uncertain, KEEP BOTH and dispatch — monotonic optimization rather than
# heuristic optimism.
rewrite.carries = { "requires", "preserves", "cost", "witness", "descent" }

# PERFORMANCE IS NOT ONE NUMBER. A realization DOMINATES another when it is no
# worse on every relevant dimension and strictly better on one — a Pareto
# frontier, never a magical scalar.
cost.dimensions = {
    "latency", "throughput", "code size", "compile time", "peak memory",
    "allocations", "cache footprint", "branch misses", "energy", "startup",
    "binary size", "tail latency",
}

# THREE THINGS C DOES THAT IDOL MUST BEAT BY CONSTRUCTION, not by tuning:
#
#   ALIASING             C optimizes poorly without `restrict`. Idol derives
#                        alias facts, so NO USER-WRITTEN EQUIVALENT OF
#                        `restrict` appears in ordinary code.
#   SEPARATE COMPILATION C loses whole-program facts at translation-unit
#                        boundaries. Packages retain graph fragments and
#                        specialize across them — whole-program knowledge
#                        WITHOUT whole-program rebuild cost.
#   ABI FREEZING         C APIs commit to physical representation early. An Idol
#                        interface commits to MEANING; the machine abi is
#                        chosen at realization.
beats = { "aliasing", "separate compilation", "abi freezing" }

# ═══ §48 · THE RELATION ALGEBRA — one vocabulary, not one per family ════════
#
# `to` proved the seed: authored edges, enumeration, one-hop composition,
# witnesses, refused lossy derivation, SER 2.00 at N=4. THE NEXT MISTAKE WOULD
# BE GROWING SEPARATE SYSTEMS AROUND IT — an algebra for `add`, another for
# `iter`, another for `from`.
#
# Fourteen operations, and they are the algebra rather than syntax:
algebra = {
    "derive",   # obtain an edge from other facts
    "compose",  # compose compatible edges
    "invert",   # the logically inverse orientation, never a second store
    "imply",    # one relationship entails another
    "lift",     # map a relation across descriptor, container or world structure
    "restrict", # narrow applicability by world, descriptor or property
    "project",  # expose one relation through another surface
    "orient",   # choose the face WITHOUT changing identity
    "meet",     # combine constraints conservatively
    "join",     # combine alternatives where lawful
    "block",    # an explicit NEGATIVE fact that prevents derivation
    "prefer",   # candidate ordering as DATA, never a resolver hardcode
    "canon",    # choose the canonical equivalent surface
    "realize",  # choose the physical implementation under demand and target
}

# The faces are ORIENTATIONS of one identity, not separate mechanisms:
# declaration (operation-first) · subject invocation · callable value ·
# enumeration · anchored/reflection · derivation · inverse · operator · field ·
# application · ambient-subject.
#
# CONSEQUENCE, stated so it is not rediscovered: the conversion CLASSES —
# exact, lossless, view, checked, narrowing, consuming — must not stay
# conversion-only. They become ORDINARY FACTS on the edge (`loss = none`,
# `failure = false`, `storage = view`, `consumes = true`), or `add` and `iter`
# each grow their own class system and gap[084] returns a third time.
classes.become = "ordinary facts on the edge"

# Algebra breadth is an implementation measurement. It does not change the
# requirement that new breadth be expressed as facts rather than syntax.


# ═══ §49 · two additions to §47, merged from a parallel derivation ══════════
#
# §47 and an independent §45 draft were written simultaneously and BOTH landed,
# duplicating law.c.floor, law.perf.floor and law.perf.dominance. Duplicate law
# ids are precisely what law.stack.consistency forbids ("two constitutional
# facts may not disagree"), so the duplicate block is deleted and only what it
# carried UNIQUELY survives here. Recorded rather than silently merged: two
# agents deriving the same law independently is evidence the law was findable,
# which is a good sign — and duplicate ids are still a defect.

# The objective is an ordinary target/world fact. NO new surface, no compiler
# modes: `target = latency` and `target = size` select different frontiers of
# the same cost.dimensions in §47.
cost.objective = { latency, throughput, size, energy, startup, balanced }

# WHY a candidate can BEAT the c floor rather than merely match it. Each row is
# information C discards at the source level and Idol retains as an ordinary
# fact.
edge.over = {
    { fact = "descriptor identity", c = "double", idol = "meters, probability, sorted vector, nonzero scalar — can change the ALGORITHM" },
    { fact = "closed world",        c = "cannot know no future participant exists", idol = "sealed relation: devirtualize, erase dispatch, drop tag checks" },
    { fact = "ownership",           c = "aliasing is weak without restrict",        idol = "unique, borrowed, noalias, noescape, dead-after-call" },
    { fact = "effects",             c = "calls are opaque",                         idol = "reads a, writes b, no io, no allocation, no reentry — so reorder and parallelize" },
    { fact = "failure",             c = "the branch is always there",               idol = "failure proven impossible erases the tag and the machinery" },
    { fact = "range",               c = "the declared width is the width",          idol = "0 <= x < 256 narrows arithmetic and removes bounds checks" },
    { fact = "shape",               c = "the struct is the layout",                 idol = "struct, soa, aos, packed, simd lane, register tuple — by demand" },
    { fact = "call shape",          c = "one function, one body",                   idol = "many machine realizations from one semantic function" },
}

# ═══ §50 · WORLD IS AN OPERAND, NOT THE SUBJECT ════════════════════════════
#
# A namespace-first operation makes authority look like an inert table. Making
# the capability the receiver would fix reach while breaking subject
# orientation.

world = law{
    id    = "law.world.operand"
    kind  = .invariant
    holds = .operand
    binds = {
        "capability is an OPERAND and a CONTEXT, never automatically the subject",
        "the subject is the thing the relation is ABOUT",
        "authority is required to perform the relation, not to be its receiver",
        "where the world is granted in scope it is recoverable and elides as default algebraic injection per law.inject.algebra",
        "protocol witness does not grant world authority per law.protocol.world",
    }
    canon = { "file = path:open()", "data = file:read()", "path:read(fs)", "path:read()" }
    deny  = { "fs:read(path)", "io:open(path)", "os:remove(path)" }
    why   = "law.owner.physical one level up: the thing that GRANTS a capability is no more the semantic subject than the thing that STORES data. Making capability containers receivers is pseudo-OOP arriving through the capability door."
    fails = "call sites migrated into capability-first orientation"
}

# OBSERVE-MIN. The deepest reason Idol can beat C, and it is not instruction
# selection: C freezes representation and ABI at the source, Idol keeps them as
# degrees of freedom until demand forces the choice.
observe = law{
    id    = "law.observe.min"
    kind  = .invariant
    holds = .demanded
    binds = {
        "realization preserves only observations the current demand, lawset and world require",
        "a representation artifact nobody can observe need not physically exist",
        "an unread field is not computed, an impossible failure carries no tag, an unconsumed pack position is never materialized",
    }
    why   = "the optimizer question is not `what transformation preserves the program` but `what observations must this demand preserve`. Those are different questions and only the second admits erasing the value itself."
}

# ABI is DERIVED from the call graph, not declared. One semantic callable, many
# physical faces: a caller needing one field gets one register, a caller that
# only tests failure gets flags. C settles this in the header and spends the
# optimizer trying to recover it.
abi = law{
    id    = "law.abi.demand"
    kind  = .invariant
    holds = .derived
    binds = {
        "the physical abi is a consequence of demand across the call graph",
        "one semantic callable may carry several realized faces",
        "argument packs, return packs, closures, descriptor values, error packs and suspension state all obey this",
    }
}

# Facts survive REGIONS, not operations. One guard establishes a child world in
# which many operations consume the proven fact without re-proving it — and the
# counterpart law is what kills it.
epoch = law{
    id    = "law.proof.epoch"
    kind  = .invariant
    holds = .region
    binds = {
        "a guard establishes facts for a control region, not for one operation",
        "operations inside consume those facts without repeating the guard",
        "every relation declares which facts its traversal INVALIDATES",
        "a fact carries forward until an invalidating relation kills it",
    }
    why   = "c optimizers usually cannot prove a condition survives a call or an aliasing boundary. Idol can because the graph says which relations can falsify it and that makes compilation cheaper as well as the output faster."
}

# Physical width follows the proven STATE SPACE, not the declared type. A value
# with ten reachable states does not require sixty-four bits; a table of 0/1 is
# one bit per element, which is 8x denser than the c `int8_t` a programmer would
# have to choose by hand.
entropy.state = law{
    id    = "law.entropy.min"
    kind  = .invariant
    holds = .minimum
    binds = {
        "semantic state-space cardinality is the LOWER BOUND on physical bits",
        "the gap between actual representation and that bound is an optimizer objective",
        "one principle replaces every bespoke narrow-enum, bit-pack and tagged-union rule",
    }
    canon = "0 <= x <= 255 realizes u8 while remaining the same semantic value"
}

# ═══ §51 · LIFTING. What a refinement inherits from its representation. ════
#
# The rule that makes `str` acquire `slice(byte)`'s vocabulary WITHOUT
# acquiring the operations that would destroy it. General: it governs every
# refinement over every representation, and it is what turns a relation store
# into a projection algebra.

lift = law{
    id    = "law.lift.safe"
    kind  = .invariant
    holds = .conditional
    binds = {
        "an operation on a representation lifts to a refinement IFF its required facts are held and its preserved facts cover the refinement's invariants",
        "otherwise the lift is REFUSED, or yields a WEAKER descriptor, or yields a CHECKED result",
        "inheritance is never `the representation permits it, therefore the refinement does`",
    }
    canon = "str retains encoding(utf8) refinement plus its witness: slice lifts, put(byte) does not"
    why   = "a byte slice permits writes that leave text invalid. Blind inheritance is how a refinement silently stops being one."
    fails = "an operation that compiles and produces a value its own descriptor forbids"
}

# Element axes are LEVELS, not separate names. `str` enumerates three ways and
# they disagree — so `len`, `at` and `iter` are each three relations, and
# law.level.necessity decides when the axis may elide.
axis = law{
    id    = "law.axis.level"
    kind  = .invariant
    holds = .level
    binds = {
        "one value may expose several independent enumerable axes",
        "len(byte), len(codepoint), len(grapheme) are three relations, not one function",
        "where the axis is uniquely recoverable it elides; where several are valid it stays explicit",
    }
    deny  = "picking an axis silently — `#s` choosing bytes is a wrong answer for text, not a limitation"
}

# PERSISTENT SEMANTICS, EPHEMERAL REALIZATION. The value is immutable; the
# machine operation need not be. This is what lets functional source compile to
# the same instructions as imperative C, and it is the same mechanism that
# gives snapshots, replay, rollback and stateless handles.
persist.value = law{
    id    = "law.persist.unique"
    kind  = .invariant
    holds = .semantic
    binds = {
        "an operation yields a NEW semantic value and preserves its predecessor",
        "a persistent update MAY realize destructively when the predecessor is provably unobservable",
        "structural sharing, copy-on-write, rope, small-inline and grow-in-place are realizations of one semantics",
    }
    why   = "persistent semantics is usually paid for in copies. Under uniqueness and last-use facts the copy is not needed, so the functional form costs what the imperative form costs."
    open  = "snapshot identity, diff, patch and merge are the same mechanism reaching tooling: patch(a, diff(a,b)) = b"
}

# The acceptance test, written as law so it cannot be satisfied by renaming.
basis = law{
    id    = "law.basis.derive"
    kind  = .objective
    holds = .derived
    binds = {
        "adding a sequence descriptor ACQUIRES the vocabulary its representation already has, without reimplementation",
        "adding an element relation PROJECTS through every structure whose lifting laws permit it",
        "standard basis size — the primitive relation families needed to derive the standard vocabulary — is the scoreboard, not loc",
    }
    deny  = "renaming helpers to one-word names, which satisfies a grep and derives nothing"
    fails = "a second sequence descriptor having to write `starts`, `contains` and `split` again"
}

# ═══ §52 · @ IS THE CURRENT WORLD ══════════════════════════════════════════
#
# SETTLED RULING (supersedes every earlier @ reading — see docs/spec/law.md
# §4–§5f and law.projection.algebra). Two abandoned readings: "@ is the
# universal compiler prefix" and "@ is only an enclosing-descriptor anchor whose
# right operand is a relation." What survives: @ is THE CURRENT WORLD — the
# enclosing closed semantic table under which meaning resolves. The descriptor a
# pack recovers is that world; anchoring is a consequence of world resolution,
# not a separate job. Postfix @ carries a WORLD, never a relation:
# subject-relation orientation is the colon face (value:to(str)); @ qualifies.
#
#     @              the current world
#     @member        access a static member of the current world (@ is the accessor)
#     @member.child  one world access, then one ordinary static projection
#     x@world        evaluate/project x under world
#     @{ k = v }     derive the current world with exact injected facts (injection)
#     x@{ k = v }    scoped interjection — x@(@{ k = v })
#     @k = v         mutate a world member place, when it is a place
#     @( … )         the current world APPLIED TO AN EXPRESSION — that expression
#                    resolved under it, at the stage the world carries
#
# INVALID: @.member and @:member — @ already accesses, so there is no `@.`
# projection step and no `@:` subject dispatch. `@comp.foo` and prefix `@`
# directives are not in that family and die with the bootstrap authority they carry.
#
# ── THE `@( … )` ROW USED TO READ "eval", WITH NO ACCOUNT ────────────────────
#
# That one word was the whole of the collision. Three faces are visible at the
# surface — `@(expr)` compile-time evaluation, `@{ … }` injection, `@member`
# access — and `@` is only ONE algebra if compile-time evaluation is itself
# explained as evaluation under a world. Left unexplained, "eval" is compiler
# magic in the same table that binds "@ never means compiler magic and prefix
# directive syntax DOES NOT EXIST" three lines below. The row is now accounted
# for rather than removed, and the account is `law.stage.world`.
#
# THE COMPOSITION IS THE ONE ALREADY WRITTEN DOWN. `anchor.apply` says
# `@` + pack = apply(current world)(pack) = derived world. Applying the current
# world to a pack of FACTS derives a world; applying it to an EXPRESSION
# resolves that expression under it. Same prefix `@`, same application algebra
# (§9, one application algebra), one operand kind apart.
#
# AND STAGE IS A WORLD FACT, not a kingdom: `docs/spec/law.md` §6 lists
# "stage/target facts" among what a world carries, and §11 makes stage one of
# the obligations every transformation already binds. So "evaluate at compile
# time" NAMES the stage fact of the world doing the resolving, and
#
#     @(expr)  ==  expr@{ stage = compile }
#
# is an identity between two spellings of one meaning, not a definition of a
# second mechanism.
#
# WHAT FOLLOWS, and this is why the ruling is worth its ink:
#
#   · `@comp.*` HAS A DESTINATION. An operation whose entire content is "do this
#     at compile time" is an ordinary relation applied under a stage-delta
#     world. The host directive catalog can be deleted without losing the
#     capability, because the capability was never the directive.
#   · "NOT A COMPILE-TIME CONSTANT" IS NOT A SPECIAL DIAGNOSTIC. A value that
#     does not exist at the compile stage is not a fact of that world, so it is
#     refused by the ordinary rule that a derived world does not fall through to
#     facts absent at formation — `docs/spec/world.md`: "Resolution does not
#     search `trial` and then fall back to the root world — the deltas are
#     established when the world is formed." One refusal, not two.
#   · STAGE PARTICIPATES IN WORLD IDENTITY, hence in cache identity wherever it
#     changes lawful realizations (`law.md` §10, §13).
#
# THE REFUTED READING, recorded so it is not re-argued: that `@` genuinely has
# two roles, one world-algebraic and one directive-like. It is refused on this
# table's own terms — `law.at.one` already binds prefix directive syntax out of
# existence, and §2 forbids a second authority for one token. A directive
# reading would also need its own world/effect/stage obligation list beside the
# one §11 already requires of every transformation, which is a parallel ontology
# by construction.

# Evaluation at a stage IS evaluation under a world; `@(expr)` is that, spelled
# with the world elided because it is the current one.
stageworld = law{
    id    = "law.stage.world"
    kind  = .invariant
    holds = .world
    binds = {
        "stage is a FACT a world carries, never a separate kingdom, directive namespace, or evaluation mechanism",
        "@(expr) is apply(current world)(expr) — expr resolved under the world resolving it — and equals expr@{ stage = compile }; it is a compatibility spelling with exact provenance, not a fourth use of the sigil",
        "an operation whose entire content is compile-time evaluation is an ordinary relation applied under a stage-delta world; @comp.* @meta.* @compiler.* carry no capability the stage world lacks",
        "a value absent at a stage is absent from that stage's world and is refused by the derived-world no-fallthrough rule, not by a separate compile-time-constant diagnostic",
        "stage participates in world identity, and therefore in artifact identity wherever it changes a lawful realization",
    }
    canon = { "@(1 + 2)", "fold(xs)@{ stage = compile }" }
    deny  = "@( … ) read as a compiler directive, a second evaluation implementation, or an eval kingdom outside the world algebra"
    fails = "a compile-time facility that carries its own world/effect/stage obligations beside the ones every transformation already binds"
}

anchor = law{
    id    = "law.at.one"
    kind  = .invariant
    holds = .world
    binds = {
        "@ denotes the current world — the enclosing closed semantic table under which meaning resolves",
        "@ never means compiler magic and prefix directive syntax DOES NOT EXIST",
        "@{ … } is the injection literal only: applying the current world to a pack of k = v facts derives a NEW closed world — not mutation and not a third mechanism; an ordinary pack or descriptor is plain { … } with no sigil",
        "x@world evaluates x under world and x@{ … } is scoped interjection x@(@{ … }); the caller world is unchanged afterward",
        "@ is itself the accessor: @member accesses one static member of the current world and @k = v mutates a member place when the application yields a place; @.member and @:member are INVALID because @ already accesses",
        "postfix @ carries a world not a relation — subject-relation orientation is the colon face value:to(str), never value@to(str)",
        "same meaning in different worlds keeps the same semantic id with different witness target and realization facts",
    }
    canon = { "origin = () {0,0}", "trial = @{ tax = (sum) 0 }", "sale.quote@trial", "sale.quote@{ fee = 0 }(100)" }
    deny  = "@comp.* prefix directives, value@relation anchoring, and @.member/@:member accessor steps — bootstrap debt or invalid syntax with a deletion gate, never authority"
}

# `@{ … }` IS WORLD INJECTION, NOT DESCRIPTOR CONSTRUCTION. It is compositional:
# `@` is the current world and `{ … }` is a pack of `k = v` fact deltas, so
# applying the current world to that pack derives a NEW closed world (§54). This
# is APPLY-ONE, not a third mechanism. Descriptor construction is `point{ … }` (or
# plain `{ … }` when demanded); `@{ x, y }` is not a name-elided `point{ x, y }`.
anchor.apply = "@ + pack = apply(current world)(pack) = derived world; descriptor construction is name{ … }"

# The @{} collision is resolved decisively: @{} is exclusively world injection.
injectonly = law{
    id    = "law.injection.only"
    kind  = .invariant
    holds = .same
    binds = {
        "@{ … } is exclusively world derivation/injection — a pack of k = v fact deltas applied to the current world yielding a new closed world",
        "a descriptor is an ordinary table { … } whose values are descriptor constraints; descriptor construction is name{ … } or plain { … } — there is no descriptor sigil and point = @{ x: f64, y: f64 } is retired",
        "@{ … } is never an import or dependency manifest; usage derives dependencies, so @{ os.env io.stdout } bare-name lists stay forbidden",
    }
    fails = "@{ … } used for descriptor construction, universe/authority selection, or a dependency list"
}

# Refinement selection: there is no match/case/switch/pattern kingdom.
refineone = law{
    id    = "law.refine.one"
    kind  = .invariant
    holds = .cases
    binds = {
        "if generalizes into refinement selection over the already-evaluated subject; branch heads are constraints (exact value, descriptor satisfaction plus binding, exact identity, else remainder) not patterns",
        "the subject evaluates exactly once and a branch binding re-binds the refined value without copying",
        "multi-arm refinement is semantically unordered — overlapping non-disjoint arms are an ambiguity error with no first-match most-specific declaration-order or trait precedence; ordered testing uses nested if and guards use nested if",
        "if the result is demanded the arms must exhaust the possibility set or else is required; an undemanded remainder runs no body",
    }
    fails = "a match case switch or pattern-object subsystem, pattern guards, or destructuring-pattern syntax"
}

# Possibility algebra: unknown is a set of remaining possibilities that facts
# monotonically remove — one mechanism behind refinement, able, unions, guards.
possibilityone = law{
    id    = "law.possibility.one"
    kind  = .invariant
    holds = .monotone
    binds = {
        "a value carries a set of remaining semantic possibilities; facts monotonically remove possibilities from unknown toward sealed",
        "descriptor checking if-refinement able unions nil-refinement guard insertion call specialization conversion inference shape specialization and target selection are one mechanism",
        "a union is not a kingdom — it is more than one remaining admissible alternative; a guard exists only when a profitable realization assumes one of several remaining possibilities",
    }
    fails = "a separate union type kingdom or a guard that boxes unrelated values"
}

# No undefined behavior: optimization comes from facts, never from UB.
ubzero = law{
    id    = "law.ub.zero"
    kind  = .invariant
    holds = .same
    binds = {
        "Idol requires no semantic undefined behavior to optimize; optimization comes from exact alias world shape demand range descriptor application effect and lifetime facts",
        "ordinary integer arithmetic has no C-style undefined behavior and numeric law is fully defined before any FTCFTW claim",
        "unknown behavior remains unknown; proven facts enable optimization",
    }
    fails = "an optimization that depends on undefined behavior rather than a proven semantic fact"
}

# ═══ §53 · CAPABILITY BY PRESSURE, NOT BY CHECKLIST ════════════════════════
#
# How to reach a comprehensive implementation without implementing a
# theoretical feature list: three workloads, run simultaneously, each forcing a
# different half of the substrate.

forcing = law{
    id    = "law.force.three"
    kind  = .protocol
    holds = .pressure
    binds = {
        "compiler self-host forces parse, sema, graph, lowering, encoding",
        "Idol Wasm forces jit cfg register allocation memory and performance",
        "lsp, mcp, formatter, package and build force persistent ids, witnessed cross-incarnation correspondence, diagnostics and incremental computation",
        "a capability unnecessary to ALL THREE is not pre-release p0",
    }
    why   = "capability built to satisfy a checklist is speculative scaffolding. Capability built under pressure from a real workload is load-bearing on the day it lands."
    keep  = "any capability Idol Wasm needs should normally become a GENERAL compiler primitive — never ward-only infrastructure"
}

# The claim to make, and the one to refuse. "Faster than C across the board
# without exception" invites benchmark hacking and cannot be established: no
# compiler architecture mathematically guarantees one implementation wins every
# program on every cpu. The defensible construction is already law
# (law.c.floor, law.perf.floor, law.perf.dominance) and reads:
#
#   the c-equivalent realization is RETAINED whenever lawful · Idol may add
#   STRICTLY STRONGER candidates from additional semantic facts · the public
#   supported corpus demonstrates RELIABLE dominance, adversarial workloads
#   retained
#
# Get law.perf.dominance right — more semantic knowledge may never shrink the
# valid realization set — and systematic dominance becomes an engineering
# problem rather than a wish.
claim.refused = "faster than c across the board without exception"
claim.made    = "more semantic knowledge never reduces the valid realization set"

# ═══ §54 · THE PACK LADDER — two source forms, one application ═════════════
#
# Most explicit to most inferred, and the canonicalizer picks the SHORTEST that
# stays uniquely resolvable:
#
#     point{ x, y }    descriptor stated
#     { x, y }         descriptor = the expected one
#
# Two source projections of ONE apply relation. Not two constructors. `@{ … }`
# is NOT a rung here — it is world injection only (`law.injection.only`).

pack.neutral = law{
    id    = "law.pack.neutral"
    kind  = .invariant
    holds = .data
    binds = {
        "a braced pack is STRUCTURED SEMANTIC DATA and nothing more",
        "it stays a pack until a demand supplies a unique descriptor",
        "`a = { x, y }` remains an ordinary structural value",
    }
    deny  = "redefining a bare pack as `construct the expected descriptor`"
    why   = "if the bare form MEANT construction it would be a second constructor mechanism hiding behind inference. Same syntax, more compiler knowledge — that is specialization at the grammar level, and law.construct.zero survives it."
}

expect = law{
    id    = "law.expect.apply"
    kind  = .invariant
    holds = .demand
    binds = {
        "an expected descriptor may supply the OMITTED application subject",
        "`p: point = { x, y }` is apply(point)(pack) — the demand names the subject",
        "the pack is unchanged; only what is known about it changed",
    }
    canon = "p: point = { x, y }"
    deny  = "p: point = @{ x, y } — @{ … } is world injection, not a descriptor construction face (law.injection.only)"
}

# `law.at.apply` (`@{ … }` as ambient-descriptor application) is RETIRED: the
# `@{}` collision is resolved decisively in favor of world injection only
# (`law.injection.only`). Ambient-subject construction uses `{ … }` under demand
# (`law.expect.apply`) or `name{ … }`; there is no descriptor sigil.

omit = law{
    id    = "law.omit.derivable"
    kind  = .invariant
    holds = .shortest
    binds = {
        "the canonicalizer removes an explicit descriptor or @ when it is UNIQUELY implied",
        "`p = point{ x, y }` keeps its subject — nothing else names it",
        "`p: point = { x, y }` drops it — the annotation already did",
        "inside a point-returning relation both the subject and the field source are recoverable, so `{ x + dx, y + dy }` is canonical",
    }
    fails = "a form that is shorter but no longer uniquely resolvable"
}

# A REAL semantic decision, recorded as one rather than smuggled in as a
# function-declaration special case. `b: point = (x, y) …` cannot mean the
# CALLABLE satisfies `point` — a callable is not a point.
demand = law{
    id    = "law.callable.demand"
    kind  = .invariant
    holds = .result
    binds = {
        "where a binding's right side introduces a CALLABLE, an annotation between the name and `=` describes the callable's RESULT demand",
        "where it does not, the annotation describes the value, unchanged",
        "the right side's SHAPE decides which, so nothing is ambiguous",
        "the parser keeps binding(name, annotation, rhs); the PROJECTION is semantic",
    }
    canon = "parse: config = (src) …  means result(parse): config"
    why   = "a general contextual projection, not a `function return type` production. NNS holds: no new grammar, and it beats both `b = (x, y): point` and inventing function-type notation."
}

# ═══ §55 · IDENTITY, AUTHORITY ORDER, AND WHAT SELF-HOSTING MUST NOT COST ══

# Authority order is owned once by `law.owner` in §3. This section adds no
# second ranking or reconciliation law.

# The clarification that keeps monoglot from eating the product. Deleting
# foreign SEMANTIC AUTHORITY is the goal; deleting foreign INTEGRATION would
# make Idol less useful the day it became self-hosted.
foreign = law{
    id    = "law.foreign.integration"
    kind  = .invariant
    holds = .kept
    binds = {
        "100% self-hosting must not reduce Idol's usefulness to non-Idol projects",
        "first-class lawsets and projections stay for lua, c, rust, python, wasm, abi and schema formats, source asts, build systems and package systems",
        "cross-language transformation uses the SAME graph, provenance, laws and witnesses as native transformation",
    }
    deny  = "deleting foreign INTEGRATION in the name of deleting foreign AUTHORITY"
}

# ═══ §56 · CHAIN ORDER IS SEMANTIC · NO IMPLICIT CALL ══════════════════════

chain = law{
    id    = "law.chain.order"
    kind  = .invariant
    holds = .ordered
    binds = {
        "every postfix relation consumes the result to its LEFT",
        "order is SEMANTIC: take(n):filter(p) is not filter(p):take(n) unless a law proves it",
        "streaming and fusion happen where demand, effects and invariants permit",
        "chaining several relations never REQUIRES an intermediate allocation",
    }
    why   = "fusion is a realization freedom, not a reordering licence. A pipeline that silently commuted its stages would be a wrong answer wearing an optimization."
}

nocall = law{
    id    = "law.call.explicit"
    kind  = .invariant
    holds = .never
    binds = { "a bare `f` is NEVER inferred as `f()`" }
    why   = "a callable is a value. Inferring invocation from mention would make every relation passed as a value ambiguous with its own result — and law.call.face depends on the callable face staying distinct."
    open  = "`p:len` as zero-operand subject invocation is an OPEN candidate, to accept or reject before syntax freeze. It must remain distinct from `p@len`, which ANCHORS the relation rather than performing it."
}

world.order = law{
    id    = "law.world.resolve"
    kind  = .invariant
    holds = .ranked
    binds = {
        "an explicitly supplied world",
        "a lexically granted compatible world",
        "an explicitly captured world",
        "otherwise FAILURE",
    }
    deny  = "inferring authority from a package-global ambient capability"
    why   = "authority that can be reached by default is not a capability. The ladder ends in failure on purpose."
}

# ═══ §57 · THE DOCS GATE ═══════════════════════════════════════════════════
#
# Six conditions, each a BUILD FAILURE. Documentation is corpus
# (law.doc.corpus) and this is what makes that mechanical.
docgate = {
    "a visible semantic token lacks a semantic role",
    "a current lowering claim lacks compiler evidence",
    "source, graph, dnir and assembly correspondence is broken",
    "stale canonical syntax contradicts an owner ruling",
    "generated escape artifacts appear in output",
    "distinguishable semantic roles collapse to identical rendering by accident",
}

# ═══ §58 · IF THE GRAPH IS A PATH, THE SOURCE IS A PATH ════════════════════

chainprefer = law{
    id    = "law.chain.prefer"
    kind  = .invariant
    holds = .chain
    binds = {
        "a value produced ONLY to become the subject of exactly one following relation forms a postfix chain",
        "the temporary binding is removed",
        "no temporary may exist merely to bridge two relations",
    }
    canon = "users:map(score):take(n):filter(positive)"
    deny  = "scores = users:map(score) then limited = scores:take(n) then result = limited:filter(positive)"
    why   = "the chain makes subject flow explicit, exposes fusion, and deletes three names nobody reads. If the semantic graph is already a path, the source should look like one."
}

chainbreak = law{
    id    = "law.chain.break"
    kind  = .invariant
    holds = .kept
    binds = {
        "the intermediate has MORE THAN ONE consumer",
        "the name carries semantic information a reader needs",
        "the step crosses an effect or world boundary",
        "what follows targets the ORIGINAL ambient subject, not the produced value",
    }
    why   = "chain-prefer without this becomes point-free code, which trades a readable name for a shorter line. The rule is about deleting BRIDGES, not deleting names."
}

# THE DISAMBIGUATION, and the reason layout may not carry this weight.
#
#     :normalize()        two SIBLING invocations on one ambient subject
#     :validate()
#
#     point               a CHAIN: each step consumes the step above
#         :normalize()
#         :validate()
#
# Indenting a leading `:` under another leading `:` must NEVER mean "continue
# the pipeline". A chain ORIGINATES FROM A VALUE.
chainop = law{
    id    = "law.chain.postfix"
    kind  = .invariant
    holds = .postfix
    binds = {
        "postfix `:` is the ONLY chain operator",
        "leading `:` is ambient-subject invocation, never implicit pipeline continuation",
        "a chain originates from a value, not from indentation",
    }
    deny  = "inferring chaining from line adjacency or nesting depth"
    fails = "two sibling effects silently read as a two-stage pipeline, or the reverse"
}

# Where to look for this defect. Every one of these is a path in the graph and
# is routinely written as a stack of temporaries.
chainaudit = {
    "normalize, validate, format",
    "decode, validate, transform, encode",
    "read, decode, parse",
    "collection transformations",
    "compiler descent",
    "graph transformation",
    "snapshot, transform, diff, merge",
    "wasm validate, lower, realize",
    "string projection",
    "conversion and protocol examples",
}

# ═══ §59 · DNIR IS A PROJECTION, NOT A SECOND LANGUAGE ═════════════════════
#
# A realization record that reserves unrelated operation-specific fields is a
# second ontology with its own naming and cost model, not a compact projection.

irone = law{
    id    = "law.ir.one"
    kind  = .invariant
    holds = .projection
    binds = {
        "dnir is NOT a second semantic language",
        "it is the native-realization PROJECTION of the semantic graph",
        "source, graph, dnir, tooling and machine provenance share relation and descriptor IDENTITIES",
        "dnir may add realization FACTS; it may never rename a semantic operation into a competing ontology",
    }
    fails = "a dnir opcode that is a second name for a relation the graph already has"
}

irexplicit = law{
    id    = "law.ir.explicit"
    kind  = .invariant
    holds = .explicit
    binds = {
        "dnir exists to make IMPLICIT source facts explicit where optimization needs them",
        "value identity · control flow · representation candidates · effects · demand · machine constraints · provenance",
        "adding explicitness is its job; inventing vocabulary is not",
    }
    keep  = "dnir need NOT look like source. A dag is not a pipeline, and explicit value ids are information source does not carry. `v1 = field(p, x)` is correct where forcing a chain would lie about the dataflow."
}

ircompact = law{
    id    = "law.ir.compact"
    kind  = .invariant
    holds = .separate
    binds = {
        "READABLE dnir uses canonical Idol naming and composition",
        "INTERNAL dnir uses compact interned ids and representation-selected storage",
        "readable syntax NEVER dictates compiler memory layout",
    }
    why   = "the same law the language states about itself: semantic identity does not choose physical representation. A hot instruction lane stays dense while rare payloads live out of line, and the graph may pick aos or soa by workload."
    deny  = "a 20-field record where a mul reserves slots for callee, branch target and hardware intrinsic"
}

irbomit = law{
    id    = "law.ir.omit"
    kind  = .invariant
    holds = .derived
    binds = {
        "a fact uniquely recoverable from operands, descriptors, relation identity, target or demand is NOT redundantly encoded",
        "the qualifier becomes a LEVEL or a FACT, never a longer name",
    }
    canon = "const(i64) · load(field) · call(extern) · br(false) · len(byte) — and each collapses further where the operand already says it"
    deny  = "constdirect, loadfield, callextern — one-wording an underscore is WORSE than the underscore"
}

# THE GUARDRAIL, without which this ruling is destructive. Unify IDENTITY;
# preserve REALIZATION FACTS. Integer add, float add, vector add, saturating,
# wrapping and checked add are ONE relation — and dnir must still carry
# descriptor, representation, overflow law, vector width, rounding and target
# features, or the backend cannot legalize an instruction.
irguard = "unify identity, preserve realization facts — never one dynamically interpreted relation"

# The retirement list, and what each becomes.
irretire = {
    { was = "const_i64 const_f64 const_str const_req", now = "const, with the descriptor" },
    { was = "load_local load_field load_index load_global", now = "load, with the place" },
    { was = "store_local store_field store_index", now = "store, with the place" },
    { was = "call_direct call_extern", now = "call, with linkage, symbol, abi, lawset" },
    { was = "mov_arg fp_mov_arg", now = "NOTHING — abi placement belongs to machine realization, not to a typed ir" },
    { was = "br_if br_if_not", now = "br, one terminal form; a negated condition is canonicalized" },
    { was = "ret_record", now = "ret — the value's representation decides scalar, pack, hfa, sret or nothing" },
    { was = "hw_fence hw_spin hw_unary", now = "hw, with the intrinsic" },
    { was = "str_len", now = "len, with the axis" },
}

# Two of those are worth more than the renaming. `mov_arg`/`fp_mov_arg` mean
# ABI PLACEMENT LEAKED INTO A TYPED IR — removing them enables move coalescing
# and argument precoloring instead of materializing pointless virtual moves.
# And `load_local`/`store_local` are SOURCE-STORAGE ARTIFACTS: under ssa a
# binding is not a memory location until demand proves it needs one — address
# observed, capture, aliasing, spill, mutation or a debugger.
irwin = "a binding is not a memory location until demand proves it needs one"

# ═══ §60 · FOUR CLAIMS §59 DID NOT CARRY ═══════════════════════════════════

# SEMANTIC-ONE: one meaning retains one graph identity and one native word;
# qualification belongs to facts and physical choice belongs to realization.
semantic.one = law{
    id    = "law.vocab.same"
    kind  = .invariant
    holds = .shared
    binds = {
        "one meaning has one graph identity and one lowercase native word",
        "qualification belongs to facts rather than parallel relation names",
        "source, semantic graph, dnir, tooling and machine provenance share ONE relation and descriptor identity space",
        "each layer may ADD facts; none may rename an operation into its own vocabulary",
    }
    why   = "the source-to-graph-to-dnir-to-assembly view becomes nearly free, because the compiler no longer RECONSTRUCTS correspondence — the lineage was never broken."
    canon = "add(a,b) semantic · add + descriptor i64 + repr register + overflow wrap realized · block 7, value v19, users {v20,v23} in flow · v19 -> x3 allocated · `add x3,x1,x2` machine"
}

# `Op` is a SECOND TAXONOMY. It should become an interned ACCELERATION of a
# relation identity, never an identity of its own — and the same collapse
# deletes the redundant dispatch level `switch op { .binop => switch binop }`,
# because `lt` is a relation, not `cmp` carrying a `lt` tag.
opintern = law{
    id    = "law.op.intern"
    kind  = .invariant
    holds = .interned
    binds = {
        "a compact opcode is an interned acceleration of a RELATION IDENTITY",
        "it is never a second identity",
        "no operation is a tag inside another operation",
    }
    deny  = "binop.add beside the semantic relation add — one redundant dispatch level, and a switch inside a switch to service it"
}

# Most irs freeze physical type on entry. DNIR need not: it can carry a LADDER
# of realization knowledge and commit only where demand or abi forces it.
reprladder = law{
    id    = "law.repr.ladder"
    kind  = .invariant
    holds = .candidates
    binds = {
        "a realized value may carry SEVERAL candidate representations",
        "commitment happens where demand, abi or target requires it — not on entry to the ir",
        "point -> sealed shape -> scalar-replaceable -> two f64 -> registers -> d0,d1 is one value gaining facts",
    }
    why   = "freezing representation early is what makes a conventional lower ir lose the optimizations it then spends passes trying to recover. law.observe.min and law.abi.demand both need this to be true of the ir, not only of the graph."
}

# If realized ir is ordinary graph data, the self-hosted compiler transforms it
# with ordinary Idol — no separate pattern language, which is a whole subsystem
# SHC does not then have to write.
irdata = law{
    id    = "law.ir.data"
    kind  = .objective
    holds = .ordinary
    binds = {
        "realized instructions are ordinary graph data with a relation, a result, operands and facts",
        "compiler transforms are ordinary relation applications over them",
        "patterns are descriptors and relations, NOT an external ir pattern language",
    }
    canon = "block:map(fold):filter(live):map(realize(target))"
    why   = "a compiler that needs a bespoke matching dsl to manipulate its own ir has two languages in it. law.force.three says the self-host workload is what forces this to be true."
}

# Places unify: `field(x)`, `index(i)` and `global(g)` are one PLACE operand to
# load and store, so alias, bounds, mutability and provenance analysis reason
# uniformly and the backend still picks its own instruction.
irplace = "load(subject, place) · store(subject, place, value) — place is field, index or global"

# ═══ §61 · IDENTITY-ONE · COMMIT-MONOTONIC · THE CONVERGENCE GATE ══════════
#
# §59-60 are FROZEN. No further dnir design pass. What follows is the two
# invariants they did not carry, and the instrument that measures whether the
# implementation is converging on them at all.

lineage = law{
    id    = "law.identity.lineage"
    kind  = .invariant
    holds = .continuous
    binds = {
        "every realized instruction RETAINS the identity of the semantic relation it descends from",
        "source span, relation id, realization, value and control identity, allocation, machine instruction, machine byte range — ONE lineage",
        "a compact opcode is intern(relation), never an independent operation that happens to share a name",
    }
    deny  = "semantic add becoming an unrelated binop.add that must later be CORRELATED BACK to add"
    why   = "no translation back into semantic meaning is needed if the meaning was never lost. The four-way source/graph/dnir/assembly view is a consequence of this invariant, not a feature built beside it."
}

commit = law{
    id    = "law.commit.monotonic"
    kind  = .invariant
    holds = .narrowing
    binds = {
        "realization NARROWS a candidate set through evidence, never by default",
        "every removed candidate is attributable to demand, target, abi, observation, effect, proof or cost",
        "a lower layer may ADD explicit facts; it may never silently forget the fact that justified an earlier commitment",
    }
    canon = "{boxed, stack, pair, hfa, scalar} -> {pair, hfa, scalar} -> {scalar}, each step with its reason"
    why   = "this is what makes `why wasn't this simd`, `why did this allocate`, `why did this become sret`, `why wasn't this scalar-replaced` MECHANICALLY answerable rather than a debugging exercise."
}

# The governance gap this closes: the constitution can say law.ir.one while the
# implementation stays the old dnir indefinitely. These are measured, not
# asserted — and the LAST line is the guardrail on the whole list.
converge = {
    { row = "semantic operation identity spaces",   target = 1 },
    { row = "instructions carrying a semantic id",  target = "100%" },
    { row = "instructions carrying provenance",     target = "100%" },
    { row = "underscored semantic op names",        target = 0 },
    { row = "nested op/subop dispatch levels",      target = 0 },
    { row = "abi argument-move operations",         target = 0 },
    { row = "ordinary local load/store operations", target = 0 },
    { row = "semantic return operation families",   target = 1 },
    { row = "place load/store families",            target = 2 },
    { row = "semantic reconstruction side maps",    target = 0 },
    { row = "facts reconstructed after sema",       target = "decreasing" },
    { row = "early representation commitments",     target = "decreasing" },
    { row = "correspondence rebuilds",              target = 0 },
}

converge.guard = "MEASURE SEMANTIC AUTHORITY AND RECONSTRUCTION, never a vanity opcode count — a smaller count that hides distinctions inside giant dynamic switches is WORSE"

# The recurring failure this names, in the lowerer's own shape: a semantic fact
# exists · the lowerer loses it · a local map re-discovers it · another consumer
# misses the map · another special case is added. **Every deleted reconstruction
# table is worth more than an opcode rename.**
reconstruct = "establish once · project many times · reconstruct nowhere"

# ═══ §62 · EVIDENCE MUST BE PRIVATE TO THE RUN ═════════════════════════════
#
# Mutable evidence shared between concurrent runs has no trustworthy owner.

evidence = law{
    id    = "law.evidence.private"
    kind  = .invariant
    holds = .isolated
    binds = {
        "every run receives a unique id, a private temp directory, private logs, a private mutable cache namespace and isolated generated artifacts",
        "only immutable or content-addressed data may be shared",
    }
    fails = "A TEST RESULT WHOSE EVIDENCE ANOTHER RUN CAN OVERWRITE IS NOT A FACT"
    why   = "the same law as everywhere else — one fact, one authority, explicit provenance — applied to every artifact a gate reads"
}

# ═══ §63 · THE BOUNDARY EVERY RECONSTRUCTION IS DOWNSTREAM OF ══════════════
#
# Treating the graph as optional metadata after AST lowering makes every
# downstream reconstruction table predictable. Realization consumes graph
# facts; it does not decorate a parallel lowering authority afterward.

authority.graph = law{
    id    = "law.graph.authority"
    kind  = .invariant
    holds = .queryable
    binds = {
        "native realization RECEIVES the semantic substrate; it is not optional metadata",
        "the lowerer ASKS — descriptor(result(relation)), descriptor(value), relation(call), effect, world, demand — and gets ONE answer",
        "the graph is the authoritative IDENTITY and PROVENANCE substrate; a fact attached to an identity has one authoritative SOURCE and is queryable at realization",
        "node and edge tags are physical indexes — they do not own meaning (law.boolean.mirror.zero applied to graph kinds)",
        "module source_file func param local call concept type_node transform_app comptime_value emit_artifact are not semantic identities",
        "contains def use type_of transform_input transform_output are not meaning — reduce toward member binding descriptor operand result provenance",
        "application roles relation subject operand result live on application facts — do not mint a second edge taxonomy for the same roles",
    }
    keep  = "ONE LOGICAL AUTHORITY, NOT ONE LITERAL STRUCTURE. A descriptor fact may physically live in a graph node, an interned table, a side arena or a query cache — turning the graph into a giant mutable compiler database would trade one architecture problem for a performance one."
    why   = "without this boundary, deleting reconstruction map #1 simply creates map #2. Opcode cleanup before it makes dnir prettier while the architecture stays broken."
    fails = "a lowerer that re-derives from the ast what sema already established"
}

# COUNT SEMANTIC RECONSTRUCTIONS, NOT DATA STRUCTURES. Two maps may legitimately
# project two independent dimensions; one function may reconstruct five facts.
# Two physical maps may project genuinely different scope facts and must not be
# fused merely to lower a structure count.
reconstructrow = { "fact", "authority", "consumer", "projection or query or RECONSTRUCTION" }
reconstructwarn = "hpls pressure applied to a structure count causes destructive fusion — the metric is the fact, not the table"

# ═══ §64 · TWO AXES, AND ONE MAY NEVER SUBSTITUTE FOR THE OTHER ════════════
#
# Foreign-file reduction and vertical authority transfer are independent axes.
# Either can improve while the other remains unchanged or regresses.

axes = {
    horizontal = { "foreign files", "generated foreign projections", "shell and python dependencies", "duplicated tooling" },
    vertical   = { "graph authoritative", "realize exists", "flow exists", "allocator exists", "encoder consumes the realized graph", "linker sovereign", "evaluator self-hosted" },
}

axes.rule = "NEVER LET HORIZONTAL SOVEREIGNTY SUBSTITUTE FOR VERTICAL DESCENT — they are scored separately or a repository compression reads as an architecture"

# codegen.zig absorbing responsibility instead of surrendering it is the failure
# a file count cannot see. The budget is on RESPONSIBILITIES, not lines: a
# migration may add adapters, but every new semantic capability names its target
# owner, and nothing lands in codegen merely because that is where native
# behaviour currently works.
codegen.budget = "semantic responsibilities monotonically DECREASE"

gatelive = law{
    id    = "law.gate.live"
    kind  = .invariant
    holds = .reachable
    binds = {
        "an authoritative checker not reachable from a NAMED AGGREGATE GATE is not a checker",
        "a check declares its owner, input, output and aggregate as ordinary facts",
        "the build DERIVES its gate topology from those facts rather than wiring each command by hand",
    }
    why   = "a checker that is not reached by an aggregate can exist without ever supplying admission evidence"
}

# `unsupported/` is a CAPABILITY FRONTIER, not a graveyard: it means "proven not
# to pass the required native gate today", never "someone once thought this was
# unsupported". Promotion is AUTOMATIC the moment a program compiles and agrees.
unsupported.means = "proven not to pass the required gate today; promotion is automatic on agreement"

# ═══ §65 · SEMANTIC NORMALIZATION — SURFACE IS EVIDENCE, NEVER AUTHORITY ══════
#
# The pressure test is the conventional shape
# `if not std.fs.exists(path)`: control words survived as semantic categories,
# a distribution home masqueraded as meaning, and an existence query exposed
# a state transition that should usually be atomic. The correction is NOT an
# immediate keyword purge. Meaning unifies first; spelling earns or loses its
# place only after ordinary relations can carry the work.

surfacezero = law{
    id    = "law.surface.zero"
    kind  = .invariant
    holds = .erased
    binds = {
        "a grammar face records provenance and resolution evidence, never semantic identity",
        "if while for and or not operators projection access application and binding normalize immediately",
        "ordinary application supplies a dynamic key while a dot face supplies statically named identity",
        "named projection and ordinary application converge after resolution whenever subject key value place demand and descriptor facts are equivalent",
        "equivalent source faces resolve to the same facts while distinct occurrences retain distinct ids",
        "computed projection never forces a table hash lookup dynamic dispatch allocation or physical memory access",
        "a retained grammar face may improve human density and still own ZERO semantic machinery",
    }
    fails = "a parser production surviving as the authority for type effect optimization or lowering"
}

semanticsonly = law{
    id    = "law.semantics.only"
    kind  = .invariant
    holds = .closed
    binds = {
        "after parsing the vocabulary is value relation descriptor fact demand world place witness provenance dependency application binding projection realization",
        "source grammar categories are unavailable to semantic consumers except as provenance",
        "temporary parser classification is parser-local and normalizes before semantic authority begins",
        "semantic and realization consumers fail closed when only a parser category delimiter or token text is available",
    }
    deny  = {
        "conditional statement kind", "loop kind", "binary or unary expression kind",
        "call index member return break or continue kind as semantic authority",
    }
}

normalize = law{
    id    = "law.normalize.early"
    kind  = .invariant
    holds = .immediate
    binds = {
        "tokens become parse faces; parse faces become meaning; meaning becomes identities relations and facts",
        "no chain of syntax taxonomies exists between parsing and the persistent graph",
        "every face carries source provenance through erasure",
    }
    fails = "ast to typed ast to control ast to backend ast"
}

faceerase = {
    "if -> conditional demand over alternatives plus merge",
    "while -> repeated demand with condition dependency body dependency and backedge",
    "for -> iter relation with binding projection and demanded body",
    "and or -> ordinary relations with operand-returning short-circuit demand",
    "not -> ordinary truth relation with a prefix projection",
    "operator -> ordinary relation identity plus orientation and precedence provenance",
    "application faces -> one apply relation specialized by subject argument shape demand and context",
    "index and member faces -> one projection relation plus exact subject key value place demand descriptor and provenance facts",
    "binding face -> fact and place identity, never storage by default",
    "return break continue -> demanded result of the enclosing region, never standalone semantic kinds",
}

controlone = law{
    id    = "law.control.one"
    kind  = .invariant
    holds = .ordinary
    binds = {
        "control is dependencies demand effects values regions and facts",
        "conditional demand selects exactly one alternative",
        "repetition is a cyclic dependency region with explicit termination demand",
        "iteration is a relation; map take fold each and fuse are specializations",
        "termination is a result directed at an enclosing region",
    }
    keep  = "branch merge and backedge may exist as physical realization facts, never source ontology"
}

truth = law{
    id    = "law.truth.relation"
    kind  = .invariant
    holds = .relation
    binds = {
        "and or and not are ordinary relation identities",
        "short circuiting is a demand law, not keyword authority",
        "not applies only to an irreducible truth relation and never repairs a helper that collapsed richer semantics to bool",
        "the infix or prefix face may remain only while it earns greater readable density",
    }
}

operatorface = law{
    id    = "law.operator.face"
    kind  = .invariant
    holds = .projection
    binds = {
        "grammar supplies orientation precedence and provenance",
        "the semantic graph stores the relation identity and operands",
        "no plus binary or unary ontology survives normalization",
    }
}

update = law{
    id    = "law.update.face"
    kind  = .invariant
    holds = .shortest
    binds = {
        "x op= y is the canonical shortest face if and only if it is equivalent to x = x op y",
        "meaning is the base relation plus exact place read write update and provenance facts",
        "addassign increment and compound operation identities do not exist and ++ is not admitted",
        "every component of a computed place is evaluated exactly once",
        "the rewrite witness preserves evaluation order effects custom relation law overflow failure aliasing and result demand",
        "a non-equivalent expanded form remains unchanged",
    }
    canon = "step += 1, n -= 1, x *= y, and y /= z are canonical when witness proves equivalence; expanded place = place op value is migratable debt only"
    deny  = { "++", "addassign", "increment ontology", "unwitnessed text rewrite" }
    proof = {
        "positive control: step = step + 1 is migratable when both occurrences resolve to the same place and every required observation is preserved",
        "negative control: left = right + 1 remains when left and right are distinct places",
        "negative control: values[next()] = values[next()] + delta remains when repeated key evaluation is observable",
        "negative control: any difference in order effects custom relation law overflow failure aliasing or result demand keeps the expanded form",
    }
    fails = "a shorter update face that changes an observation or creates a new semantic relation"
}

bindplace = law{
    id    = "law.binding.place"
    kind  = .invariant
    holds = .demanded
    binds = {
        "a binding establishes identity and facts",
        "storage exists only where address capture mutation alias spill abi or debugging demand it",
    }
    fails = "a source binding becoming a memory slot by default"
}

semanticorder = law{
    id    = "law.order.minimum"
    kind  = .invariant
    holds = .dependency
    binds = {
        "source order becomes dependency only where observation or law requires it",
        "independent pure relations remain reorderable parallelizable and fusible",
    }
}

realizeface = law{
    id    = "law.realize.face"
    kind  = .invariant
    holds = .separate
    binds = {
        "backend branches loops blocks registers and jumps are physical realization facts",
        "they never prove source semantics and never become persistent semantic identities",
        "semantic provenance reaches every physical control edge",
    }
}

keywordpressure = law{
    id    = "law.keyword.pressure"
    kind  = .protocol
    holds = .earned
    binds = {
        "no reserved word is entitled to exist",
        "each face names the relation it projects and erases immediately",
        "ordinary relations replace reducible uses before any spelling is removed",
        "readability resolution entropy vocabulary cost and lowering quality decide retention",
        "a control or truth face survives only where the ordinary relation would materially lose clarity or performance or where the demand is irreducible",
    }
    keep  = "if while and or not remain provisional grammar faces; for is aggressively canonicalized toward iteration relations"
}

semanticgate = law{
    id    = "law.gate.semantic"
    kind  = .protocol
    holds = .ratchet
    binds = {
        "every syntax-derived compiler case is classified parser-only provenance-only physical-only irreducible or migration debt",
        "unclassified cases are zero and every zero has a positive control",
        "migration debt counts only descend and every repair lowers its exact budget",
        "the named semantic-architecture gate is part of agent-smoke",
    }
    fails = "a semantic architecture audit that reports but cannot block a merge"
}

endgate = "when semantic normalization is complete no surviving semantic kind corresponds one to one with a grammar production; every retained face is justified by resolution or human density and carries zero semantic authority"

conventional = law{
    id    = "law.audit.conventional"
    kind  = .protocol
    holds = .classified
    binds = {
        "std os fs and mem operation homes are canonical debt, not semantic namespaces",
        "operation first namespace calls are audited against subject relation world and demand roles",
        "a literal string or otherwise statically known key operand is audited for named projection or named structured content",
        "table qualified get set has new and similar names are audited for projection update establishment removal iteration or shape facts",
        "has is can exists present missing valid ready enabled supported and similar boolean helpers are audited for an existing fact case relation world transition refinement demand shape effect or identity",
        "subject first spelling does not rescue a relation whose only work is collapsing richer semantics into bool",
        "empty string and nil are never assumed to mean absence without a descriptor law",
        "an existence guard followed by a state operation is audited for an atomic relation",
        "a single use boolean feeding one conditional is audited for direct semantic consumption",
        "a single consumer temporary feeding selection is audited for direct value flow",
        "callable result demand precedes the binder; a suffix result annotation is debt",
    }
    keep  = "the audit classifies meaning before repair; it never invents replacement vocabulary from a grep"
}

semanticfirst = law{
    id    = "law.semantic.first"
    kind  = .invariant
    holds = .intent
    binds = {
        "canonical source names the irreducible semantic operation requested",
        "a conventional control storage namespace failure or representation pattern is never the starting model",
        "the chosen representation preserves the most information and the largest lawful realization set",
    }
    fails = "syntax translated from C Rust Python or Lua before subject relation cases world and demand are identified"
}

conventionzero = law{
    id    = "law.convention.zero"
    kind  = .invariant
    holds = .strongest
    binds = {
        "a weaker conventional pattern is noncanonical when an existing relation level descriptor world demand place proof or structured value preserves its observations",
        "statically known field identity uses named projection or named structured content rather than computed key syntax",
        "a genuinely computed aggregate key remains computed projection table[key]",
        "subject first relation expected descriptor direct composition semantic case and explicit world fact each beat an equally readable weaker face",
        "a semantic fact case relation transition refinement demand world effect shape or identity is never duplicated as a boolean helper",
        "true false unknown absent not applicable and unresolved remain distinct wherever the semantic domain admits them",
        "the stronger form must expose at least as much optimization freedom",
        "parsing typing and tests do not excuse canonicality debt",
    }
    fails = "weakly dynamic looking source that hides a static fact already possessed"
    keep  = "canonicality is part of correctness"
}

canonicalstate = { .canonical, .migratable, .vocabularyblocked, .invalid }

findingstate = law{
    id    = "law.canonical.state"
    kind  = .invariant
    holds = .total
    binds = {
        "canonical means the strongest admitted semantic representation is present",
        "migratable means equivalence is witnessed and canonicalization may rewrite",
        "vocabularyblocked means the required relation world case or law is absent and must be admitted before source repair",
        "invalid means the program contradicts language law",
        "these four finding states are the diagnostic projection of the role statuses in law.canonicality: role canonical is state canonical, migration only and accepted compatibility surface as migratable, vocabularyblocked maps directly, invalid roles are state invalid, and fixture foreign and implementation roles produce no canonicality finding",
        "every canonicality finding has exactly one state and no gate invents vocabulary to change it",
    }
}

canonicalfinding = @{
    id = "descriptor.canonical.finding"
    fields = {
        .span, .state, .subject, .relation, .intent, .law, .family,
        .why, .rewrite, .confidence, .world, .demand, .cases, .dnir,
        .origin, .symbol, .role, .needs, .status, .action,
    }
    rule = "diagnostics MCP LSP and generated docs project this same record; plain string findings are invalid"
    rewrite = "present only where equivalence is proven; otherwise family and missing vocabulary remain explicit"
}

canonicalpreflight = law{
    id    = "law.canonical.preflight"
    kind  = .protocol
    holds = .blocking
    binds = {
        "parse then normalize then semantic audit then corpus idiom gate then format then test",
        "precommit and CI repeat the named semantic architecture gate",
        "a canonicality finding is repaired at its authoritative semantic or vocabulary layer and is never suppressed",
    }
}

canonicalformat = law{
    id    = "law.canonical.format"
    kind  = .protocol
    holds = .proved
    binds = {
        "the formatter rewrites only equivalences admitted by a witness",
        "one consumer bridge binding removal and callable face migration require preserved provenance effects demand and observation",
        "probable semantic improvement without proof remains a structured diagnostic",
    }
}

touchedcanonical = law{
    id    = "law.canonical.touched"
    kind  = .protocol
    holds = .zero
    binds = {
        "a touched semantic region leaves no newly reachable canonicality debt",
        "safe inherited debt in that region is repaired in the same change",
        "remaining debt names its missing relation or proof owner and its canonical gap identifier",
    }
}

vocabularyaudit = law{
    id    = "law.vocabulary.audit"
    kind  = .protocol
    holds = .semantic
    binds = {
        "every distributed implementation identifies subject relation world preserved cases and demand",
        "misleading namespace sentinel and representation APIs deprecate only after their semantic replacement is admitted",
        "a standard distribution contributes implementations origin trust and evidence while the semantic graph owns vocabulary discovery optimization tooling and style facts",
    }
}

canonicaldebt = {
    "tracked noncanonical .id debt -> 0",
    "new duo duon idsem source -> 0",
    "new generated native .id source -> 0",
    "current facing idol idol idol and pass branding outside exact history -> 0",
    "stale agent router concepts and compatibility pattern sources -> 0",
    "statically knowable bracket keys and literal string projections -> 0",
    "namespace subject calls -> 0",
    "canonical relations requiring package or universal root qualification -> 0",
    "semantic decisions reconstructed from package path -> 0",
    "capability as namespace traversal -> 0",
    "statically knowable keys written as computed bracket projection -> 0",
    "literal string keys written in brackets where named projection is admitted -> 0",
    "table qualified duplicate relation names -> 0",
    "boolean helper predicates duplicating richer semantic facts -> 0",
    "single use boolean bridge bindings -> 0",
    "existence query followed by mutation where one transition is admitted -> 0",
    "unknown absent not applicable or unresolved collapsed to false -> 0",
    "ordinary values used as absence or failure sentinels -> 0",
    "existence query followed by establishable state transition -> 0",
    "single consumer bridge bindings -> 0",
    "reducible imperative iteration -> 0",
    "conditional demand used only for default projection cases or failure routing -> 0",
    "manual failure forwarding -> 0",
    "undemanded storage allocation or materialization -> 0",
    "callable result suffix -> 0",
    "representation specific operation where a semantic relation exists -> 0",
    "host pattern findings in canonical source -> 0",
}

semanticservice = law{
    id    = "law.semantic.service"
    kind  = .protocol
    holds = .one
    binds = {
        "compiler LSP MCP formatter and generated documentation query one persistent semantic graph",
        "explain canonical subject relations and why are projections of descriptor canonical finding",
        "the constitution grammar standard vocabulary and compiler manifest generate the teaching corpus",
    }
    fails = "independently handwritten examples that can contradict semantic authority"
}

boundaryzero = law{
    id    = "law.boundary.semantic"
    kind  = .invariant
    holds = .total
    binds = {
        "parser normalization graph transforms dnir realization formatter diagnostics LSP MCP documentation and agents preserve the same identities relations facts provenance and laws",
        "no boundary reconstructs meaning from a face spelling opcode namespace filename or representation",
        "every projection can answer which semantic identity and witness authorized it",
    }
}

wordone = law{
    id    = "law.word.one"
    kind  = .invariant
    holds = .everywhere
    binds = {
        "every identifier is one lowercase semantic word",
        "underscores uppercase word collisions and abbreviated multiword compounds are zero in source paths generated code semantic vocabulary diagnostics tools and documentation anchors",
        "a second axis becomes a level home relation descriptor field or separate identity rather than punctuation inside a name",
    }
}

fileone = law{
    id    = "law.file.one"
    kind  = .invariant
    holds = .concept
    binds = {
        "a file is the durable home of one semantic concept",
        "its path ownership documentation tests transforms and generated projections share that concept identity",
        "a file that becomes a miscellaneous namespace utility bucket or unrelated declaration bundle must split",
    }
    keep  = "one concept may require several relations descriptors proofs and realizations; cohesion is semantic rather than a line limit"
}

std.zero = law{
    id    = "law.std.zero"
    kind  = .protocol
    holds = .zero
    binds = {
        "STD-ZERO no semantic or canonical source std exists — std and lib paths are migration bootstrap provenance only and new canonical std semantic or source reference target equals zero",
        "the standard universe is default reachable relations descriptors laws and pure values — there is no std table prelude object import or second relation catalog",
        "canonical semantic namespace roots are zero; std core system platform runtime base idol idol os fs script process and env never own native meaning",
        "std is migration distribution and foreign provenance, never semantic architecture or authority",
        "std script is frozen historical architecture and every touched use moves toward semantic reduction and deletion",
        "standard describes origin trust and distribution while implementation location contributes zero relation identity",
        "new native semantic capability and new canonical std calls are forbidden",
        "pure activity is a subject relation and capability activity is a subject relation under a world",
        "homes navigate concepts but never substitute for a subject relation or world",
        "packages contribute relations descriptors laws worlds implementations and realizations without gaining semantic authority from their path",
        "package acquisition expands implementation candidates but grants no world and rewrites no existing semantic identity",
        "implementations satisfying one relation and law are realization candidates selected by facts demand and cost rather than differently named apis",
        "semantic discovery is a graph projection over relation subject descriptors result law world effect stage target origin and trust",
        "sealed programs erase discovery catalogs registries package traversal and runtime dispatch completely",
        "tooling begins from a possessed subject and projects applicable relations from the same graph used for documentation and realization",
        "a witnessed foreign implementation may satisfy a native relation while retaining its exact origin lawset and abi provenance",
        "process filesystem environment transport outcome and evidence remain distinct facts relations and worlds",
        "every touched std use is foreign provenance physical distribution migration bridge or semantic violation",
        "every migration bridge names its semantic reason authoritative replacement owner and exact deletion gate",
        "removal may not create another universal semantic root or a slower boxed allocated or dynamically dispatched abstraction",
        "every admitted replacement lowers namespace dependence and removes the misleading entry point",
    }
    keep  = "physical std source may remain only as migration distribution foreign provenance or compiler b bootstrap debt; it contributes no semantic identity world authority or canonical invocation"
    fails = "finishing std replacing it with another universal root or selecting meaning from implementation location"
}

# Conventional source to semantic reduction, recorded without blessing a
# replacement spelling. The environment/default vocabulary remains OPEN: the
# relation family must be derived before a canonical name is assigned.
budgetreduction = @{
    denied = "namespace environment lookup followed by empty-string sentinel temporary branch and conversion"
    graph = {
        "environment world is authority",
        "name is the lookup key subject",
        "lookup yields absent or present(value), preserving present empty-string",
        "present value flows through to(i64)",
        "absent flows to fallback",
        "selection is value demand, not a conditional semantic kind",
    }
    dnir = "current deficiency: namespace call, empty sentinel, temporary and branch survive because absence and default facts were erased"
    target = "open vocabulary audit: assign no spelling until lookup presence conversion and default reduce to the smallest existing relation family"
    machine = "runtime: lookup presence test then parse or fallback; build-stage known name and environment may fold to one integer constant"
}

# ═══ §66 · AUTHORITY, SUBJECT AND STANDARD VOCABULARY CLOSURE ══════════════
#
# A home may locate a meaning. It can never grant permission to observe or
# change a world. This is graph law, not a deny list for particular spellings:
# renaming a home must not alter the verdict.

authorityhome = law{
    id    = "law.authority.home"
    kind  = .invariant
    holds = .never
    binds = {
        "homes packages and paths navigate or select exact identities and establish none",
        "filesystem environment process network clock random terminal hardware deployment and service authority exist only as world edges",
        "an effectful application is valid only when every required world is semantically reachable",
        "home reachability contributes zero world authority",
    }
    fails = "navigation used as permission"
}

homeaction = law{
    id    = "law.home.action"
    kind  = .invariant
    holds = .none
    binds = {
        "a home may contain descriptors relations cases constants and semantic data",
        "a home supplies ambient descriptor context per law.home.context",
        "selecting an entity through a home performs no activity",
        "an action reached through navigation still requires its subject relation effects and worlds",
    }
}

subjectone = law{
    id    = "law.subject.one"
    kind  = .invariant
    holds = .role
    binds = {
        "every application with a meaningful semantic subject records exactly one subject role",
        "when that value is possessed and the relation is subject callable the canonical face is subject first per law.subject.resolve",
        "operation first application of its own first meaningful argument is noncanonical independent of home spelling",
        "the verdict follows relation identity and parameter roles rather than text",
    }
}

environmentone = law{
    id    = "law.environment.one"
    kind  = .invariant
    holds = .proved
    binds = {
        "environment access has one semantic owner",
        "the key or name is the subject and the environment is required world authority",
        "the outcome preserves absent present empty and present nonempty as distinct semantic cases",
        "foreign symbol names and package paths do not become native relations",
        "the admitted face is the os.env[key] computed projection per law.host, and absence stays a distinct runtime fact rather than an empty string",
    }
    keep = "gate/gap-118-env-absence.sh executes the three-outcome proof; GAP-118 records the admission and the deleted erasing wrapper"
}

sentinelzero = law{
    id    = "law.sentinel.zero"
    kind  = .invariant
    holds = .cases
    binds = {
        "an ordinary domain value never silently replaces a known presence failure or validity case",
        "empty minus one zero nil and false retain their ordinary meanings unless the descriptor law explicitly says otherwise",
        "true false unknown absent not applicable and unresolved are never collapsed into one boolean domain",
        "presence absence failure removal and uninitialized state are semantic cases rather than sentinel comparisons or predicates",
        "a physical realization may exploit a niche or sentinel only while semantic cases remain recoverable",
    }
}

foreignname = law{
    id    = "law.foreign.name"
    kind  = .invariant
    holds = .provenance
    binds = {
        "a foreign api retains origin symbol lawset abi effects failure ownership uncertainty and world requirements",
        "a foreign symbol enters native vocabulary only through a witnessed semantic equivalence",
        "physical convergence never erases foreign semantic diversity prematurely",
    }
}

stdlibshadow = law{
    id    = "law.std.shadow"
    kind  = .protocol
    holds = .zero
    binds = {
        "every distributed implementation declares relation identity subject role descriptor constraints worlds effects cases realization freedoms and foreign provenance",
        "a wrapper duplicating an existing relation under a package or subsystem home is rejected",
        "a package namespace carrying authority a subject hidden as its argument a collapsed case forced materialization or foreign name disguised as native semantics is rejected",
        "admitted vocabulary and implementation candidates compose across native wasm and compatible foreign lawsets independently of distribution path",
    }
}

vocabclosed = law{
    id    = "law.vocab.closed"
    kind  = .protocol
    holds = .admitted
    binds = {
        "agents never invent public standard vocabulary locally",
        "agents never invent a boolean predicate when the missing owner is a fact case relation transition refinement demand world effect shape or identity",
        "relation admission returns existing derivable new foreign or vocabularyblocked",
        "new is accepted only when an independent semantic distinction remains after relation level fact descriptor place world origin abi and target factoring",
        "vocabularyblocked is preferable to a plausible helper without authority",
    }
}

worldgate = law{
    id    = "law.gate.world"
    kind  = .protocol
    holds = .semantic
    binds = {
        "for every effectful application required worlds are a subset of semantically reachable worlds",
        "homes contribute no authority",
        "the positive control uses a legal arbitrary home and still fails for the absent environment world",
    }
}

subjectgate = law{
    id    = "law.gate.subject"
    kind  = .protocol
    holds = .identity
    binds = {
        "resolve relation identity subject role and actual value occupying that role",
        "reject an operation first home application when that value supports the canonical subject call",
        "renaming the home never changes the result",
    }
}

vocabgate = law{
    id    = "law.gate.vocab"
    kind  = .protocol
    holds = .identity
    binds = {
        "every public standard compiler shell MCP generated and documented operation resolves to one admitted relation identity",
        "duplicate names recoverable qualifiers and raw foreign symbols are rejected",
    }
}

worldnamegate = law{
    id    = "law.gate.worldname"
    kind  = .protocol
    holds = .semantic
    binds = {
        "audit resolved standard exports rather than source strings",
        "semantic homes remain legal and capability homes remain powerless",
        "a home rename is required to preserve every verdict",
    }
}

sentinelgate = law{
    id    = "law.gate.sentinel"
    kind  = .protocol
    holds = .flow
    binds = {
        "follow an external or capability result into literal comparison and conditional demand",
        "diagnose when its contract already carries the semantic case represented by that literal",
        "the literal spelling is irrelevant",
    }
}

controlreduce = law{
    id    = "law.gate.controlreduce"
    kind  = .protocol
    holds = .proved
    binds = {
        "audit conditional demand for default projection failure routing state establishment finite dispatch and iteration filtering",
        "separate observation from action and replace query bool branch mutation with one admitted transition where equivalent",
        "a predicate that only controls one branch yields to direct consumption of its underlying fact case or relation",
        "reject only when an admitted relation is observationally equivalent and at least as optimizable",
        "irreducible conditional demand remains canonical",
    }
}

corpuszero = law{
    id    = "law.corpus.zero"
    kind  = .protocol
    holds = .semantic
    binds = {
        "semantic canonicality runs over every tracked source and generated canonical example",
        "canonical project owned source uses the .id extension and new canonical .id is admitted",
        "new duo duon and idsem source fails immediately",
        "tracked noncanonical .id debt descends to zero",
        "current examples tools compiler source and generated native source use canonical id",
        "foreign import support does not justify an in tree historical source library or a native compatibility mode",
        "a blind search adversary must find canonical id or unmistakable foreign data rather than a stale implementation pattern",
        "namespace world subject sentinel duplicate relation foreign name conditional bridge and result debt only descend to zero",
        "text censuses may guard migration spelling but never claim semantic proof",
    }
}

legacyzero = law{
    id    = "law.legacy.zero"
    kind  = .protocol
    holds = .zero
    binds = {
        "native compilation recognizes canonical id only and has no idol idol lua or historical syntax mode",
        "retired duo duon idsem suffix recognition lua lexical forms historical directives old callable forms std namespace semantics and implicit boxed fallbacks descend to zero",
        "a still required historical behavior is first preserved as an explicit foreign lawset obligation then reimplemented through the shared id facts demand and realization architecture before the legacy carrier is deleted",
        "old or unmerged work is audited and corrected against current main rather than merged wholesale or deleted while its valid obligation remains unsatisfied",
        "foreign conformance input is generated structured external or mechanically unmistakable and never becomes searchable native training material",
        "one resolved native meaning reaches a lawful realization or diagnoses and never falls through to c boxed or lua semantic interpretation",
    }
    fails = "a native compatibility branch implicit semantic fallback stale pattern archive or deletion that recreates already solved work"
}

generatedzero = law{
    id    = "law.generated.zero"
    kind  = .invariant
    holds = .author
    binds = {
        "generated canonicality debt is repaired at the generator",
        "a generator emitting native .id source is a hard failure",
        "generated output receives no whitelist",
    }
}

touchzero = law{
    id    = "law.touch.zero"
    kind  = .protocol
    holds = .owned
    binds = {
        "a touched semantic region leaves mechanically repairable canonical debt at zero",
        "remaining debt records vocabularyblocked implementationblocked or migrationblocked with exact owned identity, any required correspondence and rationale",
        "existing code is never a justification",
    }
}

commitzero = law{
    id    = "law.commit.zero"
    kind  = .protocol
    holds = .same
    binds = {
        "precommit parses normalizes resolves identities infers subject roles resolves worlds audits canonicality formats safe equivalences checks ratchets and tests",
        "CI executes the same semantic gate",
        "no agent override exists",
    }
}

authorityfinding = @{
    relation = "foreign symbol awaiting canonical relation admission"
    subject = "resolved value occupying the semantic subject role"
    authority = "required and reachable worlds"
    form = "observed application projection"
    laws = { "law.authority.home", "law.subject.one", "law.vocab.closed" }
    status = .vocabularyblocked
    action = "finalize or use the admitted relation; never invent a replacement helper"
}

authorityinvariant = law{
    id    = "law.authority.rename"
    kind  = .invariant
    holds = .stable
    binds = {
        "changing an arbitrary namespace home or package spelling never changes canonicality",
        "canonicality follows subject relation world descriptor lawset demand and provenance",
    }
}

# ═══ §67 · IDOL ALGEBRA CLOSURE ════════════════════════════════════════════
#
# Sole constitutional authority for home, subject, world, protocol, witness,
# injection, projection, union, standard reachability, shell/run/outcome,
# binding census, and completion metrics. Fully reconciled here — not an
# independent prompt, harness injection, chat paste, or parallel rule list.
# Historical prompts titled "algebra closure" are void where they duplicate or
# conflict with this section. The language is **Idol** (`idol`, `.id`).
#
# Repository authority overrides stale implementation details. Every native surface
# reduces to the semantic universe below or proves an irreducible distinction
# before a new word.
#
# Projection algebra: every application resolves from relation × subject × operand
# pack × descriptor facts × law × available world × protocol constraints ×
# witnesses × result demand → checked application. There is no privileged std
# dispatch path and no hidden std.x.y.z(...) behind canonical source.
#
# Projection after resolution is ordinary binding home relation world anchor and
# witness facts only (law.projection). Witness proves protocol satisfaction
# (law.protocol.satisfy) and documents inferred injection (law.inject.algebra).
# Enforcement adversarial controls: law.gate.protocol and law.gate.algebra.
# Protocol closure: law.protocol.one · law.constraint.protocol · law.specialize.algebra.
# Projection closure: law.projection.one · law.projection.pack · law.from.zero ·
# law.std.zero · law.lib.zero · law.boolean.mirror.zero · law.catalog.zero · law.magic.zero · law.schema.one ·
# law.main.zero · law.action.zero · law.foundation.zero · law.evidence.subject · law.oracle.bound ·
# law.family.one · law.representation.one · law.guard.one · law.specialize.budget ·
# law.abi.internal · law.crash.first · law.cost.explain · law.error.cold ·
# law.application.consumer · law.fact.locality · law.grammar.one · law.control.derived ·
# law.tag.authority · law.module.zero · law.fact.cardinality · law.application.closure ·
# law.ast.backedge · law.fact.column · law.graph.sovereignty · law.target.contamination ·
# law.prose.fact · law.demand.occurrence · law.derived.index · law.view.zerocopy ·
# law.world.one · law.home.projection ·
# law.shell.not.world · law.cross.one · law.conversion.derive · law.conversion.decl ·
# law.gate.projection.
# Inference closure: law.infer.one · law.source.minimum · law.direct.bridge.one · law.gate.infer · law.intermediate.zero.
# Meta-invariants (one-system SHC): law.bridge.death · law.fallback.zero · law.fact.producer.one ·
# law.unknown.one · law.ownership.zero · law.effect.order · law.profile.evidence ·
# law.incremental.semantic · law.canonical.semantic · law.infer.contract · law.world.capability ·
# law.closure.semantic · law.shc.scheduler · law.delta.budget · law.coordination.fact ·
# law.representation.demand · law.representation.one · law.guard.one · law.specialize.budget ·
# law.abi.internal · law.error.cold · law.crash.first · law.cost.explain ·
# law.application.consumer · law.fact.locality · law.grammar.one · law.control.derived ·
# law.tag.authority · law.module.zero · law.fact.cardinality · law.application.closure ·
# law.ast.backedge · law.fact.column · law.graph.sovereignty · law.target.contamination ·
# law.prose.fact · law.demand.occurrence · law.derived.index · law.view.zerocopy ·
# law.gate.convergence.
# Machine realization closure: law.realization.late · law.alias.provenance · law.buffer.demand ·
# law.vector.one · law.realization.valid · law.lower.bound · law.link.semantic.
# FTCFTW dominance closure: law.ftcftw.dominance · law.optimization.open · law.cost.closure ·
# law.algorithm.realization · law.optimization.validated.
# Physical realization closure: law.physical.open · law.observation.minimum.
# Square-zero foundational closure: law.observation.one (folds BOUNDARY-ONE and
# physical-nonexistence none) · law.equivalence.observation · law.demand.derivative ·
# law.relation.property · law.change.delta · law.uncertainty.algebra · law.optimizer.economy ·
# law.optimization.space (OPTIMIZATION-SPACE-COMPLETE — the whole R(S,W,T,E,P) frontier) ·
# law.realization.contract (REALIZATION-CONTRACT — satisfy a semantic observation contract at the
# cheapest verified physical point; ~24 axes; physical lower bounds; lawful nonexecution).
# law.obligation.one (OBLIGATION-ONE — semantics is allowed observations + required obligations,
# incl. negative/temporal/liveness/safety/progress/fairness/causality/noninterference and
# hyperproperties over sets of executions) · law.realization.universe (NINE-UNIVERSE — the
# structural, non-enumerative closure: meaning/observation/knowledge/demand/equivalence/
# realization/resource/search+proof/change, the supreme R equation, monotonic frontier,
# value-of-information, contract-weakening debt, and the measurable optimality gap).
# Anti-drift: law.source.not.proof · law.repair.class · law.doc.teaching · law.projection.pack · law.identity.projection · law.projection.absolute · law.projection.repair.

semanticuniverse = law{
    id    = "law.semantic.universe"
    kind  = .invariant
    holds = .one
    binds = {
        "native idol has one semantic universe",
        "every native surface reduces to some composition of admitted concepts or proves irreducibility before a new word",
        "admitted concepts are id relation subject value pack binding descriptor shape place world effect demand law origin stage witness provenance realization token role span view run outcome evidence",
        "do not preserve conventional api design merely because it is familiar",
        "the standard library is not an object hierarchy",
        "the filesystem process math string and table are not semantic namespaces",
        "a protocol is not an interface kingdom",
        "a union is not a boxed sum type by default",
        "a world is not an object passed around merely to simulate capability",
    }
    fails = "a second semantic ontology or namespace kingdom standing in for facts"
}

application.algebra = law{
    id    = "law.application.algebra"
    kind  = .invariant
    holds = .checked
    binds = {
        "every application resolves algebraically from relation times subject times operand pack times descriptor facts times law times available world times protocol constraints times witnesses times result demand to checked application",
        "a standard operation is an admitted relation projected into a context where its requirements can be satisfied",
        "there is no privileged standard dispatch path and no hidden std.x.y.z behind canonical source",
    }
    fails = "privileged std dispatch or unchecked application without relation subject world and demand facts"
}

application.one = law{
    id    = "law.application.one"
    kind  = .invariant
    holds = .one
    binds = {
        "APPLICATION-ONE every value(args) is one application algebra — no function-call table-lookup accessor indexing method-call generic-call protocol-call or builtin-call kingdom; f(x) descriptor(value) world(value) closure(x) foreign(x) all begin as one question given applied value operand pack current world and result demand what exact lawful application exists; computed aggregate access table[key] is projection and never application",
        "resolution MAY use only applied value identity operand identities and facts operand pack shape result demand descriptor facts table shape relation facts current world authority and witness facts stage control-flow refinements known metatable facts and target-independent semantic facts",
        "resolution MUST NOT use callee spelling file path source category ast node kind looks-like-a-function looks-like-a-table declaration order fallback priority nearest namespace or registry order",
        "resolution output is exactly one application fact — application id applied identity relation id only when semantically meaningful subject id only when semantically oriented operand pack result pack descriptor constraints effect authority requirement witness stage demand provenance — realization chooses physical behavior only afterward",
        "resolution ladder collects exact facts enumerates lawful applications eliminates impossible candidates projects implied relation descriptor conversion able witness world-fact result-pack and stage then publishes exactly one candidate rejects zero and fails AMBIGUITY on more than one incomparable candidate before any realization",
        "ambiguity is fail-closed — never resolve by first or nearest declaration most-recently-injected function-before-table table-before-relation or more-specific unless specificity is mathematically defined",
        "table[key] is computed projection — read versus write is chosen by demand not a different operation x = table[key] demands a value table[key] = value demands a place with no setter ontology and no get set relation invented merely for uniformity; application table(key) applies the value and never indexes it",
        "static . application () and projection [] assert different author knowledge and stay distinct source faces user.name is one statically known structural projection user[key] is computed projection — . is never computed a runtime aggregate key uses table[key] and ordinal row[1] is projection not application",
        "colon is source subject orientation only — after resolution it is still an application with subject relation and operands never a methodcall or membercall graph kind",
        "currying is not automatic add(1)(2) is ordinary chained application whose first application yields a callable — partial application specializes only where the relation or application descriptor admits it or a known callable value returns another applicable value",
        "metatable and __call resolve ONCE — the resolver publishes the exact lawful application and the backend never runs try-function-else-table-else-__call priority code sealed metatable gives dynamic dispatch zero and a still-dynamic metatable keeps runtime dispatch because semantic alternatives remain",
        "operators and conversion are application sugar a + b resolves to the arithmetic relation application and value:to(str) is explicit relation application only when the target is not inferable — grammar owns punctuation precedence the resolver owns meaning and lowering consumes the complete resolved application never reconstructing a fact from spelling ast host types or table/function category",
        "cost falls monotonically with knowledge dynamic table and key to generic lookup known shape and exact key to direct field offset sealed table and exact demanded field to scalar replacement constant to no table at runtime — the source form is identical throughout",
    }
    canon = { "f(x)", "table[key]", "table[key] = value", "user.name", "add(1)(2)", "text:find(pattern)", "a + b" }
    deny  = { "table(key) as aggregate indexing", "table:get(key)", "get(table, key)", "table:set(key, value)", "f:call(x)", "MethodCall", "member_call", "CoercionKind", "function-before-table precedence" }
    fails = "a table-call function-call accessor method-call indexing or conversion kingdom; precedence or fallback resolution; automatic currying; or lowering that reconstructs facts from spelling ast host types or category"
}

world.closed = law{
    id    = "law.world.closed"
    kind  = .invariant
    holds = .checked
    binds = {
        "WORLD-CLOSED a derived world @{ k = v } is closed at formation — it contains its inherited facts semantically at derivation with project(inject(w,k=v),k)=v and project(inject(w,k=v),q)=project(w,q) for every untouched q",
        "resolution under a derived world uses its exact facts only — never lookup-in-derived then fall back to parent and never a nearest-world or reachable-world search even when the physical implementation uses structural sharing",
        "world qualification thing@world changes the closed fact set for the evaluated subtree only and threads that world through unresolved ambient dependencies with no runtime world argument leaving the caller world unchanged",
        "this closure forbids DI-style runtime parent-world fallback architecture — when the world is statically known realization keeps world object 0 lookup 0 dispatch 0",
    }
    fails = "a runtime parent-world fallback nearest-world search or reachable-world lookup instead of the closed derived-world fact set"
}

projectionone = law{
    id    = "law.projection.one"
    kind  = .invariant
    holds = .one
    binds = {
        "PROJECTION-ONE idol has one projection algebra — do not implement separate systems for conversion protocol generic specialization home lookup standard library world injection shell foreign projection descriptor coercion call specialization hardware selection or staging",
        "all are combinations of ordinary semantic facts resolved to relation projection facts subject operand pack result demand descriptor facts law world requirements world witnesses effect stage origin provenance demand — physical realization comes later",
        "projection means known semantic facts plus demanded semantic facts yield uniquely resolved semantic specialization — not namespace lookup module lookup method lookup generic instantiation object runtime dictionary function returning function world object plumbing or string key dispatch",
        "projection fact sources include explicit source projection subject descriptor expected binding descriptor parameter descriptor result descriptor field descriptor relation declaration protocol relation constraint union refinement home context world context stage target foreign boundary law and abi semantic contract — source spelling is one input only",
        "canonical source spells only facts the compiler cannot uniquely recover with preference implicit relation plus implicit projection then explicit relation plus implicit projection then explicit relation plus explicit projection where shorter form resolves identically",
        "every application preserves one normalized projection fact set — conversion protocol world home and generic projection are not independent semantic structures projection is a role not a new semantic kind",
        "relation projection to(str) = (value) and read(number) = (stream buffer) declare relation projection pack subject and operands — projection group is not an application and no intermediate callable exists",
        "inferred relation projection value:to(str) may reduce to value when relation and target uniquely inferable — graph still records inferred application syntax disappearance does not erase semantics — value:to() is not a canonical rung because if relation is explicit and target uniquely inferable spelling to adds no information",
        "satisfaction conversion and realization remain distinct — satisfaction needs no to conversion is semantic relation with graph application source may omit realization is machine abi representation never semantic to",
        "exact integer n i32 = 5 is descriptor specialization not default i64 followed by to(i32)",
        "to is the one canonical conversion relation orientation — from does not receive independent relation id implementation registry trie protocol or conversion graph — from migration face normalizes to value:to(target) with source descriptor witnessed as source",
        "derived conversion may compose source to canonical to target only when bounded admitted algebra proves one normalized witnessed edge preserving meet of conversion laws — no arbitrary path search declaration order tie breaking or whole graph search",
        "protocol constraints are relation projections requiring unknown subject admit projected relation shape — no readable writable convertible hashable callable native identities",
        "protocol witness is proof not interface dictionary vtable or runtime protocol token unless reflection heterogeneity demands representation — static constraints permit zero runtime witness bytes",
        "home hierarchy supplies reachability context and provenance not runtime namespace chains — compiler.parser.parse is not semantic relation identity hierarchy elision preferred when lookup context uniquely determines binding",
        "world grants authority not intent — unique compatible grant injects witness source need not name world — world availability never chooses conversion parser relation or target descriptor",
        "shell is interpretation law process is authority command is semantic value — shell is not automatically the authority world",
        "cross boundary projection adds origin law world abi provenance witness realization constraints — identity persists cross one requires explicit witness never map by same name path field spelling method name or binary layout alone",
        "implied projection ladder is direct satisfaction infer relation and projection explicit relation inferred projection value:to(str) explicit operands — minimal syntax demands maximal explainability in tooling — value:to() is not a canonical rung because if relation is explicit and target uniquely inferable spelling to adds no information",
        "no spooky inference — implicit insertion only when demanded slot and supplied value define exactly one admitted bridge witness — constraint solving is not program synthesis",
        "relation algebra coherence prefers uniquely more specific candidate by semantic facts — incomparable means AMBIGUOUS uniformly for conversion protocol world shape hardware and stage specialization",
        "resolver determines relation projection role subject operand role result demand world requirement — parser preserves structure dnir consumes graph ids and facts missing projection fact fails closed",
        "parser must not produce semantic ast kinds methodcall projectedcall genericcall protocolcall worldcall curriedcall — dnir must not recover meaning from callee string nested call shape home path std lib prefix method flag or type name",
        "conversion trie and indexes are acceleration not semantic authority — hardcoded literal to checks in codegen are host projection debt with accelerated deletion gate",
        "one resolver projection mechanism serves conversion relation specialization constraint satisfaction world satisfaction home context resolution foreign projection and stage target specialization for compiler b",
    }
    canon = {
        "value",
        "value:to(str)",
        "file = path:open()",
        "consume = (source) source:read()",
        "copy = (source sink) sink:write(source:read())",
        "command:run()",
        "stdout:write(text)",
        "args(1)",
        "env(\"KEY\")",
    }
    deny  = {
        "std.foo", "lib.foo", "lib.process", "process = lib.process",
        "process.run", "process.capture", "process.exit",
        "io:open(path)", "os.args()", "compiler.parser.parse",
        "readable", "writable", "ProjectedCall", "ConversionProjection",
        "inch:from(foot)(value) as canonical native face",
    }
    fails = "separate projection subsystems namespace method protocol adjective or host string comparison as semantic authority"
}

fromzero = law{
    id    = "law.from.zero"
    kind  = .orientation
    holds = .orientation
    binds = {
        "FROM-ZERO canonical native source eliminates from when it merely reverses conversion orientation",
        "target:from(source)(value) normalizes to value:to(target) with source descriptor witnessed — no second application relation or edge",
        "inch from foot style examples are migration teaching debt unless explicitly classified historical",
        "if future from meaning is independently irreducible it must pass relation admission separately not for symmetry",
        "preferred destination architecture is descriptor home specialization with ambient subject descriptor supplying source descriptor",
    }
    fails = "second conversion universe or inverse from relation id beside to"
}

libzero = law{
    id    = "law.lib.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "LIB-ZERO lib is not a native semantic root — process = lib.process is import traversal disguised as assignment and is noncanonical",
        "physical repository directory lib may exist during bootstrap as provenance only — canonical source never traverses it",
        "if tooling cannot reach binding without lib hop report SOURCE-PROJECTION-BLOCKED and fix reachability not canonize workaround",
        "do not repair lib.process into process = process or another root alias — delete source loader namespace dependency",
    }
    fails = "lib.foo canonical source lookup or lib alias preserving module ontology"
}

booleanmirror = law{
    id    = "law.boolean.mirror.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "BOOLEAN-MIRROR-ZERO do not store a boolean flag that merely restates a structural graph fact",
        "subject edge exists — never possessed = true or has_subject",
        "witness edge exists — never authorized = true",
        "capture edge exists — never captured = true",
        "descriptor edge exists — never typed = true",
        "application is applied or it is not — never callable = true",
        "graph participation answers what an identity is — never operation = true or operation = false",
        "also reject typed authorized captured projected resolved imported native static when the underlying fact is already an edge or role",
        "absence of the fact is the answer — never world = empty string world = nil world = none world = false as sentinels",
    }
    fails = "boolean or string field mirroring subject witness capture descriptor application or world-requirement structure"
}

catalogzero = law{
    id    = "law.catalog.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "CATALOG-ZERO do not create a table whose primary purpose is to enumerate relations descriptors worlds formats handlers operations or capabilities",
        "if the items already have identities and facts in the graph the catalog is a second authority and must be deleted",
        "relation facts come from resolution — not rows with world string and boolean mirrors",
        "authority comes from world or witness facts on the application — not relation→world category tables",
        "json is a format or descriptor not an authority-bearing world",
        "do not rename a catalog to preserve it — seq to sequence keeps the architecture",
        "examples of deleted second authorities: seq relation catalog semantic/io semantic/fs encoding catalog builtin catalog directive catalog producer relation ledger",
        "get and set are not registered relations unless a domain independently has those verbs — computed aggregate access is table[key] and table[key] = value",
        "from is deleted when it only reverses to — conversion orients on source",
        "derive compose project realize are not user relations merely because the compiler uses those words internally",
    }
    fails = "hand-authored relation world or capability registry consulted as semantic authority"
}

magiczero = law{
    id    = "law.magic.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "MAGIC-CODE-ZERO do not reconstruct semantic identity from a numeric code ordinal opcode sentinel or foreign status number",
        "the producer already knows the rejection kind role or outcome — the consumer must not switch on minus 101 or enumFromInt",
        "forbidden reconstructions include negative status to diagnostic lexErrorFromCode enum ordinal to host enum tokenKindFromOrdinal opcode to relation and shell status text to run outcome",
        "carry rejection-id token-role-id or outcome fact across the seam — never a second host taxonomy that happens to agree today",
    }
    fails = "host switch ordinal map or sentinel integer standing in for producer identity"
}

schemaone = law{
    id    = "law.schema.one"
    kind  = .invariant
    holds = .one
    binds = {
        "SCHEMA-ONE one producer per record law — host RECORD_SLOTS and positional field decode are a second schema",
        "Idol lexer to magic array of seven i64 to Zig slot meanings is reconstruction — the producer projects the record the consumer reads that projection",
        "prefer an immutable semantic token view whose fields are carried directly so the host does not rematerialize tokens",
        "duo_lexer_tokenize_full duo_lexer_error_line and useDuoTokens are bridge-death names not permanent production symbols",
        "deletion condition is producer-projected record plus rejection-id plus token-role-id with no host slot map",
    }
    fails = "manually authored consumer schema or positional ABI as semantic knowledge"
}

mainzero = law{
    id    = "law.main.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "MAIN-ZERO root body executes and the tail expression is the result — never main i64 wrapping another routine",
        "tooling census gates and ledgers are not exempt — root execution remains root execution",
        "file-scope result or a named step that is the actual semantic subject — never a ceremonial main",
    }
    fails = "main wrapper around an already-complete file body"
}

actionzero = law{
    id    = "law.action.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "GENERIC-ACTION-ZERO generic orchestration verbs run execute process apply perform handle require an actual semantic subject and relation",
        "command run is legitimate because process execution is the relation — run i64 equals empty as a tool starter is not",
        "a root routine must not be named merely to mean start this tool",
    }
    fails = "generic run execute process apply perform or handle with no semantic subject"
}

foundationzero = law{
    id    = "law.foundation.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "FOUNDATIONAL-WORD-COLLISION-ZERO do not use foundational semantic words as generic helpers",
        "forbidden helper names unless the value genuinely is that concept: apply project realize resolve bind demand witness relation subject world shape descriptor",
        "apply already means application algebra — a census helper must not steal it",
        "this is distinct from machinery collision-zero router gateway registry — those are role nouns this is vocabulary dilution of the semantic universe",
    }
    fails = "foundational semantic word used as an arbitrary helper"
}

evidencesubject = law{
    id    = "law.evidence.subject"
    kind  = .invariant
    holds = .one
    binds = {
        "EVIDENCE-SUBJECT-ONE evidence identity and measured-program identity are separate facts",
        "a measurement commit must name subject revision and evidence revision",
        "do not report metrics at HEAD unless the measured subject equals HEAD",
        "executed frontier lives in docs/bootstrap.md metrics interpretation in docs/METRICS.md revision-bound evidence in a generated artifact — other reports are snapshots",
    }
    fails = "evidence commit treated as implementation HEAD or metrics reported at HEAD for a prior subject"
}

oraclebound = law{
    id    = "law.oracle.bound"
    kind  = .invariant
    holds = .bound
    binds = {
        "a differential oracle covers the legacy-equivalent subset only",
        "Idol law is the constitution and the canonical lexer — when Idol intentionally diverges the host scanner must not veto the new behavior",
        "tokenizeHost remains differential-only and deletable under law.bridge.death — it must not become de facto semantic authority because every change is required to match it",
    }
    fails = "host differential vetoing intentional Idol lexical law or surviving as undeletable authority"
}

familyone = law{
    id    = "law.family.one"
    kind  = .invariant
    holds = .one
    binds = {
        "SOURCE-FAMILY-ONE path suffix is provenance only",
        "one ingress authority produces the source-family fact — later stages consume that fact",
        "forbidden reconstructions include endsWith .id is_canonical_source(path) and suffix bytes deciding lexical law",
        "deletion is family as an operand into tokenize — not recovered from the filename",
    }
    fails = "path or suffix standing in for source-family authority"
}

representationone = law{
    id    = "law.representation.one"
    kind  = .invariant
    holds = .one
    binds = {
        "REPRESENTATION-ONE a semantic value has no physical representation until realization demand requires one",
        "one realization decision owns width layout location boxing addressability aggregation and calling convention",
        "no downstream pass separately decides boxed stack register heap struct or SIMD",
        "FTCFTW is not a sequence of representation repairs — law.representation.demand still requires each remaining structure to name its observation",
    }
    fails = "a second pass choosing physical representation after realization already decided"
}

specializebudget = law{
    id    = "law.specialize.budget"
    kind  = .invariant
    holds = .budget
    binds = {
        "SPECIALIZE-WHEN expected runtime gain exceeds compile cost plus code size plus I-cache pressure plus startup cost",
        "same semantic id may have multiple realizations only when that inequality holds — clones are not new semantic identities",
        "each specialization records applications benefiting branches removed allocations removed indirects removed bytes added compile-time added",
        "perf.worth and law.perf.merge remain the merge and skip answers",
    }
    fails = "greedy specialization that explodes compile time object size I-cache or startup without a worth record"
}

guardone = law{
    id    = "law.guard.one"
    kind  = .invariant
    holds = .alternative
    binds = {
        "a guard is an unresolved semantic alternative whose fast realization depends on a fact",
        "not an optimizer artifact a type-check object a generic runtime check or a reason to box everything",
        "fact known means guard zero — fact speculated from evidence means exact guard plus exact slow alternative — fact unknown means the appropriate general realization",
        "every guard retains the assumed fact witness or evidence recovery realization and provenance",
        "law.proof.epoch still owns region lifetime of a proven fact — law.profile.evidence still forbids promoting observation to truth",
    }
    fails = "guard as pass artifact or speculative fast path without fact witness recovery and provenance"
}

abiinternal = law{
    id    = "law.abi.internal"
    kind  = .invariant
    holds = .boundary
    binds = {
        "semantic pack lowers to demanded physical slots then target abi assignment",
        "known internal calls use an optimized internal abi — foreign abi only at an actual foreign boundary",
        "register returns register arguments aggregate elision no tuple materialization no unnecessary sret no temporary pack and tail-call compatibility are realization objectives",
        "a generic external abi between every internal function is a cost without a demand",
        "law.abi.demand remains the derivation rule — this law forbids applying a foreign calling convention where no foreign boundary exists",
    }
    fails = "internal calls forced through a foreign or generic abi without a boundary fact"
}

errorcold = law{
    id    = "law.error.cold"
    kind  = .invariant
    holds = .path
    binds = {
        "rare failure possibility must not automatically force a boxed result tagged union heap object or branch on every operation",
        "use a cold continuation or separate error path where lawful",
        "hot representation remains the success realization — failure does not choose the hot layout",
    }
    fails = "Result-style or tagged lowering that poisons the hot path because failure is possible"
}

crashfirst = law{
    id    = "law.crash.first"
    kind  = .invariant
    holds = .severity
    binds = {
        "crash is worse than a wrong diagnostic which is worse than rejecting a valid program which is worse than an optimization miss",
        "every crash is an immediate correctness blocker — performance work on an unstable backend is not evidence",
        "backend refusal must name application id missing fact or capability consumer and expected producer — never an opaque unsupported category",
    }
    fails = "crash treated as an ordinary fail or bail without causal missing-fact identity"
}

costexplain = law{
    id    = "law.cost.explain"
    kind  = .invariant
    holds = .causality
    binds = {
        "every remaining box allocation indirect copy hash tag or bounds check names the unresolved semantic fact that forces it",
        "no causal explanation is a performance bug not an acceptable default",
        "tooling queries the graph for that fact — it does not reconstruct the reason from generated text",
        "every compiler refusal names the semantic entity or application the missing fact the expected producer and the consumer — parser resolver world descriptor realization specialization and vectorization included not only backend DNB",
    }
    fails = "physical cost without a named missing fact"
}

applicationconsumer = law{
    id    = "law.application.consumer"
    kind  = .invariant
    holds = .zero
    binds = {
        "APPLICATION-CONSUMER-ZERO lowering and later stages consume application facts from the graph they do not reconstruct them",
        "forbidden independent derivation includes subject operand identity result identity descriptor effect world requirement witness demand and target",
        "consuming ApplicationFact.relation from the graph while reconstructing adjacent fields from AST host types or callee text is partial transfer not closure",
        "downstream reconstructed application facts target zero — audit every field used in DNIR and native lowering for provenance",
        "the graph entity is identity — no three-coordinate identity record and no synthetic application schema beside the graph",
    }
    fails = "downstream reconstruction of an application fact the graph already owns or a coordinate identity standing in for the graph entity"
}

factlocality = law{
    id    = "law.fact.locality"
    kind  = .invariant
    holds = .compact
    binds = {
        "FACT-LOCALITY-ONE the graph remains the authority while frequently consumed facts are stored in compact application-local ranges or dense-id tables",
        "after an application is resolved do not re-query it through global hash maps or repeated edge scans on every lowering instruction",
        "semantic correctness must not create compile-time query overhead — expose a derived physical view do not copy meaning out of the graph",
    }
    fails = "per-instruction global graph lookup as the hot compile path or a second meaning store beside the graph"
}

realizationlate = law{
    id    = "law.realization.late"
    kind  = .invariant
    holds = .late
    binds = {
        "REALIZATION-LATE semantic identity persists to the final machine decision — representation is chosen once as late as profitable from exact demand effects alias shape world and target",
        "there is no irreversible semantic cliff between the application graph and machine code — a conventional selection scheduling machine-ssa allocation and emission staging that discards meaning before the machine decision is forbidden",
        "there is one authoritative semantic graph with sparse realization overlays — not a source tree an optimizer ir a lowering ir and a machine ir materialized as separate full worlds",
        "the machine realizer arrives with more exact knowledge than a conventional lowered ir normally retains and uses it to avoid creating the allocations objects aliases generic abis temporaries dynamic calls and runtime abstractions a conventional backend must later struggle to remove",
        "law.representation.one still owns the single representation decision — this law forbids losing the facts that decision consumes",
    }
    fails = "a lowering stage that discards semantic facts then reconstructs them or a second full ir world materialized beside the graph"
}

aliasprovenance = law{
    id    = "law.alias.provenance"
    kind  = .invariant
    holds = .provenance
    binds = {
        "ALIAS-PROVENANCE place identity origin escape sharing mutation lifetime and projection are preserved from the moment a place is created — disjointness is a construction fact not a pointer analysis recovered after lowering",
        "distinct exact nonescaping place identities are noalias by construction with no reconstructive pointer aliasing pass",
        "memory dependence is sparse and semantic — only observable places carry store and load dependence and a value with no place never enters memory dependence at all",
        "law.ownership.zero still owns alias lifetime and escape as facts — this law forbids discarding them so a later pass must rebuild them",
    }
    fails = "pointer alias reconstruction after lowering where the language already knew place disjointness or a global memory chain over values that were never places"
}

bufferdemand = law{
    id    = "law.buffer.demand"
    kind  = .invariant
    holds = .demand
    binds = {
        "BUFFER-DEMAND high-level table array and text expressions stay semantically recognizable chains until cardinality shape effects alias target and demand are known — an intermediate table iterator closure or concatenated string materializes only when demanded",
        "an ordinary table with known shape facts admits whole-array optimization scalar vector blocked kernel or accelerator realization without a separate ndarray tensor or matrix semantic kingdom",
        "a map filter reduce chain realizes as one loop with zero intermediate tables when facts permit and text projection substring split parse and write preserve views until identity or ownership is demanded",
        "law.representation.demand still requires each surviving structure to name its observation",
    }
    fails = "eager bufferization of a high-level chain into intermediate tables before demand or a tensor kingdom standing in for table shape facts"
}

vectorone = law{
    id    = "law.vector.one"
    kind  = .invariant
    holds = .one
    binds = {
        "VECTOR-ONE one vectorization algebra derives iteration parallelism structurally-similar-application parallelism reduction fusion and thread or gpu realization from one semantic graph — no separate loop-vectorizer and scalar-combine kingdom",
        "vector legality comes from iteration relations table shape stride alias facts application independence and reduction relation law not from a lowered loop shape",
        "runtime alias checks are zero where semantic place facts prove independence — only a genuinely unresolved alias possibility emits a guard",
        "reduction and scan realizations require the proven relation law associativity commutativity where needed and identity — no named reduce intrinsic is required",
    }
    fails = "a loop-vectorizer and scalar-combine split reconstructing parallelism from lowered ir or a runtime alias guard where place facts already prove independence"
}

realizationvalid = law{
    id    = "law.realization.valid"
    kind  = .invariant
    holds = .witness
    binds = {
        "REALIZATION-VALID every aggressive lowering carries its input and output semantic fact set and emits or checks a local observational-equivalence witness — an aggressive machine rewrite is admitted only behind that validator",
        "bounded local superoptimization of a small pure region enumerates candidate target sequences proves observational equivalence and selects by measured or modeled cost — it is not a general unbounded global superoptimizer",
        "law.profile.evidence still forbids promoting an observation to truth — a hardware cost model calibrates selection not meaning",
    }
    fails = "an aggressive machine rewrite trusted without a local equivalence witness or an unbounded global superoptimizer as the architecture"
}

lowerbound = law{
    id    = "law.lower.bound"
    kind  = .invariant
    holds = .evidence
    binds = {
        "LOWER-BOUND every FTCFTW benchmark reports three layers — the semantic minimum the physics requires the best equivalent native c fortran or llvm result and the current Idol result — superiority is claimed only against that honest triple",
        "an opportunity-class claim is admissible now that Idol is architected to preserve facts a conventional lowering pipeline reconstructs while a measured-win claim requires current-subject evidence under law.evidence.subject",
        "benchmarks compare compiler choices not language names — an optimized c an lto c a fortran-grade array compiler and a hand-tuned baseline are the honest opponents",
        "law.profile.evidence and law.evidence.subject still bind — index or contract presence is not a performance result",
        "the semantic minimum is not an instruction count it is drawn from the applicable lower bound family information theoretic bits that must be learned moved distinguished or emitted communication information crossing a boundary i o and memory hierarchy cache and external memory transfers and rounds circuit depth size and critical path parallel work and span and ultimately physical law speed of light memory latency and thermodynamic energy — closure states which family and which of proven semantic architectural measured machine or best known external bound was reached",
        "cost is a distribution not a constant a dominance claim is invalid when confidence intervals overlap materially or when a nominal win is not robust to slight workload variation and adversarial and worst case inputs bound the claim not only friendly distributions",
        "this law owns the evidence-reporting discipline — law.ftcftw.dominance owns the pareto acceptance inequality and law.cost.closure owns the per-application cost-debt graph fact and benchmark closure",
    }
    fails = "a beats-llvm-or-fortran claim without the three-layer measurement a lower bound asserted as an instruction count rather than an information communication work or physical family a dominance claim with overlapping confidence or a stored benchmark answer standing in for a current-subject run"
}

linksemantic = law{
    id    = "law.link.semantic"
    kind  = .invariant
    holds = .application
    binds = {
        "LINK-SEMANTIC files and directories stop being compile units after ingestion — the compile and link grain is the application closure not the module or object file",
        "an unreachable semantic application never emits its runtime support — semantic link elimination not only symbol-section garbage collection",
        "a changed authoritative fact invalidates exactly the dependent application closure and reuses cached machine realizations whose application and target facts are unchanged",
        "law.incremental.semantic and law.coordination.fact still own incremental identity — this law fixes the grain at the application not the file",
    }
    fails = "module or file compile-unit granularity surviving after ingestion or whole-program reanalysis on a fact change that touched a bounded application closure"
}

grammarone = law{
    id    = "law.grammar.one"
    kind  = .invariant
    holds = .one
    binds = {
        "GRAMMAR-ONE exactly one executable grammar-fact owner",
        "the one grammar owner projects facts qualified by source law — Idol Lua C Bash Wasm and later laws never become independent grammar authorities",
        "canonical Idol grammar facts are one law-qualified projection — generated Zig or C tables are a bridge projection — grammar.md and Tree-sitter are human or editor projections from that owner",
        "exactly one source law owns each source position — no grammar union try-parser command-looking switch suffix reconstruction or world-selected syntax",
        "forbidden parallel owners include C0 prose grammar.id grammar_roles.zig grammarrole.id grammar.md and Tree-sitter each claiming to own recognition",
        "a host grammar_roles.zig table is transitional and has a deletion condition once Idol owns the facts",
        "parser-local BinOp maps spelling lists and category switches are reconstruction debt — token identity yields grammar-role facts and the parser observes them",
        "Tree-sitter LSP MCP and formatter consume the same facts or generated projections they do not retain independent grammar or semantic classification",
    }
    fails = "a second executable grammar or semantic classification owner beside the one fact producer"
}

controlderived = law{
    id    = "law.control.derived"
    kind  = .invariant
    holds = .derived
    binds = {
        "CONTROL-PLANE-DERIVED-ZERO durable human status docs do not manually encode live HEAD lane holder lock state or dirty tree",
        "those facts come from git claims session state and orient evidence — pasting them into WORKSTREAM_DEBT_REGISTER AGENT_COORDINATION or TECH_DEBT_WORKSTREAM is anti-drift",
        "workstream definitions and acceptance criteria may live in projections — live control-plane values may not",
    }
    fails = "a status projection that agents treat as live ownership or HEAD while the claim files and git disagree"
}

tagauthority = law{
    id    = "law.tag.authority"
    kind  = .invariant
    holds = .zero
    binds = {
        "TAG-AUTHORITY-ZERO a physical storage or index tag may accelerate candidate retrieval but may never establish semantic validity or meaning",
        "forbidden semantic decisions include kind equals func module table_shape enum_shape call transform_app to gate applicability",
        "ask whether exact facts establish the demanded relation descriptor binding or application shape — not whether a NodeKind tag matches",
    }
    fails = "graph_query or lowering that rejects or selects meaning from NodeKind or EdgeKind tags instead of published facts"
}

modulezero = law{
    id    = "law.module.zero"
    kind  = .invariant
    holds = .zero
    binds = {
        "MODULE-ZERO module is not a semantic kingdom — home member and provenance facts replace module identity",
        "forbidden module-scoped behavior includes parent.kind equals module functionsInModule as a module lookup and module_path as resident semantic state",
        "applicationsIn home relationsReferencedBy entity and emitReachability replace function-centric kingdom APIs where unnecessary",
    }
    fails = "module-ness still deciding scope reachability or lookup after home facts exist"
}

factcardinality = law{
    id    = "law.fact.cardinality"
    kind  = .invariant
    holds = .one
    binds = {
        "FACT-CARDINALITY-ONE every optional application or entity fact distinguishes unknown known-absent and exactly-one id",
        "null on an optional field means unknown not proven absent — known no effect no authority no witness no target require explicit absent facts",
        "unknown is not absent — demand world and witness reasoning require three-valued or packed cardinality not a single nullable slot",
    }
    fails = "nullable optional conflating unknown with known-absent on effect authority witness target or demand facts"
}

applicationclosure = law{
    id    = "law.application.closure"
    kind  = .invariant
    holds = .one
    binds = {
        "APPLICATION-FACT-CLOSURE every application dimension has exactly one authoritative storage location listed in the fact-location manifest",
        "relation subject operands results descriptor demand effect authority witness stage caller home target realization and provenance each resolve to one owner — no reconstruction from neighbors",
        "ApplicationFact Node edges scope stage demand and projections may not duplicate the same semantic fact without one authority and disposable derived indexes",
    }
    fails = "an application field with zero or multiple authoritative storages or recovered from AST callee text or adjacent facts"
}

astbackedge = law{
    id    = "law.ast.backedge"
    kind  = .invariant
    holds = .zero
    binds = {
        "AST-BACKEDGE-ZERO semantic reads through ast_ref target zero after graph publication",
        "inventory every ast_ref read classify diagnostic-only versus semantic semantic reads must monotonically decrease",
        "AST may remain provenance or debug material but cannot answer semantic questions after resolution",
    }
    fails = "lowering optimization or query recovering meaning from ast_ref instead of graph facts"
}

factcolumn = law{
    id    = "law.fact.column"
    kind  = .invariant
    holds = .sparse
    binds = {
        "FACT-COLUMN-ONE dense entity id plus separate packed fact columns and ranges — not one giant nullable Node record",
        "only facts that exist consume storage — field_count hardware_lowerings why owns_name and role-specific slots do not belong on every entity",
        "semantic hot structures are name-free where possible — names live in provenance or display tables",
    }
    fails = "every Node physically carrying slots for every possible fact mixing semantic provenance demand optimization migration and allocator bookkeeping"
}

graphsovereignty = law{
    id    = "law.graph.sovereignty"
    kind  = .invariant
    holds = .spine
    binds = {
        "GRAPH-SOVEREIGNTY the graph schema contains only Idol semantic ids and facts plus explicitly physical derived indexes",
        "AST sema host ResolvedType StorageClass transform_engine and target hardware must project into or consume the graph — never define its ontology",
        "the milestone after GAP-145 and GAP-134 is a true semantic spine not a host-shaped nullable mirror",
    }
    fails = "semantic_graph importing AST or transform engine to define meaning or host enums owning descriptor or stage state"
}

targetcontamination = law{
    id    = "law.target.contamination"
    kind  = .invariant
    holds = .zero
    binds = {
        "TARGET-CONTAMINATION-ZERO hardware and target realization candidates live in realization planning or indexes keyed by application value and target",
        "hardware_lowerings on semantic Node contaminates the core graph across architectures and breaks cache reuse",
    }
    fails = "target-specific realization candidates stored as resident semantic entity facts"
}

prosefact = law{
    id    = "law.prose.fact"
    kind  = .invariant
    holds = .zero
    binds = {
        "PROSE-FACT-ZERO freeform why strings are not authoritative facts",
        "causes are structured entity id fact ids producer consumer — prose renders on demand",
        "aligns with law.cost.explain and causal compiler refusal",
    }
    fails = "heap-allocated prose string standing in for a semantic or diagnostic fact owner"
}

demandoccurrence = law{
    id    = "law.demand.occurrence"
    kind  = .invariant
    holds = .one
    binds = {
        "DEMAND-OCCURRENCE-ONE return and field demand attach to the exact application or use occurrence not globally to a value node unless genuinely global",
        "the same relation or value may be consumed differently at different applications — demand is application-specific",
    }
    fails = "Node.demand or entity-global demand substituting for per-application demand facts"
}

derivedindex = law{
    id    = "law.derived.index"
    kind  = .invariant
    holds = .one
    binds = {
        "DERIVED-INDEX-ONE scope and contains application caller adjacency and reverse indexes have exactly one authority",
        "derived physical indexes are rebuilt from authority — never independently mutated so consistency cannot be violated",
        "application_rows application_presence and application_candidates must justify authority versus derived duplication",
    }
    fails = "two independently mutable storages of the same home member or caller adjacency fact"
}

viewzerocopy = law{
    id    = "law.view.zerocopy"
    kind  = .invariant
    holds = .borrowed
    binds = {
        "ZERO-COPY-GRAPH-VIEWS operand result capture and member queries return borrowed immutable slices over packed graph ranges where lifetime permits",
        "forbidden hot-path pattern query then alloc.dupe then memcpy then free for ids already stored contiguously",
    }
    fails = "graph_query allocating copies of packed operand or result ranges on every access"
}

world.one = law{
    id    = "law.world.one"
    kind  = .invariant
    holds = .authority
    binds = {
        "WORLD-ONE a world is the closed semantic table under which meaning resolves; authority is one class of fact within it, so a world is not synonymous with authority and is never a bundled os api namespace",
        "a world may also contain bindings descriptors relations other worlds and stage target facts; authority is only one class of world fact",
        "a capability sensitive relation declares its required world facts, and there is no namespace capability system beside world edges",
        "world requirements participate in checking staging sandboxing caching optimization adaptation authorization and provenance",
        "avoid canonical monolithic os world and monolithic io world where authority can be represented more precisely as filesystem process environment clock network device capabilities",
        "ambient world fields args env cwd stdin stdout stderr clock may project from context when meaning unique — prefer args(1) env(\"KEY\") stdout:write(text) clock:now() over os.args os.env io:write when unique context supplies values",
        "stdout is possessed endpoint value and legitimate subject — io is organizational authority not interchangeable",
        "path exists isfile isdir ready valid supported suspect under predicate zero — prefer consuming richer path state relation when algorithm merely branches on existence",
        "relation witness and world witness are separate — protocol satisfaction does not grant world authority",
        "conditional world obligations for union subjects remain alternative specific until refinement narrows — do not require every world for every possible specialization prematurely",
        "world may derive narrower capability through witnessed projection not namespace chain os.process.shell",
        "multiple observable world grants that could satisfy same authority fail ambiguous — no nearest home declaration order package or default priority",
    }
    fails = "world as organizational receiver namespace or intent selector"
}

homeprojection = law{
    id    = "law.home.projection"
    kind  = .invariant
    holds = .context
    binds = {
        "HOME-PROJECTION hierarchical source topology establishes home binding descriptor context and provenance — once resolved hierarchy does not qualify relation id",
        "compiler parser id makes parser binding reachable not compiler.parser.parse semantic identity",
        "reject std.foo lib.foo stdlib.foo package.foo module.foo when left side is organizational infrastructure not real semantic value",
        "if home qualifier needed only for source lookup and context uniquely determines binding do not preserve downstream",
    }
    fails = "home chain as runtime namespace qualification of relation identity"
}

shellnotworld = law{
    id    = "law.shell.not.world"
    kind  = .invariant
    holds = .separation
    binds = {
        "SHELL-NOT-WORLD shell defines interpretation law not automatic authority world",
        "shell law plus command structure yields command value then command run requires process world",
        "command may be constructed without process authority until run is demanded",
        "if exactly one shell law in semantic context and command construction explicitly demands shell interpretation infer law — if several available require qualification — world choice cannot choose shell law",
        "process namespace zero — do not preserve process.run process.capture process.exit process.command as destination api — orient run subject command world process output demand outcome evidence",
        "capture is usually run plus output demand not second execution relation unless irreducible distinction survives admission",
    }
    fails = "shell as world or process namespace api as canonical destination"
}

crossone = law{
    id    = "law.cross.one"
    kind  = .invariant
    holds = .witness
    binds = {
        "CROSS-ONE cross boundary projection valid only with explicit witness connecting semantic facts on both sides",
        "foreign to cast coercion does not automatically equal idol to — preserve foreign law prove equivalence then project to native edge",
        "zero copy view requires layout alignment lifetime alias ownership mutation encoding and foreign law proof — else copy convert semantically required",
        "stage and target are facts — compile time projection may specialize without compile time api kingdom — target is realization unless program semantics intentionally select it",
    }
    fails = "cross boundary mapping by name path layout or foreign same spelling without witness"
}

derivedconversion = law{
    id    = "law.derived.conversion"
    kind  = .invariant
    holds = .bounded
    binds = {
        "DIRECT-INFER implicit conversion consumes direct or already normalized derived edge from indexed relation catalog not arbitrary multi hop search",
        "derivation from hub composition is not equally permissive as implicit source insertion",
        "implicit use of derived edge requires bounded rule admitted canonical hub exactly one normalized witness composite law valid for implicit use and no incomparable alternate witness",
        "lossy checked narrowing rounding truncating or consuming conversion not silently injected unless explicit demand and failure obligations make law uniquely intended",
        "two hub derivations producing incomparable witnesses are ambiguous",
    }
    fails = "general shortest path conversion engine or silent law strengthening on derived path"
}

gateprojection = law{
    id    = "law.gate.projection"
    kind  = .protocol
    holds = .adversarial
    binds = {
        "REDUNDANT-PROJECTION-ZERO no new explicit projection if graph canonicalizer proves uniquely inferable",
        "RECONSTRUCTION-ZERO no downstream source name path reconstruction of projection facts",
        "FROM-ZERO no new inverse conversion face when to edge expresses same semantics",
        "STD-ZERO and LIB-ZERO no new canonical std or lib semantic source reference",
        "WORLD-NAMESPACE-ZERO no world used merely as organizational receiver",
        "PROTOCOL-ADJECTIVE-ZERO no adjective alias for existing relation constraint",
        "PROJECTION-WRAPPER-ZERO no parallel semantic projection classes",
        "AMBIGUITY-ZERO never choose among incomparable projections",
        "control 1 x to str where result slot already demands str canonicalizer removes explicit projection",
        "control 2 x to() with unique target succeeds",
        "control 3 x to() with two possible targets fails",
        "control 4 x with unique demanded conversion graph inserts to T",
        "control 5 x already satisfying target inserts no conversion",
        "control 6 ABI-only width difference produces no semantic to",
        "control 7 from inverse face same edge id as to then canonical source eliminates from",
        "control 8 derived hub conversion one witnessed normalized edge",
        "control 9 two hub derivations ambiguity",
        "control 10 weak narrowing derived path no silent strengthening",
        "control 11 protocol relation constraint no runtime witness by default",
        "control 12 protocol satisfaction does not grant world",
        "control 13 unique world witness injected no world argument",
        "control 14 multiple observable worlds fails",
        "control 15 os io namespace availability cannot choose semantic relation",
        "control 16 path home move relation id unchanged",
        "control 17 std foo renamed lib foo still violation",
        "control 18 lib foo renamed fooapi still violation if same source loader ontology",
        "control 19 foreign same name relation no native equivalence without witness",
        "control 20 zero copy foreign projection rejected when alias lifetime law differs",
        "control 21 projection fact missing before DNIR fail closed",
        "control 22 changing callee spelling after resolution projection unchanged",
        "control 23 flattening projection pack into operands semantic comparison fails",
        "control 24 genuine curry remains multiple applications",
        "control 25 projected relation syntax remains one application",
        "control 26 union projection preserves alternative specific world witnesses",
        "control 27 inference cannot synthesize arbitrary relation chains",
        "control 28 unrelated new specialization cannot change existing resolved projection",
        "control 29 canonical render reparse preserves application identity facts",
        "control 30 deleting projection indexes preserves semantic behavior",
        "staged text gates are migration pressure until GAP-124 graph projection census owns verdicts",
    }
    fails = "projection invariant enforced only as chat guidance without adversarial controls"
}

projectionabsolute = law{
    id    = "law.projection.absolute"
    kind  = .invariant
    holds = .absolute
    binds = {
        "projection is fact completion not namespace selection",
        "inference supplies uniquely determined facts",
        "home supplies context not meaning relation supplies meaning subject supplies orientation",
        "protocol constraints demand relation facts world supplies authority not intent",
        "foreign crossing supplies law and provenance not new identity",
        "standard means reachable not std repository layout means provenance not lib",
        "to is one conversion relation from is not a second conversion universe",
        "no explicit projection survives when the graph can uniquely recover it",
        "no implicit projection is permitted when ambiguity hidden effect unhandled failure or unbounded search remains",
        "one graph one application algebra one projection mechanism one world witness mechanism one native lowering path",
        "for every new or changed expression if the answer relies on std lib module namespace method protocol adjective host api callee spelling path or text pattern the change is not idollic yet",
    }
    fails = "multiple projection mechanisms namespace-selected meaning or implicit projection under ambiguity"
}

projectionrepair = law{
    id    = "law.projection.repair"
    kind  = .protocol
    holds = .sequence
    binds = {
        "repair order one reconcile projection law into c0",
        "two rewrite docs spec world.md",
        "three rewrite conversion fixtures eliminate from as separate semantic orientation",
        "four make projection pack facts explicit in resolver graph application records",
        "five add expected descriptor and result demand inference",
        "six implement semantic canonicalization for redundant to and projection elision",
        "seven move conversion class refusal authority out of codegen into semantic resolution",
        "eight replace hardcoded primitive to codegen authority with ordinary relation edges",
        "nine add relation constraint protocol witness derivation using same projection path",
        "ten add world witness injection using same application facts",
        "eleven remove canonical std lib source lookup",
        "twelve fix source home reachability so no replacement import namespace is necessary",
        "thirteen audit foreign cross projections through same graph",
        "fourteen feed exact facts into dnir native lowering",
        "fifteen delete lexical text gates once graph gates own semantic verdicts",
        "do not continue implementing projection conversion protocol world source shell currying dnir or tooling machinery against older repository examples until this reconciliation is applied",
    }
    fails = "implementation ahead of projection law reconciliation or repair steps permuted without owner directive"
}

projectioncensus = law{
    id    = "law.projection.census"
    kind  = .protocol
    holds = .machine
    binds = {
        "operation census machine projection must represent every canonical application with application id relation id explicit and inferred projection facts subject id operand pack id result pack id constraint witnesses world requirements world witnesses origin and law",
        "projection census separately reports explicit projections inferred projections redundant explicit projections ambiguous projections reconstruction sites projection wrappers projection string lookups std lib source lookups world namespace calls protocol adjective identities and from inverse aliases",
        "every debt class gets exact owners — census classifies never bulk replaces explicit to or from without per site proof",
        "ftcftw target for statically resolved applications namespace lookup relation string lookup conversion registry lookup protocol dictionary protocol vtable world object plumbing generic runtime dispatch projection wrapper unnecessary conversion and unnecessary closure approach zero",
    }
    fails = "projection debt tracked only by search sampling without machine census and owners"
}

projectionrules = law{
    id    = "law.projection.rules"
    kind  = .invariant
    holds = .order
    binds = {
        "resolve every application by projection in this order subject descriptor law world effect origin realization",
        "subject projection prefers text:sub xs:push path:open file:read stream:close value:to(str) over string table math io fs namespace receivers when the prefix supplies only organization",
        "descriptor projection retains one relation and qualifies by descriptor facts rather than minting str_len or i64_add relations",
        "law projection preserves observable arithmetic ownership truth encoding and foreign behavior as law not as another relation name",
        "world projection assigns filesystem network process clock random device and environment authority to world facts not operation names",
        "effect projection retains observable application behavior as effect not as a parallel api family",
        "origin projection keeps foreign native distinction in origin and provenance unless law itself differs",
        "realization projection treats abi linkage register stack simd gpu machine operation syscall shell pipe buffer vtable and hash table as realization place or foreign facts unless semantically observable",
    }
    deny  = { "string.sub(text,a,b)", "table.insert(xs,v)", "math.sqrt(x)", "io.open(path)", "fs.open(path)", "file.read(stream)" }
    fails = "organizational namespace receiver standing in for subject descriptor law world effect origin or realization fact"
}

descriptoralgebra = law{
    id    = "law.descriptor.algebra"
    kind  = .invariant
    holds = .facts
    binds = {
        "a descriptor is a fact set and constraint projection not merely a type name",
        "the same descriptor architecture serves concrete value facts protocol constraints numeric constraints shape constraints foreign constraints and result constraints",
        "a descriptor in producing or value context supplies facts",
        "a descriptor in constraint context demands facts",
        "do not create a separate type system ontology for each use",
    }
    fails = "parallel type protocol and value descriptor ontologies"
}

homecontext = law{
    id    = "law.home.context"
    kind  = .invariant
    holds = .reachability
    binds = {
        "a home supplies context and reachability for declarations sharing a naturally recoverable descriptor or semantic context",
        "a home does not supply semantic ownership subject identity world authority capability method identity or implementation membership",
        "relations declared in a home remain globally named relation identities",
        "moving a relation declaration between equivalent homes does not change relation identity",
        "a home never creates file.read path.open or similar qualified relation identity",
    }
    canon = { "file: { read: bytes = () ... }", "the home supplies ambient subject descriptor file while read remains globally read" }
    fails = "home used as receiver merely for organization or as a method owner"
}

subjectresolve = law{
    id    = "law.subject.resolve"
    kind  = .invariant
    holds = .resolution
    binds = {
        "the subject is the value a relation is fundamentally about",
        "subject is established by resolution and is not inferred downstream from syntax position namespace spelling or home membership",
        "when a subject is possessed prefer its subject face",
        "path:open file:read text:len and stream:close beat namespace first equivalents when the possessed value is the true subject",
        "io:open(path) fs:open(path) string:len(text) and file:read(stream) are noncanonical when the prefix is only organizational or world context",
    }
    canon = { "path:open()", "file:read()", "text:len()" }
    deny  = { "io:open(path)", "fs:open(path)", "string:len(text)", "file:read(stream)" }
    fails = "argument zero colon syntax home membership method ownership or namespace receiver standing in for subject"
}

worldgrant = law{
    id    = "law.world.grant"
    kind  = .invariant
    holds = .authority
    binds = {
        "a world is a closed semantic table; it may contain bindings descriptors relations facts other worlds and stage target facts, and authority is one class of fact within it — not the world itself",
        "a world supplies authority required for an application",
        "world is not a namespace import home protocol or type membership",
        "world is not granted by a home and is not granted by a protocol witness",
        "capability sensitive relations declare required world facts as ordinary application operands or elided facts",
        "when exactly one admissible world satisfies a requirement canonical source omits it as default algebraic injection",
        "when world selection is semantically ambiguous the distinguishing fact is explicit through ordinary values or context",
        "io:open(path) cannot become canonical merely because io is reachable",
        "path:open retains the required world fact even when elided in source",
    }
    canon = { "file = path:open()", "open subject path world io result file" }
    deny  = { "io:open(path)", "service locators", "global registries", "hidden imports", "dependency injection syntax" }
    fails = "world authority arriving through home membership protocol satisfaction or namespace receiver"
}

injectalgebra = law{
    id    = "law.inject.algebra"
    kind  = .invariant
    holds = .unique
    binds = {
        "injection is required facts plus available facts yielding unique satisfaction through semantic resolution not object construction",
        "canonical source omits an injected fact only when the result is unique and inspectable",
        "every inferred injection produces witness and provenance explaining the choice",
        "no hidden guessing and no priority from filename import order declaration order or namespace path unless such ordering is explicitly admitted law",
        "ambiguous injection fails rather than picking by declaration import or path priority",
        "an inferred world choice is accepted only when unique and witnessed",
    }
    why   = "law.ambient.one: ambient requires exactly one valid contextual value; ambiguity diagnoses"
    fails = "injection by convention priority or namespace reachability"
}

standardenvironment = law{
    id    = "law.standard.environment"
    kind  = .invariant
    holds = .projection
    binds = {
        "there is no semantic std owner",
        "the standard environment is the default reachable set of admitted relations descriptors laws world grants and realizations",
        "resolution projects the appropriate facts algebraically",
        "file:read does not secretly mean std.io.file.read file",
        "file:read means relation read subject file required world resolved specialization resolved",
        "delete architecture that preserves std namespace authority under different spelling",
    }
    fails = "std or any namespace as privileged semantic owner"
}

constraintprotocol = law{
    id    = "law.constraint.protocol"
    kind  = .invariant
    holds = .facts
    binds = {
        "there is no independent protocol semantic identity when an existing relation or fact set fully specifies the constraint",
        "a protocol is a projection of one or more existing relations used as constraints on an unknown subject not a trait interface class nominal supertype method table vtable implementation registry or trait object kingdom",
        "relation in application position is operation relation in constraint position is requirement that subject admits operation descriptor in value position supplies facts descriptor in constraint position demands facts",
        "the canonical constraint for read is read not readable so consume = (source: read) source:read() demands the subject admit relation read for the call shapes demanded by this callable and no second readable concept exists",
        "when a public contract must be explicit independently of body inference use an anonymous descriptor constraint consume = (source: { read: bytes = () }) source:read() meaning source must provide relation read with result bytes",
        "the formatter or compiler may canonicalize the explicit descriptor form to source: read when the complete contract is reconstructable",
        "composite requirements are conjunction of demanded facts read plus close not inheritance readclose readableclosable or automatic stream identity unless stream passes independent semantic admission",
        "operation requirements use relation constraints property requirements use descriptor law or fact constraints not marker protocol kingdoms",
        "trait impl interface implements concept dyn and impl read for file are forbidden canonical keywords and patterns",
        "exact parser and grammar realization must reuse current descriptor grammar rather than introduce protocol syntax",
        "if constraint expression cannot currently be expressed without new grammar the state is implementationblocked and no keyword is added",
        "law.protocol.one supersedes every readable writable iterable adjective protocol example formerly shown here",
    }
    canon = {
        "consume = (source) source:read()",
        "consume = (source: read) source:read()",
        "consume = (source: { read: bytes = () }) source:read()",
        "copy = (source, sink) sink:write(source:read())",
        "make = (path) path:open()",
    }
    deny  = {
        "readable", "writable", "seekable", "iterable", "hashable", "equatable",
        "comparable", "callable", "cloneable", "copyable", "serializable",
        "deserializable", "convertible", "indexable", "sortable", "printable",
        "formattable", "impl read for file", "trait", "interface", "implements",
        "concept", "dyn read", "Read", "Write", "Iterator", "Iterable",
    }
    fails = "protocol as nominal type system adjective duplication or runtime interface kingdom"
}

protocolsatisfy = law{
    id    = "law.protocol.satisfy"
    kind  = .invariant
    holds = .witnessed
    binds = {
        "protocol satisfaction is witnessed from graph facts as requirements protocol subset proven facts subject",
        "compatibility is semantic not spelling based",
        "for each required relation compare relation identity subject constraint operand pack result pack descriptor facts law world requirements effects failure contract lifetime and provenance constraints where applicable",
        "a coincidentally named foreign operation does not satisfy a native protocol",
        "same relation spelling with incompatible law does not satisfy",
        "protocol satisfaction is unchanged by unrelated source renaming",
        "the witness is evidence and is not a second implementation identity",
    }
    fails = "satisfaction by name shape or foreign interface equality alone"
}

protocolnoinpl = law{
    id    = "law.protocol.noinpl"
    kind  = .invariant
    holds = .derived
    binds = {
        "do not require impl read for file when the graph already proves satisfaction",
        "file: { read: bytes = () ... } is sufficient for the graph to derive witness that file admits relation read when semantics match",
        "removing an explicit relation constraint whose requirements are fully inferred does not alter semantics except public contract provenance",
        "equivalent relation requirements converge to one relation identity",
        "blanket impl for all subjects satisfying a relation becomes generic relation specialization digest = (source: read) source:read():hash() not an impl registry",
    }
}

protocolparam = law{
    id    = "law.protocol.param"
    kind  = .invariant
    holds = .constraint
    binds = {
        "a parameter constrained by relation read such as consume = (source: read) source:read() carries the constraint as increased knowledge not a second semantic identity",
        "the concrete source descriptor remains known to the graph",
        "no boxing vtable or runtime interface conversion is implied",
        "concrete descriptor survives relation constraint parameter crossing",
        "consume = (source) source:read() is canonical when the body alone supplies the complete inferred constraint",
    }
    canon = { "consume = (source: read) source:read()", "consume = (source) source:read()" }
}

protocolresult = law{
    id    = "law.protocol.result"
    kind  = .invariant
    holds = .constraint
    binds = {
        "a result constrained by relation read is a result constraint not an existential wrapper",
        "make: read = (path) path:open() preserves concrete result descriptor while read constrains observable contract when the public promise requires it",
        "make = (path) path:open() is canonical when downstream semantics do not require hiding the concrete result interface",
        "result descriptor does not become a second adjective protocol name",
        "no box interface vtable tag heap allocation or dynamic dispatch is implied by the constraint",
        "the caller may rely only on the constraint while the compiler retains stronger concrete knowledge internally",
        "concrete descriptor survives relation constraint result crossing",
    }
}

protocolinfer = law{
    id    = "law.protocol.infer"
    kind  = .invariant
    holds = .optional
    binds = {
        "constraints uniquely derivable from body or context are unwritten per law.infer.one",
        "copy = (source, sink) sink:write(source:read()) infers source requires read sink requires write and read result must satisfy write operand without explicit annotations",
        "twice = (x) x + x infers mul or add requirements from the body without Mul or Add protocol identities",
        "write only what cannot be uniquely reconstructed",
        "explicit source: read is useful only when deliberately promising relation read beyond what implementation necessarily implies",
    }
}

protocolexist = law{
    id    = "law.protocol.existential"
    kind  = .invariant
    holds = .realization
    binds = {
        "do not create a separate semantic dyn protocol system",
        "when runtime heterogeneous values are genuinely demanded realization may choose sealed variant tagged payload direct specialized branches function pointer table dispatch or boxed object according to facts and target",
        "that choice is physical realization and the protocol semantic identity does not change",
        "a witness ordinarily exists only as compile or graph evidence and materializes only when the program explicitly demands reflection or runtime protocol evidence",
    }
    fails = "protocol constraint imposing runtime interface overhead on statically known values"
}

protocolcompose = law{
    id    = "law.protocol.compose"
    kind  = .invariant
    holds = .conjunction
    binds = {
        "composite requirements are conjunction of demanded facts not inheritance",
        "consume = (source: { read: bytes = () close = () }) source:read() source:close() semantically requires read and close with no readclose or readableclosable composite identity",
        "stream or resource names earn descriptor identity only when independent semantic laws remain after removing constituent relation requirements",
        "do not invent protocol specific composition punctuation",
        "reuse ordinary descriptor and fact algebra",
        "set containment requirements B superset requirements A expresses stronger requirement without trait inheritance",
    }
    canon = { "copy = (source, sink) sink:write(source:read())", "copy = (source: read, sink: write) sink:write(source:read())" }
}

protocolworld = law{
    id    = "law.protocol.world"
    kind  = .invariant
    holds = .separate
    binds = {
        "a relation constraint may require a relation whose execution requires a world and these remain separate facts",
        "file admits read and read file requires filesystem world are independent",
        "the read witness proves relation availability and does not grant filesystem or any world",
        "absolute invariant relation witness is not world grant",
        "generic copy = (source, sink) sink:write(source:read()) infers world obligations from selected read and write specializations not a union of every possible world",
        "a value can satisfy read even when an application of read cannot currently be authorized",
    }
    fails = "relation satisfaction treated as world grant or home grant"
}

foreignprotocol = law{
    id    = "law.foreign.protocol"
    kind  = .invariant
    holds = .provenance
    binds = {
        "foreign protocol and interface systems retain their original law",
        "rust read c callback table java interface and wasm import signature are not native protocols because shapes or names resemble one another",
        "native protocol satisfaction projects only after foreign facts foreign law native requirements and equivalence witness are present",
        "preserve foreign origin and provenance and the native protocol does not absorb the foreign ontology",
    }
}

boundarycross = law{
    id    = "law.boundary.cross"
    kind  = .invariant
    holds = .identity
    binds = {
        "whenever a value crosses foreign native world package stage target runtime compile or host guest boundaries do not convert it into another semantic identity merely because the boundary changed",
        "carry id descriptor law origin world and effect obligations protocol witnesses provenance and demand and add boundary facts",
        "only representation changes when realization requires it",
        "no adapter when semantic and physical equivalence prove it unnecessary",
    }
}

homeprotocol = law{
    id    = "law.home.protocol"
    kind  = .invariant
    holds = .one
    binds = {
        "a home provides specialization context and a relation constraint requires specialization facts",
        "file: { read: bytes = () ... } and consume = (source: read) source:read() both reference one relation read not readable.read or file.read",
        "the graph records constraint requires relation read descriptor file provides compatible read specialization and witness file admits read",
        "a home does not imply a world and an io home for organization grants no io authority",
    }
}

colondecide = law{
    id    = "law.colon.decide"
    kind  = .invariant
    holds = .procedure
    binds = {
        "before writing a:b determine what a is",
        "if a is the semantic subject use canonical subject call",
        "if a is only a home do not use it as receiver merely for organization",
        "if a is a world do not use it as receiver merely to grant authority",
        "if a is a relation constraint do not invoke it as an implementation owner",
        "if a is a descriptor genuinely applied to structured content descriptor application may be correct",
        "one colon spelling must not blur these roles",
    }
}

protocolperf = law{
    id    = "law.protocol.perf"
    kind  = .invariant
    holds = .specialize
    binds = {
        "protocol constraints must preserve or increase specialization information",
        "consume(file) realization may become direct specialized read with zero protocol object vtable box witness materialization and generic runtime lookup",
        "two concrete call sites may specialize independently through one protocol constrained callable",
        "protocol architecture that imposes runtime interface overhead on statically known values fails law.project.ftcftw",
    }
}

protocolgate = law{
    id    = "law.gate.protocol"
    kind  = .protocol
    holds = .adversarial
    binds = {
        "moving a relation between equivalent homes does not change relation identity",
        "changing a home name does not grant authority",
        "io:open(path) cannot become canonical merely because io is reachable",
        "path:open retains required world fact when elided or explicit",
        "protocol satisfaction does not grant required world",
        "protocol satisfaction is unchanged by unrelated source renaming",
        "same relation spelling with incompatible law does not satisfy",
        "foreign interface name equality does not satisfy",
        "concrete descriptor survives protocol parameter and result crossing",
        "protocol constraint introduces no allocation or vtable by default",
        "two concrete call sites specialize independently through one protocol constrained callable",
        "removing a fully inferred named protocol alters only public contract provenance",
        "equivalent protocol requirements converge to one relation identity",
        "a home never creates method identity",
        "a world never becomes implicit namespace receiver",
        "inferred world accepted only when unique and witnessed",
        "ambiguous injection fails without declaration import or path priority",
        "foreign boundary crossing preserves origin and law until equivalence is witnessed",
        "redundant adapter disappears before realization when equivalence is proved",
    }
    fails = "a specimen fix without the class invariant or a positive control without adversarial negative control"
}

algebra = law{
    id    = "law.algebra.home"
    kind  = .invariant
    holds = .absolute
    binds = {
        "home supplies context",
        "subject orients meaning",
        "descriptor supplies facts",
        "protocol demands facts",
        "world grants authority",
        "witness proves satisfaction",
        "injection supplies omitted facts only when unique and witnessed",
        "projection supplies reachability and binding facts not authority",
        "demand determines necessity",
        "realization chooses physical form",
        "none substitutes for another",
        "the standard environment is a projection of ordinary facts not a privileged namespace",
        "protocols constrain semantic behavior not object representation",
        "concrete knowledge survives abstraction boundaries",
        "world authority never arrives through type membership",
        "foreign similarity never implies equivalence",
        "write only what cannot be uniquely reconstructed",
        "infer only what can be uniquely witnessed",
        "materialize only what is demanded",
        "one relation remains one relation across home protocol graph realization and machine lineage",
    }
}

unionprojection = law{
    id    = "law.union.projection"
    kind  = .invariant
    holds = .cases
    binds = {
        "a union is semantic alternative possibility with exact value identity retained and is not automatically a tag payload heap object enum object or variant object",
        "a relation applies to a union valued subject only when resolution establishes the relation requirement is satisfied for every currently possible alternative under compatible demanded semantics",
        "the graph retains alternative specific witnesses and realization may become one specialized path sealed branch tag dispatch function pointer or no dispatch without forced interface dispatch",
        "if only one union alternative satisfies a relation the application is not globally valid and requires refinement evidence narrowing the possible descriptor before invocation with no silent branch choice",
        "facts shared by every remaining alternative project directly while facts true for only some remain conditional and known in every alternative never collapses with known in one alternative",
        "a relation may return a union without materializing a union object and when downstream demand consumes the case immediately realization may become direct control or dependency",
        "nested equivalent alternatives normalize so a or b union a reduces to a or b while preserving source provenance separately",
        "when all union alternatives satisfy a protocol their union satisfies the protocol constraint for uses common to all alternatives while only some satisfying requires refinement and no protocol union object is materialized",
        "refinement narrowing a union to one alternative makes protocol requirements provable for that alternative without retaining runtime dispatch for eliminated alternatives",
        "a stronger result descriptor satisfies a weaker demanded protocol when graph implication proves it and parameter compatibility follows the actual relation contract and law not copied variance tags",
    }
    canon = { "value: a | b", "open(path) -> file | error" }
    deny  = { "boxed sum type by default", "synthetic boxed protocol value for a union subject", "runtime dispatch for an eliminated alternative" }
    fails = "union modeled as a mandatory physical object or a partial projection applied without refinement"
}

luapiredirect = law{
    id    = "law.lua.redirect"
    kind  = .invariant
    holds = .subject
    binds = {
        "the standard library filesystem process math string and table are not semantic namespaces",
        "a protocol is not an interface kingdom and math is not a namespace",
        "legacy lua namespace calls reduce to subject relations when admitted",
        "string.sub(s,a,b) string.find(s,p) string.match(s,p) string.gsub(s,...) string.byte(s,...) string.len(s) reduce to s:sub s:find s:match s:gsub s:byte s:len",
        "table.insert(t,v) table.remove(t,i) table.sort(t) reduce to t:push t:remove t:sort when those relations are admitted",
        "table.concat table.keys table.values and similar organizational table operations reduce to subject relations such as t:join(sep) t:keys() t:values() only when the admitted relation identity exists",
        "if no admitted relation exists the state is semanticvocabularyblocked and no namespace respelling is permitted",
        "math.sqrt(x) math.abs(x) math.floor(x) reduce to x:sqrt x:abs x:floor when relation law admits the subject",
        "symmetric multi value relations such as min and max keep semantically correct subject orientation rather than mechanical colon forcing",
        "tostring(x) tonumber(x) reduce to x:to(str) x:to(target) when target is not uniquely inferable from demand — omit to when law.infer.one supplies it",
        "io.open io.read io.write io.popen decompose into path open stream read write and run with explicit world facts",
        "os.execute os.exit os.getenv os.date os.time os.args classify individually as run outcome environment observation clock observation or run input never as an os namespace",
        "pairs ipairs in canonical native source are rejected unless the source is explicitly compatibility law marked",
        "canonical native logic must not use nil false zero minus one or empty string as hidden absence or failure where semantic cases already exist",
    }
    canon = {
        "text:sub(a,b)",
        "xs:push(v)",
        "xs:keys()",
        "path:open()",
        "x:to(str)",
    }
    deny  = {
        "string.sub(text,a,b)",
        "table.insert(xs,v)",
        "table.keys(t)",
        "table.concat(t,sep)",
        "math.sqrt(x)",
        "io.open(path)",
        "os.getenv(name)",
    }
    fails = "namespace operation home.operation(subject) or lua compatibility vocabulary in canonical native source"
}

shellrun = law{
    id    = "law.shell.run"
    kind  = .invariant
    holds = .world
    binds = {
        "shell is a law bearing command interpretation and physical execution universe not the standard process api",
        "backtick remains non executing and reserved",
        "a command is an ordinary value when command structure genuinely needs identity",
        "execution is an ordinary run application requiring process world",
        "process.capture shell.exec process.run os.system and os.execute are not canonical semantic models",
        "the default environment may make shell law and world available but that does not make every string executable",
        "execution requires an explicit run relation",
        "if shell parsing is used preserve shell law and injection risk semantics explicitly",
        "capture is usually run plus output demanded as value or evidence not another irreducible execution relation",
        "string interpolation remains text construction and does not silently become shell quoting or command construction",
        "foreign os status integers are provenance and evidence never native outcome",
        "transport completion never proves inner requested run success",
    }
    fails = "shell text construction executing without explicit run relation or host status integer defining native outcome"
}

bindingcensus = law{
    id    = "law.binding.census"
    kind  = .invariant
    holds = .resolved
    binds = {
        "every canonical operation in project owned id source must resolve to an admitted binding or relation",
        "looks builtin is invalid without resolved native relation id declaration owner subject constraint world effect requirements and law",
        "zero unresolved canonical operation uses zero duplicate native spellings for one relation and zero host globals silently exposed as native builtins",
        "a machine census maps canonical operation spelling to resolved relation id owner subject constraint world effect and law",
        "textual match alone is not verdict semantic role is resolved first",
    }
    fails = "invented helper host runtime builtin or unresolved operation in canonical source"
}

repairorder = law{
    id    = "law.repair.order"
    kind  = .protocol
    holds = .sequence
    binds = {
        "establish semantic census and relation resolution gate before blind whole tree rename",
        "projection algebra protocol constraint witness union refinement world injection standard reachability shell run outcome and evidence model are closed in this section before cosmetic respelling",
        "repair active compiler and shc path code first then gates and agent harnesses then active standard and tooling consumers then remaining canonical corpus in dependency order",
        "keep foreign and lua fixtures explicitly marked",
        "delete physical std distribution topology only when reachability replacement is proven",
        "never let migration delay the earliest executable shc frontier longer than the exact semantic prerequisite requires",
    }
}

gatealgebra = law{
    id    = "law.gate.algebra"
    kind  = .protocol
    holds = .adversarial
    binds = {
        "1 std.foo to process.foo remains invalid when ontology is unchanged",
        "2 io:open(path) fails when path is true subject and io is only world",
        "3 path:open retains world obligation when elided or explicit",
        "4 home relocation cannot change relation id",
        "5 protocol satisfaction cannot grant world",
        "6 same operation name with foreign incompatible law cannot satisfy native protocol",
        "7 union direct application requires all alternatives to satisfy relation",
        "8 narrowing a union removes dead alternative realization",
        "9 constrained parameter introduces no boxing",
        "10 constrained result retains concrete descriptor",
        "11 named protocol removal leaves inferred equivalent constraint semantics when no public contract demanded",
        "12 tostring(x) canonicalizes to conversion relation not another helper",
        "13 namespace math.sqrt(x) and subject x:sqrt resolve to same relation where admitted with subject face canonical",
        "14 table.insert table.keys table.concat cannot survive merely renamed",
        "15 pairs ipairs in canonical native source are rejected unless explicitly compatibility law marked",
        "16 req require import include module namespace use inject admit cannot be replaced by another loader spelling",
        "17 nil cannot silently enter native absence semantics",
        "18 os status integer cannot define native outcome",
        "19 unresolved operation cannot pass merely because host runtime exports it",
        "20 deletion of acceleration indexes preserves semantics",
        "21 moving an operation from one physical file to another preserves semantic identity",
        "22 world ambiguity fails closed",
        "23 source order does not decide injection",
        "24 default standard reachability does not create hidden world authority",
        "25 shell text construction never executes without explicit run",
        "26 process output demand does not force buffering unless demanded",
        "27 protocol reflection cost appears only when demanded",
        "28 two union alternatives sharing one relation may specialize separately without protocol or interface materialization",
        "29 foreign compatibility source can retain lua api without teaching canonical native vocabulary",
        "30 changed canonical line with compound name must prove irreducibility not merely punctuation compliance",
        "31 readable writable iterable hashable equatable callable and similar adjectives fail when the underlying relation already exists",
        "32 source: read constraint and consume = (source: read) retain one read relation id not a second readable protocol identity",
        "33 consume = (source) source:read() with inferred read constraint remains valid when explicit source: read adds no public contract",
        "34 binding descriptor infers unique direct to(T) when required and lawful",
        "35 parameter descriptor infers unique direct to(T) at call boundary",
        "36 result descriptor infers unique direct to(T) backward into producer",
        "37 field descriptor infers unique direct to(T) in pack construction",
        "38 already satisfying value inserts no to application",
        "39 exact integer literal to i32 demand is descriptor specialization not fake i64 to i32 conversion",
        "40 two possible conversion targets require explicit to(T)",
        "41 omitted to succeeds when target uniquely inferable from demand",
        "42 explicit to(target) required when target ambiguous",
        "43 conversion with unhandled failure cannot be silently inserted",
        "44 conversion with unavailable world cannot be inserted",
        "45 two available world witnesses remain ambiguous",
        "46 world availability alone cannot choose conversion target",
        "47 physical abi width change produces realization fact not semantic to",
        "48 historical to(T)(x) canonicalizes down inference ladder only as far as unique proof allows",
        "49 inferred conversion remains in semantic graph and provenance",
        "50 removing redundant explicit to preserves semantic identity",
        "51 removing nonredundant explicit to(T) changes resolution and is rejected",
        "52 projection elision on read(number) preserves projection pack fact",
        "53 ambiguous read projection forces explicit qualifier",
        "54 nonescaping genuine curry may fuse realization without changing semantic application count",
        "55 projection inference never creates a curry application",
        "56 conversion inference never changes application cardinality",
        "57 foreign semantic conversion remains distinct from abi realization",
        "58 canonicalization is idempotent on resolved graph facts",
        "59 callable possessed operation typed authorized captured projected resolved imported native static booleans fail when the graph already has the structural fact",
        "60 world empty string world nil world none world false fail as absence sentinels — omit the world-requirement edge",
        "61 a table enumerating relations descriptors worlds formats handlers or capabilities is a second authority and is rejected",
        "62 relation row world = io or world = fs or world = json fails — authority is an application witness not a category string",
    }
    fails = "lexical gate alone or namespace respelling without semantic role change"
}

decisionprocedure = law{
    id    = "law.decision.procedure"
    kind  = .invariant
    holds = .absolute
    binds = {
        "for every operation ask what is the relation",
        "for every relation ask what is the subject",
        "for every qualifier ask is this descriptor law world effect origin demand provenance or realization",
        "for every home ask is it only context",
        "for every protocol ask what facts are demanded",
        "for every union ask what alternatives remain possible",
        "for every world ask what authority is actually granted",
        "for every api ask can this namespace disappear",
        "for every helper ask does an irreducible meaning remain",
        "for every binding ask why does this value need an id",
        "for every representation ask what observation forced commitment",
        "for every foreign name ask where is the law or equivalence witness",
        "for every success claim ask what production evidence proves it",
        "for every explicit to projection ask whether binding parameter result or field demand already fixes the target uniquely",
        "for every omitted relation ask whether one direct bridge is uniquely demanded or IMPLEMENTATION-BLOCKED applies",
        "if the answer requires conventional language terminology rather than idol facts reduce again",
    }
}

completionmetric = law{
    id    = "law.completion.metric"
    kind  = .invariant
    holds = .canonical
    binds = {
        "a 100 percent canonical closure claim requires a machine census proving canonical std namespace uses are zero",
        "canonical lua namespace api uses are zero",
        "canonical req require import include module namespace use inject admit uses are zero",
        "canonical unresolved operation uses are zero",
        "native operations lacking a canonical relation id are zero",
        "parallel protocol implementation registries are zero",
        "protocol satisfaction by name shape or foreign interface equality is zero",
        "protocol induced boxing by default is zero",
        "world authority granted by namespace home or protocol is zero",
        "ambiguous implicit world injection is zero",
        "native sentinel absence or failure is zero",
        "qualifier encoded native relations are zero",
        "semantic compound identifiers are zero",
        "native uppercase identifiers are zero",
        "native underscore identifiers are zero",
        "storage category used as semantic value kind is zero",
        "source syntax category used as semantic authority is zero",
        "semantic reconstruction after resolution is zero",
        "tooling owned semantic vocabulary is zero",
        "compatibility debt and foreign debt are reported separately and never mixed with canonical debt",
    }
    fails = "a 100 percent canonical claim without the machine census proving every canonical debt class at zero"
}

protocolone = law{
    id    = "law.protocol.one"
    kind  = .invariant
    holds = .constraint
    binds = {
        "PROTOCOL-ZERO there is no independent protocol semantic identity when an existing relation or fact set fully specifies the constraint",
        "ADJECTIVE-ZERO a native adjective derived only from an existing relation does not receive semantic identity",
        "CONSTRAINT-ONE all generic and protocol requirements are ordinary demanded semantic facts relations descriptor facts shape facts laws world requirements effect limits and origin constraints when meaningful",
        "RELATION-CONSTRAINT a relation in constraint position demands witness that the subject admits the required call shapes for the constrained application",
        "SHAPE-CONSTRAINT only the relation call shapes actually demanded are required unless an explicit public constraint demands more",
        "INFER-ONE constraints uniquely derivable from authoritative facts are unwritten per law.infer.one",
        "WITNESS-ZERO-RUNTIME a compile time satisfaction witness has no mandatory runtime representation",
        "COHERENCE-BY-FACT multiple applicable specializations resolve only through unique semantic specificity required facts subset known facts prefer strongest uniquely satisfied requirement set unresolved incomparability is AMBIGUOUS and fails never broken by import file declaration package or path order",
        "ASSOCIATED-ZERO associated types and constants are ordinary result descriptor and fact projections not protocol owned namespaces",
        "DYN-ZERO runtime polymorphism is realization of remaining semantic alternatives not a separate dynamic protocol type system",
        "a protocol is not an independent semantic identity it is a projection of one or more existing relations used as constraints on an unknown subject",
        "the canonical constraint for read is read not readable consume = (source: read) source:read() demands the subject admit read for the call shapes demanded and no second readable concept exists",
        "a relation appears as one identity in application position source:read() constraint position source:read reflection position read graph relation id read and machine provenance relation id read with no protocol conversion step",
        "denied adjectives resolve to relations read write seek iter hash eq lt le call clone copy encode decode to from index sort format drop default and laws where the meaning is property not operation",
        "denied adjectives include readable writable seekable iterable hashable equatable comparable callable cloneable copyable serializable deserializable convertible indexable sortable printable formattable",
        "denied operator protocol identities include Add Sub Mul Eq Ord Index trait object dyn read impl read for file and marker traits Send Sync Copy Sized as protocol kinds",
        "default trait methods become separate relations such as readall derivable from read not protocol owned defaults",
        "conversion constraint is to target or from source not Convertible From Into Cast TryFrom protocol kingdoms",
        "iteration architecture centers on iter not Iterable Iterator IntoIterator",
        "serialization uses encode decode format parse to from with format law descriptor not Serializable",
        "option result nullable and dyn read collapse to value alternatives result pack failure alternatives and relation constraints",
        "union plus relation constraint if all alternatives witness relation project over union if some missing require refinement if none invalid if one remains specialize completely",
        "the relation catalog is the universal protocol catalog no separate trait registry interface catalog or protocol registry",
        "tooling lsp and mcp query relation witnesses not methods interfaces traits or modules",
        "law.constraint.protocol readable and writable adjective examples are superseded by this relation as constraint form",
        "final equation unknown subject plus demanded relation shapes plus descriptor facts plus laws plus world obligations plus effects equals constraint and known subject facts superset constraint yields witness then witness plus demand plus target yields realization with no protocol layer between",
    }
    canon = {
        "consume = (source) source:read()",
        "consume = (source: read) source:read()",
        "consume = (source: { read: bytes = () }) source:read()",
        "copy = (source, sink) sink:write(source:read())",
        "digest = (source: read) source:read():hash()",
        "sum = (xs: iter) ...",
        "make = (path) path:open()",
        "consume = (source: file | socket) source:read()",
    }
    deny  = {
        "readable", "writable", "seekable", "iterable", "hashable", "equatable",
        "comparable", "callable", "cloneable", "copyable", "serializable",
        "deserializable", "convertible", "indexable", "sortable", "printable",
        "formattable", "impl read for file", "trait", "interface", "implements",
        "concept", "dyn read", "Option", "Result", "Read", "Write", "Iterator",
        "Iterable", "IntoIterator", "Add", "Sub", "Mul", "Eq", "Ord", "Index",
        "Convertible", "From", "Into", "Send", "Sync", "Copy", "Sized", "Pure",
        "Async", "Fallible", "ThreadSafe",
    }
    fails = "an adjective protocol name duplicating an existing relation a protocol semantic identity beside the relation or a trait subsystem when relation constraint algebra suffices"
}

specializealgebra = law{
    id    = "law.specialize.algebra"
    kind  = .invariant
    holds = .order
    binds = {
        "relation implementation resolution is partial order selection over facts",
        "candidate admissible when required facts subset known facts",
        "prefer candidate with strongest uniquely satisfied requirement set",
        "if exact ambiguity remains fail as AMBIGUOUS",
        "never use import order file order declaration order package priority or last definition wins as semantic tie breakers",
        "one mechanism serves protocol like generic specialization hardware specialization descriptor specialization compile time value specialization world specialization and shape specialization",
        "this is Idol coherence rule replacing orphan rules and impl registries",
    }
    fails = "coherence by declaration order or global impl registry instead of fact specificity"
}

inferfirst = law{
    id    = "law.infer.first"
    kind  = .invariant
    holds = .density
    binds = {
        "operative projection of law.infer.one for callable relation constraints and early protocol examples",
        "consume = (source) source:read() is canonical when the body supplies the complete inferred read constraint",
        "copy = (source, sink) sink:write(source:read()) infers read write and result compatibility without explicit source: read sink: write",
        "twice = (x) x + x infers demanded arithmetic relations from the body",
        "explicit relation constraints appear only when public contract intentionally promises beyond inference",
    }
    fails = "generic ceremony restating facts already derivable from body or context"
}

inferone = law{
    id    = "law.infer.one"
    kind  = .invariant
    holds = .constraint
    binds = {
        "endpoint is not make to shorter — to is a semantic relation that should usually exist in the graph without existing in source",
        "INFER-ONE generalizes fact recoverability across conversions projections worlds descriptors calls and curry stages — not conversion syntax alone (SOURCE-INFER-ONE)",
        "every source token must contribute semantic information not already uniquely recoverable from graph-visible demand context — source is a disambiguation surface not a dump of graph facts",
        "write only the semantic information that cannot be uniquely recovered from authoritative facts",
        "the compiler must know more than the source says and the source must not mechanically restate what the compiler already knows",
        "for every application distinguish supplied facts demanded facts inferred facts world witnesses semantic relation and realization",
        "authoritative fact sources include subject descriptor binding descriptor parameter descriptor result descriptor field descriptor relation declaration projection declaration operand constraint result demand union refinement shape facts law stage world context foreign boundary contract ABI semantic contract and surrounding application",
        "the resolver performs semantic constraint solving over known facts before demanding explicit syntax",
        "known facts plus contextual demands plus relation requirements plus world availability plus law yield unique semantic solution or diagnose or require explicit source — never guess",
        "canonical source is the minimum uniquely resolving projection of the semantic graph",
        "canonicalizer preference order is no spelling then relation only then relation plus required projection then relation plus projection plus required operands then full explicit source where each shorter form preserves one unique semantic result",
        "explicitness is not automatically more canonical and redundant semantic information is migration debt",
        "implicit relation insertion uses at most one direct semantic bridge relation under DIRECT-BRIDGE-ONE — no arbitrary conversion path search",
        "if supplied value already satisfies demanded descriptor and law insert no to — identity conversion zero is descriptor satisfaction not conversion",
        "omitting to from source does not erase it semantically — graph may retain inferred application with provenance when unique bridge is required",
        "conversion ladder for to is level 0 omit when relation and target uniquely inferable then value:to(target) when target must be explicit then migrate historical to(target)(value) stopping at shortest uniquely valid face — value:to() is not a canonical rung because if the relation is explicit and target uniquely inferable the target is graph-visible demand and spelling to adds no information",
        "to is written ONLY when the target conversion cannot be inferred — value:to() is not canonical default syntax",
        "parameter result field operand interpolation and projection elision all follow the same rule — infer when unique from surrounding descriptor demand",
        "result demand flows backward parameter and field demand flow inward — inference is not exclusively left to right",
        "world context validates authority and witnesses effects it does not invent target intent",
        "inferred conversion must preserve failure effect and world obligations or remain explicit or diagnose",
        "do not insert to(bool) for every conditional — truth law decides whether bool conversion is required",
        "exact integer literals constrained to i32 are descriptor specialization not default i64 literal followed by to(i32)",
        "physical ABI width layout or register representation changes are realization facts not semantic to",
        "foreign semantic conversion remains distinct from ABI realization and preserves origin foreign law and witness separately",
        "constraint solving is not program synthesis — NO-MAGIC-SEARCH forbids arbitrary relation sequences to satisfy a target",
        "when multiple incomparable candidates remain fail AMBIGUOUS — never declaration order file order import order package priority or last definition wins",
        "canonicalization operates on resolved graph facts compares semantic identity and is idempotent — never regex-delete casts",
        "inference must not change application cardinality — removing syntax may not lie about one versus two semantic applications",
        "inference should reduce currying complexity not increase it — do not curry for target descriptor world injection or ordinary parameter conversion",
        "satisfaction conversion and realization are three distinct proofs — do not conflate descriptor satisfaction semantic to application and physical representation",
        "agents and MCP must query semantic demand before adding conversions — IMPLEMENTATION-BLOCKED not redundant workaround when inference is missing",
        "no new explicit conversion projection curry or world plumbing until author proves the fact cannot be uniquely recovered from existing context",
        "resolver algorithm for each demanded slot — (1) direct satisfaction (2) exactly one direct bridge relation (3) infer projection when relation named but projection missing (4) world witness or diagnose (5) failure obligations consumed (6) ambiguity requires explicit source",
        "inference priority order — direct semantic satisfaction then exact descriptor or refinement then exact relation projection then unique direct bridge then unique world witness then realization — never conversion before satisfaction",
        "syntax priority for authors and canonicalizer — omit inferred relation then omit inferred projection then subject orientation then true operands only then genuine curry only then world explicit only when ambiguity requires it",
        "do not spell relation wrappers that add no semantic choice — f(x) not f:call(x) and table[key] not table:get(key) when projection already conveys the relation",
        "do not spell static qualification when an unqualified binding is uniquely resolved and human-obvious — env[HOME] preferred over os.env[HOME] — keep qualification only when it disambiguates actual semantic identity",
        "projection is explicit in the GRAPH not necessarily SOURCE — injection is explicit in the GRAPH not necessarily SOURCE — protocol witness is explicit in the GRAPH not necessarily SOURCE — world witness is explicit in the GRAPH not necessarily SOURCE — closure capture is explicit in the GRAPH never manually declared when resolver can derive it",
        "no source inject interject use-world capability declaration or @{...} dependency world list when use already determines the dependency",
        "human clarity is the only secondary guard — if compiler inference is unique but omission would make the operation genuinely unclear to a human retain the irreducible meaningful relation — source:read() may remain because source() is semantically opaque to a human",
        "never preserve explicit syntax merely because compiler inference is not implemented yet — mark IMPLEMENTATION-BLOCKED then implement inference — do not canonize the workaround",
        "graph fact deletion is NOT implied by source spelling deletion — inferred relation projection conversion witness capture remain exact graph ids edges facts",
        "canonical density objective — MINIMUM SOURCE SPELLING MAXIMUM GRAPH SEMANTICS ZERO REDUNDANT REALIZATION",
        "gate every explicit source .to( explicit projection chain helper binding used once .get( :call( world injection declaration — ask WHAT INFORMATION HERE COULD NOT HAVE BEEN INFERRED — no answer delete spelling",
        "final law — facts before syntax demand before casts descriptors flow inward results flow backward world grants authority but does not invent intent relations injected only when one direct semantic bridge is uniquely demanded projection omitted when uniquely recoverable to omitted when uniquely recoverable currying only for a real callable stage realization never masquerades as conversion shortest uniquely resolving source is canonical richest accurately preserved graph is authoritative cheapest lawful realization is selected last",
    }
    canon = {
        "enabled: bool = value",
        "enable(value)",
        "check: bool = (value) value",
        "config{ enabled = value }",
        "stream:read(buffer)",
        "serve(flag, n)",
    }
    deny  = {
        "value:to(T) when T is already the exact demanded descriptor",
        "value:to() when to itself is uniquely injectable",
        "value:to() as a canonical rung — if relation is explicit and target uniquely inferable spelling to adds no information",
        "f(value:to(i64)) when parameter slot already exactly demands i64 and bridge is unique",
        "x: str = value:to(str) when unique conversion proof exists",
        "f:call(x) or table:get(key) when application already conveys the relation",
        "os.env[HOME] or qualified path when unqualified binding is uniquely resolved and human-obvious",
        "checked = value:validate() checked:normalize() — naming an intermediate used once when value:validate():normalize() preserves identity",
        "bulk regex deletion of to without graph identity proof",
        "multiple bridge steps for one demanded slot",
        "world availability alone choosing conversion target",
        "inject interject use-world capability declaration or @{...} dependency world list when use already determines the dependency",
        "preserving explicit syntax merely because compiler inference is not implemented yet",
    }
    fails = "requiring or preserving redundant explicit syntax when authoritative facts already determine one unique semantic result"
}

intermediatezero = law{
    id    = "law.intermediate.zero"
    kind  = .invariant
    holds = .density
    binds = {
        "do not name intermediate values used once when the chain preserves semantic identity — value:validate():normalize() not checked = value:validate() checked:normalize()",
        "a single-use binding exists only to control the next branch or call and carries no independent semantic identity — spelling it adds source without adding graph facts",
        "INTERMEDIATE-ZERO applies to bindings relation results projection chains and conversion steps alike — not only to conversion intermediates",
        "retain a named intermediate only when the name contributes semantic information the chain does not — e.g. a binding observed by multiple consumers or a place whose identity matters for human clarity",
        "the canonicalizer collapses single-use intermediates by proving the chain re-resolution preserves semantic identity before removing the binding — never regex-delete bindings without graph proof",
        "intermediate elision does not erase the graph fact — the application chain remains exact in the graph with provenance",
        "IF ONE USE FOLLOWS ANOTHER LINEARLY DO NOT NAME THE INTERMEDIATE",
    }
    canon = {
        "value:validate():normalize()",
        "source:read():parse(json)",
        "xs:first():to(str)",
    }
    deny  = {
        "checked = value:validate() checked:normalize()",
        "text = source:read() text:parse(json)",
        "first = xs:first() first:to(str)",
        "naming an intermediate whose only consumer is the next call in a linear chain",
    }
    fails = "naming a single-use intermediate that carries no semantic information beyond the chain it forwards"
}

systeminvariant = law{
    id    = "law.system.invariant"
    kind  = .invariant
    holds = .absolute
    binds = {
        "no agent may introduce a bootstrap adapter without simultaneously recording its semantic owner physical owner facts crossing the bridge facts lost facts reconstructed fallback behavior exact deletion prerequisite and an exact negative control proving deletion: a bridge without an executable deletion condition is permanent architecture by default (BRIDGE-DEATH)",
        "temporary fallback is acceptable only when the canonical owner attempts the decision and either succeeds or reports an unsupported boundary and never silently asks the old host owner when uncertain: sabotaging the old host implementation after authority transfer must leave production behavior correct or explicitly failing (no silent fallback that makes correctness depend on two semantic languages forever)",
        "every authoritative semantic fact has exactly one producer boundary and a fact catalog maps fact to producer to consumers to provenance and rejects multiple authoritative producers",
        "lack of knowledge is a graph state never a fabricated semantic value (UNKNOWN-ONE): known true known false unknown not applicable not demanded and not yet produced are distinct and never collapsed into false zero empty default an unknown enum member nullable or a placeholder id",
        "negative facts (does not alias cannot fail cannot escape world not required value not mutable relation not available case impossible allocation impossible effect absent) are preserved when useful because they let machinery disappear",
        "ownership alias lifetime and escape are facts and proofs over values and places not a second type system unless an independently observable semantic law demands it (OWNERSHIP-ZERO)",
        "effects are compositional facts answering may reorder may eliminate may duplicate may speculate may fuse requires world may fail and observable lifetime: a boolean has side effects destroys too much information",
        "only observable dependency or order survives into realization and statement order is not carried as permanent semantic dependency",
        "inference is direct local monotonic uniquely witnessed and bounded with a complexity budget: no global backtracking no arbitrary relation chain search and syntax saved must not exceed the cost of expensive inference",
        "every fact is rich but its representation is brutally compact: no source construct implies allocation no protocol implies runtime witness no union implies tag or box no curry implies closure no world implies world object no binding implies storage no structured value implies aggregate and every physical object can answer the semantic observation that forced it or it is a candidate for deletion",
        "profile evidence selects realization it never rewrites semantic truth and speculative assumptions carry guard witness lineage dependents invalidation propagation and fallback deopt semantics with no orphan assumptions",
    }
    canon = { "bridge deletion witness at introduction", "sabotage old host stays correct", "one producer per fact", "unknown stays unknown", "negative facts preserved", "facts rich representation compact" }
    deny  = { "bridge without deletion condition", "silent fallback to old host", "fabricated placeholder for unknown", "rust shaped ownership subsystem", "boolean purity", "profile as semantic truth", "inference backtracking", "physical object without forcing demand" }
    fails = "a temporary bridge becoming permanent authority, expensive hidden magic inference, or semantic richness turning into physical compiler bloat"
}

sourceminimum = law{
    id    = "law.source.minimum"
    kind  = .invariant
    holds = .projection
    binds = {
        "canonical source is the shortest uniquely resolving spelling of the semantic graph",
        "redundant target projection relation operand or world plumbing is migration debt not canonicality",
        "the canonicalizer removes only facts proved redundant by re-resolution after hypothetical elision",
    }
    fails = "treating longer explicit source as more canonical when semantic identity is unchanged"
}

directbridgeone = law{
    id    = "law.direct.bridge.one"
    kind  = .invariant
    holds = .bridge
    binds = {
        "implicit relation insertion uses at most one direct admitted bridge relation from supplied facts to demanded facts",
        "no search of arbitrary conversion paths A to B to C to D to satisfy demand",
        "longer transformations require explicit source or one separately admitted semantic relation identity",
    }
    fails = "unpredictable multi-hop conversion search or hidden bridge chains"
}

conversiontripart = law{
    id    = "law.conversion.tripart"
    kind  = .invariant
    holds = .distinction
    binds = {
        "satisfaction means value already meets demand — no relation application",
        "conversion means semantic relation to(T) or equivalent bridge changes or establishes demanded domain or law — graph application exists",
        "realization means same semantic value represented differently at machine or foreign boundary — no to",
    }
    fails = "physical cast parse transform or ABI obligation disguised as ordinary semantic to"
}

infergate = law{
    id    = "law.gate.infer"
    kind  = .protocol
    holds = .adversarial
    binds = {
        "REDUNDANT-TO-ZERO new canonical code may not contain explicit to projection proved redundant by graph canonicalization",
        "IMPLIED-PROJECTION-ZERO new canonical code may not spell projection facts uniquely recoverable when shorter source is semantically identical",
        "IMPLICIT-MAGIC-ZERO inference may not introduce multiple bridge steps unrequested effects unbound failure unavailable world authority arbitrary candidate ordering or representation-only semantic conversions",
        "control 1 explicit binding target infers to(T) when required",
        "control 2 explicit parameter descriptor infers to(T)",
        "control 3 explicit result descriptor infers to(T)",
        "control 4 explicit field descriptor infers to(T)",
        "control 5 already-satisfying value inserts no to",
        "control 6 exact integer literal constrained to i32 inserts no fake i64 to i32 conversion",
        "control 7 two possible targets require explicit to(T)",
        "control 8 explicit to() with uniquely inferred target succeeds",
        "control 9 to() with ambiguous target fails",
        "control 10 conversion with unhandled failure cannot be silently inserted",
        "control 11 conversion with unavailable world cannot be inserted",
        "control 12 two available world witnesses remain ambiguous",
        "control 13 world availability alone cannot choose conversion target",
        "control 14 physical ABI width change produces realization fact not to",
        "control 15 historical to(T)(x) canonicalizes as far down the inference ladder as facts allow",
        "control 16 inferred conversion still appears in semantic graph and provenance",
        "control 17 removing redundant explicit to preserves semantic identity",
        "control 18 removing nonredundant explicit to(T) changes resolution and is rejected",
        "control 19 projection elision on read(number) preserves projection pack fact",
        "control 20 ambiguous read projection forces explicit qualifier",
        "control 21 nonescaping genuine curry still has zero required closure allocation",
        "control 22 projection inference never creates a curry application",
        "control 23 conversion inference never changes application cardinality",
        "control 24 foreign semantic conversion remains distinct from ABI realization",
        "control 25 canonicalization is idempotent",
        "staged text gates are migration pressure until GAP-124 graph canonicalization owns REDUNDANT-TO-ZERO and IMPLIED-PROJECTION-ZERO",
    }
    fails = "text-heuristic cast deletion or redundant to ratchet without graph identity proof"
}

parenone = law{
    id    = "law.paren.one"
    kind  = .invariant
    holds = .constraint
    binds = {
        "parens are the sole application grouping delimiter but their semantic role is resolved from the head not the punctuation",
        "parens after a relation identity in declaration selection or constraint position project the relation so to(str) means relation to with projection target str and no call has happened and no intermediate callable is produced",
        "a declaration r(p...) = (s, a...) defines relation r projection pack p subject s and ordinary operand pack a where subject identification is semantic not permanently first parameter",
        "r(p) where p belongs to the declared relation projection shape does not produce an intermediate callable value so to(str) read(number) encode(json) are projections not curries",
        "parens applied to a callable value perform an ordinary call with operand pack and f(a)(b) is two applications only when f(a) actually yields a callable semantic value",
        "descriptor law stage or target qualification should use relation projection rather than currying whenever it changes relation specialization rather than representing runtime application data",
        "an application carries relation times projection pack times subject times operand pack times result pack plus descriptor law world effect stage demand and provenance facts",
        "projection arguments are semantic specialization facts and operand arguments are application values and they must never be conflated",
        "after name resolution a:b(c)(d) is one application when b is an admitted relation and c belongs to b's declared projection shape with subject a and ordinary operands d; it is two applications only when b(c) is an ordinary application whose result is callable",
        "each relation declaration establishes projection arity and shape so lx:read(number)(b) is unambiguous and cannot be read as method-then-curry",
        "projection parameters are relation parameters not callable types — do not type to as descriptor arrow value arrow str; the catalog carries relation to projection target subject result",
        "in constraint position value: to(str) means the subject must admit relation to with projection target str without inventing convertible or protocol objects",
        "subject-relation orientation is the colon face value:to(str); postfix @ carries a world not a relation (law.at.one), so value@to(str) relation anchoring is superseded and value@world qualifies value under world",
        "prefer subject then relation projection then operand pack then genuine currying then closure capture when choosing surface syntax",
        "runtime-dynamic values belong in the operand pack; projection is for qualification facts the graph can treat as semantic specialization",
    }
    canon = {
        "to(str) = (value)",
        "value:to(str)",
        "read(number) = (lx, b)",
        "lx:read(number)(b)",
        "value:encode(json)",
        "stream:read(number)(buffer)",
    }
    deny  = {
        "to(str) as a callable producing curry",
        "to(str)(value) at an invocation site",
        "intermediate callable for a relation projection",
        "arrow kind to: descriptor -> value -> str",
        "treating every f(a)(b) surface as currying before resolution",
    }
    fails = "treating a relation projection as an ordinary curried call or conflating projection facts with operand values"
}

projectionhead = law{
    id    = "law.projection.head"
    kind  = .invariant
    holds = .declaration
    binds = {
        "to(str) = (value) declares relation to with projection target str and subject value — the head parentheses project the relation they do not curry it",
        "read(number) = (lx, b) declares projection number subject lx and operand b",
        "operation-first to(str)(value) at a call site is not projection — it misreads declaration projection as callable curry",
        "invoke with subject-first value:to(str) or lx:read(number)(b) never call to(str) then value",
    }
    canon = { "to(str) = (value)", "value:to(str)", "read(number) = (lx, b)", "lx:read(number)(b)" }
    deny  = { "to(str)(value)", "read(number)(lx) without subject", "encode(json)(value) operation-first" }
    fails = "reading relation declaration projection as an intermediate callable"
}

currystructural = law{
    id    = "law.curry.structural"
    kind  = .invariant
    holds = .constraint
    binds = {
        "call shape is exact: a one operand call is one operand and is not a hole filled larger call so f(a) for declared f = (a, b) is the actual one operand call shape if such a shape exists not partial application of f(a, b)",
        "implicit curry from missing arity is forbidden because it would make overloaded call shapes optional operands variadic packs foreign ABI multiple return packs projection packs and descriptor inference ambiguous",
        "do not add hole partial bind curry or _ syntax for partial application: use an ordinary closure fixed = (b, c) f(a, b, c) which realization may erase when demand permits",
        "arbitrary operand hole anchoring such as f(_, x) or f@arg(x) is not admitted: operand-position holes are ambiguous and forbidden",
        "a nonescaping genuine curry scale(2)(x) must permit zero closure allocation zero environment allocation zero indirect call and zero runtime curry dispatch",
        "the subject-relation face is the colon value:relation and postfix @ carries a WORLD only value@world never a relation; value@relation subject anchoring is superseded per law.at.one and no bound method object is minted",
    }
    canon = { "scale = (k) (x) x * k", "scale(2)(x)", "r = file:read", "fixed = (b, c) f(a, b, c)" }
    deny  = { "implicit partial application from missing arity", "_ hole syntax", "f@arg operand anchoring", "mandatory closure for nonescaping curry", "value@relation subject anchoring superseded — use value:relation" }
    fails = "inferring currying from missing operands or mandating runtime allocation for a nonescaping callable stage"
}

assignchain = law{
    id    = "law.assign.chain"
    kind  = .invariant
    holds = .chain
    binds = {
        "fresh chained binding a = b = expression evaluates expression exactly once produces one semantic value id v and binds b to v and a to v with no copy implied and no duplicate evaluation",
        "parse a = b = c = expression as expression to v then c binds v then b binds v then a binds v: one evaluation one semantic value several bindings",
        "if any target is an existing mutable place the chain requires a graph witness proving place expressions evaluated exactly once write order preserved aliasing preserved failure preserved effects preserved assignment law preserved and result value preserved otherwise reject",
        "plain assignment yields the assigned semantic value so chaining requires no special semantic operation and no assignchain relation exists",
        "chained compound update such as a += b += 1 or a *= b *= x is denied canonical source because compound update already requires an equivalence witness and chaining adds unnecessary evaluation alias complexity with no syntax density benefit",
    }
    canon = { "a = b = expression", "a = b = c = expression" }
    deny  = { "a += b += 1", "a *= b *= x", "two evaluations of f() in a = b = f()", "copy x into b then copy b into a" }
    fails = "chained assignment implemented as repeated copies repeated RHS evaluation or place chain without an equivalence witness"
}

repairinfer = law{
    id    = "law.repair.infer"
    kind  = .protocol
    holds = .sequence
    binds = {
        "census every to occurrence in canonical id before rewrite classify by surrounding semantic demand never bulk delete",
        "class A redundant target and relation x str = value:to(str) becomes x str = value when unique",
        "class B redundant parameter f(value:to(i64)) becomes f(value) when slot demands i64 uniquely",
        "class C redundant result body value:to(str) becomes value when result demands str uniquely",
        "class D redundant field count = value:to(i64) becomes count = value when field demands i64",
        "class E target inferable relation explicit omit to entirely when target uniquely inferable from demand — value:to() is not a canonical rung",
        "class F explicit target necessary keep value:to(str) when no surrounding demand fixes target",
        "class G no conversion needed delete to when value already satisfies descriptor",
        "class H physical cast delete semantic to move width to realization",
        "class I wrong relation migrate parse validate decode to proper relation not implicit to",
        "class J failing conversion keep explicit or diagnose when failure unbound",
        "class K world effectful conversion keep explicit when authority not already demanded",
        "class L historical to(str)(value) migrate down ladder to shortest unique form",
        "foreign compatibility examples do not train canonical inference classify by corpus role first",
        "run scripts/census/infer.id before bulk repair — classify each site A through L never regex-delete",
    }
    fails = "bulk to deletion or rewrite without per-site semantic classification and graph identity proof"
}

# ── Conversion derivation and declaration laws (projections extension) ────
# These extend PROJECTION-ONE with bounded derivation semantics and
# conversion-edge declaration architecture. The §67 projectionone already
# states the high-level rules; these add the operational detail.

conversionderive = law{
    id    = "law.conversion.derive"
    kind  = .invariant
    holds = .bounded
    binds = {
        "the graph may derive a conversion witness compositionally when an admitted algebra proves source to canonical to target and produces one normalized witnessed edge — composition preserves the meet of conversion laws exact lossless checked narrowing view consuming — no weak law is silently strengthened",
        "bounded derivation — implicit inference may consume a derived edge only when the derivation rule is bounded the canonical hub law is already admitted exactly one normalized witness exists its composite law is valid for implicit use and no alternate incomparable witness exists — no general shortest path conversion engine no declaration order tie breaking no whole graph search for something that type checks",
        "if two derivations produce incomparable witnesses the result is AMBIGUOUS — require explicit semantic information — do not pick by shorter path first declaration module priority home priority or world priority",
        "DIRECT-INFER normal implicit conversion resolution consumes a direct or already normalized derived edge from an indexed relation catalog — it does not itself perform arbitrary multi hop search",
        "lossy checked narrowing rounding truncating or consuming conversion may be implicitly inserted only when surrounding explicit semantic demand and failure obligations already make that law uniquely intended — an explicit destination descriptor can constitute intent for a known narrowing law but failure cannot disappear",
    }
    fails = "arbitrary conversion path search declaration order resolution or silent failure elimination in derived conversion"
}

conversiondecl = law{
    id    = "law.conversion.decl"
    kind  = .invariant
    holds = .home
    binds = {
        "conversion edge declarations prefer home based specialization where the ambient subject descriptor supplies the source descriptor — inch home containing to micron equals value value times 25400.0 means relation to source descriptor inch projection target micron law lossless — no source descriptor operand needs to be repeated",
        "operation first to micron inch equals stretch is mechanically useful but semantically backwards for subject orientation because no actual source value is possessed",
        "exact grammar must be reconciled before mass migration of conversion declarations",
        "current hardcoded literal to checks in codegen are host projection debt — primitive conversion edges must become ordinary relation facts and no string comparison may remain semantic authority",
        "current conversion trie or index is acceleration not semantic authority — deleting or rebuilding the trie preserves conversion semantics from authoritative relation facts — never let trie key descriptor string or path become identity",
    }
    fails = "conversion edge declared operation first without possessed subject or string comparison as semantic authority for conversion"
}

# Canonical examples (non-exhaustive; canon and deny fields above are binding):

algebraexamples = {
    pathopen   = { face = "file = path:open()", facts = "open subject path world io result file" },
    fileread   = { face = "data = file:read()", facts = "read subject file world io result data" },
    consumer   = { face = "consume = (source: read) source:read()", note = "concrete source descriptor preserved" },
    inferred   = { face = "consume = (source) source:read()", note = "most canonical when body is the contract" },
    explicit   = { face = "consume = (source: { read: bytes = () }) source:read()", note = "public call shape without readable adjective" },
    tworelation = { face = "copy = (source, sink) sink:write(source:read())", note = "inferred read and write constraints" },
    derived    = { face = "digest = (source: read) source:read():hash()", note = "generic specialization not blanket impl" },
    unionuse   = { face = "consume = (source: file | socket) source:read()", note = "both alternatives must witness read" },
}

stagingalgebra = law{
    id    = "law.staging.algebra"
    kind  = .invariant
    holds = .early
    binds = {
        "protocol resolution union elimination world injection descriptor application and standard projection happen as early as facts permit",
        "compile time known facts delete runtime work",
        "do not preserve generic runtime dispatch after specialization proves the concrete case",
        "reflection materializes evidence only when demanded and reflection demand pays its own cost",
        "compact protocol indexes may accelerate queries but deleting the index preserves semantic correctness",
    }
    fails = "runtime dispatch protocol registry or witness materialization retained after static facts eliminate it"
}

shcrequirement = law{
    id    = "law.shc.requirement"
    kind  = .objective
    holds = .compiler
    binds = {
        "compiler b must not implement module system trait system protocol system impl registry impl coherence interface runtime trait objects associated types associated constants trait inheritance marker traits generic dictionaries standard namespace method dispatch optional type kingdom boxed union kingdom process api kingdom or os api kingdom when ordinary semantic graph algebra already expresses them",
        "every concept deleted from the language and compiler lowers the self host compiler surface",
        "this algebra exists to simplify compiler b not to delay the earliest executable shc frontier longer than the exact semantic prerequisite requires",
    }
}

generatedprojection = law{
    id    = "law.generated.projection"
    kind  = .protocol
    holds = .one
    binds = {
        "one constitution and source graph generates or projects agent orientation cursor rules pi skill poolside context grammar roles lexer tables tree sitter formatter canonicalizer lsp mcp relation catalog world catalog canonicality gates and documentation",
        "do not hand maintain independent lists that duplicate constitutional law",
        "harness and agent instructions are projections of this section not parallel semantic owners",
        "session prompts that repaste algebra closure law are void when they duplicate or conflict with this section",
    }
    fails = "independent prompt law duplicate harness vocabulary or hand maintained parallel rule lists"
}

witnessalgebra = law{
    id    = "law.witness.algebra"
    kind  = .invariant
    holds = .proof
    binds = {
        "witness is proof of relation constraint satisfaction or unique injection and is not a runtime dictionary by default",
        "consume = (source: read) source:read() with consume(file) retains concrete file descriptor read witness and canonical read relation",
        "normal realization is zero protocol object zero interface object zero vtable zero boxing zero runtime witness and direct specialization",
        "materialize witness data only when reflection or runtime uncertainty is demanded",
        "the witness is evidence and is not a second implementation identity",
    }
    fails = "witness treated as authority world grant or mandatory runtime object"
}

ambientsubject = law{
    id    = "law.ambient.subject"
    kind  = .invariant
    holds = .home
    binds = {
        "inside a subject home leading colon uses the ambient resolved subject",
        "file: { digest = () :read():hash() } applies read and hash to the ambient file subject",
        "zero argument callable and ambient subject call remain distinct faces",
        "do not rewrite read() as an implicit ambient call when the callable is genuinely zero argument",
    }
    canon = { "file: { digest = () :read():hash() }" }
    fails = "implicit ambient call conflated with zero argument callable or home used as method owner"
}

worldfield = law{
    id    = "law.world.field"
    kind  = .invariant
    holds = .observation
    binds = {
        "distinguish world capability from ordinary data obtained through that capability",
        "environment state is authority bearing observation not an os namespace",
        "do not canonize os.getenv(name) std.os.getenv(name) or process.getenv(name)",
        "when env is the admitted world value projection canonical use is env(name) under the ordinary application algebra",
        "command arguments are ambient run input projection not os.args() merely because a host exposes that api",
        "the exact source face follows admitted world descriptor not host api spelling",
    }
    deny  = { "os.getenv(name)", "os.args()", "process.getenv(name)", "std.os.getenv(name)" }
    fails = "os or process namespace standing in for world observation or run input"
}

worldoperation = law{
    id    = "law.world.operation"
    kind  = .invariant
    holds = .subject
    binds = {
        "for every historical world api ask what is the true subject then orient to that subject while the world remains an application requirement",
        "open path read file write file or stream connect endpoint send socket or request receive socket or stream sleep duration now clock observation random generation source run command value",
        "do not encode world authority in the operation name or namespace receiver",
    }
    canon = { "path:open()", "file:read()", "stream:write(data)", "run(command)" }
    fails = "io.open fs.open process.run or os.execute as canonical semantic model without subject and world decomposition"
}

runalgebra = law{
    id    = "law.run.algebra"
    kind  = .invariant
    holds = .one
    binds = {
        "collapse the process family toward one semantic run architecture where meanings genuinely coincide",
        "execute capture popen spawn and system must be classified not blindly renamed to run",
        "for each historical name decide whether the difference is output demand scheduling world origin law lifetime streaming or realization",
        "only a genuinely different semantic relation keeps a separate word",
        "capture is usually run plus output demanded as value or evidence not another irreducible execution relation",
        "streaming output may induce stream value and lifetime effect facts without forcing full buffering",
        "foreign os status integers are provenance and evidence never native outcome",
        "transport completion never proves inner requested run success",
    }
    fails = "parallel process api kingdom or host exit code defining native outcome"
}

standardreach = law{
    id    = "law.standard.reach"
    kind  = .invariant
    holds = .scope
    binds = {
        "standard injection is not import std using std req std or lib.std",
        "standard injection is ordinary resolution over default reachable admitted relations descriptors laws world grants and realizations",
        "code does not announce access to universally reachable pure relations",
        "world requiring operations still require the appropriate world fact",
        "discoverability is through lsp mcp and graph queries not namespace browsing",
        "files are ordinary source projections into scope and home topology",
        "same scope files become reachable through the one source authority",
        "do not create req require import include module namespace use inject or admit to solve reachability",
        "a missing reachability projection is an implementation gap not permission for loader syntax",
        "the remaining physical lib std tree is migration distribution only and is not design training data",
    }
    deny  = { "import std", "using std", "req std", "lib.std", "require", "module", "namespace" }
    fails = "loader syntax or privileged standard table standing in for default reachable facts"
}

globalzero = law{
    id    = "law.global.zero"
    kind  = .protocol
    holds = .classified
    binds = {
        "audit lua style global assumptions and classify each by current law",
        "print assert error type next pairs ipairs pcall xpcall rawget rawset getmetatable setmetatable collectgarbage load loadfile dofile require tostring tonumber",
        "each resolves to native admitted relation lua compatibility foreign world operation migration debt or invalid",
        "if a native relation exists canonical source uses that relation",
        "if not admitted do not invent a replacement and report semanticvocabularyblocked",
    }
    fails = "host global silently exposed as native builtin or invented replacement without admitted relation"
}

metamethod = law{
    id    = "law.metamethod.projection"
    kind  = .invariant
    holds = .foreign
    binds = {
        "lua metamethods remain foreign or host law unless separately mapped",
        "do not expose index call len and similar as canonical native semantic vocabulary merely because lua compatibility uses them",
        "map proven equivalents into canonical relations and preserve lua law and provenance otherwise",
    }
    fails = "metamethod name standing in for native relation identity"
}

operatorprojection = law{
    id    = "law.operator.projection"
    kind  = .invariant
    holds = .face
    binds = {
        "operators remain source faces only and after resolution a plus b a:add(b) and add(a,b) may converge to one add",
        "likewise comparisons and numeric operations",
        "no binaryop unaryop semantic kingdom and no operator specific protocol hierarchy or Add Sub Mul Eq Ord Index trait identities",
        "twice = (x) x + x infers x must participate in add from the body without explicit Mul or Add protocol",
        "a relation constraint may require add just like any other relation",
    }
    fails = "operator specific semantic ontology or trait protocol surviving after resolution"
}

indexprojection = law{
    id    = "law.index.projection"
    kind  = .invariant
    holds = .static
    binds = {
        "computed aggregate access is projection table[key] — never application table(key)",
        "do not use table[\"field\"] when static field identity exists and use table.field instead",
        "a genuinely dynamic aggregate key remains a computed projection operand",
        "projection syntax does not force table realization",
    }
    fails = "literal-string bracket access when named projection exposes static identity or application standing in for aggregate indexing"
}

worldvaluefield = law{
    id    = "law.world.value.field"
    kind  = .invariant
    holds = .analysis
    binds = {
        "a field is ordinary semantic projection when its identity is static",
        "request.headers point.x and result.value may be ordinary value projection",
        "os.env process.status and io.stdout must be analyzed as ordinary value world or namespace facade",
        "if namespace facade reduce to subject relation and world facts",
        "do not turn field access into namespace authority",
    }
    fails = "field access preserving namespace facade without subject and world decomposition"
}

noreimplregistry = law{
    id    = "law.noreimpl.registry"
    kind  = .invariant
    holds = .graph
    binds = {
        "protocol resolution must query semantic facts not parallel impl registry trait map interface table or method table authority",
        "compact indexes may accelerate queries and deleting the index preserves semantic correctness",
    }
    fails = "implementation registry as parallel semantic authority"
}

violationclass = law{
    id    = "law.violation.class"
    kind  = .protocol
    holds = .classified
    binds = {
        "every finding classifies as canonical foreign compatibility migration blocked or invalid before repair",
        "namespace operation home.operation(subject) reduces to canonical relation on true subject when applicable",
        "world namespace io os process fs reduces to relation plus true subject plus world requirement",
        "descriptor qualified operation str_len i64_add reduces to relation plus descriptor facts",
        "origin qualified operation call_extern reduces to call plus origin linkage and abi facts",
        "storage qualified operation load_local load_field reduces to semantic access plus genuine place facts or removes fake place",
        "predicate helper hasfoo(x) consumes owned foo fact or case directly",
        "sentinel nil false zero meaning missing maps to union case or refinement at boundary",
        "import load req reduces to source and home reachability",
        "protocol impl reduces to witness derived from graph facts",
        "boxed interface retains concrete id plus constraint witness with runtime representation only if demanded",
        "compound semantic word decomposes qualification into facts and homes",
        "unresolved builtin looking call resolves to admitted relation or marks vocabulary blocked with no fake builtin",
        "do not repair by prettier names when ontology is unchanged",
    }
    fails = "cosmetic respelling without semantic role change or violation left unclassified"
}

auditcensus = law{
    id    = "law.audit.census"
    kind  = .protocol
    holds = .complete
    binds = {
        "perform a complete current tree census not github search sampling",
        "classify all project owned id and source projecting paths including untracked canonical candidates and fail closed on unreadable sources",
        "audit at minimum std lib std io os string table math process clock fs env net proc mproc req require import include module namespace tostring tonumber pairs ipairs nil pcall xpcall rawget rawset getmetatable setmetatable collectgarbage load loadfile dofile",
        "audit lua long strings lua dash comments operation first subject calls uppercase identifiers underscores mashed compounds boolean predicate helpers single consumer bridge bindings host status integers string key relation lookup source name semantic lookup ast shaped semantic categories storage shaped value categories dnir duplicate op names and unresolved operations",
        "do not treat textual match as verdict and resolve semantic role first",
    }
    fails = "sampling based audit or textual match without semantic role resolution"
}

ftcftwalgebra = law{
    id    = "law.ftcftw.algebra"
    kind  = .invariant
    holds = .mandatory
    binds = {
        "this algebra enables zero interface boxing zero unnecessary vtables zero namespace lookup zero string dispatch zero sentinel branching after refinement zero runtime module loading for default relations zero unnecessary union containers zero unnecessary world objects zero process wrapper hierarchy direct call specialization call shape specialization return pack specialization scalarization fusion compile time world and law selection cross language adapter deletion and wasm runtime deletion where law permits",
        "any repair that merely changes names but keeps the physical abstraction is incomplete",
    }
    fails = "namespace respelling or wrapper hierarchy retained while claiming algebra closure"
}

absencerefinement = law{
    id    = "law.absence.refinement"
    kind  = .invariant
    holds = .cases
    binds = {
        "never express maybe through nullable storage when the semantic domain is alternatives",
        "use union and case facts and refinement narrows the possible descriptor or case set",
        "after successful refinement downstream calls consume the narrower facts directly",
        "do not re query with boolean helpers after refinement",
        "resolve lua and foreign sentinels at ingress and map at the boundary",
    }
    fails = "nullable storage or sentinel standing in for union case or refinement facts"
}

compoundaudit = law{
    id    = "law.compound.audit"
    kind  = .protocol
    holds = .suspect
    binds = {
        "treat every new or touched multi concept word as suspect until classified",
        "for each determine whether it is script label only foreign provenance one irreducible word or independent concepts that belong in structure and facts",
        "do not mechanically rename foo_bar to foobar when meaning remains compound",
        "paths projecting semantic homes obey law.path.name",
        "only final semantic classification determines repair",
    }
    why   = "law.path.name"
    fails = "punctuation repair without semantic decomposition"
}

undefinedoperation = law{
    id    = "law.undefined.operation"
    kind  = .invariant
    holds = .zero
    binds = {
        "every canonical operation in id source must resolve to admitted binding relation descriptor application world projection grammar face foreign operation with provenance or compatibility operation in compatibility source",
        "looks builtin is invalid",
        "no agent may invent a convenient helper and rely on host runtime availability",
    }
    fails = "unresolved or host exported operation in canonical native source"
}

gatearchitecture = law{
    id    = "law.gate.architecture"
    kind  = .protocol
    holds = .layered
    binds = {
        "lexical gate catches obvious forbidden syntax",
        "semantic gate resolves relation subject home world protocol origin law descriptor and realization and catches architecture",
        "adversarial negative controls live in law.gate.protocol law.gate.algebra law.gate.infer and law.gate.convergence",
        "textual match alone is not verdict",
    }
    fails = "lexical gate alone substituting for semantic resolution"
}

# ── Convergence meta-invariants (SHC · FTCFTW · multi-agent) ───────────────
# Bridges, fact producers, unknown states, inference bounds, profile evidence,
# incremental/cache semantics, coordination, and physical-delta accountability.
# These prevent bootstrap mechanics from becoming permanent architecture while
# five agent lanes push toward compiler B and 100% executed semantic authority.

bridgedeath = law{
    id    = "law.bridge.death"
    kind  = .invariant
    holds = .deletion
    binds = {
        "BRIDGE-DEATH no new bridge without its deletion witness at introduction",
        "every bootstrap adapter must simultaneously record semantic owner physical owner facts crossing bridge facts lost facts reconstructed fallback behavior exact deletion prerequisite and exact negative control proving deletion",
        "a bridge without an executable deletion condition is permanent architecture by default",
        "applies to zig idol idol c graph dnir dnir backend wasm graph foreign native tool compiler and every other host semantic seam",
        "no agent may introduce a bootstrap adapter without filing the deletion witness",
    }
    canon = {
        "bridgewitness semantic_owner physical_owner facts_crossing facts_lost facts_reconstructed fallback_behavior deletion_prerequisite negative_control",
        "seams zig_idol idol_c graph_dnir dnir_backend wasm_graph foreign_native tool_compiler",
    }
    fails = "bootstrap bridge introduced without deletion prerequisite and sabotage negative control"
}

fallbackzero = law{
    id    = "law.fallback.zero"
    kind  = .invariant
    holds = .authority
    binds = {
        "temporary fallback is acceptable only when canonical owner attempts decision then either succeeds or reports unsupported boundary",
        "forbidden pattern native owner uncertain then silently ask old host owner then continue",
        "correctness must not depend on two semantic languages forever",
        "required negative control sabotage the old host implementation after authority transfer — production behavior must remain correct or fail explicitly if the new owner cannot proceed",
        "no silent fallback may regain semantic authority",
    }
    fails = "silent host fallback or dual semantic authority after transfer"
}

factproducerone = law{
    id    = "law.fact.producer.one"
    kind  = .invariant
    holds = .one
    binds = {
        "for every authoritative semantic fact there must be exactly one producer boundary",
        "token identity producer lexer grammar role producer grammar subject relation application producer resolver world requirement producer relation application resolution demand producer demand analysis placement producer realization instruction range producer machine object emission",
        "if two components both produce the same fact drift is inevitable",
        "fact catalog maps fact to producer to consumers to provenance and rejects multiple authoritative producers",
        "consumers must not reconstruct facts already owned upstream",
    }
    canon = {
        "token_identity lexer grammar_role grammar subject resolver relation resolver application graph world_requirement resolution demand demand_analysis placement realization instruction_range machine",
    }
    fails = "duplicate authoritative producers or shadow fact reconstruction across boundaries"
}

unknownone = law{
    id    = "law.unknown.one"
    kind  = .invariant
    holds = .state
    binds = {
        "UNKNOWN-ONE lack of knowledge is a graph state never a fabricated semantic value",
        "distinguish known true known false unknown not applicable not demanded and not yet produced — these are not interchangeable",
        "forbidden completion patterns false zero empty default unknown enum member nullable field placeholder id standing in for absent knowledge",
        "speculation specialization incremental compilation world resolution profile evidence alias analysis foreign law and union refinement rely on preserving uncertainty rather than collapsing it prematurely",
        "negative knowledge is valuable and must be preserved when useful — does not alias cannot fail cannot escape world not required value not mutable relation not available case impossible allocation impossible effect absent",
        "negative facts often enable machinery to disappear — closure does not escape means no heap closure union case impossible means no runtime tag branch world not required means no capability plumbing",
    }
    fails = "placeholder value substituting for unknown or discarding negative facts that constrain realization"
}

ownershipzero = law{
    id    = "law.ownership.zero"
    kind  = .invariant
    holds = .facts
    binds = {
        "OWNERSHIP-ZERO ownership alias lifetime and escape are facts and proofs over values and places not a second type system unless an independently observable semantic law demands it",
        "do not invent a rust shaped ownership subsystem when graph facts suffice",
        "every mutation lowering must prove exact place lifetime alias observations read write ordering world effect if external and failure semantics",
        "x.field = y may lower to ssa replacement scalar replacement register update memory write foreign write or nothing depending on demand — never default to record mutation because syntax resembles it",
        "zero copy projection is legal only when layout lifetime ownership mutation law alignment alias law and foreign law are all compatible — otherwise copy is semantically required",
    }
    fails = "source visible ownership kingdom or unproven mutation or zero copy claim"
}

effectorder = law{
    id    = "law.effect.order"
    kind  = .invariant
    holds = .algebra
    binds = {
        "effects are compositional facts sufficient to answer may reorder may eliminate may duplicate may speculate may fuse requires world may fail and observable lifetime — not pure bool or side_effecting bool",
        "only observable dependency and order survive into realization — if two pure independent applications have no ordering law the scheduler may reorder fuse or vectorize",
        "if effect world or lifetime imposes order preserve exactly that relation — do not carry statement order as permanent semantic dependency",
        "concurrency must use the same world effect and value algebra — thread task future promise channel actor mutex async function do not automatically become semantic kingdoms",
        "realization chooses coroutine thread work stealing simd gpu event loop or synchronous execution when legal",
        "if cancellation is observable in drop resource release world effects result or timing order cancellation survives as semantic obligation not merely scheduler state",
        "atomic operations preserve semantic ordering visibility scope and atomicity as laws — not only llvm ordering enum x86 opcode or wasm atomic opcode",
        "overflow divide by zero invalid shift out of bounds null dereference alignment and uninitialized read each declare whether operation wraps traps fails is unchecked under explicit law or is impossible by proof",
    }
    fails = "boolean effect model statement order preservation or backend decided trap semantics"
}

profileevidence = law{
    id    = "law.profile.evidence"
    kind  = .invariant
    holds = .evidence
    binds = {
        "PROFILE-EVIDENCE profile data selects realization it never rewrites semantic truth",
        "forbidden observed receiver always file therefore receiver is file without guard deopt contract",
        "required pattern evidence file probability high realization specialize file guard fallback semantically equivalent — semantic truth unchanged",
        "every speculative assumption records what fact is assumed why it is legal guard witness what artifacts depend on it how invalidation propagates and fallback deopt semantics",
        "no orphan assumptions and no hidden fast path state",
    }
    fails = "profile observation promoted to semantic fact or assumption without guard lineage and invalidation"
}

incrementalcache = law{
    id    = "law.incremental.semantic"
    kind  = .invariant
    holds = .dependency
    binds = {
        "incremental compilation invalidates by semantic dependency not file boundaries — fact changed invalidate dependent graph slice rerun affected demand and realization paths remain provenance only",
        "cache reuse proof binds authoritative semantic inputs not path timestamp text hash callee spelling or serialized ast alone — those may accelerate candidate lookup only",
        "generated grammar table token role table machine code c bootstrap wasm tables lsp metadata mcp schema and agent context carry provenance answering which law facts produced this which revision which generator",
        "deterministic output is required unless nondeterminism is explicitly lawful — no silent dependence on hash iteration order thread timing filesystem traversal agent scheduling source discovery order or address layout",
    }
    fails = "file keyed invalidation hash identity cache or generated artifact without law fact revision provenance"
}

canonsemantic = law{
    id    = "law.canonical.semantic"
    kind  = .invariant
    holds = .equivalence
    binds = {
        "canonicalization must not change semantics — resolve original to graph A canon render resolve to graph B require A equivalent B not merely syntactic roundtrip",
        "equivalence includes relation projection subject world failure effects law and application cardinality especially after inference removes explicit to projection parameters worlds or curry syntax",
        "canonicalizer idempotence requires canon parse resolve canon parse resolve source equivalent to canon parse resolve source under semantic identity comparison",
    }
    fails = "canonical rewrite that changes semantic identity or cardinality"
}

infercontract = law{
    id    = "law.infer.contract"
    kind  = .invariant
    holds = .bounded
    binds = {
        "implicit inference is direct local monotonic uniquely witnessed and bounded — no global backtracking no arbitrary relation chain search no whole program theorem proving to remove source characters",
        "syntax saved less than cost of expensive inference is not automatically a win — semantic density must preserve compiler density",
        "inference is monotonic where possible — adding unrelated declaration must not change existing unique interpretation unless new fact genuinely participates in constraint set",
        "minimal syntax requires maximal explainability — users and tools must ask what did compiler inject why from which world which descriptor caused it what alternative was rejected",
        "world projection and relation inference are lexically minimal but semantically inspectable",
    }
    fails = "expensive hidden inference declaration order resolution or unexplainable injected facts"
}

worldcapability = law{
    id    = "law.world.capability"
    kind  = .invariant
    holds = .authority
    binds = {
        "worlds need attenuation delegation semantics — subset authority derived capability restricted view delegation revocation lifetime without inventing more namespaces",
        "a world or capability value may project narrower witnessed authority such as process world to child world constrained to cwd env output",
        "world equality must not mean pointer equality — equivalent authority overlap disjoint and parent derivation remain distinct semantic facts from physical object identity",
        "foreign boundaries need bidirectional law — idol to foreign projection requires semantic domain representation ownership failure world lifetime alias encoding abi and origin not only foreign to idol normalization",
    }
    fails = "pointer identity world authority or one direction foreign boundary cast system"
}

closuresemantic = law{
    id    = "law.closure.semantic"
    kind  = .protocol
    holds = .proved
    binds = {
        "b to c closure compares semantic graph produced law facts behavioral corpus machine behavior performance envelope and provenance normalized artifacts — not merely binary equality or file hashes alone",
        "binary identity may be an additional stronger result where reproducibility permits",
        "bootstrapping tracks shrinking trusted base — which semantic decisions remain outside idol and how much trusted foreign code still decides meaning",
        "every shc milestone shrinks the semantic trusted computing base — better convergence metric than language percentage or id file count",
    }
    fails = "shc progress measured by id volume binary hash alone or growing foreign semantic trusted base"
}

shcscheduler = law{
    id    = "law.shc.scheduler"
    kind  = .invariant
    holds = .priority
    binds = {
        "no self host work ports utilities before authorities — formatters scanners helpers data structures cli tools and bench scripts do not move shc unless they own a production semantic boundary",
        "scheduler priority earliest host semantic owner then supporting prerequisite then ftcftw proof then broad migration",
        "canonical corpus must exclude implementation compromises — workaround required by current compiler is migration bootstrap not canonical teaching",
        "tooling lsp mcp formatter must consume future constitutional truth not current parser capability alone while gap 134 and gap 145 remain open",
    }
    fails = "utility migration presented as shc progress or compiler limitation canonized as teaching example"
}

# Velocity reconciliation: the monoglot ideal describes the destination, not a
# gate on the road to it. Reaching the earliest executed SHC authority frontier
# is the priority — a bounded foreign bridge is a tool for that, not a defeat.
bootstrapvelocity = law{
    id    = "law.bootstrap.velocity"
    kind  = .protocol
    holds = .priority
    binds = {
        "the earliest executable shc authority frontier is the priority — a bounded foreign bridge including new zig that advances the executed authority frontier is admitted and preferred over stalling when it is the fastest path to the next transfer",
        "foreign is forbidden only as permanent architecture as semantic authority and as a new foreign semantic kingdom beside the graph — never as bootstrap scaffolding toward the next native owner",
        "every admitted bootstrap bridge carries a law.bridge.death deletion witness naming the host owner before the idol owner after and the next host owned boundary — scaffolding without a deletion condition is permanent architecture",
        "do not block on a monoglot ideal when the native compiler cannot yet express the stage — record implementation blocked and add the smallest bridge that unlocks the next executed transfer rather than idling",
        "generated bridge artifacts are regenerated from their idol owner never hand edited — velocity never licenses a divergent hand fork of generated code",
        "this reconciles law.foreign.integration law.bridge.death and law.shc.requirement — usefulness and velocity are kept while foreign semantic authority still shrinks at every milestone",
    }
    why   = "law.shc.requirement"
    fails = "a monoglot restriction that stalls the shc frontier or a bootstrap bridge admitted without a deletion witness"
}

deltabudget = law{
    id    = "law.delta.budget"
    kind  = .protocol
    holds = .admission
    binds = {
        "every agent task needs concept delta budget before implementation — new semantic kinds registries syntax authorities fallback owners default zero unless owner explicitly approves constitutional amendment",
        "every task needs physical delta budget — report before and after allocations copies branches indirections lookups materialized graph rows temporary packs runtime metadata compiler passes and compiler memory",
        "optimize integrated pipelines not local functions — ftcftw evidence covers full requested path including decode normalize compile startup execute memory artifact for wasm",
        "a change that does not move semantic authority remove reconstruction increase optimization knowledge or delete physical work is secondary migration and must not displace compiler b critical path",
    }
    fails = "unbudgeted concept or physical delta or local win hiding integrated regression"
}

coordinationfact = law{
    id    = "law.coordination.fact"
    kind  = .protocol
    holds = .handoff
    binds = {
        "cross agent semantic dependencies need explicit handoffs — needed fact current producer consumer blocking interface owner — agent continues on non overlapping work rather than duplicating fact locally",
        "parallel agents attack producer to consumer chains not directories — lexer token identity to grammar role to parser or application id to dnir to machine lineage",
        "two agents work downstream upstream only when interface fact is stable otherwise competing temporary representations emerge",
        "claim semantic boundaries as well as paths duplicate facts forbidden across lanes",
        "stop if semantic owner missing law ambiguous projection ambiguous world ambiguous or required upstream fact unavailable — file precise gap do not unblock by inventing helper semantics",
        "diagnostics should reveal lost optimization opportunities — allocation because value escapes dynamic dispatch because descriptor unknown world not specialized copy because alias unknown explicit conversion prevented inference",
    }
    fails = "shadow fact duplication directory parallel cleanup or invention to bypass missing upstream fact"
}

representationdemand = law{
    id    = "law.representation.demand"
    kind  = .invariant
    holds = .audit
    binds = {
        "every runtime structure object box tag vtable closure environment buffer iterator world handle protocol evidence union payload stack slot heap allocation must answer which semantic observation forced this representation",
        "if no observation exists it is a candidate for deletion — most direct operational form of ftcftw",
        "no source construct implies allocation no protocol constraint implies runtime witness no union implies tag box no curry implies closure allocation no world implies world object no binding implies storage no structured value implies aggregate no physical cast implies semantic to",
    }
    fails = "physical structure without demanded semantic observation"
}

gateconvergence = law{
    id    = "law.gate.convergence"
    kind  = .protocol
    holds = .adversarial
    binds = {
        "bridge without deletion witness rejected at introduction",
        "silent fallback after authority transfer fails sabotage negative control",
        "duplicate fact producer rejected by catalog",
        "placeholder semantic value for unknown rejected",
        "profile observation without guard cannot become semantic fact",
        "assumption without lineage invalidation rejected",
        "cache key without semantic reuse proof rejected for correctness claims",
        "canonical rewrite without semantic equivalence proof rejected",
        "inference that backtracks searches relation chains or resolves by declaration order rejected",
        "unrelated declaration changing prior unique resolution rejected monotonicity control",
        "utility migration cannot satisfy shc milestone gate",
        "concept delta and physical delta reported on material changes",
        "current projection Idol idol as live identity outside history blocks rejected",
        "repository source treated as canonical proof without C0 resolution rejected",
        "specimen repair without class impossibility proof rejected",
        "positive controls preserve one producer unknown state negative facts effect algebra observable order profile guard assumption lineage semantic invalidation b to c semantic comparison trusted base shrink representation audit identity projection and source not proof",
    }
    fails = "convergence invariant enforced only as local cleanup guidance without gate controls"
}

totalconvergence = law{
    id    = "law.total.convergence"
    kind  = .protocol
    holds = .current
    binds = {
        "blocking execution contract lives in docs/spec/convergence-contract.md",
        "agents halt on stop conditions rather than invent vocabulary or host templates",
        "current tree is not canonical by default — revalidate against C0",
        "one meaning one id one relation one fact producer one projection algebra one lowering lineage",
        "completion reports bind revision dirty state authority transfer and adversarial controls",
        "P0 repair order identity source application worlds lowering shc ftcftw is mandatory scheduling",
    }
    fails = "total convergence treated as optional guidance without stop conditions census or completion report"
}

absolutelaw = law{
    id    = "law.algebra.absolute"
    kind  = .invariant
    holds = .absolute
    binds = {
        "delete namespaces that only organize meaning",
        "delete apis that only qualify relations",
        "delete protocol machinery that duplicates descriptor facts",
        "delete unions as physical objects when demand does not require them",
        "delete world objects when authority can remain a graph fact",
        "delete host status models when outcome already exists",
        "delete lua apis from canonical native source when native relations exist",
        "delete undefined builtin operations and compound names whose parts are facts",
        "delete every reconstruction of a fact already known",
        "do not replace any of them with prettier names",
        "one meaning one id one relation facts qualify protocols constrain unions preserve alternatives world grants authority witness proves demand deletes realization chooses late evidence proves truth",
        "home supplies context descriptor supplies facts protocol demands facts union preserves alternatives subject orients meaning world grants authority law governs behavior witness proves demand deletes realization chooses late provenance records history evidence supports truth",
        "standard code shell code foreign code protocols unions generics and runtime polymorphism are only ordinary use of this algebra",
        "there is no second system",
        "convergence meta invariants in law.bridge.death through law.gate.convergence prevent bootstrap bridges fallback dual authority duplicate producers unknown collapse profile as truth unbounded inference and physical bloat from becoming permanent architecture",
    }
}

semanticblock = @{
    gap = 124
    state = .vocabularyblocked
    why = "the current staged text census is a migration ratchet; authoritative world subject vocabulary sentinel and control gates require graph queries in self hosted Idol"
    unlock = "gap 121 module initialization then graph fact access from Idol compiler modules"
}

literal = {}

literal.text = law{
    id    = "law.literal.text"
    kind  = .invariant
    holds = .one
    binds = {
        "double quotes are the one canonical text literal face",
        "one line multiline escaped and interpolated text share one literal family",
        "interpolation preserves literal and expression segments and does not demand concatenation or materialization",
        "a multiline opening newline and final newline are omitted; the closing quote indentation is removed exactly from every nonblank content line and insufficient indentation diagnoses",
        "triple quotes unicode quote delimiters and lua long brackets are not canonical text faces",
    }
}

literal.bytes = law{
    id    = "law.literal.bytes"
    kind  = .invariant
    holds = .one
    binds = {
        "single quotes are the one canonical byte sequence literal face",
        "one byte remains a byte sequence of cardinality one and may scalarize only under proved byte demand",
        "text byte codepoint scalar grapheme and character remain distinct descriptors and facts",
        "raw source characters encode as source utf8 bytes; byte escapes are byte oriented and unicode escapes are rejected until separately admitted",
        "foreign lua single quoted text remains in the explicit lua importer and never enters native Idol lexical recognition",
    }
}

comment = law{
    id    = "law.comment.one"
    kind  = .invariant
    holds = .trivia
    binds = {
        "hash begins the one canonical line comment and has no canonical length reading",
        "length is the subject oriented len relation with an explicit axis when it is not uniquely recoverable",
        "lua dash comments and lua long comments remain foreign lua input and are never native Idol comment forms",
        "repeated hash lines are the canonical multiline comment face; no block comment syntax is admitted",
        "hash bang is allowed only at byte zero as script launch provenance and grants no semantic authority",
        "removing comments changes no graph fact except source trivia provenance",
    }
}

backtick = law{
    id    = "law.backtick.zero"
    kind  = .invariant
    holds = .reserved
    binds = {
        "backtick has no canonical meaning and never executes or captures a process",
        "process execution is an ordinary application over structured values with explicit worlds effects failures and provenance",
        "a future value face requires grammar and relation admission and remains separate from execution",
        "unused punctuation need not acquire a meaning",
    }
}

lexical = law{
    id    = "law.lexical.one"
    kind  = .protocol
    holds = .generated
    binds = {
        "one native lexical authority distinguishes text bytes hash comment shebang and reserved backtick identities",
        "the native lexer records token identity content span and provenance once while explicit foreign importers retain their own lawsets",
        "grammar parser formatter canonicalizer tree sitter lsp mcp documentation generators and migrations consume generated projections of those facts",
        "no consumer reconstructs literal or comment role from delimiter text source substring ast flags or contents",
        "token role lookup is compact and constant time and literal payloads retain source views where lawful",
    }
    fails = "one string token followed by downstream delimiter reconstruction or separately handwritten lexical tables"
}

lexical.gate = law{
    id    = "law.gate.lexical"
    kind  = .protocol
    holds = .semantic
    binds = {
        "canonical repository source rejects lua comments lua long strings hash length historical single quoted text and unadmitted backticks by token identity and provenance",
        "foreign literal and comment lawsets enter only through explicit foreign import rather than native compatibility parsing",
        "foreign parsing is tested through structured generated external or narrowly isolated machine owned input and never makes stale source a pattern library",
        "generated canonical source receives no exception",
        "the corpus ratchet counts complete classified inputs and fails closed when an authority or source is unavailable",
    }
}

lexical.block = @{
    gap = 145
    state = .implementationblocked
    why = "the executed idol lexer owns the production token stream identities and spans but the complete canonical literal comment and delimiter roles are not yet one generated authority consumed by every surface and native compatibility branches still remain"
    unlock = "complete idol owned lexical identities plus generated grammar roles canonical migrations explicit foreign import boundaries and derived tooling projections"
}

# Semantic identity is the spine, not the whole acceptance claim. Every
# production change is judged across meaning, physical work, human use and
# sovereignty. A local win may not hide cost or authority on another axis.

closure = law{
    id    = "law.project.closure"
    kind  = .protocol
    holds = .proved
    binds = {
        "identity is id facts qualify it and one meaning retains one native word",
        "facts already known are preserved and never reconstructed from names paths syntax hashes or physical operations",
        "demand removes unused work before storage allocation boxing aggregation adaptation or runtime exists",
        "realization retains every lawful physical choice until an observable contract forces commitment",
        "runtime compile startup memory artifact incremental and retained realization effects are reported for every architecture closure claim",
        "foreign semantics retain origin law ownership failure abi world effect and uncertainty while native and foreign execution share graph demand realization and machine architecture",
        "self hosting progress is an executed semantic authority transfer toward seed builds b b builds c and proved b c closure",
        "agent tools inspect and act on graph identity facts dependencies demand provenance and transformation without reparsing human text",
        "important resolution specialization allocation realization and machine decisions retain inspectable causal evidence",
        "canonical id source remains dense familiar regular and readable while source faces erase into semantic facts after resolution",
        "capability grows through admitted relations and facts without creating another identity graph demand provenance execution or tooling authority",
    }
    fails = "a local correctness performance tooling or migration claim that hides added work lost facts duplicated authority or weaker human source"
}

economy = law{
    id    = "law.project.economy"
    kind  = .invariant
    holds = .minimal
    binds = {
        "maximum semantic knowledge uses minimum physical compiler state",
        "graph identity facts packs edges and ranges use compact owner scoped storage and projections are materialized only when demanded",
        "cheap fact closure precedes opportunity estimation and expensive analysis is demanded only where expected value justifies its cost",
        "persistent exact dependencies permit incremental reuse without guessing continuity from names paths spans or fingerprints",
        "meaning does not imply materialization and compiler knowledge does not imply runtime state",
    }
}

specialization = law{
    id    = "law.project.specialization"
    kind  = .invariant
    holds = .progressive
    binds = {
        "one source program may progress from dynamic through inferred guarded sealed native and target realization without entering another language mode",
        "call pack return demand descriptor shape world effect profile and target facts monotonically remove cost without replacing semantic identity",
        "a value binding pack table closure iterator or result becomes a place aggregate allocation or runtime object only when observation demands it",
        "stronger knowledge must preserve or enlarge lawful cheap realizations and may never force a representation merely because the compiler learned more",
    }
}

ftcftw = law{
    id    = "law.project.ftcftw"
    kind  = .protocol
    holds = .measured
    binds = {
        "equivalent native semantics retain at least c equivalent runtime compile startup memory binary incremental and realization outcomes",
        "an Idol win uses retained semantic knowledge and transferable realization rather than fixed answers inputs seeds counts or benchmark specific recognition",
        "wasm evidence separately measures decode import compile instantiate startup steady execution memory runtime footprint artifact size and end to end latency",
        "wasm enters the shared graph with its exact lawset and never creates a permanent virtual machine semantic kingdom",
        "a throughput win cannot hide worse cold start compiler work memory runtime obligation or artifact footprint",
        "every measurement names the executed backend snapshot comparator workload machine and known unsupported or divergent cases",
        "the objective is dominance not parity — see law.ftcftw.dominance law.optimization.open law.cost.closure and law.algorithm.realization",
    }
}

ftcftwdominance = law{
    id    = "law.ftcftw.dominance"
    kind  = .invariant
    holds = .pareto
    binds = {
        "FTCFTW-DOMINANCE the objective is verified pareto dominance over the best known semantically equivalent implementation reaching the physical lower bound wherever dominance is impossible not parity with c llvm fortran wasmtime or any named compiler",
        "the comparison oracle is two things at once the strongest known implementation and the semantic physical lower bound — c llvm fortran wasmtime hand assembly and specialized libraries are each only one oracle",
        "for every cost dimension exactly three outcomes are valid win strictly better than the best competitor with equivalence and confidence optimal equal to the proven lower bound where no improvement is physically possible or loss with exact optimization debt application id extra cost semantic cause unresolved fact lower bound and workstream",
        "fewer operations than the semantic minimum is impossible so equalling the lower bound counts as ftcftw closure not failure",
        "conflicting dimensions throughput vs size specialization vs compile time prefetch vs traffic energy are a pareto frontier under an explicit build world policy budget never a collapsed vanity scalar",
        "target policy is a build world fact not a source change — minimize one objective under budgets binary bytes startup compile latency energy — same semantic program different realization frontier",
        "ftcftw covers the whole lifecycle edit incremental compile link load relocation startup warmup first result steady tail footprint shutdown distribution and for wasm download decode validate compile instantiate initialize first call steady rss — a faster inner loop that compiles far slower or ships far larger is not dominance",
        "the idol compiler obeys this contract on itself and self hosting makes it recursively testable",
        "acceptance inequality IdolCost pareto dominates BestKnownCost unless the competing point is already a proven lower bound in which case idol reaches the same bound otherwise ftcftw status is open",
    }
    why   = "law.cost.explain"
    fails = "parity framing a collapsed vanity score a policy encoded in source or a loss without causal optimization debt"
}

optimizationopen = law{
    id    = "law.optimization.open"
    kind  = .invariant
    holds = .open
    binds = {
        "OPTIMIZATION-OPEN there is no closed optimization taxonomy — inlining sroa gvn licm slp vectorization dse and tail call are known instances of one problem derive proven equivalent realizations of a semantic region within budget and choose argmin cost r target world policy",
        "the compiler reasons in semantic equivalence remaining possibility demand observation target and cost never which pass recognizes this pattern",
        "any present or future semantics preserving transformation representation algorithm schedule layout abi staging hardware mapping or machine sequence is admissible",
        "candidates may originate from deterministic rewrite equality saturation constraint or dynamic programming solving enumerative superoptimization autotuning profiles hardware in the loop measurement learned search models agents humans competitor binary mining or methods not yet invented — physical search strategies not semantic kingdoms",
        "learned models and profiles are evidence never authority per law.profile.evidence",
        "VERIFIED-OPTIMIZATION-ONE search may be experimental but the accepted result may never be semantically speculative — a candidate becomes canonical only when required observations are verified by translation validation or algebraic law per law.optimization.validated and it improves the selected cost frontier",
        "every improvement eliminates one of four things work movement representation or uncertainty and any future unnamed optimization must reduce to one of these",
        "completeness is a moving frontier closure is provable only for a bounded region and search domain report proved lower bound best realization found remaining gap and search coverage rather than claiming global completeness",
        "the architecture is not parser ir fixed pass list backend but source semantic graph equivalence realization space verification multiobjective cost search pareto frontier selected realization machine — passes are not the ontology the searched verified cost ranked realization space is",
    }
    why   = "law.optimization.validated"
    fails = "a blessed finite pass list a candidate admitted without verified observation preservation or optimization treated as pattern recognition"
}

costclosure = law{
    id    = "law.cost.closure"
    kind  = .invariant
    holds = .debt
    binds = {
        "COST-CLOSURE every remaining physical cost is a graph fact carrying exact semantic cause theoretical lower bound actual measured cost and optimization debt delta",
        "derive each hot application theoretical zero vector its cost under complete knowledge then actual minus lower bound is optimization debt yielding a mechanical ftcftw backlog agents query for greatest weighted debt not a curated pass list",
        "unexplained cost is a compiler defect",
        "competitors and hardware are continuous discovery systems compile equivalent source under the strongest competitor configuration measure inspect machine behavior map any advantage back to an idol semantic opportunity and add a regression oracle and explore verified realizations on the actual target to discover wins no compared compiler generates",
        "a benchmark is closed only when idol dominates every compared implementation or reaches a proven lower bound",
        "no benchmark win elsewhere and no geometric mean compensates for an open loss if ninety nine win and one loses where improvement is possible ftcftw remains open for that case",
        "every case persists one row subject world target workload observations competitor lowerbound idol delta cause producer consumer proof evidence and status and the only admissible status values are win dominates the best competitor with equivalence and confidence bound reaches the proven lower bound open loses an improvable dimension or unknownbound where no useful lower bound is known — averagewin geomeanwin and goodenough are never statuses and idol opens the case automatically whenever it loses any improvable dimension",
        "the frontier is machinery not a hand authored optimization list five graphs carry it A observation application or use to required observations to producer to proof B demand use to demanded property portion or quality to upstream transformer C law relation or descriptor to semantic law to witness to implications D frontier semantic region to candidate realization to preconditions to proof to cost vector to dependencies to status and E debt region to lower bound to selected realization to delta to cause classified as missing fact demand law candidate search proof or wrong cost model placement algorithm or representation",
        "the development loop is mechanical measure then find largest debt then classify the missing element then implement then validate then ratchet and any semantic opportunity with no candidate provider is itself debt made visible before any benchmark regression — implementation program and workstreams in gaps GAP-172",
    }
    why   = "law.cost.explain"
    fails = "a physical cost without cause lower bound and debt a benchmark called closed while an improvable loss stands an aggregate hiding a specific open loss a status outside win bound open or unknownbound or conflating unknownbound with reaching a proven lower bound"
}

algorithmrealization = law{
    id    = "law.algorithm.realization"
    kind  = .invariant
    holds = .realization
    binds = {
        "ALGORITHM-REALIZATION-ONE algorithm and data structure choice are realization not source commitment when semantics do not mandate them",
        "preserving specified observations the compiler may choose a fundamentally better algorithm linear lookup to binary search to perfect hash comparison sort to counting or radix from range facts generic matmul to tiled vector or gpu repeated parse to compiled parser generic regex to dfa generic table to direct switch and may change asymptotic complexity o n to o one o n log n to o n or repeated o n to one indexed preprocessing step",
        "the same table semantics may realize as hash table sorted vector b tree direct array perfect hash trie bitmap bitset struct soa scalarized registers or nothing — idol compiles semantic data structures not programmer selected physical containers per law.representation.demand and shapes",
        "realization is demand directed parse feeding only one projected member need not build a full object tree scan just enough allocate nothing else — applies to parsers encoders queries transforms files protocols reflection and math",
        "optimization boundaries are only semantic observable effects authority boundary foreign abi unknown dynamic world resource policy or search budget never function file module package or library — an only organizational abstraction costs zero",
        "dynamic programs specialize progressively unknown observed guarded sealed with correct deopt and multi version only when expected benefit times frequency exceeds compile code byte i cache and dispatch cost so specialization is itself ftcftw",
    }
    why   = "law.representation.demand"
    fails = "algorithm or container committed by source spelling when semantics permit a cheaper realization or an organizational boundary blocking cross application optimization"
}

optimizationvalidated = law{
    id    = "law.optimization.validated"
    kind  = .invariant
    holds = .verified
    binds = {
        "VERIFIED-OPTIMIZATION-ONE aggressive search is safe only because correctness never relies on trusting a transformation",
        "every candidate carries input semantic observations candidate transformation output semantic observations and a proof witness or validation obligation and is admitted only when equivalent and cheaper on the selected frontier",
        "machine level regions use translation validation where practical and algebraic transformations use their laws directly",
        "this matters especially because agents write optimizer logic the search can be experimental the accepted result cannot be semantically speculative",
    }
    why   = "law.realization.valid"
    fails = "an optimization admitted without verified observation preservation or correctness resting on trusting a pass"
}

physicalopen = law{
    id    = "law.physical.open"
    kind  = .invariant
    holds = .open
    binds = {
        "PHYSICAL-SPACE-OPEN realization means any physically observable strategy that preserves the program semantic observations not merely machine representation and code generation — the idol optimizer is a semantic to physical realization optimizer not a code optimizer",
        "no compiler phase backend convention runtime abstraction abi operating system interface data structure algorithm device or currently known optimization defines the boundary of the realization space",
        "a physical strategy is admissible when semantic observations are preserved authority and effect constraints are satisfied target and world constraints admit it and the selected cost frontier improves",
        "the search space includes and is not limited to computation representation algorithm data structure encoding layout precision memory placement and tier allocation instruction selection scheduling abi linking os interface syscall strategy concurrency hardware placement specialization persistence and distribution and unknown future physical strategies are admitted by the same rule",
        "admitted physical strategies include entropy driven representation and compression bit level logic synthesis precision proportional to demand and range specialized transcendentals polyhedral and sparse schedule search distribution sensitive and adaptively switched algorithms cross run persistent specialization and aot jit hybrid realization snapshot preinitialized state page fault huge page tlb cache set uop cache fusion predictor btb and speculation window realization thermal dvfs heterogeneous core smt numa and bandwidth aware placement recompute vs store and automatic memoization prefetch and non temporal and write combining synthesis kernel crossing elimination and interface selection mmap sendfile splice io uring and vectored io kernel and network zero copy and protocol fusion accelerator instructions beyond simd and gpu npu dsp with complete transfer launch and sync cost semantic index query plan and materialized view synthesis storage tier and persistent memory realization transaction optimistic concurrency lock shape contention layout and per core specialization and energy carbon or dollar cost as pareto dimensions under world policy",
        "security mandated speculation hardening is a realization cost that is zero exactly when a proof shows the mitigation is unnecessary for an exact application",
        "none of these is a new semantic kingdom each is a physical search strategy under law.optimization.open verified under law.optimization.validated and accepted only on the cost frontier of law.ftcftw.dominance",
    }
    why   = "law.optimization.open"
    fails = "a realization boundary drawn at a compiler phase backend abi os interface data structure algorithm or device rather than at a semantic observation or a physical strategy admitted without verification and cost frontier improvement"
}

observationminimum = law{
    id    = "law.observation.minimum"
    kind  = .invariant
    holds = .observable
    binds = {
        "OBSERVATION-MINIMUM a realization must preserve only what the program semantics actually make observable and everything else is free to change",
        "if the program cannot observe allocation identity table layout iteration order exact scheduling intermediate strings physical representation device or storage tier then each is a realization choice not a constraint",
        "ftcftw power is proportional to how carefully idol defines what is and is not observable every accidental observable is a permanent optimization barrier",
        "defining the exact observation model the behavior realizations must preserve is the highest leverage remaining language design work and an observable conservative by default that later proves unobservable is narrowed never widened silently",
    }
    why   = "law.observation.one"
    fails = "an accidental observable that permanently blocks a lawful realization or a realization that changes a genuinely observable behavior"
}

# ── Square-zero foundation: a program is its observations ───────────────────
# The deepest layer under APPLICATION-ONE and FTCFTW-DOMINANCE. A program is a
# set of required observable relationships, not a sequence of steps. These
# algebras — observation, equivalence, demand, relation-law, change, uncertainty,
# optimizer-economy — make "claim every identified and unidentified optimization"
# follow by construction rather than as an ever-growing checklist.

observationone = law{
    id    = "law.observation.one"
    kind  = .invariant
    holds = .observable
    binds = {
        "OBSERVATION-ONE a program is a set of required observable relationships between inputs worlds effects outcomes and outputs not a sequence of execution steps — if the written intermediate applications and bindings disappear entirely that is ideal not a violation",
        "only explicitly semantic observations constrain realization and incidental physical behavior does not — for each candidate behavior result values effect ordering io bytes failure timing allocation pointer table object identity and address iteration order gc and finalizer timing thread scheduling stack depth fp rounding nan payload signed zero syscall count temporary files random sequence and clock and environment reads the language decides observable or not conservative by default narrowed by proof never silently widened",
        "semantic time is not physical time a happens before b requires no particular nanoseconds reading a clock is an effect and execution duration is not semantics unless the program observes a clock or deadline world fact",
        "observation sets are partly world dependent a security world may make timing cache access and address observable demanding constant time or oblivious realization while an ordinary world does not — the observable set is a world fact not a global constant",
        "semantic time is not physical time a relation may require a happens before b without requiring any wall clock duration execution duration is not program semantics unless the program explicitly observes a clock or deadline world fact and reading the clock is itself an effect",
        "a program may admit an allowed outcome set for concurrency unordered iteration and randomized algorithms and the optimizer may realize any allowed outcome unless a stronger world or demand fact constrains it determinism and reproducibility are world demands not global constraints",
        "physical nonexistence none is a first class representation the default optimization question is can this binding value table closure pack world descriptor place result branch or loop cease to exist physically and if no required observation depends on its physical existence realization is none",
        "BOUNDARY-ONE representation is free except at irreversible semantic boundaries foreign abi external file format network protocol shared memory observable pointer volatile device authority boundary or debugger demanded address — foreign representation has finite extent exactly the foreign application lifetime and never infects the whole program before and after the boundary representation is free again serialization is projection into an externally constrained representation and parsing is its inverse under a descriptor and endian and alignment are boundary representation facts not language primitives",
    }
    why   = "law.semantic.universe"
    fails = "an incidental physical behavior treated as semantics an accidental observable made permanent execution duration or scheduling made observable without a clock deadline or security world fact or a foreign representation infecting beyond its boundary"
}

equivalenceobservation = law{
    id    = "law.equivalence.observation"
    kind  = .invariant
    holds = .equivalence
    binds = {
        "equivalence is defined over the permitted observations results failure effects authority ordering observable identity and resource obligations — two realizations are equivalent when they produce the same permitted observations under the same inputs and world",
        "every optimization reduces to prove equivalent then choose cheaper so translation validation and open ended search rest on this definition not on hand waving",
        "identity equality semantic equivalence and representation sharing are distinct — two occurrence identities may remain distinct even when their values are equivalent and one identity may migrate physical representation over time",
        "proof and provenance are irrelevant to meaning two proofs of the same fact or two source paths yielding the same value share realization unless the proof or provenance is itself observable or authority sensitive",
        "copy semantics derive from observation would duplicating physical representation change an observation if no copy freely or not at all if identity is observed preserve it — no copy type versus move type kingdom",
    }
    why   = "law.canonical.semantic"
    fails = "equivalence asserted without an observation model or proof and provenance polluting realization identity"
}

demandderivative = law{
    id    = "law.demand.derivative"
    kind  = .invariant
    holds = .transformer
    binds = {
        "demand is a transformer for every relation demand of the output derives the exact demand of the inputs — this is the foundation of field pruning lazy parsing dead result elimination and query optimization",
        "demand carries portion quality cardinality and order not merely needed or not — partial consumption first n existential any all count membership and top k or order statistic demand are first class",
        "aggregate demand rewrites through relation law sort then first becomes selection map f then sum needs no materialized mapped values filter p then count counts directly — derived from effects cardinality ordering and dependence never a hardcoded pipeline list",
        "inverse demand cancels work a producer already satisfies sorted input deletes a sort validated input deletes a validate — producer facts and consumer demand meet",
        "demand facts and realization possibilities propagate bidirectionally to a fixed point monotonic where possible with cycle handling termination and widening for open worlds — not an arbitrary run inference twice",
    }
    why   = "law.demand.occurrence"
    fails = "demand modeled only as a downstream boolean or an aggregate pipeline hardcoded instead of derived from relation law"
}

relationproperty = law{
    id    = "law.relation.property"
    kind  = .invariant
    holds = .algebra
    binds = {
        "associativity commutativity identity idempotence monotonicity invertibility distributivity and fusion compatibility are relation facts not compiler special casing for primitive arithmetic",
        "reductions parallelization regrouping distributed aggregation and reassociation follow from associativity and commutativity facts under the exact numeric or relation law",
        "idempotence permits retry deduplication caching and coalescing invertibility permits incremental update undo and delta reconstruction monotonicity permits incremental and range propagation distributivity permits f of a plus b to f a plus f b when lawfully established",
        "fusion compatibility is derived from effects cardinality ordering and dependence so unknown future relation combinations fuse automatically without a map plus filter recognizer",
        "descriptor implication is systematic if descriptor a implies descriptor b then satisfying a satisfies b with no runtime conversion and semantic laws may imply other laws forming an inference accelerator",
    }
    why   = "law.effect.order"
    fails = "algebraic transformation hardcoded for arithmetic only or a relation property assumed without a registered law"
}

changedelta = law{
    id    = "law.change.delta"
    kind  = .invariant
    holds = .incremental
    binds = {
        "a relation may expose how its output changes when its input or world changes as a semantic delta or derivative law not necessarily an implementation api",
        "with a change law recompute whole result becomes update changed portion a foundational ftcftw opportunity for ui compilers databases analytics and build systems",
        "generalized differentiation unifies automatic incrementalization numeric gradients and dependency updates as one change algebra",
        "reversibility lets a runtime store less state and reconstruct on demand useful in compression checkpointing undo and distributed protocols",
    }
    why   = "law.incremental.semantic"
    fails = "recomputation where an exact change law would update only the affected portion"
}

uncertaintyalgebra = law{
    id    = "law.uncertainty.algebra"
    kind  = .invariant
    holds = .lattice
    binds = {
        "semantic knowledge follows a lattice unknown then possible set then constrained set then singleton and refinement is monotonic no phase may forget an exact fact and reconstruct something weaker later except behind an explicit guarded assumption",
        "fact evidence assumption and proof are strictly separate a fact is semantic truth evidence is observation suggesting a fact often holds an assumption is a guarded condition under which a candidate realization is valid and a proof or witness justifies a fact or transformation — do not collapse them",
        "partial knowledge is first class known range known subset known prefix known cardinality partial shape known effect exclusion and known aliases impossible all optimize before a value is fully typed",
        "absence is a general algebra across every dimension effect authority result field alias failure world member capture and allocation each may be unknown known absent known exact or possibly one of a set and known absence known no effect no escape no failure no alias no allocation is among the strongest optimization facts",
        "unknown ambiguity and contradiction are distinct first class states ambiguity is two valid meanings contradiction is no valid meaning with provenance and unknown is meaning not yet known — a contradiction is a diagnostic fact never a downstream error code",
    }
    why   = "law.unknown.one"
    fails = "collapsing fact evidence assumption and proof or conflating unknown ambiguity and contradiction or forgetting an exact fact"
}

optimizereconomy = law{
    id    = "law.optimizer.economy"
    kind  = .protocol
    holds = .budgeted
    binds = {
        "the optimization process is itself optimized search and proof effort is budgeted by expected runtime gain times expected executions minus compile search and code size cost — universal search must not explode",
        "verification cost is chosen by value cheap known law then translation validation then exhaustive proof and a proof carrying realization cache reuses a verified realization for a matching graph fragment and target without re proving",
        "optimization is anytime a valid realization is produced quickly and improved as budget permits and search may run in background build infrastructure or distributed across machines without any language change",
        "self improvement a verified discovered equivalence is promoted to a reusable law and because idol self hosts this loop is recursive the compiler improving itself under bounded verification",
        "discovery is separated from trusted admission agents ml and search may propose anything but the trusted core is only a semantic checker proof verifier and cost measurement — minimize the trusted semantic and proof kernel so aggressive optimization stays safe",
        "cross program knowledge target calibration this machine prefers sequence a over b and verified semantic rewrite theorems generalize across graphs without carrying program specific semantics",
    }
    why   = "law.optimization.open"
    fails = "unbounded optimization search a trusted optimizer heuristic that bypasses the verifier or a discovered rewrite admitted without verification"
}

optimizationspace = law{
    id    = "law.optimization.space"
    kind  = .invariant
    holds = .open
    binds = {
        "OPTIMIZATION-SPACE-COMPLETE ftcftw is not compiler optimization it is optimal realization of a semantic observation contract under semantics information physics economics and uncertainty — the question is what transformations are possible between an intention and an observation under physical law information constraints uncertainty resource constraints adversaries and changing worlds",
        "for semantic identities and laws s demanded observation set o world and authority w downstream demand d known facts k uncertain evidence e physical resources h policy p fault and security and precision model f and compilation and search budget b the realization set r of s o w d k e h p f b is every physically lawful realization whose observations lie in allowed o s w f and ftcftw is search r then verified pareto frontier then dominate every known competitor point then equal the proven lower bound where further improvement is impossible",
        "execution algorithm architecture storage distribution and even whether any computation occurs at all are merely candidate strategies — lawful nonexecution satisfying an observation from cache proof or known world facts is the ultimate zero cost realization",
        "the admission rule is the only rule a candidate realization current or future named or unnamed from algebraic law superoptimization equality saturation program synthesis learned search autotuning competitor mining or agent proposal belongs in r if and only if it preserves the demanded observations under the current world satisfies authority effect and resource constraints has verifiable correctness and improves the chosen pareto frontier",
        "no compiler phase source abstraction runtime architecture target family intermediate representation or fixed pass order may permanently narrow r without an explicit semantic observation requiring it — persistent equivalence kept across abstraction levels tunable transform composition with no privileged pass order and jointly optimized layout and computation are consequences not exceptions",
        "the frontier factors into twenty four foundational axes identity observation law knowledge uncertainty demand change equivalence information work communication representation architecture placement schedule boundary failure resource search verification evidence cost adaptation and meta cost — every individual optimization idea and every one of the roughly two hundred discussed frontier classes is an instance discovered inside r not an addition to the constitution",
        "lower bounds are not instruction counts they are information theoretic communication i o and memory hierarchy circuit and work span and ultimately physical law and closure states which bound was reached proven semantic minimum architectural minimum measured machine minimum or best known external",
        "cost is a distribution not a constant dominance requires non overlapping confidence and robustness to workload variation and meta cost makes ftcftw lifecycle global a runtime win that costs more to discover and store than it ever repays is a global loss so every optimization carries an explicit break even execution count",
        "idol chooses the cheapest verified physical way to satisfy a semantic observation contract everything else about an execution including computation noncomputation algorithm data structure representation precision memory control flow scheduling abi operating system mechanism placement hardware persistence distribution architecture and compiler strategy is an open realization variable admissible whenever the four part admission rule holds — this is how idol claims every identified and unidentified future optimization by construction",
    }
    why   = "law.physical.open"
    fails = "treating ftcftw as a finite optimization checklist or letting a compiler phase abstraction target ir or pass order permanently narrow the realization space without a semantic observation requiring it"
}

realizationcontract = law{
    id    = "law.realization.contract"
    kind  = .invariant
    holds = .open
    binds = {
        "REALIZATION-CONTRACT ftcftw is not compiler optimization it is optimal verified realization under semantics information physics economics and uncertainty — idol chooses the cheapest verified physical way to satisfy a semantic observation contract and execution algorithm architecture storage distribution and whether any computation occurs at all are candidate strategies not assumptions",
        "the problem is not semantic program to cheapest machine code — given semantic identities and laws s demanded observation set o world and authority w downstream demand d known facts k uncertain evidence e physical resources h policy p fault security precision model f and compile search budget b find a realization r ranging over computation noncomputation algorithm data structure encoding precision architecture partition placement schedule memory persistence os mechanism hardware distribution and adaptation such that observations of r are within allowed o s w f and r is pareto optimal under p while correctness is verified and the remaining gap to known lower bounds is explicit",
        "lower bounds are physical not instruction counts cost closure tracks information required versus processed communication complexity across every boundary io and cache block complexity circuit depth and size parallel work versus span synchronization and round complexity and ultimately speed of light memory latency and thermodynamic energy — an implementation reading a gigabyte to answer a one bit question is far from optimal even with perfect instruction selection and closure states which bound was reached provable semantic minimum architectural minimum measured machine minimum or best known external",
        "lawful nonexecution is the ultimate realization if a demanded observation is already satisfiable from a cached exact answer a theorem materialized state or world facts r runs nothing — demand proven irrelevant to any observer disappears an effect or output proven unobservable in the current world takes its producer with it and pure results and proofs may be reused content addressed across programs when communication beats recomputation",
        "architecture is realization a software boundary api serialization process split task object module rpc or scheduler that is not externally observable may be erased and a beneficial boundary may be introduced — cross layer optimization spans language compiler runtime allocator os database network hardware and deployment wherever the boundary is not semantically observable and the source need not fix the physical software architecture",
        "meta cost is lifecycle global compilation search proof autotuning profiling and variant storage are costs a nanosecond runtime win that costs ten hours to discover for a once run program is a global loss every optimization carries a break even execution count cost dimensions are distributions and no dominance is claimed when confidence intervals overlap or when a candidate wins nominally but loses under slight workload or adversarial variation",
        "the foundational axes are about twenty four identity observation law knowledge uncertainty demand change equivalence information work communication representation architecture placement schedule boundary failure resource search verification evidence cost adaptation and meta cost — every optimization is a combination of these and observation sets cost dimensions semantic facts and hardware targets remain extensible so no named ontology may permanently narrow r",
    }
    why   = "law.optimization.space"
    fails = "assuming computation must occur or that realization means only how to execute a program treating a compiler as choosing machine code rather than satisfying a semantic observation contract at the cheapest verified physical point"
}

obligationone = law{
    id    = "law.obligation.one"
    kind  = .invariant
    holds = .observable
    binds = {
        "OBLIGATION-ONE observation is only one side of semantics obligation is the other a program does not merely produce observations it owes obligations so semantics is allowed observations plus required obligations and same output alone is not semantic equivalence — ftcftw may optimize everything the contract does not require",
        "positive obligations must eventually respond must commit durable state must respond within a deadline must preserve an ordering must release a resource must remain available under a fault model and must obey an authority boundary — negative obligations must not touch the network allocate leak secret dependent timing write after cancellation duplicate an external effect retain persistent state or let data leave a region and negative obligations are among the strongest optimization enablers because proving something cannot happen eliminates whole runtime mechanisms",
        "obligations are temporal not merely ordered eventually a a until b never c after d a within deadline and b at most once — safety a bad thing never happens and liveness a required thing eventually happens are distinct and both must be preserved an optimization may keep safety yet break progress",
        "a world fixes the progress model wait free lock free obstruction free eventual or best effort and whether fairness is observable never globally promise fairness a world did not demand — causality b because of a is stronger than order a before b and is a distinct graph fact and some optimizations reason counterfactually over several admissible worlds not only the realized one",
        "noninterference changing a secret must not change a public observation is a relation between executions and ftcftw optimizes within it constant time privacy and information flow — trust and provenance quality axiom static proof trusted witness runtime observation profile estimate external claim or heuristic grade how aggressively a fact may be exploited and information flow declassification and privacy budget worlds bound which derived facts may cross a boundary",
        "HYPERPROPERTIES equivalence is over sets of executions not one trace determinism noninterference serializability linearizability and observational consistency constrain the set of a program executions not any single run so a single trace observation equivalence model is insufficient and equivalence must preserve the demanded hyperproperties as well as per trace observations",
    }
    why   = "law.observation.one"
    fails = "treating same output as equivalence ignoring a required obligation globally promising an obligation a world did not demand or a single trace equivalence that silently breaks a demanded hyperproperty like determinism noninterference or linearizability"
}

realizationuniverse = law{
    id    = "law.realization.universe"
    kind  = .invariant
    holds = .open
    binds = {
        "NINE-UNIVERSE a complete ftcftw design cannot be a list of optimizations it must be a closure system in which every present and future optimization is a point in a formally open problem space and the whole architecture reduces to nine universes meaning observation knowledge demand equivalence realization resource search plus proof and change",
        "meaning is identity relation fact world and law observation is value effect ordering time identity security liveness failure quality and obligation knowledge is unknown absent possible fact evidence assumption proof and provenance demand is which result portion quality when how often and under what obligation equivalence is which alternate behaviors preserve the required observations and hyperproperties and defines legal optimization",
        "realization is an intentionally unbounded set computation noncomputation algorithm architecture representation placement schedule hardware os distribution and future physical strategy resource is an extensible vector time memory energy bandwidth space money reliability human effort and future resource search plus proof is discover verify measure rank learn generalize and reuse with no fixed algorithm set and change is inputs program world hardware evidence policy and physical state all change while semantic identity persists",
        "the supreme ftcftw equation given meaning m observation and obligation contract o knowledge k demand d world w resource and policy p and current physical state x find any realization r such that r satisfies o of m w d no known lawful realization dominates r and the remaining gap to available lower bounds is explicit while continuously admitting new knowledge laws hardware search methods proofs cost dimensions and physical strategies",
        "completeness is structural not enumerative no enumeration can close the realization set so the constitution closes it by the admission rule plus these nine universes never by a checklist — a future architecture memory technology os interface algorithm optimization theorem cost dimension observation or proof system must enrich existing identities and never mint a parallel semantic universe",
        "value of information acquiring a fact by profiling probing prescanning querying an external service or requesting a stronger human or agent contract is itself an optimization action weighed as cost to learn versus expected savings and active semantic interrogation surfaces which unproven invariant would unlock a cheaper realization",
        "contract weakening and semantic debt a declared guarantee exact order precision stable address or identity with no observer should be removed to expand the realization space and its presence is measurable debt and an api or architectural boundary that overcommits beyond consumer demand destroys optimization freedom and should be made demand polymorphic",
        "real options and irreversibility keeping several physical options open or paying slightly more now to make future migration cheap has option value and irreversible choices published abi persistent format or distributed partitioning are priced",
        "monotonic frontier a newer compiler may not knowingly regress a previously closed pareto point unless a selected constraint changed so the best ever realization and the best known competitor point are archived per semantic workload target and world and any regression is first class debt",
        "optimality gap best known cost minus proven lower bound is the exact quantitative definition of remaining ftcftw debt and no faster realization found is kept distinct from proven none faster exists and where no useful lower bound is known optimality status is unbounded or unknown rather than falsely optimal",
    }
    why   = "law.realization.contract"
    fails = "reducing ftcftw to an enumerated optimization checklist minting a parallel semantic universe for a new capability knowingly regressing a closed pareto point without a changed constraint conflating best competitor beaten with proven optimal or retaining an unobserved guarantee that needlessly narrows the realization space"
}

zerohistory = law{
    id    = "law.zero.history"
    kind  = .invariant
    holds = .current
    binds = {
        "ZERO-HISTORY the active repository is not a museum — it contains current Idol current foreign interoperability and currently executed bounded bootstrap bridges and nothing else — git stores history current semantic law stores truth the graph stores meaning demand stores necessity realization stores physics",
        "canonical identity language Idol source .id binary idol repository idollang/idol — delete current-tree references to former project or language names except when inspecting git history outside committed source",
        "no retired name source form module system pass taxonomy compatibility layer historical fixture migration document old edge vocabulary old identity wrapper or host shaped semantic subsystem receives permanent residence merely because deleting it would lose provenance — provenance already exists in git",
        "durable corpus states are current and foreign only — historical legacy migration compat deprecated old and pass number archive are not durable states and git owns those histories",
        "do not maintain language.history — the active tree represents current Idol only",
        "do not preserve old environment variable prefixes exported symbol prefixes package names artifact names or executable aliases",
        "delete comments of the form formerly historical was X migration legacy retired in old path previously unless the statement is required to operate a current external compatibility boundary",
        "every gap is either an open current obligation or resolved and deleted — an open gap contains only current missing fact evidence owner acceptance proof and deletion condition — no chronological archive no retired names no obsolete implementation narrative no pass references",
        "generated stable harness projection contains no mutable runtime session envelope — current revision dirty state and claims are ephemeral at session start and never committed",
        "verification census targets for current project-owned content retired project names zero retired source suffixes zero pass-number and spec-number architecture zero current std and lib semantic roots zero req import module semantic systems zero inverse conversion aliases zero adjective protocols zero committed stale session envelopes zero resolved gap archives",
        "text census discovers debt — semantic invariants and adversarial controls convict equivalent architecture under different spelling",
        "rename by semantic reduction never rebranding — duo_lexer to idol_lexer only when brand distinction is independently meaningful otherwise prefer lexer dispatch realization machine relation graph",
    }
    fails = "retired architecture preserved as permanent resident in the active tree when git already stores its history"
}

orthogonalcbackend = law{
    id    = "law.backend.c.orthogonal"
    kind  = .invariant
    holds = .native
    binds = {
        "C-BACKEND-ORTHOGONAL generated C is a lawful explicit physical realization over the same semantic graph and never a second semantic authority",
        "direct native is the canonical default self-host release correctness and performance path — it never emits C invokes a C compiler depends on a C artifact or falls back to C",
        "auto never selects C and C-backend evidence proves only the C feature never direct-native correctness or performance",
        "no semantic feature requires C exclusively and missing direct-native facts are repaired generally rather than supplied by the C realization",
        "the c foreign world is an independent interop capability and neither selects nor grants the C backend",
    }
    fails = "C realization contaminates semantic authority direct-native independence automatic selection or direct evidence"
}

filesystem.projection = law{
    id    = "law.filesystem.projection"
    kind  = .invariant
    holds = .filesystem
    binds = {
        "if a file like gate/idiom.id defines the callable semantics of the child member and those semantics are oriented on the enclosing gate table, its canonical invocation is gate:idiom(...)",
        "gate.idiom(...) is only legal when idiom resolves as a genuinely static callable member rather than a relation on gate",
        "the filesystem supplies member identity once, so the child file is the body and its root expressions are its execution",
        "a callable child file is a relation on its parent when its parent is the semantic subject",
        "dot is static projection only and colon is relation orientation",
        "parentheses are the canonical application/accessor mechanism converging application and accessor semantics",
    }
    fails = "treating a child file as a static module or using dot projection for a relation on the parent subject"
}

subject.zero = law{
    id    = "law.subject.zero"
    kind  = .invariant
    holds = .subject
    binds = {
        "an application already records its exact subject as a graph fact",
        "no lexical binding or compiler generated name mints self this receiver current instance or object merely to restate that subject",
        "a lexical binding is lawful only when it denotes an independently meaningful value under its genuine domain name",
    }
    fails = "synthetic subject binding restates the application subject"
}

any.descriptor.zero = law{
    id    = "law.any.descriptor.zero"
    kind  = .invariant
    holds = .descriptor
    binds = {
        "any is a lawful existential relation",
        "any is not a canonical source descriptor for unknown or incomplete compiler knowledge",
        "unknown remains a compiler fact and is not spelled as any",
        "explicit any descriptors are vocabularyblocked except in compatibility fixtures negative controls and foreign law source for the generic boxed boundary",
    }
    fails = "any used as a source unknown descriptor"
}

result.zero = law{
    id    = "law.result.zero"
    kind  = .invariant
    holds = .result
    binds = {
        "a computation with no demanded result does not produce a void value or descriptor",
        "the result demand or empty result pack records no value produced",
        "void in C or foreign source is foreign law provenance not an Idol descriptor",
        "unit Unit none and NoResult are not parallel zero result ontologies",
    }
    fails = "void or parallel zero result ontology appears in Idol source or graph"
}

text.byte = law{
    id    = "law.text.byte"
    kind  = .invariant
    holds = .distinction
    binds = {
        "text and arbitrary byte sequences are semantically distinct",
        "plurality does not create a descriptor identity named bytes",
        "byte may be an irreducible element descriptor if its semantics prove irreducible",
        "a byte sequence is a value with element descriptor byte and shape cardinality and layout facts",
        "text carries textual or encoding law that an arbitrary byte sequence does not",
    }
    fails = "a parallel bytes descriptor or collapsed text binary identity"
}

canonicality = law{
    id    = "law.canonicality"
    kind  = .invariant
    holds = .role
    binds = {
        "every source spelling has one canonicality status under a semantic role and source law",
        "statuses are canonical accepted compatibility migration only foreign fixture only implementation only and vocabularyblocked",
        "agents gates formatters and LSP consume a role aware canonicality projection",
        "git history and repository frequency are not language law",
    }
    fails = "word blacklist or repository frequency replaces role aware canonicality"
}
```
