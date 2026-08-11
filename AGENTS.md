# Agent Instructions

## Authority

The language law has one home. Read these files before editing Idsem, in this
order:

1. `docs/spec/constitution.md` — C0, the sole semantic authority. It is
   structured law documentation, not executable source or a source template.
2. `CLAUDE.md` — the operative projection of C0.
3. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md`, and the relevant projection
   in `docs/spec/`.
4. `.agents/AGENT_CANONICAL.md` and `.agents/AGENT_COORDINATION.md` — routing,
   ownership, and current obligations.

This file is only the agent workflow and mechanical preflight. It is not a
second language specification. If it conflicts with C0 or `CLAUDE.md`, stop,
report the conflict, and repair this projection. Repository history and the
legacy corpus are migration evidence, never authority.

The language is Idsem. Canonical source files use `.id`; `.duo` is historical
source provenance during migration.

## Monoglot boundary

The destination is an Idsem compiler, standard vocabulary, build, tools, gates,
and documentation projections implemented in Idsem.

Do not add a new Zig, C, Lua, shell, Python, or other foreign subsystem. Existing
foreign implementation is bootstrap debt. A foreign edit is admissible only
when an active gap and evidence show that it is the smallest bridge needed to
unlock its Idsem replacement, or when it strictly removes foreign surface. Keep
the bridge local, preserve native performance, and move the authority into Idsem
in the same vertical slice as soon as the compiler can express it.

Never route a typed or compile-time value through a boxed compatibility value.
The semantic value and its native realization remain distinct; compatibility
front ends do not own Idsem meaning.

## Semantic-first correctness

Never translate a C, Rust, Python, Lua, or conventional compiler pattern into
Idsem syntax. Begin with the semantic operation the program requests. Express it
with the smallest existing combination of relation, level, descriptor, value,
demand, world, place, proof, application, and structured value.

Canonicality is part of correctness. Parsing, type checking, and tests do not
make a weaker conventional representation canonical.

Every canonicality result has one of four states:

- `canonical` — the strongest admitted semantic representation is present.
- `migratable` — equivalence is proved and the canonicalizer may rewrite it.
- `vocabularyblocked` — the missing semantic relation, world, case, or law must
  be added at its authoritative layer before source is written.
- `invalid` — the program contradicts language law.

Do not invent vocabulary to silence a gate. When the result is
`vocabularyblocked`, record the missing semantic requirement and repair the
authoritative semantic model first.

Source faces are not semantic ontology. `if`, `else`, `while`, `for`, `and`,
`or`, `not`, calls, indexing, updates, and operators must erase during early
normalization into durable relation, value, demand, dependency, world, place,
and realization facts. Retain a source face only when its use is irreducible or
removing it would measurably sacrifice clarity or performance.

Each file owns one semantic concept. Each Idsem identifier is one lowercase
semantic word. An underscore or uppercase letter in an Idsem identifier is never
canonical. `std` is migration distribution, not semantic architecture.
`std.script` is frozen debt. New canonical `std.*` APIs and call sites are
forbidden. Do not replace `std` with another universal namespace: possessed
values supply subjects, authority belongs to worlds, and qualification belongs
in facts. If the required relation or world is not admitted, report
`SEMANTIC-VOCABULARY-BLOCKED` instead of adding a helper.

The following shapes are presumptively noncanonical whenever written or
touched:

- namespace activity whose first meaningful value is the subject;
- module traversal standing in for a subject or world;
- an ordinary value used as an absence or failure sentinel;
- a boolean helper or negation that projects an owned semantic fact, case,
  capability, descriptor, shape, demand, transition, or realization decision;
- a single-use boolean binding that exists only to control the next branch;
- an existence query followed by a transition that could establish the desired
  state atomically;
- conditional demand used only for defaulting, projection, case handling, or
  failure routing;
- imperative repetition equivalent to an admitted iteration relation;
- a single-consumer bridge binding with no semantic identity;
- storage, allocation, or materialization not demanded by observation;
- manual failure forwarding;
- a callable result suffix rather than a result demand on the binding;
- syntax-derived identity surviving as semantic authority;
- representation-specific vocabulary where an admitted semantic relation
  exists.
- computed-key syntax when the key identity is already statically known;
- a literal string projected through `[]` when admitted named projection or a
  structured field exposes the same identity directly.

After parsing, describe meaning in semantic terms. Parser terms such as
statement, loop node, binary expression, or call expression are valid only
while discussing recognition. Later boundaries must expose the actual relation,
values, conditional demand, dependencies, carried values, worlds, result
demand, places, proofs, provenance, and realization facts.

## Mechanical preflight

The grammar is closed. New capability does not justify a token, sigil,
directive, keyword, or special AST ontology.

A changed canonical `.id` line, or touched historical `.duo` line, is rejected
when it introduces any of these forms:

- an identifier containing an underscore or uppercase letter;
- `end`, a semicolon, `then`, or `do` instead of offside structure;
- `--` or Lua long comments instead of `#` comments;
- Lua long strings, historical single-quoted text, `#value` length, or an
  unadmitted backtick use;
- a new prefix directive or compatibility directive use;
- Lua globals or module operations;
- a namespace call when the held value is the receiver;
- constructor ladders, `self`, manual error forwarding, or concatenation
  plumbing;
- a plain-string diagnostic, MCP, LSP, or REPL response where the structured
  semantic tuple is required;
- legacy callable-result spelling;
- a new foreign source file.

Canonical lexical meaning is fixed: double quotes are text, single quotes are
bytes, hash starts a comment, length is the subject relation `len`, and backtick
is reserved and never executes a process. Compatibility parsing may retain Lua
comments, long strings, and historical single-quoted text only with explicit
lawset provenance. Until `GAP-145` provides distinct lexer identities and
generated grammar roles, do not migrate delimiters by search/replace or infer a
literal/comment role downstream from token text.

Before staging Idsem, run the repository-native idiom check over the exact
working-tree diff:

    gate="$(mktemp -t duogate)" && trap 'rm -f "$gate"' EXIT
    git diff -U0 -- '*.id' '*.duo' > "$gate"
    DUOGATEDIFF="$gate" duo run scripts/idiomgate.duo

`scripts/semanticgate.duo` reads the staged index, so run it after staging or let
the pre-commit hook run it. The hook repeats both blocking gates. Do not
suppress, bypass, weaken, or route around a finding. Safe formatting rewrites
require proved semantic equivalence. Intent-sensitive findings require a
semantic repair, not a regex rewrite.

Before writing a nontrivial Idsem expression, answer:

1. What value is the semantic subject?
2. What relation is requested?
3. What information is represented indirectly?
4. Is an ordinary value standing in for a semantic case?
5. Is explicit control merely implementing a value relation?
6. Is repetition hiding an admitted iteration relation?
7. Is a binding meaningful or only a bridge?
8. Is a namespace standing in for a world or subject?
9. Is storage or allocation observable?
10. What lawful realization or optimization freedom would this spelling erase?
11. Does every `[]` key genuinely require evaluation, or is a stronger static
    field/projection face already known?
12. Is a boolean or negation erasing a semantic case, unknown state, fact, or
    transition that should be consumed directly?

Prefer the representation that preserves the most semantic information and the
largest lawful realization set with the least source ceremony. Static identity
looks static; computed identity uses `[]`; neither face chooses representation.

## Coordination and commits

Idsem is developed by concurrent agents in one dirty checkout.

1. Read the local router and current bootstrap ledger, then call
   `duo_agent_session_start` and inspect `git status --short --branch`, recent
   commits, live claims, live `gaps/GAP-*.md`, and `git stash list`. Until
   `GAP-131` closes, a session response reporting zero P0 gaps is invalid; scan
   the gap files and fail closed instead.
2. Claim exact paths with `duo_dev_claim_acquire` before editing. Never edit a
   path owned by another live session.
3. Use `duo_agent_gaps_update` for numbered obligations. Do not create a second
   tracker or hand-allocate a gap.
4. Serialize builds and benchmarks through the locked MCP build tools. Until a
   world-backed Idsem coordinator is admitted, do not teach a `std.script`
   wrapper as canonical authority. A concurrent benchmark is not evidence.
5. Commit only explicit owned pathspecs. Inspect the staged diff and the final
   commit before pushing. Never absorb, revert, format, or hide another agent's
   work.
6. Release only claims owned by the current session and leave a durable handoff
   with commands, outcomes, blockers, and remaining debt.

Never use `git stash`. Never use `git reset --hard`. To undo your own commit,
prefer a path-scoped repair or `git reset --soft` only when it cannot disturb a
shared branch. Uncommitted work in the shared tree belongs to its author.

For performance or lowering work, read `docs/performance.md` before editing and
append measured evidence afterward. Run the focused correctness checks first,
then the prescribed locked broad gate. Never hard-code benchmark answers,
inputs, seeds, iteration counts, or literal-specific recognizers. A performance
change must improve a transferable realization, runtime path, data structure,
or algorithm family.
