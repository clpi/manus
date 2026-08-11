# Idsem operative projection

`docs/spec/constitution.md` is the one semantic-law authority. This file is a
short operative projection for agents and implementers. It does not add law. A
conflict means this projection is wrong and must be repaired.

The constitution is structured law documentation, not executable source or a
pattern library. Canonical implementation remains `.id`; `GAP-145` records the
separate unclosed lexical and grammar projection.

## Identity

The language and project are **Idsem**. Canonical native source uses `.id`.
Historical `Duo`, `Duon`, `.duo`, and the `duo` executable name are migration
provenance or bootstrap aliases where their exact spelling still exists.

`std` is migration distribution, not semantic architecture. `std.script` is
frozen debt. Never add, improve, alias, advertise, or generate a native
`std.*` capability. A possessed value supplies the subject; authority belongs
to worlds; package location supplies neither. Missing admitted vocabulary is
`SEMANTIC-VOCABULARY-BLOCKED`, not permission to invent another namespace.

Semantic identity persists while representation changes. The graph entity is
the semantic identity within one graph incarnation. Names, paths, spans,
source suffixes, pointers, hashes, fingerprints, intern slots, lowering tags,
and machine instructions are provenance, coordinates, acceleration, or
realization. None may select semantic meaning after resolution.

One irreducible native meaning has one lowercase word. Facts carry
qualification. Demand carries need. Realization carries physical choice.

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

Idsem and Lua are distinct lawsets hosted by one compiler. Foreign law and
provenance remain explicit until equivalence is proven; proven equivalents use
the same graph, demand, and realization machinery. Wasm is an imported lawset,
not a permanent second optimizer or virtual-machine ontology.

## Source

Canonical source uses `.id`. New canonical `.duo` is forbidden. New foreign
semantic implementation is forbidden by default; existing Zig, C, Lua, shell,
Python, and historical `.duo` are bootstrap or compatibility debt.

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
into Idsem.

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
-> executed Idsem parser recognition
-> binding and scope
-> graph and application authority
-> demand
-> realization and machine
-> seed builds B
-> B builds C
-> proved B/C closure
```

An `.id` file counts only when it executes in the production path and replaces
an exact host decision. Every transfer states the host owner before, the Idsem
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
the session-start open-P0 summary is not yet a trustworthy complete census.

## Workflow

Start at `AGENTS.md`, then use `.agents/AGENT_CANONICAL.md` as the stable path
router. Read `docs/AGENT_ALIGNMENT.md`, `docs/bootstrap.md`, and the relevant
scope authority. Start the MCP session, inspect live claims and the dirty tree,
claim exact paths, and serialize heavy commands through:

```text
./zig-out/bin/duo run scripts/duo_lock.duo -- <command>
```

`duo` in commands and `duo-*` in MCP names are current physical bootstrap
aliases, not the language identity or permission to create a parallel current
brand.

Never stash, hard-reset, absorb another session's changes, bypass a gate, or
repair combined-tree failures by restoring a shadow authority. Commit only
explicit owned paths.

If authority conflicts, current state cannot be verified, semantic vocabulary
is absent, or another owner has not exposed a required fact: stop that branch,
record the exact conflict or blocker, and do not guess.
