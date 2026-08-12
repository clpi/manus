# Idol operative projection

`docs/spec/constitution.md` is the one semantic-law authority. This file is a
short operative projection for agents and implementers. It does not add law. A
conflict means this projection is wrong and must be repaired.

The constitution is structured law documentation, not executable source or a
pattern library. Canonical implementation remains `.id`; `GAP-145` records the
separate unclosed lexical and grammar projection.

## Identity

**Idol** is the public command and repository identity (`idol`, `.id`).
**Idsem** is the semantic language whose sole law is
`docs/spec/constitution.md`. Branding is not ontology; do not mint artificial
`idsem.*` namespaces for graph, value, or relation.

The language and project ship as Idol. No production `idol` compiler binary
exists yet. Earlier `Idol`, `Duo`, and `Duon` names and historical `.id` /
`.duo` source are migration provenance. Exact `duo` executable, path, symbol,
command, and MCP tool spellings are physical bootstrap aliases until their owned
replacements execute; their presence does not rename Idol.

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
`AGENTS.md` and `scripts/idiomgate.id`. Ingress home checks use
**`ingress(path)`** — ingress is the subject; never `only(ingress)(path)` or
`ingressonly`.

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

Canonical source uses `.id`. New canonical `.id` is forbidden. New foreign
semantic implementation is forbidden by default; existing Zig, C, Lua, shell,
Python, and historical `.id` are bootstrap or compatibility debt.

The current closed lexical and delimiter law is:

```text
"text"       text, including admitted multiline content
'bytes'      bytes; one byte remains a byte-sequence value until demand
# comment    trivia
value:len()  length relation
`            reserved; never implicit process execution

()           ordinary application and grouping
{}           structured packs, descriptor application, and bounded homes
[]           computed or indexed projection
.            statically named projection
:            admitted descriptor, subject, and home faces by grammar role
```

Lua long strings/comments, dash comments, hash length, and historical
single-quoted text are compatibility forms only. Parser grammar decisions use
lexer token identity and generated grammar roles, never token-text spelling
lists. `GAP-145` records the unclosed lexical implementation boundary.

Use the smallest source face that exposes the strongest fact already known.
Square brackets mean a genuinely computed key. Prefer `value.name` to a
literal-string bracket projection and `{ name = value }` to a structured field
whose known name is reconstructed through a string. Do not preserve dot,
bracket, call, or table syntax as semantic operation kinds, and do not let any
source face choose physical representation.

Canonical callable result demand is on the binding:

```id
main: i64 = ()
    0
```

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
pressure only: the added-line check in `scripts/idiomgate.id` is not
authoritative equivalence proof.

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
Equivalent semantics retain at least a C-equivalent lawful realization. FTCFTW
claims bind to the exact exercised path and separately report runtime, compile,
startup, memory, artifact, support footprint, and incremental work. Wasm claims
also report decode/import, instantiate, and end-to-end latency. Generated-C
evidence is not direct-native evidence; direct-native evidence is not Wasm
evidence.

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
Git, live ownership from `duo_dev_claim_files`, open obligations from `gaps/`,
and the current aggregate outcome from a serialized run. `GAP-131` records that
the session-start open-P0 summary is unknown rather than a trustworthy census.
Run `tools/node/dev/orient` for the current observed count, then inspect every
matching `gaps/GAP-*.md` record directly before work. A copied count is
orientation evidence rather than replacement status authority.

## Workflow

Start at `AGENTS.md`, then use `.agents/AGENT_CANONICAL.md` as the stable path
router. Read `docs/AGENT_ALIGNMENT.md`, `docs/bootstrap.md`, and the relevant
scope authority. Start the MCP session, inspect live claims and the dirty tree,
claim exact paths, and serialize heavy commands through:

```text
repo="$(git rev-parse --show-toplevel)"
"$repo/zig-out/bin/duo" run #backend=c "$repo/scripts/duo_lock.id" # <command>
```

`duo` in commands and `duo-*` in MCP names are current physical bootstrap
aliases, not the `idol` command identity or permission to create a parallel
current brand. The physical `.id` spelling of this lock entrypoint is not by
itself semantic migration or self-host authority transfer. The repository
remains at S0 and no compiler B exists.

Never stash, hard-reset, absorb another session's changes, bypass a gate, or
repair combined-tree failures by restoring a shadow authority. Commit only
explicit owned paths.

If authority conflicts, current state cannot be verified, semantic vocabulary
is absent, or another owner has not exposed a required fact: stop that branch,
record the exact conflict or blocker, and do not guess.
