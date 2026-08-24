# Idol operative projection

`docs/spec/law.md` is the SUPREME one-page law and is authoritative over every
document. `docs/spec/constitution.md` (C0) is its structured long-form expansion
and the home of the `law.*` identities. This file is a short operative projection
for agents and implementers. It does not add law. A conflict means this
projection is wrong and must be repaired; where C0 diverges from
`docs/spec/law.md`, C0 is corrected to match `docs/spec/law.md`.

The constitution is structured law documentation, not executable source or a
pattern library. Canonical implementation remains `.id`; `GAP-145` records the
separate unclosed lexical and grammar projection.

## The decomposition (read before writing Idol)

> **A name is a SUBJECT and an EDGE.** The edge is the relation; the subject is
> the value the relation is about. You write `subject:edge(rest)`.

`strlen(s)` is wrong not because it appears on a list but because `len` is the
edge and `s` is the subject, so it is `s:len()`. Every naming rule in this file
is a consequence; learn the decomposition and the consequences stop needing
recall, because the violating name does not occur to you. A rule list cannot do
this — it is checked against a name you have already chosen, so its violations
are by omission.

The full statement and its four consequences are in `AGENTS.md` § "Read first —
the decomposition". **The executable version is one command:**

    cd ../idol-native && ./bin/idol run gate/subject.id   # agreement count IS the exit

It places each canonical form beside the retired one it replaces and requires
them to AGREE on every input, so it is simultaneously the lesson and its proof.
Prefer it to this file wherever the two could disagree, and prefer running it to
quoting it: **numbers live in the runner that checks them, never in prose.**
Every rule this project recorded as an assertion has decayed — a sibling
`AGENTS.md` asserted a gate exited 34 while it exited 42, in two places at once.

## Identity

**Idol** is the language and project identity (`idol`, `.id`). Its supreme law is
`docs/spec/law.md`, whose structured expansion is `docs/spec/constitution.md`
— including §67 Idol algebra closure
(home, subject, world, protocol, witness, injection, union, standard reachability,
shell/run/outcome, binding census, completion metrics). Do not mint artificial
secondary language namespaces for graph, value, or relation. No independent algebra
prompt is authority.

The language and project ship as Idol (`idol`, `.id`, repository `idollang/idol`).
No production `idol` compiler binary exists yet. The priority is the earliest
executed SHC authority frontier: bounded bootstrap bridges — including new Zig
where it is the fastest path to the next transfer — are admitted and preferred
over stalling, each with a known deletion condition (`law.bridge.death`,
`law.bootstrap.velocity`). Foreign is forbidden only as permanent architecture,
semantic authority, or a new foreign semantic kingdom — never as bootstrap
scaffolding.

**No `std` anywhere** in Idol source, agents, gates, or teaching examples.
There is no `std` table, prelude, or namespace. Use layout-projected homes and
worlds (`fs`, `json`, `os`, `io`, …) with subject-first relations. Never
`std.*`. **`proc` and `ir` are not source vocabulary** — DNIR is realization
encoding only. A possessed value supplies the subject; authority belongs
to worlds; package location supplies neither. Missing admitted vocabulary is
`SEMANTIC-VOCABULARY-BLOCKED`, not permission to invent another namespace.

Semantic identity persists while representation changes. The graph entity is
the semantic identity within one graph incarnation. Names, paths, spans,
source suffixes, pointers, hashes, fingerprints, intern slots, lowering tags,
and machine instructions are provenance, coordinates, acceleration, or
realization. None may select semantic meaning after resolution.

One irreducible native meaning has one lowercase word. Facts carry
qualification. Demand carries need. Realization carries physical choice.

### Gate scan boundaries

Migration gates that walk unified diffs or path lists use **curried boundary
symbols**, not mashed compounds or string dispatch:

```id
scan(diff)(body) = ()   # diff is a symbol in the curry slot
total = scan(diff)(files)

ingress(path) = ()       # ingress is the subject/home edge
hit(io) = (code: str)   # hit(prefix)(code) — prefix symbol in curry slot
dot(io) = (code: str)
    hit(io)(code)
```

Never write `scandiff`, `scanline`, `diffhead`, `bareend`, or `scan("diff")`.
Use `audit`, `head`, `bare`, and `scan(diff)(…)` / `scan(path)(…)` per
`AGENTS.md` and `gate/idiom.id`. Ingress home checks use
**`ingress(path)`** — ingress is the subject; never `only(ingress)(path)` or
`ingressonly`.

### Home, world, and protocol algebra

Authoritative law: `docs/spec/constitution.md` §67 Idol algebra closure
(`law.home.context` through `law.algebra.absolute`; adversarial controls in
`law.gate.protocol` and `law.gate.algebra`). Session prompts are not authority.

| Role | Supplies | Does not supply |
|---|---|---|
| **Home** | Context, reachability, ambient descriptor | Ownership, subject, world, capability, method identity |
| **Subject** | Value a relation is about (resolution-owned) | Argument position, namespace receiver, home membership |
| **World** | Authority required for an application | Namespace, import, home grant, protocol witness |
| **Protocol** | Relation/fact constraints (`source: read`) | Trait, adjective protocol, vtable, impl registry |
| **Witness** | Proof of relation constraint satisfaction | World grant, second implementation identity |
| **Injection** | Required + available facts → unique satisfaction | Object construction, hidden priority, service locators |

Prefer `path:open()`, `file:read()`, `text:len()` over `io:open(path)`,
`fs:open(path)`, `string:len(text)`. Algebraic world injection omits a world
only when uniquely satisfiable and witnessed. Protocol satisfaction and world
grant remain separate facts. **Relation is protocol:** `source: read` not
`source: readable`. No `trait`, `impl`, `interface`, `implements`, `concept`,
or adjective protocols (`readable`, `iterable`, `hashable`, …). See
`law.protocol.one`. Concrete knowledge survives relation constraint crossing.
The ONE explicit protocol/requirement boundary is `able(...)` — `able(eq)`,
`able(read)`, `able(to(str))` — meaning the unknown subject must admit the
demanded relation/application shape. `able` is normally INFERRED and spelled only
at a real boundary (open generic contract, implementation unavailable,
higher-order boundary, ambiguity); it mints no trait, dictionary, or vtable and
grants no authority (`docs/spec/law.md` §9, `able` in C0 §6).

## Architecture

The production direction is:

```text
source/import -> graph -> demand -> realization -> machine
```

Source faces are recognition and provenance. They do not create AST, method,
binary-operation, primitive, foreign, or backend semantic kingdoms. Equivalent
faces converge on one relation and one graph identity. Distinct application
occurrences remain distinct identities.

A value is not a place. A binding is not storage. A pack is not an allocated
aggregate. Meaning does not imply materialization. Preserve every lawful cheap
realization until an observable law or demand forces commitment.

DNIR is a compact migration encoding for realization scheduling. It may add
physical facts but may not rename graph meaning or recover meaning from source
text, a callee name, a hash, or an opcode.

Idol and Lua are distinct lawsets hosted by one compiler. Foreign law and
provenance remain explicit until equivalence is proven; proven equivalents use
the same graph, demand, and realization machinery. Wasm is an imported lawset,
not a permanent second optimizer or virtual-machine ontology.

Resolution does not use import, module, package, namespace, require, req, use,
using, inject, admit, include, or any admission syntax. Files and directories
contribute ordinary table/home topology derived from source layout; scope decides
referability; worlds remain authority (`docs/spec/source.md`, `GAP-153`).
Same-directory references need no dependency syntax — the semantic reference is
the dependency edge. Visibility is already a graph fact; change scope facts at
the owner boundary instead of writing admission ceremony in source.

## Host boundary

Idol source sees semantic values — not host OS APIs (`docs/spec/host.md`,
`GAP-154`). Arguments, environment, input, output, error, and cwd are
root/home-projected values supplied by the launcher. Process execution uses
structured command values under a process world — not `popen`, opaque shell
strings, or `os.execute`. Endpoints are embedding-polymorphic; stdin-only is
not language architecture. Shell is an execution home with command projection,
not a mode bit. Build world != program world. `--backend=c` is foreign CLI input
projected to realization facts — not canonical source semantics. Do not rename
`os.args` / `getenv` / `popen` without semantic decomposition. Host APIs belong
only at classified bootstrap ingress/egress with deletion gates.

## Source

Canonical source uses `.id`. New canonical `.id` is admitted — it is the Idol
source extension. New `.duo` / `.duon` / `.idsem` is forbidden. New foreign
SEMANTIC AUTHORITY and new permanent foreign subsystems are forbidden; existing
Zig, C, Lua, shell, and Python are bootstrap or compatibility debt. A new bounded
Zig bootstrap bridge is admitted when it is the fastest path to the next executed
SHC transfer, carries a `law.bridge.death` deletion witness, and gains no
semantic authority (`law.bootstrap.velocity`). Tracked noncanonical `.id`
content remains SOURCE-ZERO debt; the extension itself is not.

The current closed lexical and delimiter law is:

```text
"text"       text, including admitted multiline content
'bytes'      bytes; one byte remains a byte-sequence value until demand
# comment    trivia
value:len()  length relation
`            reserved; never implicit process execution

()           ordinary application and grouping
[]           computed or indexed projection
{}           structured packs, descriptor application, and bounded homes
.            statically named projection
:            admitted descriptor, subject, and home faces by grammar role

Lua long strings/comments, dash comments, hash length, and historical
single-quoted text are compatibility forms only. Parser grammar decisions use
lexer token identity and generated grammar roles, never token-text spelling
lists. `GAP-145` records the unclosed lexical implementation boundary.

Use the smallest source face that exposes the strongest fact already known.
Computed or indexed aggregate access uses projection: `table[key]` and
`row[1]`. Ordinary `value(args)` remains application and never table indexing.
Prefer `value.name` to `value["name"]` and `{ name = value }` to a structured
field whose known name is reconstructed through a string. Do not preserve dot,
bracket, application, or table syntax as semantic operation kinds, and do not
let any source face choose physical representation.

Canonical callable result demand is on the binding:

```id
main: i64 = ()
    0
```

### Relation projection vs curry

`()` is the sole grouping delimiter; resolution assigns its role — punctuation
alone does not define curry (`law.paren.one`, `law.projection.head`).

Three roles after resolution:

1. **Relation projection** — `to(str)`, `read(number)`, `index(key)` attached to
   a relation identity in declaration, selection, or constraint position. No call
   has happened; no intermediate callable is produced.
2. **Ordinary operand application** — `f(x)` when `f` is a callable value.
3. **Genuine curried application** — `f(x)(y)` only when `f(x)` actually yields
   another callable semantic value.

Declaration and invocation stay distinct faces (`call.face`):

```id
to(str) = (value)
    ...

value:to(str)

read(number) = (lx, b)
    ...

lx:read(number)(b)
```

Read `to(str) = (value)` as: relation `to`, projection `{str}`, subject `value`,
operand pack `{}`. Read `value:to(str)` as: subject `value`, relation `to`,
projection `{str}` — not `call to(str)` then apply `value`.

An application carries relation × projection pack × subject × operand pack ×
result pack. Projection operands are qualification/specialization facts; operand
pack members are runtime application values — never conflate them.

Prefer subject → relation projection → operand pack → genuine currying → closure
capture when choosing syntax. Operation-first `to(str)(n)` at a call site is
migratable debt; canonical invocation is `n:to(str)`.

### Inference (SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE)

No source spelling should survive merely to restate a semantic fact the compiler
can already recover uniquely — not only `to`, but relation/method names,
projections, world/protocol witnesses, capture, and projection/injection
composition.

Every source token must contribute semantic information not already uniquely
recoverable from: subject; operands; result demand; descriptor demand;
reachable exact facts; relation constraints; world/effect requirements; stage;
provenance; control-flow refinement.

If omission is compiler-unique but human-ambiguous, retain the irreducible
meaningful relation (`source:read()` may remain; `source()` alone does not).

Write only semantic information the compiler cannot uniquely recover from
authoritative facts (`law.infer.one`). The resolver solves constraints before
demanding explicit syntax; never guess.

**Conversion ladder** (shortest uniquely resolving form wins):

```text
level 0   enabled: bool = value          # graph records to(bool) when unique
level 1   value:to(target)               # ONLY when target is not inferable
migrate   to(target)(value) → value:to(target) → value
```

There is no canonical `value:to()` rung.

**FACT-COMPOSITION-INFER-ONE:** projection, injection, capture, protocol/world
satisfaction are graph facts — normally zero source syntax. Usage derives
dependencies (`stdout:write(env["HOME"])`, not `@{ os.env io.stdout }`).

**Source-density order:** omit redundant binding → relation → projection →
conversion → world/protocol composition → retain minimum for uniqueness + human
meaning.

**INTERMEDIATE-ZERO** (`law.intermediate.zero`): chain relations directly when
identity is preserved; no single-use bridge bindings.

Descriptor demand flows inward (parameters, fields) and backward (results).
Omit `to` when the value already satisfies the demanded descriptor. One direct
bridge relation only (`law.direct.bridge.one`). Physical ABI width is realization,
not semantic `to`.

Do not add `:to(T)` when `T` is already the exact demanded descriptor.
`IMPLEMENTATION-BLOCKED` — not a redundant workaround — when inference is missing.

### Convergence meta-invariants (SHC · multi-agent)

Before substantive work, audit seams per `docs/spec/harness-projection.md` and
§67 convergence closure. Named laws agents must not neglect:

- **BRIDGE-DEATH** (`law.bridge.death`) — no bridge without deletion witness
- **UNKNOWN-ONE** (`law.unknown.one`) — unknown is graph state, not placeholder value
- **OWNERSHIP-ZERO** (`law.ownership.zero`) — alias/lifetime/escape as facts, not Rust
- **PROFILE-EVIDENCE** (`law.profile.evidence`) — profile selects realization, never truth

Also: one fact producer (`law.fact.producer.one`), no silent fallback
(`law.fallback.zero`), bounded inference (`law.infer.contract`), concept/physical
delta budgets (`law.delta.budget`), producer→consumer scheduling
(`law.coordination.fact`), utilities-after-authorities forbidden
(`law.shc.scheduler`).

**Anti-drift (mandatory):** current repo source is not canonical proof
(`law.source.not.proof`); fix semantic classes not specimens (`law.repair.class`);
projection pack is first-class, not curry (`law.projection.pack`); Idol is current
identity only (`law.identity.projection`).

### Projection (PROJECTION-ONE)

One projection algebra (`law.projection.one`) — no separate conversion/protocol/world/shell
subsystems. **FROM-ZERO:** `to` only; `from` normalizes to same edge. **STD-ZERO /
LIB-ZERO:** no canonical `std.*` / `lib.*` traversal. **WORLD-ONE:** worlds grant
authority not intent; prefer `stdin:read()`, `args(1)`, `stdout:write()` over
`os.*` / `io.*` namespace teaching. **SHELL-NOT-WORLD:** shell is law; `run` uses
process world. Spell only facts not uniquely recoverable; ladder ends at implicit
relation + implicit projection when proved.

Identifiers are lowercase single words without underscores or casing-based
distinctions. Subject-applicable work starts from the held subject. Do not port
host save/restore observation, source-category flags, helper predicates,
sentinel states, visitor taxonomies, string dispatch, or bridge temporaries
into Idol.

### Update of place

An admitted compound update is canonical only when a witness proves it
equivalent to `place = place op value`. Normalization keeps the base relation
`op` and the exact place, read, write, update, value, provenance, effect, and
result demand facts; it never creates `addassign`, another compound relation
identity, or a `++` operation. With that witness, the compound form is the
canonical shortest face and the expanded form is migratable.

The witness must prove that the read and write designate the same place, that a
computed place is evaluated exactly once, and that evaluation order, custom
relation law, overflow, failure, aliasing, effects, and result demand are
unchanged. Without that complete proof, neither spelling may be rewritten into
the other merely because their text looks similar.

A graph-aware formatter and canonicality gate for this face depend on the
lexical identities in `GAP-145`, generated grammar roles in `GAP-134`, and the
graph-derived semantic gate in `GAP-124`. Current text ratchets are migration
pressure only: the added-line check in `gate/idiom.id` is not
authoritative equivalence proof, and today its direct execution is blocked by
DNB001 `concat`.

PREDICATE-ZERO applies after subject correction. Do not encode a semantic case,
descriptor, capability, shape, identity, demand, transition, or realization
decision as `has`, `is`, `can`, `exists`, a similar boolean helper, its negation,
or a sentinel comparison. Preserve unknown, absent, not applicable, and
unresolved distinctly. Prefer an admitted fact or transition; missing semantic
vocabulary is `SEMANTIC-VOCABULARY-BLOCKED`.

## Compiler B

The immediate objective is the earliest remaining production authority
boundary, not backend polish. Read the current executed-authority ledger in
`docs/bootstrap.md` and verify it against the current tree before acting.

The dependency order is:

```text
lexical identities
-> machine-readable grammar authority
-> generated grammar roles
-> immutable token view
-> executed Idol parser recognition
-> binding and scope
-> graph and application authority
-> demand
-> realization and machine
-> seed builds B
-> B builds C
-> proved B/C closure
```

An `.id` file counts only when it executes in the production path and replaces
an exact host decision. Every transfer states the host owner before, the Idol
owner after, and the next host-owned boundary. Do not build a bootstrap AST,
identity service, graph, grammar registry, IR, or error model beside the
production owner.

## Project admission

Every material change classifies its effect on:

```text
identity facts demand realization runtime compile startup memory artifact
incremental foreign wasm selfhost agent provenance evidence surface grammar
vocabulary convergence
```

The performance law is **maximum semantic knowledge, minimum physical state**.
FTCFTW is not parity with C, LLVM, Fortran, Wasmtime, or any named compiler — it
is verified **Pareto dominance** over the best known semantically equivalent
implementation, reaching the proven semantic/physical lower bound wherever
dominance is impossible, with optimization space permanently open
(`docs/spec/law.md` §98 `law.ftcftw.dominance`, §99 `law.optimization.open` /
`law.optimization.validated`, §100 `law.cost.closure`, §101
`law.algorithm.realization`). The comparison oracle is always two things at once:
the strongest known implementation AND the semantic/physical lower bound; each
named compiler or library is only one oracle. Every workload/metric has exactly
three outcomes — WIN (strictly better, equivalence + confidence), OPTIMAL (equal
the proven lower bound, no improvement physically available), or LOSS with named
optimization debt (application id, extra physical cost, semantic cause,
unresolved fact, lower bound, workstream). Conflicting dimensions form a Pareto
frontier, never a vanity scalar; no win elsewhere and no geometric mean
compensates for an open loss. There is no closed optimization taxonomy — any
verified semantics-preserving transformation, algorithm, data structure, layout,
ABI, schedule, or machine sequence is admissible from any source (rewrite,
equality saturation, superoptimization, solver, autotuner, profile, hardware
measurement, learned search, agent, competitor mining, or a method not yet
invented), canonical only when observations are verified AND the cost frontier
improves. FTCFTW claims bind to the exact exercised path and separately report
runtime, compile, startup, memory, artifact, support footprint, and incremental
work across the whole lifecycle. Wasm claims also report decode/import,
instantiate, and end-to-end latency. Generated-C evidence is not direct-native
evidence; direct-native evidence is not Wasm evidence.

Realization is not code generation. It is any physically observable strategy that
preserves the program's semantic observations, spanning the whole
machine/OS/hardware/workload stack (§102 `law.physical.open` PHYSICAL-SPACE-OPEN):
representation/encoding/compression, algorithm and data structure, precision,
layout (cache/TLB/page/uop), instruction selection (SIMD/AMX/SVE/crypto),
scheduling (polyhedral/sparse), ABI, OS interface (mmap/sendfile/io_uring/
zero-copy), concurrency, hardware placement (heterogeneous/NUMA/thermal/DVFS/
GPU), specialization (AOT/JIT-hybrid, snapshot, cross-run persistence),
persistence, and distribution — with energy/carbon/cost as first-class Pareto
dimensions and unknown future strategies admitted by the same rule. A realization
must preserve **only** what semantics make observable; everything else is free
(§103 `law.observation.minimum` OBSERVATION-MINIMUM). Every accidental observable
is a permanent optimization barrier, so new source faces and library contracts
minimize incidental observables.

FTCFTW is the whole frontier, not a checklist: the realization set
`R(S,W,T,E,P)` is every physically lawful realization preserving the required
observations (§104 OBSERVATION-ONE, §105 BOUNDARY-ONE, §107
OPTIMIZATION-SPACE-COMPLETE / `law.optimization.space`). A candidate is admitted
iff it preserves demanded observations under the current world, satisfies
authority/effect/resource constraints, is verifiable, and improves the chosen
Pareto frontier. Every individual optimization is an instance discovered inside
`R` on the frontier axes — never a new constitutional mechanism. The square-zero
algebras (§106) — `law.equivalence.observation`, `law.demand.derivative`,
`law.relation.property`, `law.change.delta`, `law.uncertainty.algebra`,
`law.optimizer.economy` — make this follow by construction.

REALIZATION-CONTRACT (§108 `law.realization.contract`) corrects the premise
further: FTCFTW is not compiler optimization but **optimal verified realization
under semantics, information, physics, economics, and uncertainty** over the full
tuple `R(S,O,W,D,K,E,H,P,F,B)`. Execution, algorithm, architecture, storage,
distribution, and *whether any computation occurs at all* are candidate
strategies — lawful nonexecution (cached exact answer, a theorem, materialized
state, a world fact preanswering a query, demand/observer elimination) is the
ultimate realization. Lower bounds are information/communication/I-O/circuit/
work-vs-span/physical-law, not instruction counts (reading 1 GiB to answer a
1-bit question is far from optimal with perfect codegen). Architecture is
realization (erase an unobservable API/serialization/process/RPC boundary;
introduce one where beneficial), and meta-cost is lifecycle-global. The ~24
foundational axes: identity, observation, law, knowledge, uncertainty, demand,
change, equivalence, information, work, communication, representation,
architecture, placement, schedule, boundary, failure, resource, search,
verification, evidence, cost, adaptation, meta-cost — all extensible; no named
ontology may permanently narrow `R`.

Prefer demanded work only, dense graph handles, packed facts and ranges,
arenas, bitsets, generated tables, and incremental dependency reuse. A smaller
compiler encoding that produces worse machine code is a regression.

Optimization converges through three reusable graph engines rather than a
fixed procession of semantic passes:

```text
sparse monotone fact propagation
-> bounded witnessed equivalence retained in the same graph
-> demand/profile/cost-budgeted realization extraction
```

Fact families supply lattices to one dependency worklist; recursive work uses
derived SCC, dominance, loop, and effect-version indexes. Equivalence keeps
lawful alternatives only while their expected reuse and machine value justify
their graph and compile cost. Extraction spends cheap linear effort on cold
regions and may use verified synthesis or integrated allocation and scheduling
only where demand and profile justify it. These engines use specialized packed
columns and adjacency, never a generic property database, separate e-graph,
pass-local semantic registry, or uniform expensive optimization level.

Every important decision retains causal provenance from source through graph,
transformation, realization, instruction, and object range where that boundary
is supported. Tooling consumes graph facts; it does not invent a vocabulary or
reconstruct meaning from formatted text.

## Evidence

Use one chain:

```text
run -> completion -> outcome -> evidence
```

Transport completion is not semantic success. A focused pass is not an
aggregate pass. A fixture is not production ownership. A historical benchmark
is not current evidence. A zero needs a positive control.

Every claim names the exact tree, command, executed path, outcome, and known
red aggregate. Obtain volatile state live: current HEAD and dirty tree from
Git, live ownership from `tools/node/dev/claim list`, open obligations from
`gaps/`, and the current aggregate outcome from a serialized run.
`tools/node/dev/orient` derives `activep0` from exact gap headers after the
`GAP-131` closure; inspect every matching `gaps/GAP-*.md` record directly before
work because the derived count does not replace status authority.

## Workflow

Start at `AGENTS.md`, then use `.agents/AGENT_CANONICAL.md` as the stable path
router. Read `docs/AGENT_ALIGNMENT.md`, `docs/bootstrap.md`, and the relevant
scope authority. Inspect live claims and the dirty tree, claim exact paths with
`tools/node/dev/claim acquire`, and serialize heavy commands through:

```text
repo="$(git rev-parse --show-toplevel)"
"$repo/tools/node/dev/idol-lock" -- <command>
```

The lock and claim commands are bootstrap coordination transport, not semantic
authority or self-host transfer. The repository remains at S0 and no compiler B
exists.

Never stash, hard-reset, absorb another session's changes, bypass a gate, or
repair combined-tree failures by restoring a shadow authority. Commit only
explicit owned paths.

If authority conflicts, current state cannot be verified, semantic vocabulary
is absent, or another owner has not exposed a required fact: stop that branch,
record the exact conflict or blocker, and do not guess.
