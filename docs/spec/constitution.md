# Idol constitution

This is the sole living semantic law. `CLAUDE.md`, `docs/spec/*.md`, agent
routers, tests, tools, and implementation are projections and may not contradict
it. Historical pass documents and retired source are provenance only.

The fenced body is structured law notation retained while `GAP-145` closes the
canonical lexical and generated-role boundary. It is not executable canonical
Idol, not a source template, and its `--` notation must not be copied into
`.id`. The current law lives in the facts; the notation is a documentation
projection until the whole file can move truthfully to `constitution.id`.

```text
-- C0 structured law notation. NON-SOURCE.

-- ═══ §1 · the primary representation ═══════════════════════════════════════
--
-- The first fact, and the one every other fact depends on: law lives in the
-- graph, not in sentences.

law: {
    id: str
    kind: { invariant, objective, deprecated, boundary, protocol }
    holds: any
    binds: seq(str)
    fails: str
    -- These fields describe the complete law record in the structured
    -- documentation bridge. Canonical constitution source and generated
    -- machine validation remain blocked by GAP-145.
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
    holds = .sole
    binds = {
        "this document is the one living semantic law",
        "every generated projection and implementation must trace its rule to this law",
        "no implementation projection pass document router corpus or tool encodes an independent rule",
        "machine consumption remains blocked until canonical constitution id and generated projections replace the documentation bridge",
    }
    fails = "two encodings of one rule is two languages"
}

-- The structural goal. Note it is an OBJECTIVE, not an invariant: it states
-- where the language is going, and it is measured, not asserted.
correctness = law{
    id    = "law.correctness"
    kind  = .objective
    holds = .unrepresentable
    binds = {
        "invalid syntax cannot be written",
        "invalid semantics is refused by the graph, not by a linter",
    }
}

-- ═══ §2 · the constitutional stack ═════════════════════════════════════════

level: { rank: i64, name: str, role: str }

stack = {
    level{ 0, "constitution", "the source of truth" },
    level{ 1, "grammar", "constraints derived from C0" },
    level{ 2, "verification", "corpus, diagnostics, roles, agent context" },
    level{ 3, "implementation", "execution" },
}

descent = law{
    id    = "law.descent"
    kind  = .invariant
    holds = .downward
    binds = { "C0 to C3 only", "no upward dependency" }
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

-- ═══ §3 · RULE-OWNER — precedence, and why it exists ═══════════════════════
--
-- Agent output and historical pass material never outrank an owner directive
-- reconciled into this constitution. A conflicting projection is void and must
-- be repaired rather than treated as another authority.

precedence = {
    "directive",       -- the owner, verbatim, until reconciled here
    "constitution",    -- the sole living repository law
    "projection",      -- grammar, corpus, context and workflow views
    "implementation",  -- what happens to be implemented
    "history",         -- pass documents and retired source, provenance only
}

owner = law{
    id    = "law.owner"
    kind  = .invariant
    holds = .directive
    binds = {
        "a current explicit owner directive is reconciled into this constitution before implementation continues",
        "this constitution is the sole living semantic law inside the repository",
        "pass documents summaries projections corpus patterns and implementation are never parallel law",
    }
    fails = "leaving a current directive beside contradictory repository law or treating historical pass text as authority"
}

-- ═══ §4 · identity ═════════════════════════════════════════════════════════

language = @{
    name  = "idol"
    file  = ".id"
    binary = "idol"
    repository = "idollang/idol"
    epoch = 3
}

language.history = {
    @{ names = { "Idsem", "idsem" }, binaries = { "idsem" }, role = "historical and bootstrap provenance only" },
    @{ names = { "Duon", "duon", "Duo", "duo" }, files = { ".id" }, binaries = { "duo" }, role = "historical and bootstrap provenance only" },
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

-- ═══ §5 · syntax ═══════════════════════════════════════════════════════════

syntax.name = @{
    shape     = .word          -- one lowercase word
    underscore = false
    uppercase  = false
}

syntax.anchor = @{
    bare    = .descriptor      -- `@` is the enclosing descriptor
    postfix = .relation        -- `x@rel` moves the anchor
    prefix  = false            -- prefix `@` does not exist
}

syntax.block = @{
    bound     = .offside
    close     = false
    semicolon = false          -- the repair is "press enter"
}

-- ═══ §6 · semantic roles ═══════════════════════════════════════════════════

call.face = @{
    declare = .operation       -- read(number) = (lx, b) …
    invoke  = .subject         -- lx:read(number)(b)
}

subject = @{
    implicit = true
    named    = false           -- SELF-ZERO: there is no self
}

failure = @{
    result   = .union          -- t | error; structural nil is unwritten
    obligate = true            -- an unconsumed failure position diagnoses
    route    = .contract       -- B-15 routes under a declared contract
}

-- ═══ §7 · lua is hosted, not assimilated ═══════════════════════════════════
--
-- Language origin is not merely metadata. A Lua table lookup and an
-- Idol sealed-shape field lookup can have identical graph SHAPE and different
-- semantic LAW. If origin were only provenance, an optimizer could prove a
-- fact using Idol laws over a Lua node.
--
-- So: the SUBSTRATE is shared, the LAWSET is not. Lua shares shapes,
-- specialization, representation selection and witnesses without becoming
-- almost-Idol.

lua = @{
    host   = .hosted
    law    = .lua              -- lua semantics, exactly
    face   = .foreign
}

-- ═══ §8 · passes become provenance ═════════════════════════════════════════
--
-- Pass numbers stop being authority and become history. Supersession is a
-- graph operation, not a numeric comparison — which is what let "higher pass
-- wins" overrule a directive in the first place.

passes = law{
    id      = "law.pass"
    kind    = .deprecated
    holds   = false
    binds   = { "pass numbers are provenance", "supersedes is a graph edge" }
}

supersedes = @{
    old = .retired             -- removed from the current view
    new = .active
}

-- ═══ §9 · CLAUDE.md is a non-normative projection ══════════════════════════
--
-- Generation is the target. Until that projection exists, a hand-maintained
-- view must remain short, declare its source and fail closed on disagreement.

context = @{
    source = .constitution
    write  = .bootstrap
    target = .generated
    binds  = false             -- non-normative
    parts  = {
        "identity", "invariants", "canon", "denied",
        "ownership", "gates", "gaps", "foreign",
    }
}

-- ═══ §10 · the pattern lattice ═════════════════════════════════════════════
--
-- A canonical pattern is not an example. It is five artifacts, and a pattern
-- missing any of them is undefended.

pattern: {
    canon: str
    denied: str
    graph: str
    lowering: str
    diagnostic: str
}

selfzero.pattern = pattern{
    canon      = "scale = (k) @{ x * k, y * k }"
    denied     = "scale = (self, k) …"
    graph      = "scale(point, k)"
    lowering   = "param 0 is the subject; the surface names no receiver"
    diagnostic = "a parameter named self is an audit finding"
}

-- ═══ §11 · dialect identity ════════════════════════════════════════════════

dialect = @{
    kinds  = { .idol, .lua, .generated, .foreign },
    switch = false             -- no implicit mode switch
    hidden = false             -- no hidden semantics
}

-- Every semantic fact carries these three. `law` is what §7 adds and what the
-- substrate RFC was missing.
fact.marks = { "origin", "dialect", "law" }

-- ═══ §12 · canonicalization ════════════════════════════════════════════════

canon = law{
    id    = "law.canon"
    kind  = .invariant
    holds = .idempotent
    binds = {
        "parse, resolve, canon, render, reparse, compare identity",
        "canon(parse(canon(parse(s)))) == canon(parse(s))",
    }
}

-- ═══ §13 · corpora ═════════════════════════════════════════════════════════

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

-- ═══ §14 · the allowed semantic kinds ══════════════════════════════════════
--
-- This list is CLOSED. A subsystem that is not one of these, and not one of
-- the four allowed roles below, requires a constitutional amendment — which
-- means editing this file, in the open, with the owner.

kinds = {
    "id", "descriptor", "relation", "binding", "place", "demand",
    "obligation", "effect", "world", "capability", "lifetime", "provenance",
    "trust", "origin", "realization", "witness",
}

roles = { "index", "cache", "projection", "bootstrap" }

subsystems = law{
    id    = "law.subsystem"
    kind  = .invariant
    holds = false              -- no freeform subsystems
    fails = "needs a constitutional amendment, not a directory"
}

-- ═══ §15 · the mechanism delta ═════════════════════════════════════════════
--
-- What a change must NOT add. All zeros, and a nonzero is not a warning.

delta = @{
    kinds      = 0
    registries = 0
    syntax     = 0
    keywords   = 0
    operators  = 0
    authorities = 0
}

-- ═══ §16 · the agent protocol ══════════════════════════════════════════════

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

-- The stop condition, and it is a STOP, not a fallback. An agent that cannot
-- find an owner must record a gap rather than invent a home.
-- `do` cannot name this field — it is a reserved word, and `noowner` would be
-- two words jammed into one, which LAW-ONE forbids as surely as an underscore.
-- `.orphan` is the one word that names the state: an entity with no owner.
agent.stop = @{
    when = .orphan
    act  = .gap
}

-- ═══ §17 · the gate ════════════════════════════════════════════════════════

gate.agent = {
    "constitution consistent",
    "source law and canonicality classified",
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

-- ═══ §18 · what an agent reports ═══════════════════════════════════════════

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

-- ═══ §19 · why ═════════════════════════════════════════════════════════════

why.takes = { "syntax", "edge", "relation", "failure", "span" }

why.gives = {
    "canonical form", "semantic identity", "law", "graph fact",
    "origin", "resolution path", "witness",
}

-- ═══ §20 · totality — THREE gates, not one ═════════════════════════════════
--
-- The distinction the audit was right about: 100% role coverage is not 100%
-- understood meaning. A token can be beautifully coloured while its binding
-- resolution is wrong. These are separate dimensions and each gets its number.

total.role = "every span has ONE role"
total.meaning = "every semantic occurrence resolves to an id and facts or to an explicit error"
total.origin = "every non-source fact carries its chain"

-- ═══ §21 · identity is one graph entity ════════════════════════════════════
--
-- Equal content may share realization without replacing id.
-- Incarnation, correspondence, provenance and content remain separate facts.

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

-- ═══ §22 · lawsets ═════════════════════════════════════════════════════════

lawsets = @{
    native = { "idol" }
    foreign = { "lua", "c", "rust", "python", "wasm", "abi", "schema", "source", "build", "package" }
    closed = false
}

-- ═══ §23 · the lua firewall ════════════════════════════════════════════════
--
-- Exact source behaviour is non-negotiable. Representation may specialize
-- arbitrarily; behaviour may not move. Each of these participates in guards,
-- and each specialization owes a behavioural differential.

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

-- ═══ §24 · the shared substrate ════════════════════════════════════════════
--
-- Shared REPRESENTATION. Not shared law — §7 and §22 are the firewall.

shared = {
    "values", "descriptors", "bindings", "places", "calls", "relations",
    "control", "effects", "demand", "lifetime", "provenance", "origin",
    "law", "trust", "representation", "realization", "witness",
}

-- ═══ §25 · cross-language equivalence ══════════════════════════════════════

equiv = @{
    kind    = .edge
    form    = "equiv(a)(b)"
    witness = true             -- A5: no claim without one
}

-- ═══ §26 · effects touch resources ═════════════════════════════════════════
--
-- NOT a total order. A per-function happens-before chain over-constrains and
-- costs reordering, vectorization, commuting and parallelism. Effects name
-- what they TOUCH and in what mode; ordering is DERIVED where dependence
-- actually requires it.

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

-- ═══ §27 · ownership ═══════════════════════════════════════════════════════

ownership = {
    "native", "region", "rc", "borrowed", "pinned",
    "foreign.lua", "foreign.python", "foreign.jvm", "wasm.linear",
}

-- ═══ §28 · what dnir is, and is not ════════════════════════════════════════

-- `is` and `not` are both reserved, so the fields are `role` and `denies` —
-- two more places the constitution had to obey itself to be written.
dnir = @{
    role   = "demand-selected realization, linearized"
    denies = { "the semantic graph", "the language definition" }
}

-- dnir is a FAMILY of canonical realization facts with backend views, not one
-- linear form serving every backend forever. These are FACETS of one graph, not
-- independent IRs; a backend requests the facets it needs and the textual
-- `.dnir` form is a deterministic projection of them.
dnir.facets = {
    "core",        -- scalars, places, blocks, calls, packs, effects, control
    "mem",         -- lifetime, retain/release, region operations
    "vector",      -- lanes, masks, vector operations
    "concurrent",  -- suspend, resume, atomic
    "machine",     -- target-selected constraints
}

-- Every dnir operation carries these. A physical temporary may be `%17`, and
-- `%17` is NEVER semantic identity — that is what keeps backend-local numbering
-- out of MCP, LSP, debugging and the persistent graph.
dnir.marks = { "meaning", "incarnation", "origin", "law", "witness" }

-- Linearization need not be perfectly reconstructable — optimization destroys
-- surface structure — but every instruction maps BACKWARD to its semantic
-- nodes, source spans, transforms and witnesses. That route is what powers
-- debugging, perf blame, why(realization), review and certification.
dnir.reverses = true

-- ═══ §28a · what is persisted ══════════════════════════════════════════════
--
-- "Persist meaning; derive mechanics." Not every compiler detail belongs in the
-- persistent graph. Register allocation is not persisted merely because graphs
-- are fashionable.

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

-- ═══ §29 · realization candidates ══════════════════════════════════════════

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

-- ═══ §30 · optimization is a witnessed rewrite ═════════════════════════════

rewrite: {
    pattern: str
    holds: seq(str)
    gives: str
    preserves: seq(str)
    cost: str
    witness: str
}

-- ═══ §31 · frontends ═══════════════════════════════════════════════════════
--
-- A foreign language lifts to the SUBSTRATE directly. Routing it through a
-- Idol AST first would assimilate its semantics on the way in, which is §7.

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

-- ═══ §32 · a call across a boundary ════════════════════════════════════════

edge.call = {
    "caller law", "callee law", "abi", "ownership", "effects",
    "failure translation", "trust", "representation",
}

-- ═══ §33 · the self-hosting sequence ═══════════════════════════════════════
--
-- In SLICES, never all at once. At every rung: the old implementation is the
-- ORACLE, the new one is the CANDIDATE, and the differential is the JUDGE.
-- Do not rewrite from faith.

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

-- ═══ §33a · the orientation truths every agent gets first ══════════════════

-- The structured documentation keeps one rule per string so every obligation
-- remains independently reviewable. This notation is not canonical source.
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

-- ═══ §34 · the final architectural invariant ═══════════════════════════════

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

-- ═══ §35 · topology ════════════════════════════════════════════════════════

layers = {
    "constitution", "grammar", "context", "tooling", "frontends",
    "graph", "specialized", "realization", "dnir", "backend",
}

-- ═══ §36 · THE COMPILER'S OWN ARCHITECTURE IS IDOL-SHAPED ══════════════════
--
-- The compiler should not merely COMPILE Idol this way. A host helper that
-- owns a recoverable semantic distinction is evidence that the architecture
-- has not internalized its own language.

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

-- These are not unrelated functions sharing a prefix. They are ONE open
-- relation successively specialized: `add`, then the LEVEL, then the subject,
-- then the value. Where the operand already names its kind, `g:add(n)` resolves
-- through the descriptor of `n` and the level is unnecessary.
add.canon = { "g:add(n)", "g:add(mode)(n)" }   -- level ONLY where mode is a real choice

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

-- `parent contains child` is the fact; child scope, parent children and
-- ancestry are projections. A host helper may project that fact but does not
-- create another semantic operation.
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

-- `add` is an ORDINARY OPEN RELATION, not privileged compiler magic. The
-- compiler ships well-known specializations; a graph world may authorize more
-- under coherence. A hidden switch over kinds would fix forever what adding can
-- mean.
--
-- Closed host enums are compact indexes only. They may not freeze the set of
-- relations or revive retired source concepts as graph ontology.
kinds.role = .index          -- bootstrap acceleration, never ontology
kinds.authority = false

-- A graph VALUE is immutable current truth. Authority to produce the next
-- incarnation is a WORLD, so arbitrary code cannot mutate compiler truth by
-- accident. G0 --transaction--> G1, never mutation in place — which is what
-- buys incrementality, undo, replay, speculation, parallel agents and stable
-- incarnation identity.
edit.canon = { "edit = world(graph)(g)", "parent:add(child)" }  -- graph is AUTHORITY, not cargo

-- The irreducible primitives. Everything else — descriptor, binding, place,
-- effect, capability, lifetime, origin, trust, provenance, representation,
-- realization — is a semantic FAMILY OF FACTS, not a separate graph object
-- class. The graph must not look like an OO graph database implemented in Zig;
-- it is Idol's relation calculus made persistent.
primitives = { "value", "relation", "fact", "world", "demand", "witness" }

-- TRUST IS A LEVEL ON A FACT, never a mechanism standing beside one. The line
-- above already names trust a FAMILY OF FACTS; these are its levels, in the
-- ordinary Idol sense that `read(number)` is a level — no new object class, no
-- new surface.
--
-- An assertion must be recorded, attributable and invalidatable. An unlabelled
-- assumption is never allowed to masquerade as proof.
trust = @{
    inferred = .derived      -- the compiler derived it from the graph
    proven   = .witness      -- A5 satisfied; the witness is inspectable
    observed = .sample       -- profile-time; carries its sample and its expiry
    asserted = .author       -- the author knows and the compiler cannot check
    foreign  = .lawset       -- a foreign lawset guarantees it, trust-tagged
    guarded  = .runtime      -- true under a check, which carries its descent
}

-- Weakest last, and an unlabelled claim takes the WEAKEST level rather than the
-- strongest. A default of `proven` is how six mechanisms became invisible.
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

-- ABSENCE IS A FACT, AND ITS SPELLING ALREADY EXISTS. A2 NNS, checked against
-- this document rather than assumed: a false-valued field in a descriptor is
-- how absence has always been written here — `syntax.anchor` denies a prefix,
-- `syntax.name` denies underscore and uppercase, `syntax.block` denies the
-- semicolon, `subject` denies a name, `kinds` denies authority, `std` denies
-- ambient reach. Nothing is owed at the SURFACE, and a proposal for `noalias`,
-- `restrict` or an unsafe block is the signal that the existing form has not
-- been found yet.
--
-- What IS owed is the ENUMERATION. Optimization runs on negative facts — no
-- alias, no re-entry, no failure edge, no observer — and the compiler spells
-- none of them, so a flag stands in for "no alias exists" and hopes. Each
-- negative below is an ordinary fact taking an ordinary trust level, which is
-- the whole point: `alias = false` proven by an ownership witness and the same
-- words asserted by an author are different claims, and only the census can
-- tell them apart.
--
-- The negative ownership fact is `sharing`; a reserved grammar word does not
-- become a new fact identity merely because a proposal used it.
absence = @{
    sharing  = .ownership    -- no other live place reaches this one
    reentry  = .world        -- no foreign frame re-enters during this scope
    failure  = .contract     -- no failure edge leaves this realization
    observer = .region       -- no other thread observes this place
    effect   = .purity       -- no world is touched
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

-- dnir is THE CANONICAL REALIZED RELATION STREAM — not nodes plus an operation
-- taxonomy. This SUPERSEDES the earlier "family of facets" reading in §28:
-- naming sub-ir families recreates ir kingdoms under a friendlier word.
-- The `add` identity stays traceable at every rung, which a conventional opcode
-- enum cannot promise:
--
--     semantic     x --add--> y, z
--     realized     add(i64)(register, register)
--     dnir         %3 = add.i64 %1 %2
dnir.stream = true

-- ═══ the final invariant ═══════════════════════════════════════════════════

final = law{
    id    = "law.final"
    kind  = .invariant
    holds = .one
    binds = { "no competing semantic systems", "all meaning reduces to here" }
    fails = "a second place where meaning is decided"
}

-- ═══ §36 · what the twenty-point review added, and nothing more ════════════
--
-- Five rulings the adjudication produced that no fact above carries yet. Added
-- rather than restated: every other point of that review was already law here.

-- SELF-ZERO deletes a PARAMETER, not a PROOF. Unspecified, the ambient subject
-- becomes a second borrowing mechanism by accident — `capture = () .` and a
-- nested `f = () () .` have to answer reference vs copy vs view vs lifetime
-- extension, and each answer touches closures, regions, ownership, aliasing and
-- ABI. A surface cheaper than the binding it abbreviates is how implicit
-- borrowing gets in.
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

-- The memory ladder's load-bearing undefined term. `cycle-possible` is doing
-- enormous work: dynamic tables, closures capturing tables capturing closures,
-- foreign objects, weak refs, finalizers, resurrection, cross-thread graphs,
-- detection latency, behaviour under memory pressure, per-object metadata.
-- "Never a tracing collector" is a LATENCY PROMISE, so it is measured, not
-- asserted — and lua hosting generates pathological cyclic graphs routinely,
-- which makes the supremacy story and the memory doctrine ONE experiment.
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

-- The wasm engine is one very large file BECAUSE compiler defects punish
-- decomposition. An agent reading it could conclude giant modules are idiomatic
-- high-performance Idol. THEY ARE NOT. Every such workaround is a gap with a
-- removal fixture, and the engine is the primary language-design fuzzer: each
-- ugly thing it needs is either inherent wasm complexity or an Idol defect, and
-- it gets adjudicated as exactly one of the two.
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

-- Fastest AND smallest AND most featureful are conflicting dimensions, so the
-- WHOLE matrix publishes, losses included. The external reference runtime is a
-- moving oracle and ceiling, never an ancestor: its performance is ITS claim,
-- and this repository may publish only its own last reproducible measurement.
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

-- Package composition is a semantic exercise, not package-system detail owed
-- after implementation.
-- And compatibility does not reduce to graph shape: complexity, effects,
-- allocation, determinism, the error set, precision, ordering stability, a
-- sealed descriptor opening, and timing observable through a foreign interface
-- all move while the edge set stands still. A COMPUTED number that misses an
-- effect growth is worse than a declared one, because it is trusted.
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

-- ═══ §37 · ORIENTATION. Semantic expressibility is not canonicality. ═══════
--
-- Idol source may be semantically correct and still noncanonical. Orientation,
-- compaction and idiom are LAW, not taste — and the compiler, formatter,
-- agents, std, the self-hosted compiler, Idol Wasm, the docs and every piece of
-- architectural pseudocode obey the same one.

-- Declare from the relation. Work from the value. The two faces are different
-- questions: the declaration answers "what relation exists?", the invocation
-- answers "what can this value do or become?". Never collapse them into one
-- spelling. Operation-first at a CALL SITE is canonical only when the relation
-- itself is the value being held or passed — `xs:map(to(str))`.
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

-- A level names a REAL CHOICE, never a category already recoverable. If removing
-- a level leaves exactly one valid edge, the canonicalizer removes it. `x:to(str)`
-- cannot collapse — `str` is the demanded destination and is an independent
-- decision. `g:add(node)(n)` DOES collapse, because `n` names its own descriptor.
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

-- THE OBJECT THAT STORES THE DATA IS NOT NECESSARILY THE SEMANTIC SUBJECT.
-- A host structure owning the memory does not make it the receiver. If the
-- operation resolves a subject, canonical orientation is `subject:resolve(rel)`
-- with the graph ambient — NOT `graph:resolve(relation)(subject)` merely because
-- the index physically lives in a graph object. This is the law that stops
-- pseudo-OOP drift, and it is the twin of law.face.subject: together they
-- forbid both `compiler:everything(...)` and `lower(target)(value)`.
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

-- Ambient is earned, not assumed: a thing is ambient ONLY where exactly one
-- valid contextual value exists. Otherwise it DIAGNOSES. No hidden global
-- compiler graph — the dynamic global environment is a lua fact, not an Idol one,
-- and it may not return as architecture.
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

-- Canonical source is a FIXED POINT, semantically and not merely by formatting.
-- The canonicalizer performs semantic REPAIRS — `to(str)(n)` becomes `n:to(str)`
-- — and emits a witness naming the relation, subject, level and the unchanged
-- graph identity, which is what makes the rewrite justified rather than a
-- reformat. Idiom is checked across every dimension at once, not one grep:
-- face, level, home, bind, return, route, subject, case, chain, convert.
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

-- Relation metadata carries the canonical face, so rendering is DERIVED rather
-- than left to agent taste. An argument list is not `{ a, b, c }` — each operand
-- carries a ROLE, and orientation follows from the roles automatically. This is
-- also what stops a bootstrap host signature from teaching the renderer that its
-- first parameter is the receiver.
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

-- DOCUMENTATION IS CORPUS. A code block in a normative document is a canonical
-- corpus member and compiles under the same gate, because an architect writing
-- `to(str)(x)` in a design note teaches every later agent the wrong idiom. A
-- block is Idol, dnir, foreign or CONCEPTUAL — and if an idea cannot yet be
-- expressed canonically it is marked conceptual and filed as a gap. Never invent
-- near-Idol. Prose is lintable too: say "add fact" and "resolve relation", never
-- "call addnode" or "the registry owns".
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

-- ═══ §37 · DISTRIBUTION IS NOT SEMANTICS (the stdlib reconciliation) ════════
--
-- THE DEEPEST RULE, and everything below is a consequence:
--
--   Distribution boundaries must never become semantic boundaries unless the
--   semantics genuinely require it.
--
-- Four distinctions follow:
--
--   1. A function does not become conceptually different because it arrived
--      from another package.
--   2. A standard operation does not need a package root because of where its
--      implementation file lives.
--   3. A package namespace is not a substitute for relation identity.
--   4. IMPORTING CODE IS NOT GRANTING CAPABILITY.

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

-- The orthogonal facts that a conventional standard-library namespace blurs.
--
--   meaning    ordinary Idol descriptors, relations, values and laws —
--              relation, table, callable, failure, basic numerics and
--              sequences, reflection. Always present. No import, no prefix.
--   vocabulary standardized relation and descriptor IDENTITIES that are NOT
--              language axioms — sort, encode, json, time, format. Standard
--              MEANING; realization is replaceable.
--   package    a separately versioned GRAPH FRAGMENT contributing descriptors,
--              relations, implementations, worlds, laws, realizations. It does
--              NOT contribute a namespace.
--   world      AUTHORITY to perform effects, orthogonal to distribution.
distribution.projects = { "relation", "descriptor", "law", "world", "implementation", "realization", "origin", "trust" }

-- Availability and authority remain orthogonal. A relation may be known while
-- its required world refuses the application.
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

-- MEANING is standard and non-replaceable; REALIZATION is replaceable. A
-- package may contribute a better `sort` realization — insertion, introsort,
-- radix, simd, gpu — and the call stays `xs:sort()`. It may NOT redefine what
-- standard `sort`, `eq`, `hash` or `to` MEAN, or ordinary code would change
-- behaviour on installation.
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

-- REACHABILITY FOR LINKING AND REACHABILITY FOR RESOLUTION ARE DIFFERENT
-- RELATIONS. `app -> orm -> driver` must not hand the app every edge the driver
-- contributes; `orm` decides what it re-exports. Without this, a project with
-- 400 dependencies has an unreasonable resolution universe and composition
-- becomes spooky.
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

-- Coherence under composition, which is the real pre-registry problem: two
-- fragments may each imply a different edge for the same identity. "Latest
-- import wins" is DENIED — it destroys semantic locality.
coherence.rule = "a package may freely define relations over identities it OWNS. extending a relation where it owns NEITHER side needs explicit extension authority or a local scope."

-- Packages advertise PROVEN FACTS, not only apis — allocation-free, deterministic,
-- no-network, native on a target, thread-safe, no-failure under a descriptor.
-- Downstream optimization consumes them, which makes a package a fragment
-- carrying realization knowledge rather than only code you can call.
package.publishes = { "origin", "version", "exports", "requires", "guarantees", "implementations", "provenance" }

-- Build, dev, runtime and plugin dependencies are ONE system. The STAGE at
-- which a fragment is demanded decides when it participates; separate
-- dependency families are a mechanism duplicated four times.
depends = law{
    id    = "law.depends"
    kind  = .invariant
    holds = .stage
    fails = "build-dependency, dev-dependency and proc-macro as separate families"
}

-- Feature flags are DEMAND, not package metadata booleans. If nothing demands
-- tls, its fragment and realization disappear. A package with 50,000 semantic
-- facts may contribute 17 machine realizations to a given program — which is
-- what makes "more featureful AND smaller binary" expressible rather than
-- contradictory.
features = law{
    id    = "law.features"
    kind  = .invariant
    holds = .demand
    fails = "a feature-configuration mini-language beside the language"
}

-- ═══ §38 · THE PERFORMANCE CONSTITUTION ════════════════════════════════════
--
-- NORTH STAR: Idol source states MAXIMUM SEMANTICS; the compiler emits MINIMUM
-- MACHINERY.
--
-- Performance, binary size, compile time, memory and specialization cost are
-- REALIZATION OBJECTIVES, not benchmarks run afterwards. Every layer preserves
-- enough semantic information for the compiler to optimize them JOINTLY rather
-- than locally.

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

-- Every dynamic mechanism carries the SAME ladder and an exact descent.
-- Relation lookup, tables, closures, failures, packages, worlds, foreign
-- values, wasm dispatch, lua metatables — one ladder, not one per subsystem.
perf.ladder = {
    "dynamic", "observed", "guarded", "sealed", "direct", "erased",
}

-- Budgeted GLOBALLY, never greedily. A specialization justifies its code
-- growth or it is refused, and `why(skip)` answers.
perf.worth = {
    "hotness", "expected cycles saved", "guard cost", "compile cost",
    "icache pressure", "binary growth", "duplication", "deopt probability",
}

-- THE INVERSE OPERATION, and the tree has no mechanism for it. Without
-- re-generalization the compiler can derive billions of variants and has no way
-- to recover compactness.
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

-- Three reusable engines replace a conventional procession of semantic passes.
-- Their physical indexes are disposable projections; ids, facts, relations,
-- witnesses and provenance remain the authority.
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

-- THE SIZE INVARIANT, and it is what makes "more featureful AND smaller" a
-- statement rather than a contradiction:
--
--   FEATUREFULNESS is a property of the SEMANTIC GRAPH.
--   BINARY SIZE is a property of DEMANDED REALIZATION.
size.invariant = true

-- Every emitted byte range is attributable to a semantic demand — the relation,
-- what demanded it, its realization, and why it was retained. That is what
-- `idol why size` reads, and it reports semantic causes rather than symbols.
size.ledger = { "relation", "demanded by", "realization", "retained because" }

-- Multi-objective cost. The build's world chooses the objective; these are
-- ordinary descriptors, NOT compiler-mode kingdoms, so one deployment may
-- optimize a hot kernel for speed and everything else for size.
cost.facts = {
    "cycles", "bytes", "compile", "peak", "allocations",
    "misses", "footprint", "energy", "variance",
}
cost.objectives = { "speed", "size", "startup", "latency", "energy", "balanced" }

-- These ratios are definitions. Current values belong to revision-bound
-- evidence, never to the constitution.
perf.ratios = {
    "retention: realized facts / reachable semantic facts",
    "erasure: constructs erased / constructs used",
    "efficiency: measured speedup / added code bytes",
    "compression: semantic values / physical runtime objects",
    "density: demanded relations / binary kb",
    "reuse: realized capabilities / distinct mechanisms",
}

-- ═══ §39 · THE PRIME DIRECTIVE (what every agent receives first) ════════════
--
-- You are MODIFYING Idol. You are not designing a conventional compiler in Zig
-- and you are not inventing language architecture. The job is to move the
-- repository MONOTONICALLY toward 100% self-hosted canonical Idol with zero
-- competing semantic mechanisms.
--
-- THE CORE QUESTION, asked before adding anything:
--
--   Is this an irreducible NEW concept, or is it already a value, relation,
--   fact, world, demand, witness or realization — specialized by operands and
--   context?
--
-- ASSUME THE LATTER UNTIL PROVEN OTHERWISE. Prefer one relation with many
-- specializations over many functions, enums, registries, managers and systems.

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

-- For every semantic operation, name all eight. An operation that cannot name
-- them is not understood well enough to land.
operation.names = {
    "canonical relation", "semantic subject", "semantic owner", "fact",
    "lawset", "witness", "physical projection", "deletion gate",
}

-- What an agent must be able to show is ZERO before completion. A nonzero entry
-- is not a warning; it needs a constitutional amendment.
delta.zero = {
    "semantic owners added", "competing registries added", "semantic enums added",
    "syntax added", "keywords or operators added", "string-based semantic cases",
    "unclassified semantic apis", "new silent fallbacks",
}

-- THE FINAL TEST, and it is the strongest rule in this file because it is the
-- only one that closes a class rather than an instance:
--
--   Could another competent agent look at this change and reasonably implement
--   the SAME semantic idea using another registry, enum, helper family, api
--   orientation, syntax or subsystem?
--
--   IF YES, DO NOT STOP. Find and enforce the missing constitutional invariant
--   so there is only ONE reasonable Idol-native direction.
--
-- Restated as the rule it generalizes: any architectural mistake an agent can
-- make TWICE is a missing machine-enforced invariant. The constitution evolves
-- primarily by converting recurring review findings into executable
-- impossibility.
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

-- THE OBJECTIVE, stated so it is not mistaken for code quality: not merely code
-- that works, but a repository in which non-Idol architecture becomes
-- IMPOSSIBLE TO WRITE, IMPOSSIBLE TO TEACH, IMPOSSIBLE TO MERGE, and
-- UNNECESSARY TO REPRESENT.
objective = law{
    id    = "law.objective"
    kind  = .objective
    holds = .unrepresentable
    binds = {
        "impossible to write", "impossible to teach",
        "impossible to merge", "unnecessary to represent",
    }
}

-- A lexical host scan can ratchet spellings but cannot close an architectural
-- class. Different names can own the same shadow meaning, while a correctly
-- named physical helper can still orient the semantic subject incorrectly.
--
-- So the scan MEASURES the habit and does not CLOSE it. The invariant it is
-- missing is declarative rather than lexical: every function that mutates or
-- resolves semantic state DECLARES the relation it projects, and an unannotated
-- semantic mutation is the finding. Then the question stops being "what is it
-- called" and becomes "how many physical apis project `add`, and why".
scan.gap = "lexical rows cannot close an architectural class — projects= is owed"

-- ═══ §40 · SYNTAX SUBTRACTION — leading dot is retirement debt ══════════════
--
-- This law supersedes every earlier leading-dot reading.
--
-- CANONICAL `.` HAS ONE MEANING: explicit postfix projection from an
-- ALREADY-WRITTEN subject — `x.y`. Every other leading-dot form is retirement
-- debt, and is not preserved merely because the parser accepts it.
--
-- THE TEST, asked of every syntactic form and not only this one:
--
--   Does this token encode semantic information ALREADY UNIQUELY RECOVERABLE
--   from subject, expected descriptor, demand, relation identity or context?
--
--   If yes it is canonicalization debt. AND THE REPAIR IS NOT NEW SYNTAX.
--
-- THE TARGET IS NOT FEWER CHARACTERS. It is FEWER SYNTACTIC SEMANTIC
-- MECHANISMS. A shorter spelling that adds a mechanism is a loss.

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

-- FIVE OBLIGATIONS BEFORE ANY DELETION. Retirement is proven, not asserted.
--
-- Replacement parsing is insufficient. The replacement must resolve, lower and
-- preserve behavior by value before a source face is deleted.
subtract.proves = {
    "the replacement RESOLVES AND LOWERS, proven BY VALUE, on both backends",
    "every semantic role has a strictly SIMPLER EXISTING spelling",
    "resolution is deterministic",
    "canonical lowering is NO WORSE",
    "the canonicalizer migrates it mechanically",
    "lua and foreign dialects are unaffected",
}

-- SELF-ZERO requires implicit-subject fields to use ordinary bare identities.
-- Leading-dot fields and bare dot are retirement debt; leading colon remains
-- the admitted ambient-subject application face.
--
--   scale = (k) @{ x * k, y * k }
--
-- Which collides with a local binding named `x`, so obligation 2 —
-- DETERMINISTIC RESOLUTION — is the one that decides this form, and it is not
-- yet proven either way. This is recorded as OPEN rather than resolved.
subtract.blocked = "self-zero's implicit subject: bare identity vs local binding"
subtract.free = { "case in construction", "argument lens", "inferred case" }

-- ═══ §41 · SELF-ZERO, REDEFINED — the receiver disappears, not into dots ════
--
-- This resolves the open SELF-ZERO question and supersedes every punctuation-
-- receiver definition.
--
-- THE MISTAKE THE OLD DEFINITION MADE: it defined SELF-ZERO as `.x` / `.y` /
-- `:length()`, which makes `.` and `:` CARRY THE BURDEN OF SELF. The receiver
-- did not disappear; it was respelled as punctuation.
--
-- THE CORRECTED DEFINITION:
--
--   A subject-bearing scope contributes its subject's visible relations and
--   projections to ORDINARY NAME RESOLUTION. The subject has no user-visible
--   binding name.
--
-- So this is the SELF-ZERO form:
--
--   point:scale = (k) @{ x * k, y * k }
--
-- and this is not:
--
--   point:scale = (k) @{ .x * k, .y * k }

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

-- THE COMPLETE RECEIVER MODEL. Seven rows, and every one of them earns its
-- spelling:
--
--   explicit field            p.x
--   IMPLICIT field            x
--   explicit relation         p:length()
--   IMPLICIT relation         :length()
--   explicit whole subject    p
--   passed field projection   map(name)
--   passed relation           map(to(str))
receiver.model = 7

-- `:` IS KEPT BECAUSE IT CONTRIBUTES INFORMATION. `normalize()` could be an
-- ordinary local or world function; `:normalize()` unambiguously says "invoke
-- the normalize relation on the ambient subject". That earns its syntax.
--
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

-- THE ONE RULE THAT REPLACES THREE PUNCTUATION ENCODINGS. `.case`, `.field`
-- and `.lens` were three spellings for three contexts the graph already
-- distinguishes:
--
--   BARE IDENTITY + SEMANTIC DEMAND + AVAILABLE HOMES -> ONE IDENTITY, OR A
--   DIAGNOSTIC.
--
--   law{ kind = invariant }     `invariant` resolves: kind demands a case
--   point:scale = (k) x * k     `x` resolves: the subject has one projection x
--   users:map(name)             `name` resolves: map demands a callable
resolution.rule = "bare identity plus demand plus homes yields one identity or a diagnostic"

-- SHADOWING IS DIAGNOSED, NEVER SILENTLY RESOLVED. "Locals win" is DENIED:
-- adding `x = 3` would silently change every later `x` from a subject
-- projection to a local binding, which makes source meaning depend on a
-- declaration the reader may not have reached yet.
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

-- Leading-dot fields retire to bare identity once deterministic resolution is
-- implemented. Bare dot has no canonical role. Leading colon remains because
-- it contributes the ambient-subject application fact.
subtract.resolved = "leading dot retires; bare dot is invalid; leading colon remains"

-- ═══ §42 · SURFACE SUBTRACTION — the rules that keep it from becoming golf ══
--
-- Canonical Idol encodes ONLY distinctions the compiler cannot
-- recover from the explicit subject, the ambient subject, expected descriptor,
-- relation identity, operand descriptors, demand, lexical scope, or
-- world/lawset context. Syntax restating recoverable information is debt.
--
-- ULTIMATE RULE: syntax exists to RESOLVE UNCERTAINTY, not to RESTATE
-- CERTAINTY. The shortest form is not the one with the fewest characters — it
-- is the one containing the FEWEST UNNECESSARY SEMANTIC DECISIONS.

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

-- THE CANONICAL-PERFORMANCE LAW.
-- A canonical rewrite is INVALID if it lowers worse than the form it replaces
-- without a semantic reason. Canonicality and performance CANNOT DISAGREE —
-- and where they do, COMPILER CAPABILITY IS THE GAP, never the corpus.
--
-- A canonical face that does not yet resolve or lower while a noncanonical
-- fallback does is compiler-capability debt, not permission to canonize the
-- fallback.
--
-- In both the corpus looked like bad taste and was authors writing what
-- compiles. This law inverts the repair order permanently: FIX THE CAPABILITY,
-- THEN ENFORCE THE ORIENTATION.
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

-- RESOLUTION ENTROPY CEILING. Every omitted token transfers work to semantic
-- resolution, and that cost is MEASURED, not assumed away. A compaction is
-- accepted only when resolution stays unique, diagnostics stay good, local
-- reasoning stays predictable, and AGENT GENERATION ACCURACY DOES NOT REGRESS.
-- If removing syntax causes a large nonlocal search, THE SYNTAX WAS EARNING ITS
-- KEEP.
entropy.resolution = law{
    id    = "law.entropy"
    kind  = .invariant
    holds = .bounded
    binds = { "hpls includes compaction WITHOUT semantic-distance explosion" }
}

-- SEMANTIC LOCALITY. Bare-identity resolution draws from a PREDICTABLE LOCAL
-- LATTICE and nothing wider. Transitive dependency existence does NOT make an
-- identity visible — no global graph soup.
locality.lattice = {
    "lexical", "ambient subject", "expected descriptor",
    "exact visible semantic identities", "admitted vocabulary",
}

-- WHAT IS NOT COMPACTED, stated so subtraction does not become point-free code.
-- Idol does not delete syntax merely because the graph can technically infer
-- meaning. These carry irreducible or high-value HUMAN information:
keep = {
    "x.y", "x:f()", ":f() under self-zero",
    "if", "while", "for x in xs", "break", "continue",
    "arithmetic and comparison operator faces", "[expr] computed keys",
    "() ordinary application", "{} structured packs and descriptor homes",
    "[] computed keys", ". named projection", ": descriptor, subject and home roles",
    "ordinary interpolated strings", "offside layout",
}

-- THE THREE TIERS. Retirement is not one list — it is a judgement per form.
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

-- LEVEL-ZERO, HOME-ZERO, TEMP-ZERO, ROUTE-ZERO, SUBJECT-ZERO, CASE-ZERO,
-- CONVERT-ZERO. One test serves all seven: does removing it leave EXACTLY ONE
-- valid reading? If yes it goes; if no it stays in its smallest existing form.
zero.test = "does removal leave exactly one valid edge"

-- CONSTITUTION SOURCE MIGRATION. This Markdown document is structured law
-- notation, not executable canonical source. It moves atomically to
-- `constitution.id` only after GAP-145 closes lexical identity and generated
-- grammar roles and the complete body passes all four canonical source layers.
migrate.first = "the constitution"
migrate.blocked = "gap[145] — canonical lexical identity and generated roles are incomplete"

-- Grammar reconciliation: postfix `expr.name` is statically named projection;
-- bare dot has no ambient-subject meaning. The formal grammar and this law must
-- converge through one generated role projection.
grammar.owed = "remove bare dot primary; preserve postfix named projection; generate every role from one authority"

-- ═══ §43 · DELIMITER CLOSURE — useful source distinctions survive ═══════
--
-- Brace-zero and bracket-zero are closed.
--
-- Source faces preserve useful human distinctions while semantic meaning
-- converges immediately after resolution. One application architecture does
-- not imply one delimiter. Parentheses carry ordinary callable operands;
-- braces carry structured packs, descriptor homes and descriptor application;
-- brackets carry genuinely computed keys. None selects a physical aggregate.

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

-- `@{ … }` IS THE SAME FORM with the name ELIDED — the enclosing descriptor
-- supplies it. So the anchor constructor is not a third mechanism either; it is
-- `name{ … }` where the name is recovered from context, which is exactly what
-- §42's minimum-information rule says should happen when the name is already
-- known.
anchor.recover = "the same form, name recovered from the enclosing descriptor"

-- The provisional brace-call is retired. Ordinary call and descriptor
-- application converge semantically only after their distinct source facts
-- have been recognized.
audit.braceresolved = "brace-call retired; callable uses parentheses; descriptor application uses braces"

-- The resolution rule is §41's, unchanged and now doing a second job:
--
--   BARE IDENTITY + SEMANTIC DEMAND + AVAILABLE HOMES -> ONE IDENTITY, OR A
--   DIAGNOSTIC.
--
-- Here the demand is a descriptor applicable to a structured pack. Callable
-- resolution remains the ordinary parenthesized face. Both produce graph
-- application facts without preserving a source delimiter as semantic truth.

-- ═══ §44 · APPLICATION IS ONE MECHANISM ════════════════════════════════════
--
-- Application unification is SEMANTIC, never punctuation unification. The
-- recognizer retains the minimum source structure and provenance. Resolution
-- supplies relation, subject, operand pack, result pack and descriptor facts.

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

-- Unification of the MECHANISM is not a claim that every application is
-- observationally identical. These stay distinct EDGES — specializations of one
-- relation, exactly as `add(node)` and `add(edge)` are specializations of `add`,
-- never separate grammar or object models.
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

-- Unification must EXPOSE facts, not erase them. The application identity
-- carries subject identity, argument labels and positions, operand descriptors,
-- constants, world, demand and return pack — so `point{ x = 1, y = 2 }` is a far
-- stronger fact than a generic dynamic call, and specializes accordingly.
apply.carries = {
    "subject identity", "argument labels", "argument positions",
    "operand descriptors", "constants", "world", "demand", "return pack",
}

-- ═══ §44a · the traps, the surviving distinction, and the ladder ══════════
--
-- The laws below extend the one application architecture without duplicating
-- its identity, construction or pack owners.

-- THREE TRAPS, each a plausible implementation that would regress this ruling:
--
--   1. PARSER-LEVEL OVERLOAD — the parser asking whether `point` is a type,
--      emitting a constructor node if so and a call node if not. That is the
--      split this law deletes,
--      relocated one layer down. My own reverted patch did this in codegen,
--      branching on `record_aliases`, and it was the same mistake at a third
--      layer.
--   2. BRACES AS CALL — accepting `f{…}` for an ordinary callable erases a
--      useful source distinction. Defining `f({…})` as a forced table operand
--      separately commits representation before demand.
--   3. LOST CALL SHAPE — application identity must PRESERVE subject identity,
--      argument labels, positions, descriptor identities, constants, world,
--      demand and return pack. `point{ x = 1, y = 2 }` must be strictly
--      STRONGER than a generic dynamic call, never equal to one.
apply.traps = { "parser overload", "braces as sugar", "lost call shape" }

-- The distinction that SURVIVES, and it is not "constructor versus call":
--
--   { x = 1, y = 2 }         an ordinary anonymous structured value
--   point{ x = 1, y = 2 }    APPLICATION of `point` to that shape
--
-- Different because one has a SUBJECT.
--
-- Descriptor, callable and staged applications remain distinguishable through
-- facts while sharing one application architecture. Computed indexing retains
-- subject, key pack, place, value, descriptor and demand facts without becoming
-- callable syntax.
apply.edges = { "descriptor", "callable", "staged" }

-- The ladder this buys, which is why the unification is worth more than the
-- collision it fixes:
--
--   dynamic application -> descriptor known -> field shape known -> layout
--   known -> direct initialization -> scalar replacement -> registers
--
-- NO CONSTRUCTOR ABSTRACTION SURVIVES INTO MACHINE CODE UNLESS DEMANDED.
apply.ladder = 7

-- ═══ §45 · DELETION CONTRACTS — relation.zig may not fossilize ═════════════
--
-- `src/relation.zig` is a deletion-gated bootstrap projection of ordinary graph
-- relation facts. None of its host object taxonomy is semantic authority, and
-- cleaner host names do not make a parallel registry canonical.

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

-- FOUR DEBTS NAMED, each with the condition that retires it:
--
--   string identities   relation resolution must not depend on textual
--                       descriptor names once exact graph relation identities exist —
--                       packages, renames, MCP, refactoring and multiple
--                       versions all break on text.
--   codegen legality    the lossy-composition REFUSAL happens at codegen, so
--                       `duo check` approves what compilation later refuses.
--                       Class algebra belongs in SEMANTIC RESOLUTION: legality
--                       above realization, always.
--   one hop             derivation is deliberately one hop. Before longer
--                       paths, a path-selection law must cover multiple valid
--                       paths, cost, loss, effects, ownership, failure, trust
--                       and ambiguity. **Adding BFS would be architecturally
--                       wrong** — search is not a coherence law.
--   `to` in codegen     four literal `"to"` comparisons remain, annotated
--                       non-authoritative. HARD GATE: once primitive
--                       conversions are authored std relation facts,
--                       `codegen.zig` must go NET NEGATIVE in conversion code,
--                       or the relation layer is a front-end feeding the same
--                       builtin emitter kingdom.
relation.retires = { "string identities", "codegen legality", "one hop", "to comparisons" }

-- ═══ §46 · NOMINAL IDENTITY IS THE NEXT WALL ═══════════════════════════════
--
-- A nominal value cannot participate in derived relations if the compiler
-- collapses it into the descriptor of its physical initializer.
--
-- That is not a conversion feature. It is REPRESENTATION POLYMORPHISM, and it
-- is the milestone the algebra is waiting on: **a `feet` value may physically
-- remain an f64 while being semantically distinct.** Expanding conversion
-- machinery before this lands buys nothing, because there is nothing for the
-- derived edges to act on.
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

-- ═══ §47 · C-DOMINANCE — C is a CANDIDATE, not the ceiling ═════════════════
--
-- THE HONEST QUALIFICATION FIRST, because the goal as usually stated cannot be
-- met: no compiler can guarantee that EVERY Idol program beats EVERY
-- hand-written C program on every machine and every metric. A human can write
-- assembly, exploit undocumented behaviour, or choose a workload built to
-- defeat one optimizer.
--
-- What IS achievable, and is strictly stronger than benchmarking:
--
--   For every Idol program whose semantics are no stronger than an equivalent
--   C program, the compiler must be able to produce machine code NO WORSE than
--   the best C realization in its candidate set — while exploiting semantic
--   facts unavailable to C where they exist.
--
-- THE MECHANISM. C stops being the ceiling and becomes ONE CANDIDATE
-- REALIZATION. For any semantic fragment the compiler holds several: Idol
-- native lowering, a C-equivalent scalar lowering, simd, an intrinsic, a
-- generated sequence, a library call, a profile-guided version. It costs them
-- and picks. If Idol-native is worse, IT PICKS THE C-EQUIVALENT ONE.
--
--   Idol semantic information   >=  C semantic information
--   candidate set              includes the C-equivalent realization
--   chosen                     = min cost over candidates
--
-- Idol cannot lose, because it keeps the fallback. That is monotonicity rather
-- than optimism, and it is why this is architecture and not a benchmark claim.

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

-- Every rewrite carries these, and a candidate replaces another ONLY when
-- correctness is proven AND cost does not rise for the chosen objective. Where
-- uncertain, KEEP BOTH and dispatch — monotonic optimization rather than
-- heuristic optimism.
rewrite.carries = { "requires", "preserves", "cost", "witness", "descent" }

-- PERFORMANCE IS NOT ONE NUMBER. A realization DOMINATES another when it is no
-- worse on every relevant dimension and strictly better on one — a Pareto
-- frontier, never a magical scalar.
cost.dimensions = {
    "latency", "throughput", "code size", "compile time", "peak memory",
    "allocations", "cache footprint", "branch misses", "energy", "startup",
    "binary size", "tail latency",
}

-- THREE THINGS C DOES THAT IDOL MUST BEAT BY CONSTRUCTION, not by tuning:
--
--   ALIASING             C optimizes poorly without `restrict`. Idol derives
--                        alias facts, so NO USER-WRITTEN EQUIVALENT OF
--                        `restrict` appears in ordinary code.
--   SEPARATE COMPILATION C loses whole-program facts at translation-unit
--                        boundaries. Packages retain graph fragments and
--                        specialize across them — whole-program knowledge
--                        WITHOUT whole-program rebuild cost.
--   ABI FREEZING         C APIs commit to physical representation early. An Idol
--                        interface commits to MEANING; the machine abi is
--                        chosen at realization.
beats = { "aliasing", "separate compilation", "abi freezing" }

-- ═══ §48 · THE RELATION ALGEBRA — one vocabulary, not one per family ════════
--
-- `to` proved the seed: authored edges, enumeration, one-hop composition,
-- witnesses, refused lossy derivation, SER 2.00 at N=4. THE NEXT MISTAKE WOULD
-- BE GROWING SEPARATE SYSTEMS AROUND IT — an algebra for `add`, another for
-- `iter`, another for `from`.
--
-- Fourteen operations, and they are the algebra rather than syntax:
algebra = {
    "derive",   -- obtain an edge from other facts
    "compose",  -- compose compatible edges
    "invert",   -- the logically inverse orientation, never a second store
    "imply",    -- one relationship entails another
    "lift",     -- map a relation across descriptor, container or world structure
    "restrict", -- narrow applicability by world, descriptor or property
    "project",  -- expose one relation through another surface
    "orient",   -- choose the face WITHOUT changing identity
    "meet",     -- combine constraints conservatively
    "join",     -- combine alternatives where lawful
    "block",    -- an explicit NEGATIVE fact that prevents derivation
    "prefer",   -- candidate ordering as DATA, never a resolver hardcode
    "canon",    -- choose the canonical equivalent surface
    "realize",  -- choose the physical implementation under demand and target
}

-- The faces are ORIENTATIONS of one identity, not separate mechanisms:
-- declaration (operation-first) · subject invocation · callable value ·
-- enumeration · anchored/reflection · derivation · inverse · operator · field ·
-- application · ambient-subject.
--
-- CONSEQUENCE, stated so it is not rediscovered: the conversion CLASSES —
-- exact, lossless, view, checked, narrowing, consuming — must not stay
-- conversion-only. They become ORDINARY FACTS on the edge (`loss = none`,
-- `failure = false`, `storage = view`, `consumes = true`), or `add` and `iter`
-- each grow their own class system and gap[084] returns a third time.
classes.become = "ordinary facts on the edge"

-- Algebra breadth is an implementation measurement. It does not change the
-- requirement that new breadth be expressed as facts rather than syntax.


-- ═══ §49 · two additions to §47, merged from a parallel derivation ══════════
--
-- §47 and an independent §45 draft were written simultaneously and BOTH landed,
-- duplicating law.c.floor, law.perf.floor and law.perf.dominance. Duplicate law
-- ids are precisely what law.stack.consistency forbids ("two constitutional
-- facts may not disagree"), so the duplicate block is deleted and only what it
-- carried UNIQUELY survives here. Recorded rather than silently merged: two
-- agents deriving the same law independently is evidence the law was findable,
-- which is a good sign — and duplicate ids are still a defect.

-- The objective is an ordinary target/world fact. NO new surface, no compiler
-- modes: `target = latency` and `target = size` select different frontiers of
-- the same cost.dimensions in §47.
cost.objective = { latency, throughput, size, energy, startup, balanced }

-- WHY a candidate can BEAT the c floor rather than merely match it. Each row is
-- information C discards at the source level and Idol retains as an ordinary
-- fact.
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

-- ═══ §50 · WORLD IS AN OPERAND, NOT THE SUBJECT ════════════════════════════
--
-- A namespace-first operation makes authority look like an inert table. Making
-- the capability the receiver would fix reach while breaking subject
-- orientation.

world = law{
    id    = "law.world.operand"
    kind  = .invariant
    holds = .operand
    binds = {
        "capability is an OPERAND and a CONTEXT, never automatically the subject",
        "the subject is the thing the relation is ABOUT",
        "authority is required to perform the relation, not to be its receiver",
        "where the world is granted in scope it is recoverable and elides",
    }
    canon = { "path:read(fs)", "path:read()" }
    deny  = { "fs:read(path)", "os:remove(path)" }
    why   = "law.owner.physical one level up: the thing that GRANTS a capability is no more the semantic subject than the thing that STORES data. Making capability containers receivers is pseudo-OOP arriving through the capability door."
    fails = "call sites migrated into capability-first orientation"
}

-- OBSERVE-MIN. The deepest reason Idol can beat C, and it is not instruction
-- selection: C freezes representation and ABI at the source, Idol keeps them as
-- degrees of freedom until demand forces the choice.
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

-- ABI is DERIVED from the call graph, not declared. One semantic callable, many
-- physical faces: a caller needing one field gets one register, a caller that
-- only tests failure gets flags. C settles this in the header and spends the
-- optimizer trying to recover it.
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

-- Facts survive REGIONS, not operations. One guard establishes a child world in
-- which many operations consume the proven fact without re-proving it — and the
-- counterpart law is what kills it.
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

-- Physical width follows the proven STATE SPACE, not the declared type. A value
-- with ten reachable states does not require sixty-four bits; a table of 0/1 is
-- one bit per element, which is 8x denser than the c `int8_t` a programmer would
-- have to choose by hand.
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

-- ═══ §51 · LIFTING. What a refinement inherits from its representation. ════
--
-- The rule that makes `str` acquire `slice(byte)`'s vocabulary WITHOUT
-- acquiring the operations that would destroy it. General: it governs every
-- refinement over every representation, and it is what turns a relation store
-- into a projection algebra.

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

-- Element axes are LEVELS, not separate names. `str` enumerates three ways and
-- they disagree — so `len`, `at` and `iter` are each three relations, and
-- law.level.necessity decides when the axis may elide.
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

-- PERSISTENT SEMANTICS, EPHEMERAL REALIZATION. The value is immutable; the
-- machine operation need not be. This is what lets functional source compile to
-- the same instructions as imperative C, and it is the same mechanism that
-- gives snapshots, replay, rollback and stateless handles.
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

-- The acceptance test, written as law so it cannot be satisfied by renaming.
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

-- ═══ §52 · @ IS ANCHORING, AND NOTHING ELSE ════════════════════════════════
--
-- The old reading — "@ is the universal compiler prefix" — is permanently
-- abandoned. What survives is one irreducible job, and the three surviving
-- The anchor forms omit a descriptor identity the semantic environment already
-- knows. Ambient subject application is the distinct leading-colon source face;
-- dot remains statically named projection.
--
--     @        the enclosing descriptor
--     x@rel    the relation anchored at x
--
-- `@comp.foo` is not in that family and dies with the bootstrap authority it
-- carries.

anchor = law{
    id    = "law.at.one"
    kind  = .invariant
    holds = .anchor
    binds = {
        "@ only denotes or establishes a semantic ANCHOR",
        "@ never means compiler magic",
        "prefix directive syntax DOES NOT EXIST",
        "@ supplies the ambient descriptor while leading colon marks ambient subject application",
        "dot supplies only a statically named projection after a written subject",
        "x@rel selects relation rel anchored at semantic value or descriptor x",
    }
    canon = { "origin = () @{0,0}", "point@ordering", "ward@allocation" }
    deny  = "@comp.* and the legacy attributes — bootstrap debt with a deletion gate, never authority"
}

-- `@{ … }` IS NOT A CONSTRUCTION SYNTAX. It is compositional: `@` recovers the
-- enclosing descriptor and `{ … }` is the pack, so it is APPLY-ONE with the
-- subject elided. `@{ x, y }` and `point{ x, y }` are the SAME family; the
-- first recovers `point` from context. This is why @ carries zero special
-- construction semantics and why the anchor form did not become a third
-- mechanism when §43 preserved brace structure and retired brace call.
anchor.apply = "@ + pack = apply(enclosing descriptor)(pack)"

-- ═══ §53 · CAPABILITY BY PRESSURE, NOT BY CHECKLIST ════════════════════════
--
-- How to reach a comprehensive implementation without implementing a
-- theoretical feature list: three workloads, run simultaneously, each forcing a
-- different half of the substrate.

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

-- The claim to make, and the one to refuse. "Faster than C across the board
-- without exception" invites benchmark hacking and cannot be established: no
-- compiler architecture mathematically guarantees one implementation wins every
-- program on every cpu. The defensible construction is already law
-- (law.c.floor, law.perf.floor, law.perf.dominance) and reads:
--
--   the c-equivalent realization is RETAINED whenever lawful · Idol may add
--   STRICTLY STRONGER candidates from additional semantic facts · the public
--   supported corpus demonstrates RELIABLE dominance, adversarial workloads
--   retained
--
-- Get law.perf.dominance right — more semantic knowledge may never shrink the
-- valid realization set — and systematic dominance becomes an engineering
-- problem rather than a wish.
claim.refused = "faster than c across the board without exception"
claim.made    = "more semantic knowledge never reduces the valid realization set"

-- ═══ §54 · THE PACK LADDER — three source forms, one application ═══════════
--
-- Most explicit to most inferred, and the canonicalizer picks the SHORTEST that
-- stays uniquely resolvable:
--
--     point{ x, y }    descriptor stated
--     @{ x, y }        descriptor = the ambient one
--     { x, y }         descriptor = the expected one
--
-- Three source projections of ONE apply relation. Not three constructors.

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
    deny  = "p: point = @{ x, y } — @ restates what the demand already said"
}

atapply = law{
    id    = "law.at.apply"
    kind  = .invariant
    holds = .ambient
    binds = {
        "@{ … } explicitly supplies the AMBIENT descriptor as the application subject",
        "it earns its keep only where demand does not already determine the subject",
    }
    canon = "inside point: `copy = () @{ x, y }` where nothing else names point"
    why   = "narrowing @{} to this makes it USEFUL rather than ubiquitous — and it stays compositional, @ recovering the descriptor and { } being the pack, so it is never a third mechanism."
}

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

-- A REAL semantic decision, recorded as one rather than smuggled in as a
-- function-declaration special case. `b: point = (x, y) …` cannot mean the
-- CALLABLE satisfies `point` — a callable is not a point.
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

-- ═══ §55 · IDENTITY, AUTHORITY ORDER, AND WHAT SELF-HOSTING MUST NOT COST ══

-- Authority order is owned once by `law.owner` in §3. This section adds no
-- second ranking or reconciliation law.

-- The clarification that keeps monoglot from eating the product. Deleting
-- foreign SEMANTIC AUTHORITY is the goal; deleting foreign INTEGRATION would
-- make Idol less useful the day it became self-hosted.
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

-- ═══ §56 · CHAIN ORDER IS SEMANTIC · NO IMPLICIT CALL ══════════════════════

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

-- ═══ §57 · THE DOCS GATE ═══════════════════════════════════════════════════
--
-- Six conditions, each a BUILD FAILURE. Documentation is corpus
-- (law.doc.corpus) and this is what makes that mechanical.
docgate = {
    "a visible semantic token lacks a semantic role",
    "a current lowering claim lacks compiler evidence",
    "source, graph, dnir and assembly correspondence is broken",
    "stale canonical syntax contradicts an owner ruling",
    "generated escape artifacts appear in output",
    "distinguishable semantic roles collapse to identical rendering by accident",
}

-- ═══ §58 · IF THE GRAPH IS A PATH, THE SOURCE IS A PATH ════════════════════

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

-- THE DISAMBIGUATION, and the reason layout may not carry this weight.
--
--     :normalize()        two SIBLING invocations on one ambient subject
--     :validate()
--
--     point               a CHAIN: each step consumes the step above
--         :normalize()
--         :validate()
--
-- Indenting a leading `:` under another leading `:` must NEVER mean "continue
-- the pipeline". A chain ORIGINATES FROM A VALUE.
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

-- Where to look for this defect. Every one of these is a path in the graph and
-- is routinely written as a stack of temporaries.
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

-- ═══ §59 · DNIR IS A PROJECTION, NOT A SECOND LANGUAGE ═════════════════════
--
-- A realization record that reserves unrelated operation-specific fields is a
-- second ontology with its own naming and cost model, not a compact projection.

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

-- THE GUARDRAIL, without which this ruling is destructive. Unify IDENTITY;
-- preserve REALIZATION FACTS. Integer add, float add, vector add, saturating,
-- wrapping and checked add are ONE relation — and dnir must still carry
-- descriptor, representation, overflow law, vector width, rounding and target
-- features, or the backend cannot legalize an instruction.
irguard = "unify identity, preserve realization facts — never one dynamically interpreted relation"

-- The retirement list, and what each becomes.
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

-- Two of those are worth more than the renaming. `mov_arg`/`fp_mov_arg` mean
-- ABI PLACEMENT LEAKED INTO A TYPED IR — removing them enables move coalescing
-- and argument precoloring instead of materializing pointless virtual moves.
-- And `load_local`/`store_local` are SOURCE-STORAGE ARTIFACTS: under ssa a
-- binding is not a memory location until demand proves it needs one — address
-- observed, capture, aliasing, spill, mutation or a debugger.
irwin = "a binding is not a memory location until demand proves it needs one"

-- ═══ §60 · FOUR CLAIMS §59 DID NOT CARRY ═══════════════════════════════════

-- SEMANTIC-ONE: one meaning retains one graph identity and one native word;
-- qualification belongs to facts and physical choice belongs to realization.
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

-- `Op` is a SECOND TAXONOMY. It should become an interned ACCELERATION of a
-- relation identity, never an identity of its own — and the same collapse
-- deletes the redundant dispatch level `switch op { .binop => switch binop }`,
-- because `lt` is a relation, not `cmp` carrying a `lt` tag.
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

-- Most irs freeze physical type on entry. DNIR need not: it can carry a LADDER
-- of realization knowledge and commit only where demand or abi forces it.
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

-- If realized ir is ordinary graph data, the self-hosted compiler transforms it
-- with ordinary Idol — no separate pattern language, which is a whole subsystem
-- SHC does not then have to write.
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

-- Places unify: `field(x)`, `index(i)` and `global(g)` are one PLACE operand to
-- load and store, so alias, bounds, mutability and provenance analysis reason
-- uniformly and the backend still picks its own instruction.
irplace = "load(subject, place) · store(subject, place, value) — place is field, index or global"

-- ═══ §61 · IDENTITY-ONE · COMMIT-MONOTONIC · THE CONVERGENCE GATE ══════════
--
-- §59-60 are FROZEN. No further dnir design pass. What follows is the two
-- invariants they did not carry, and the instrument that measures whether the
-- implementation is converging on them at all.

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

-- The governance gap this closes: the constitution can say law.ir.one while the
-- implementation stays the old dnir indefinitely. These are measured, not
-- asserted — and the LAST line is the guardrail on the whole list.
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

-- The recurring failure this names, in the lowerer's own shape: a semantic fact
-- exists · the lowerer loses it · a local map re-discovers it · another consumer
-- misses the map · another special case is added. **Every deleted reconstruction
-- table is worth more than an opcode rename.**
reconstruct = "establish once · project many times · reconstruct nowhere"

-- ═══ §62 · EVIDENCE MUST BE PRIVATE TO THE RUN ═════════════════════════════
--
-- Mutable evidence shared between concurrent runs has no trustworthy owner.

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

-- ═══ §63 · THE BOUNDARY EVERY RECONSTRUCTION IS DOWNSTREAM OF ══════════════
--
-- Treating the graph as optional metadata after AST lowering makes every
-- downstream reconstruction table predictable. Realization consumes graph
-- facts; it does not decorate a parallel lowering authority afterward.

authority.graph = law{
    id    = "law.graph.authority"
    kind  = .invariant
    holds = .queryable
    binds = {
        "native realization RECEIVES the semantic substrate; it is not optional metadata",
        "the lowerer ASKS — descriptor(result(relation)), descriptor(value), relation(call), effect, world, demand — and gets ONE answer",
        "the graph is the authoritative IDENTITY and PROVENANCE substrate; a fact attached to an identity has one authoritative SOURCE and is queryable at realization",
    }
    keep  = "ONE LOGICAL AUTHORITY, NOT ONE LITERAL STRUCTURE. A descriptor fact may physically live in a graph node, an interned table, a side arena or a query cache — turning the graph into a giant mutable compiler database would trade one architecture problem for a performance one."
    why   = "without this boundary, deleting reconstruction map #1 simply creates map #2. Opcode cleanup before it makes dnir prettier while the architecture stays broken."
    fails = "a lowerer that re-derives from the ast what sema already established"
}

-- COUNT SEMANTIC RECONSTRUCTIONS, NOT DATA STRUCTURES. Two maps may legitimately
-- project two independent dimensions; one function may reconstruct five facts.
-- Two physical maps may project genuinely different scope facts and must not be
-- fused merely to lower a structure count.
reconstructrow = { "fact", "authority", "consumer", "projection or query or RECONSTRUCTION" }
reconstructwarn = "hpls pressure applied to a structure count causes destructive fusion — the metric is the fact, not the table"

-- ═══ §64 · TWO AXES, AND ONE MAY NEVER SUBSTITUTE FOR THE OTHER ════════════
--
-- Foreign-file reduction and vertical authority transfer are independent axes.
-- Either can improve while the other remains unchanged or regresses.

axes = {
    horizontal = { "foreign files", "generated foreign projections", "shell and python dependencies", "duplicated tooling" },
    vertical   = { "graph authoritative", "realize exists", "flow exists", "allocator exists", "encoder consumes the realized graph", "linker sovereign", "evaluator self-hosted" },
}

axes.rule = "NEVER LET HORIZONTAL SOVEREIGNTY SUBSTITUTE FOR VERTICAL DESCENT — they are scored separately or a repository compression reads as an architecture"

-- codegen.zig absorbing responsibility instead of surrendering it is the failure
-- a file count cannot see. The budget is on RESPONSIBILITIES, not lines: a
-- migration may add adapters, but every new semantic capability names its target
-- owner, and nothing lands in codegen merely because that is where native
-- behaviour currently works.
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

-- `unsupported/` is a CAPABILITY FRONTIER, not a graveyard: it means "proven not
-- to pass the required native gate today", never "someone once thought this was
-- unsupported". Promotion is AUTOMATIC the moment a program compiles and agrees.
unsupported.means = "proven not to pass the required gate today; promotion is automatic on agreement"

-- ═══ §65 · SEMANTIC NORMALIZATION — SURFACE IS EVIDENCE, NEVER AUTHORITY ══════
--
-- The pressure test is the conventional shape
-- `if not std.fs.exists(path)`: control words survived as semantic categories,
-- a distribution home masqueraded as meaning, and an existence query exposed
-- a state transition that should usually be atomic. The correction is NOT an
-- immediate keyword purge. Meaning unifies first; spelling earns or loses its
-- place only after ordinary relations can carry the work.

surfacezero = law{
    id    = "law.surface.zero"
    kind  = .invariant
    holds = .erased
    binds = {
        "a grammar face records provenance and resolution evidence, never semantic identity",
        "if while for and or not operators projection indexing application and binding normalize immediately",
        "a bracket face says only that evaluating an expression supplies the key while a dot face supplies statically named identity",
        "dot and bracket faces converge after resolution whenever subject key value place demand and descriptor facts are equivalent",
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
    canon = "step = step + 1 is migratable to step += 1 when the witness proves equivalence"
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
        "a literal string or otherwise statically known key in brackets is audited for named projection or named structured content",
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
        "brackets remain canonical when evaluating their expression genuinely supplies key identity",
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
    "tracked project owned .id source -> 0",
    "new generated native .id source -> 0",
    "current facing idsem duo duon and pass branding outside exact history -> 0",
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

stdzero = law{
    id    = "law.std.zero"
    kind  = .protocol
    holds = .zero
    binds = {
        "canonical semantic namespace roots are zero; std core system platform runtime base idol idsem os fs script process and env never own native meaning",
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

-- Conventional source to semantic reduction, recorded without blessing a
-- replacement spelling. The environment/default vocabulary remains OPEN: the
-- relation family must be derived before a canonical name is assigned.
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

-- ═══ §66 · AUTHORITY, SUBJECT AND STANDARD VOCABULARY CLOSURE ══════════════
--
-- A home may locate a meaning. It can never grant permission to observe or
-- change a world. This is graph law, not a deny list for particular spellings:
-- renaming a home must not alter the verdict.

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
        "when that value is possessed and the relation is subject callable the canonical face is subject first",
        "operation first application of its own first meaningful argument is noncanonical independent of home spelling",
        "the verdict follows relation identity and parameter roles rather than text",
    }
}

worldone = law{
    id    = "law.world.one"
    kind  = .invariant
    holds = .edge
    binds = {
        "a capability sensitive relation declares its required world facts",
        "world requirements participate in checking staging sandboxing caching optimization adaptation authorization and provenance",
        "there is no namespace capability system beside world edges",
    }
}

environmentone = law{
    id    = "law.environment.one"
    kind  = .invariant
    holds = .unsettled
    binds = {
        "environment access has one semantic owner",
        "the key or name is the subject and the environment is required world authority",
        "the outcome preserves absent present empty and present nonempty as distinct semantic cases",
        "foreign symbol names and package paths do not become native relations",
        "no source spelling is admitted until the smallest existing relation family is proved",
    }
    keep = "vocabularyblocked is the only honest state until relation admission settles the canonical expression"
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
        "tracked project owned .id source descends to zero and new .id source fails immediately",
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
        "native compilation recognizes canonical id only and has no duo duon lua or historical syntax mode",
        "tracked project owned duo source native duo suffix recognition lua lexical forms historical directives old callable forms std namespace semantics and implicit boxed fallbacks descend to zero",
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

-- Semantic identity is the spine, not the whole acceptance claim. Every
-- production change is judged across meaning, physical work, human use and
-- sovereignty. A local win may not hide cost or authority on another axis.

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
    }
}
```
