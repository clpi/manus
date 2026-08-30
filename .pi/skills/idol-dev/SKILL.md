---
name: idol-dev
description: Idol language development loop. Use whenever editing .id source, the constitution or spec projections, the compiler, gates, gaps, or claims. Encodes the authority read-order, the monoglot boundary, the closed lexical/grammar law, claim coordination, serialized builds, and the gates/preflight chain. Run orient + doctor first; claim paths before editing; commit explicit pathspecs only.
license: MIT
---

# Idol development loop

You are working on **Idol** (`idol`, `.id`) in the active development repository
reported by `tools/node/dev/repository`; the release repository remains untouched
until explicit release-readiness authorization.

This skill is a tooling projection. It does not add law. When it conflicts with
authority, authority wins and this skill must be repaired.

## 1. Authority — read in this order before editing

1. Read `AGENTS.md` (workflow + mechanical preflight — the file that sent you here)
2. Run `./tools/node/dev/generate-harness` then read `.agents/HARNESS.md`
   (pre-task reduction is mandatory before choosing work or editing)
3. `docs/spec/law.md` (supreme one-page law)
4. `docs/spec/canonical.md` (blind-start constitution)
5. `docs/spec/agent.md` (sole new-agent bootstrap)
6. `docs/spec/constitution.md` (C0, the sole semantic law; structured law
   notation, **not** executable source)
7. `CLAUDE.md` (operative projection of C0)
8. `docs/spec/source.md` (source/home/package/world closure — no native module
   system)
9. `docs/spec/host.md` (host boundary / shell / capability closure — blocking)
10. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md`, the relevant `docs/spec/*.md`
11. `.agents/AGENT_CANONICAL.md`, `.agents/AGENT_COORDINATION.md`
12. The exact `gaps/GAP-*.md` for the frontier you are touching

`docs/spec/grammar.md`, `docs/spec/diagnostics.md`, etc. are **projections**.
They defer to C0. A projection never overrides C0.

**Skill identity:** this skill is `idol-dev`. Do not use retired skill names or
former project branding for current Idol work.

## 2. Orient before every substantive change

```sh
repo="$(git rev-parse --show-toplevel)"
"$repo/tools/node/dev/orient"     # regenerates .agents/HARNESS.md + current state
"$repo/tools/node/dev/doctor"     # pre-agent admission check (rejects stale/broken state)
# claims: inspect tools/node/dev/claim list
"$repo/tools/node/dev/orient"     # includes activep0; read exact gaps/GAP-*.md
```

`orient` reports `activep0` and `frontier`. Until GAP-131 closes, the
The P0 summary is derived — read the exact gap files.

## 3. Claim exact paths before editing

This repository runs **concurrent agent lanes** (Cursor, Codex, Poolside,
Devin, AGY). Never edit a path owned by another live session.

- Read and mutate the shared claim view with `tools/node/dev/claim`. Do not
  invent or use the removed `idol-bench` or `duo_*` transports, and do not add
  claim semantics to an MCP text dispatcher.
- **Do not edit** paths another live session owns. Coordination is the
  authority for safety, not a convenience.
- Reserve a new numbered obligation with `tools/node/dev/gap reserve`; never
  hand-allocate a number or create another ledger.

## 4. Build and test through the locked path

```sh
repo="$(git rev-parse --show-toplevel)"
cd "$repo" && zig build --summary all && zig build unit-test
```

For serialized builds and benchmarks, use the repository lock wrapper, not a
bare concurrent run:

```sh
repo="$(git rev-parse --show-toplevel)"
"$repo/tools/node/dev/idol-lock" -- <command>
```

## 5. Mechanical preflight — the grammar is closed

Run the idiom gate over the **exact working-tree diff** before staging Idol
source:

```sh
repo="$(git rev-parse --show-toplevel)"
gate="$(mktemp "${TMPDIR:-/tmp}/idolgate.XXXXXX")" && trap 'rm -f "$gate"' EXIT
git diff -U0 -- '*.id' > "$gate"
cat "$gate" | "$repo/zig-out/bin/idol" run "$repo/gate/idiom.id"
```

Stage, then let `.githooks/pre-commit` orchestrate the staged direct gates,
including `gate/architecture.id`. Do not suppress, bypass, weaken, or route
around a finding. A formatting rewrite requires a proved semantic equivalence,
not a regex.

A changed canonical `.id` line (or touched historical `.id` line) is rejected
when it introduces any of:

- an identifier with an underscore or uppercase letter;
- `end`, a semicolon, `then`, or `do` instead of offside structure;
- `--` or Lua long comments instead of `#`;
- Lua long strings, historical single-quoted text, `#value` length, or an
  unadmitted backtick;
- a new prefix/compatibility directive, Lua globals/module ops;
- a namespace call when the held value is the receiver;
- constructor ladders, `self`, manual error forwarding, concatenation plumbing;
- a plain-string diagnostic/LSP/REPL response where the structured tuple is
  required;
- legacy callable-result spelling; a new foreign source file.

Closed lexical law: `"text"` is text, `'bytes'` are bytes, `#` starts a
comment, `value:len()` is the length relation, backtick is reserved and never
executes a process. `()` ordinary application/grouping including a computed
key, `{}` structured packs/descriptor application/homes, `.` static named
projection, `:` only its admitted descriptor/subject/home roles.

Each source position has exactly one selected source law. One grammar authority
projects that law into recognition. Worlds supply semantic context and
authority after recognition; they never select grammar.

Layout law: no `req`, `import`, `module`, `use(`, `using(`, `inject`, or `admit`.
Reachability is scope and home projection only.

Host law (`docs/spec/world.md`, `GAP-154`, `GAP-157`): **no `std` anywhere**.
Use `os.args[n]`, `os.env[k]`, `io:read`, `io:write`. Never `std.*`,
`os.getenv`, `environment[...]`, or `io.read`/`io.write`.

## 6. Semantic-first correctness

Do not translate a C/Rust/Python/Lua compiler pattern into Idol syntax. Begin
with the semantic operation. Express it with the smallest existing combination
of relation, level, descriptor, value, demand, world, place, proof,
application, structured value.

Each file owns one concept. Each identifier is one lowercase word. `std` is
migration distribution, not architecture; `std.script` is frozen debt; new
canonical `std.*` is forbidden. Missing admitted vocabulary is
`SEMANTIC-VOCABULARY-BLOCKED`, not permission to invent a namespace.

Canonicality has four states: `canonical`, `migratable`, `vocabularyblocked`,
`invalid`. Do not invent vocabulary to silence a gate.

**SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE / INTERMEDIATE-ZERO
(`law.infer.one`, `law.intermediate.zero`):** no source spelling restates facts
uniquely recoverable from subject, operands, result/descriptor demand, reachable
facts, relation constraints, world/effect requirements, stage, provenance, or
control-flow refinement. Projection, injection, capture, protocol/world
satisfaction are graph facts with normally zero source syntax. Query resolver
before adding `:to(T)`, projection qualifiers, or world plumbing. No canonical
`value:to()` rung. Shortest uniquely resolving source wins (`value` →
`value:to(target)` only when target not inferable). Chain relations directly —
no single-use bridge bindings. No `@{...}` when use determines dependency.

**Seam audit (mandatory before code):** read `docs/spec/harness-projection.md`
§ seam audit — `law.bridge.death`, `law.fallback.zero`, `law.fact.producer.one`,
`law.gate.convergence`, etc. `tools/node/dev/orient` refreshes the derived
`.agents/HARNESS.md` projection.

Before writing a nontrivial Idol expression, answer the 12 preflight questions
in `AGENTS.md` (subject? relation? indirect info? sentinel? value-relation
hidden in control? iteration hidden in repetition? bridge binding? namespace
for world? observable storage? erased realization freedom? static vs computed
key? boolean erasing a case?).

## 7. Concurrent lanes — do not overlap ownership

| Lane | Owner | Scope |
| --- | --- | --- |
| Cursor | coordination / canonicality | claims, node dev admission, gates, release-readiness |
| Codex | semantic graph producer | graph facts, application/relation/subject/pack authority |
| Poolside | realization / machine | demand -> realization -> machine lineage |
| Devin | self-host transfer | one executed production stage into `.id` (owns lexical identities / GAP-145) |
| AGY | adversarial audit | read-heavy falsification; bounded mechanical repair only |

Never restore a shadow authority removed by another owner.

## 8. Evidence and commit discipline

One chain: `run -> completion -> outcome -> evidence`. Transport completion is
not semantic success. A focused pass is not an aggregate pass. A fixture is not
production ownership. A historical benchmark is not current evidence. A zero
needs a positive control.

- Never `git stash`. Never `git reset --hard`. To undo your own commit prefer a
  path-scoped repair or `git reset --soft` only when it cannot disturb a shared
  branch.
- Commit only **explicit owned pathspecs**. Inspect the staged diff and the
  final commit before pushing. Never absorb, revert, format, or hide another
  session's work.
- Release only claims owned by the current session and leave a durable handoff
  (commands, outcomes, blockers, remaining debt).

## 9. Current frontier (read orient for the live value)

The dependency order is:

```
lexical identities (GAP-145, Devin)
-> machine-readable grammar authority (GAP-134)
-> generated grammar roles (GAP-134)
-> immutable token view
-> executed Idol parser recognition
-> binding and scope -> graph and application authority -> demand
-> realization and machine -> seed builds B -> B builds C -> proved B/C closure
```

The repository is at S0: a pinned-Zig seed builds the host compiler; the lexer
boundary is executed; parser and later stages remain host-owned. No production
`idol` compiler binary exists yet.
