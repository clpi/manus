# Agent Instructions

## Read first — the decomposition

Everything below this section is a consequence. Learn the decomposition and you
will not need to recall the consequences, because the violating name will not
occur to you.

> **A name is a SUBJECT and an EDGE.** The edge is the relation; the subject is
> the value the relation is about. You write `subject:edge(rest)`.

    strlen(s)      wrong — but NOT because it is on a list
    s:len()        right — `len` is the edge, `s` is the subject

That is the whole rule, and it is generative in a way a rule list can never be.
A list is checked against a name you have ALREADY CHOSEN, so its violations are
by omission: the entry you needed is the one that was not on it. `strlen` has no
underscore, no capital, no trailing digit, no plural — it passes nearly every
lexical gate in this tree. No checker can save you. Knowing where the seam falls
can.

Four consequences worth having in hand before you write anything:

1. **SUBJECT-ONE.** `r(subject, a)` IS `subject:r(a)` — one relation, two source
   faces. Subject-first is preferred because it is the face that COMPOSES:
   `v:scale(2):scale(3)` reads in the order the work happens, and having no
   throwaway intermediate is what makes INTERMEDIATE-ZERO affordable. A
   throwaway binding is where a glued compound gets born.
2. **The edge already converged; the subject did not.** `:len` is universal here
   and `:size` / `:length` do not occur. What survives is thousands of names that
   glue a subject onto the front of an edge. Decompose to `subject:edge`.
3. **An injected world adds REACH and never takes a NAME.** `os` is
   default-injected, so `env[k]` and `arg[i]` are canonical and the anchored
   `os.env[k]` only disambiguates a contested scope. A local, parameter, or
   declared relation spelled `env` MUST WIN — this was violated and silently
   returned a descriptor address.
4. **LAW-16: one irreducible lowercase word, singular.** `arg`, not `args`. The
   subject of `write` is the STREAM (`stdout:write(x)`, never `io.write`); a
   computed aggregate key uses `a[i]`, while `a(i)` remains ordinary
   application; control words are ordinary bindings (`return x` is
   `return(x)`); parentheses the author wrote are KEPT and never relitigated by
   a printer; `void` is INFERRED, never written; `end`, `then`, `elseif` and
   `fun` are Lua vestigials.

**Read the executable version of this section before writing Idol:**

    cd ../idol-native && ./bin/idol run gate/subject.id    # agreement count IS the exit

It puts each canonical form beside the retired one it replaces and requires them
to AGREE on every input, so reading it teaches the decomposition and running it
proves the teaching is current. Its companions — `gate/access.id`,
`gate/control.id`, `gate/word.id`, `gate/shadow.id` — do the same for one ruling
each. `sh gate/all.sh` runs the lot — **in `../idol-native`, which is the tree
this whole paragraph is standing in**: `subject.id`, `access.id`, `control.id`,
`word.id` and `shadow.id` exist only there, and so does the `gate/all.sh` that
registers them (57 commits, first `02776b3`). This repository has its own,
smaller `gate/all.sh` covering the shell gates in `gate/`. gap[212] read this
sentence as naming a file that had never existed; it was reading it against the
wrong repository, which is the same error that produced its headline number.

### Numbers live in exactly one place, and that place runs

Do not copy an expected count, exit code, or census total into prose. Every rule
this project recorded as an ASSERTION has decayed, measured in one day: a sibling
`AGENTS.md` claimed a gate exited 34 in two places while it exited 42;
`gate/all.sh` claimed three counting gates agreed at 33 when they were 25, 35 and
35; a comment asserted two constants "MUST equal" and their drift left ~1,700
lines of JIT unreachable; `@comp.assert` was retired and kept 32 call sites; and
an ABI agreement test was imported by nothing and therefore could never fail a
build; it has since been deleted.
What held instead was everything that RUNS AND COMPARES. So: state the COMMAND,
not the number, and when you must pin a number put it in the runner that checks
it.

### Metaprogramming — accurate, not encouraging

Reach for a **world relation over a directive** wherever one exists; the
directive namespace is retired, not expanded. `@comp.*`, `@meta.*`,
`@compiler.*`, `@emit`, `@pipeline`, every `@c.*`, `@host.*`, `@runtime.*` and
any other compiler/namespace `@` form are not lawful Idol source. The compiler
may retire such spellings internally, but a new source spelling in any of these
namespaces is invalid. Enforcement is `gate/idiom.id` and `gate/dialect.sh`;
get live counts by running them, not from this file.

### Performance — decisions, not hints

Representation is a **DECISION the compiler makes from FACTS**, never a hint you
supply; fixed thresholds that select representation by size have been deleted for
pretending otherwise. **Elimination beats optimisation** — the fastest form of a
recomputed value is the one that never happens, and that has no size bound. And
the largest measured win available is usually a **SOURCE** change: merging one
prefix-plural family cut executed instructions 62.05% because 90.5% of the calls
recomputed an identical product differing only in which component they returned.
A gate proves EQUIVALENCE, which is the permission; the measurement is the
reason; neither substitutes for the other.

## Authority

`docs/spec/law.md` is the **SUPREME one-page law** of Idol. It is authoritative
over every other document and supersedes any stale projection wherever they
diverge; where C0 or any projection below conflicts with `docs/spec/law.md`, that
text is corrected to match `docs/spec/law.md`. Read it first.

The language law otherwise has one structured home. Read these files before
editing Idol (`.id`), in this order:

0. `docs/spec/law.md` — **SUPREME one-page law**: final language + semantic +
 compiler law; authoritative over every document below.
1. `docs/spec/canonical.md` — **blind-start constitution**: machine-enforceable
   lexical/path regex (§25–27) plus semantic-role law (§1–24, §29–33); read
   **before repository code**; do not infer law from Git frequency.
2. `docs/spec/agent.md` — **sole new-agent bootstrap**: readable constitutional
   interpretation (sections I–CXLIX); supersedes partial prompts; **not C0**.
3. `docs/spec/constitution.md` — C0, the structured long-form expansion and
   `law.*` identity owner of the supreme compact law. It is structured law
   documentation, not executable source, not a source template, and not a
   competing authority when it diverges from `docs/spec/law.md`.
   **Idol algebra closure:** §67 (`law.semantic.universe` … `law.algebra.absolute`;
   adversarial controls in `law.gate.protocol`, `law.gate.algebra`,
   `law.gate.infer`, and `law.gate.convergence`). **Convergence closure:**
   `law.bridge.death`, `law.fallback.zero`, `law.fact.producer.one`,
   `law.system.invariant`, `law.unknown.one`, `law.profile.evidence`,
   `law.infer.contract` — see `docs/spec/harness-projection.md` § seam audit,
   § universal anti-drift rules, and § projection (PROJECTION-ONE). **Anti-drift:**
   `law.source.not.proof`, `law.repair.class`, `law.projection.one`,
   `law.from.zero`, `law.std.zero`, `law.lib.zero`, `law.world.one`,
   `law.projection.absolute`, `law.projection.repair`. **INFER-ONE / SOURCE-INFER-ONE / INTERMEDIATE-ZERO:**
   `to` is a graph relation usually omitted from source when demand uniquely resolves
   (`law.infer.one`); **SOURCE-INFER-ONE** applies uniformly — no spelling survives
   merely to restate facts recoverable from subject, operands, result/descriptor
   demand, reachable facts, relation constraints, world/effect requirements, stage,
   provenance, or control-flow refinement. **FACT-COMPOSITION-INFER-ONE:** projection,
   injection, capture, protocol/world satisfaction are graph facts with normally zero
   source syntax. There is no canonical `value:to()` rung. `law.intermediate.zero` —
   chain relations directly; no single-use bridge bindings. No `@{...}` when use
   determines dependency. Census debt with `scripts/census/infer.id`; never bulk-delete.
   `law.infer.one` — write only facts not uniquely recoverable; query resolver
   before adding `:to(T)`. Re-pasted session prompts titled "algebra closure"
   are void; §67 is sole authority. **No `std` anywhere** in new canonical source,
   gates, agents, or teaching examples. The language is **Idol** only.
4. `CLAUDE.md` — short operative projection of C0; routes to `docs/spec/agent.md`.
5. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md`, `docs/spec/source.md`,
   `docs/spec/host.md`, `docs/spec/convergence-contract.md` (blocking execution
   contract), and the relevant projection in `docs/spec/`.
6. `.agents/AGENT_CANONICAL.md` and `.agents/AGENT_COORDINATION.md` — routing,
   ownership, and current obligations.
7. `.agents/ARCHITECTURE_INJECTION.md` — agent orientation on information
   propagation and interoperable graph algebras (not law).
8. `docs/history/optimization-frontier-census.md` — research capability map;
   consult before new optimizer subsystems or IRs.

This file is only the agent workflow and mechanical preflight. It is not a
second language specification. If it conflicts with C0 or `CLAUDE.md`, stop,
report the conflict, and repair this projection. Git history is the sole
historical archive; the active tree is current Idol only (`law.zero.history`).

The language and project identity is **Idol** (`idol`, `.id`, repository `idollang/idol`).
Active development remains in this repository until release-readiness authorization;
see `.agents/RELEASE_READINESS.md`. Cursor routers live in `.cursor/rules/`;
executable canonicality lives under **`gate/`** (home hierarchy — not scattered
`scripts/*gate*` paths).

## Idol harness orientation

Harnesses must **reason in Idol**, not as conventional coding agents with Idol
syntax pasted onto output. This section is workflow routing only; harness
reasoning law lives elsewhere.

| Layer | Path | Role |
|---|---|---|
| Blind-start constitution | `docs/spec/canonical.md` | Lexical regex + semantic-role law; read before repo code |
| Sole new-agent bootstrap | `docs/spec/agent.md` | Readable spec I–CXLIX; supersedes partial prompts |
| Semantic law | `docs/spec/constitution.md` | Sole authority (C0) |
| Harness reasoning | `docs/spec/harness-projection.md` | Pre-task reduction, deletion order, semantic diff, host quarantine, SHC scheduler, FTCFTW rejection, **before writing code audit seams** |
| Live boot payload | `.agents/HARNESS.md` | Revision-bound envelope + template (from `tools/node/dev/generate-harness`) |
| Mechanical preflight | This file (below) | Gates, claims, path law, host firewall |

Before choosing work or editing:

1. Read `docs/spec/harness-projection.md` § pre-task reduction, § work selection,
   and § **before writing code — audit seams**.
2. Read `.agents/HARNESS.md` for current SHC frontier and live envelope.
3. Run `tools/node/dev/generate-harness` (or `orient`, which regenerates it) and
   `tools/node/dev/doctor`.

Every nontrivial change requires a **semantic diff** (`docs/spec/harness-projection.md`
§ semantic diff) in the completion report. Lexical gate pass on changed lines
is migration pressure, not semantic convergence proof.

Do not begin from “remove std,” “fix gate,” or “implement process support.”
Begin from: what fact is missing, what identity disappears, what should cease to
exist, and whether executed authority, reconstruction debt, or FTCFTW evidence
improves.

If 1–9 in pre-task reduction lack answers, deprioritize. If the task only
renames an abstraction (`std.*` → `process.*`, `req` → local binding), reject.

## Monoglot boundary

The destination is an Idol compiler, standard vocabulary, build, tools, gates,
and documentation projections implemented in Idol.

**No `std` anywhere** in new canonical source — not a namespace, table, prelude,
or migration alias. Vocabulary reaches through layout/home/world projection
(`path:read()`, `json:encode`, `env[k]`, `args[i]`; `os.env[k]` only when scope
is contested). The `lib/std/` tree is
filesystem bootstrap provenance until renamed (GAP-157); it is not authority.

Every canonicality result has one of four states: `canonical`, `migratable`,
`vocabularyblocked`, `invalid`. Do not invent vocabulary to silence a gate.

New canonical `.id` is admitted — it is the Idol source extension. The priority
is the earliest executed SHC authority frontier (`law.bootstrap.velocity`): a
bounded foreign bridge — including new Zig — is admitted and preferred over
stalling when it is the fastest path to the next executed transfer and carries a
`law.bridge.death` deletion witness (host owner before, Idol owner after, next
host boundary). What stays forbidden is a new *permanent* foreign subsystem,
foreign SEMANTIC AUTHORITY, and a foreign semantic kingdom beside the graph.
Keep the bridge local, preserve native performance, regenerate (never hand-fork)
generated artifacts, and move the authority into Idol as soon as the compiler can
express it. Do not block on a monoglot ideal the native compiler cannot yet
express — record `IMPLEMENTATION-BLOCKED` and add the smallest unblocking bridge
rather than idling.

Never route a typed or compile-time value through a boxed compatibility value.
The semantic value and its native realization remain distinct; compatibility
front ends do not own Idol meaning.

Presumptively noncanonical shapes whenever written or touched:

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
- import, admission, or loader syntax (`req`, `require`, `import`, `module`,
  `namespace`, `include`, `use(`, `inject`, `admit`, privileged `*bind`) —
  reachability is scope and home projection only;
- a literal key applied through `table[key]` when admitted named projection or
  a structured field exposes the same identity directly;
- an adjective protocol or trait kingdom (`readable`, `writable`, `iterable`,
  `source: readable`, `trait`, `impl`, `@implements`, `concept`) — relation
  constraints only (`source: read`; `law.protocol.one`);
- a mashed gate-scan compound (`scandiff`, `scanline`, `diffhead`, `bareend`, or
  any `scan+*` binding name);
- a string where a boundary symbol belongs in a curried scan (`scan("diff")` —
  write `scan(diff)(body)`; `diff` and `path` are symbols in the curry slot, not
  string literals);
- operation-first conversion or relation projection at a call site (`to(str)(value)`,
  `to(i64)(value)`) — declare `to(str) = (value)` and invoke `value:to(str)`;
  parentheses after a relation name in a declaration head project the relation,
  they do not curry it (`law.paren.one`, `law.projection.head`);
- redundant explicit conversion when demand already fixes the target
  (`x: str = value:to(str)`, `f(value:to(i64))` when parameter demands `i64`) —
  prefer minimal source under `law.infer.one`; graph must prove redundancy before
  removal (`law.gate.infer`).

Explicit anti-drift law classes:

- **BOOLEAN-MIRROR-ZERO** (`law.boolean.mirror.zero`) — no boolean flag that
  restates a direct graph fact (`callable`, `possessed`, `operation`, `typed`,
  `authorized`, `captured`, `projected`, `resolved`, `imported`, `native`,
  `static`). If the graph can express it structurally, the boolean must disappear.
- **CATALOG-ZERO** (`law.catalog.zero`) — no table whose purpose is to enumerate
  relations, descriptors, worlds, formats, handlers, operations, or capabilities.
  Enumerations belong to graph identities and facts, not a second authority row.
- **MAGIC-CODE-ZERO** (`law.magic.code.zero`) — no numeric/status/opcode/ordinal
  code that selects semantic meaning on the consumer side. Rejection ids,
  token roles, and semantic classes must cross the seam as stable identities or
  graph facts, not as integers reconstructed by host switches.
- **GENERIC-ACTION-ZERO** (`law.generic.action.zero`) — no generic orchestration
  verb (`run`, `execute`, `process`, `apply`, `perform`, `handle`) as a project-owned
  helper unless it names an actual semantic subject/relation. Root routines may not
  be named merely to mean “start this tool.”
- **FOUNDATIONAL-WORD-COLLISION-ZERO** (`law.foundational.collision.zero`) — do not
  reuse foundational semantic words (`apply`, `project`, `realize`, `resolve`, `bind`,
  `demand`, `witness`, `relation`, `subject`, `world`, `shape`, `descriptor`) for
  local helpers that do not embody that exact canonical concept.
- **EVIDENCE-SUBJECT-ONE** (`law.evidence.subject.one`) — every evidence artifact
  must carry the exact measured subject revision separately from the evidence
  revision. Metrics reported “at HEAD” are invalid unless the measured subject
  equals the checkout HEAD.
- **DIFFERENTIAL-ORACLE-BOUNDED** (`law.oracle.bounded`) — a host differential
  oracle is valid only for the legacy-equivalent subset and must carry a concrete
  deletion condition. When Idol law intentionally diverges, the oracle must not
  veto the new behavior.

After parsing, describe meaning in semantic terms. Parser terms such as
statement, loop node, binary expression, or call expression are valid only
while discussing recognition. Later boundaries must expose the actual relation,
values, conditional demand, dependencies, carried values, worlds, result
demand, places, proofs, provenance, and realization facts.

## Mechanical preflight

The grammar is closed. New capability does not justify a token, sigil,
directive, keyword, or special AST ontology.

A changed canonical `.id` line, or touched historical `.id` line, is
noncanonical when it introduces any of these forms. The executable-enforcement
delta is stated below:

- an identifier containing an underscore or uppercase letter;
- `end`, a semicolon, `then`, or `do` instead of offside structure;
- `--` or Lua long comments instead of `#` comments — `gate/idiom.id` and `gate/path.id`
- Lua long strings, historical single-quoted text, `#value` length, or an
  unadmitted backtick use;
- a new prefix directive or compatibility directive use;
- Lua globals or module operations;
- a namespace call when the held value is the receiver;
- namespace-first module calls: `string.match`, `string.sub`, `string.find`,
  `std.string.*`, `table.*`, `math.*`, or any `std.*` module dispatch — use
  subject-first edges (`text:match(pattern)`, `text:sub(i,j)`, `xs:push(v)`);
- constructor ladders, `self`, manual error forwarding, or concatenation
  plumbing;
- a plain-string diagnostic, MCP, LSP, or REPL response where the structured
  semantic tuple is required;
- legacy callable-result spelling;
- expanded same-place updates: `hits = hits + 1`, `n = n - 1`, `x = x * y`,
  `y = y / z`, or any `place = place op value` — use compound update
  (`hits += 1`, `n -= 1`, `x *= y`, `y /= z`);
- adjective protocols or trait kingdom (`readable`, `writable`, `iterable`,
  `source: readable`, `trait`, `impl`, `@implements`, `concept`) — relation
  constraints only (`source: read`; `law.protocol.one`);
- `@` other than its world faces — `@` IS THE CURRENT-WORLD ACCESSOR: bare `@`
  (the current world), `@member` world access (`@target`, `@env`), `@member = v`
  ambient mutation (place), postfix `thing@world` / `thing@` world qualification,
  `@{ k = v }` injection (derive a closed world), `thing@{ k = v }` interjection
  (evaluate a subtree under an injected world), `@(eval)`; never `@.member` or
  `@:member` (INVALID — `@` already accesses, so `@.` and `@:` steal `.`/`:`),
  never `thing@relation` (relation orientation is the colon face `thing:relation`),
  and never a compiler/host directive `@comp`, `@c`, `@host`, `@runtime`,
  `@emit`, `@asm`, or any other `@` namespace — `gate/idiom.id` `sigil` /
  `law.anchor.one` (`docs/spec/law.md` §4 + World+projection add-on; C0
  `law.projection.algebra`, `law.at.one`);
- a new foreign source file that is a permanent subsystem, a foreign semantic
  authority, or lacks a `law.bridge.death` deletion witness — a bounded Zig
  bootstrap bridge that advances the executed SHC frontier and carries that
  witness is admitted (`law.bootstrap.velocity`).

Canonical lexical meaning is fixed: double quotes are text, single quotes are
bytes, hash starts a comment, length is the subject relation `len`, and backtick
is reserved and never executes a process. Compatibility parsing may retain Lua
comments, long strings, and historical single-quoted text only with explicit
lawset provenance. Until `GAP-145` provides distinct lexer identities and
generated grammar roles, do not migrate delimiters by search/replace or infer a
literal/comment role downstream from token text.

## Update face

Canonical Idol prefers `place op= value` only when a witnessed equivalence
proves it preserves the expanded update's observations. Normalization keeps the
base relation together with the exact place and update facts; it does not mint
`addassign`, another compound relation, or a `++` ontology. An admitted compound
update evaluates a computed place once, so collapsing repeated subject, key, or
index evaluation requires an explicit equivalence witness.

The law expressed by `gate/idiom.id` is migration guidance, not semantic proof
and not permission to rewrite. Its
`law.update.face` finding identifies only a candidate expanded face. Existing
compound forms, distinct left/right subjects, declarations, and unwitnessed
computed places remain negative controls. Semantic classification, a
graph-owned canonicalizer, and formatting for this equivalence remain blocked
by `GAP-145`, `GAP-134`, and `GAP-124`.

Today direct execution over a non-empty diff refuses at DNB001 `concat`.
Until that implementation gap closes, use a static added-line scan only as
explicitly nonsemantic migration pressure; do not report it as an executable
Idol gate or a semantic verdict. The intended serialized command, once direct
execution is repaired, is:

    repo="$(git rev-parse --show-toplevel)"
 gate="$(mktemp -t idolgate)" && trap 'rm -f "$gate"' EXIT
 git diff -U0 -- '*.id' '*.id' > "$gate"
 cat "$gate" | "$repo/zig-out/bin/idol" run "$repo/gate/idiom.id"

`gate/architecture.id` reads the staged index, so run it after staging or let
the pre-commit hook run it. The hook also runs `gate/path.id` over every
staged added or renamed path and over every added line in project teaching and
implementation surfaces. Do not suppress, bypass, weaken, or route around a
finding. Safe formatting rewrites require proved semantic equivalence.
Intent-sensitive findings require a semantic repair, not a regex rewrite.

Path and home names obey the same LAW-ONE as source identifiers (`law.path.name`).
Concat/mashed file and directory names are never allowed — each semantic unit belongs
in its own home segment through hierarchy (`compiler/graph.id`), not a compound stem
(`semantic_graph.id`, `readline.id`, `nativebackend/`). `gate/path.id` enforces
path separator and taxonomy law. `gate/idiom.id` states the corresponding
added-line law, but its direct execution is currently blocked as described
above. Together their law rejects
compounds in diff path headers, directory components, filename stems, and added-line
tokens, and namespace-first calls (`string.*`, `std.string.*`, `table.*`, `math.*`,
`std.*`) on every staged added line in project surfaces.
Do not mash compound names, strip punctuation, or invent loader syntax. Native
resolution uses source layout, scope, and worlds (`docs/spec/source.md`,
`GAP-153`). No import or admission syntax in new canonical source — change
scope facts at the owner boundary instead.

## Host boundary (blocking)

Read `docs/spec/host.md` before any work touching arguments, environment,
process, pipe, shell, transport, endpoints, cwd, PATH, or backend selection.

Idol source does not call host OS APIs as semantics. **`environment` is not a
thing** — use `os.env` table under `os` world. **`args`** is `os.args[n]`, not
`os.args()`. **I/O** uses `io:read` / `io:write`, not `io.read` / `io.write`.
Do not add `std.*`, `proc.*`, or `ir.*` to new source.

Before writing such code, state: semantic subject, canonical relation, world
requirement, home/root projection, foreign ingress/egress boundary, demand. If
blocked: `SEMANTIC-VOCABULARY-BLOCKED` or `IMPLEMENTATION-BLOCKED` — do not reach
for host APIs.

Run `./tools/node/dev/hostcensus` when auditing host debt. Never add `std.`,
`proc.`, `ir.`, or similar namespace dispatch to new canonical source.
Added-line host-pattern law: `gate/idiom.id` and `gate/host.id` (temporary until
graph enforcement, `GAP-154`); `gate/idiom.id` has the direct-run blocker stated
above.

## Gate scan boundaries (LAW-ONE + curry)

Migration gates traverse **added** unified-diff lines only. Never mint a mashed
compound for this job.

**Definition form is `name(...) = (...)`** — never `name(...): type = ()` on
curried gate bindings.

| Forbidden | Canonical |
|---|---|
| `scandiff`, `scanline`, `diffhead`, `bareend` | one word per binding |
| `scan("diff")(body)`, `scan("path")(body)` | `scan(diff)(body)`, `scan(path)(body)` |
| `ingressonly`, `only(ingress)(path)` | `ingress(path)` — ingress is the subject |
| `worlddot`, `qualworlddot`, `dot(code, "io")`, `qual(code, "std", "io")` | `dot(io)(code)`, `dot(std)(io, code)` |
| `viewedges` | `view(edges) = ()` pipe — separate from world `edges` |
| `viewrouter`, `fsrouter`, `corerouter` | `router(view)(view(home))` / `router(proof)(proof(home))` |
| `viewproof` | `view = router(proof)(proof("view"))` — slot name matches home key |
| `zig-out/bin/duo` | `zig-out/bin/idol` — public command identity is `idol` |
| `ingestbody`, `graphbody`, `bitbody`, `censusbody`, `zerostdbody`, `verdictbody` | `router(semantic)(semantic(home))` — never home+body mash |
| `recordbody`, `worldbody`, `removebody`, `mkdirbody` | `router(proof)(proof(home))` — never home+body mash |
| `fs_exists`, `fsexists`, `fs_read`, `fs_write`, `fswrite`, `fs_cp`, `fs_rm`, `fs_tmpdir` | `path:exists()`, `path:read()`, `src:copy(dst)`, `path:remove()` |
| `relationid`, `readid`, `read = 10` | one relation identity + qualifying facts — never mashed `*id` or parallel integer slots |
| `len: bool = (path`, `audit: bool = (path`, `hit: bool = (path`, `from(path) = (pattern`, `len(path, `, `audit(path, `, `hit(path, ` | boundary curry — `len(path)(min)`, `audit(path)(pattern)`, `hit(path)(pattern)` |
| `if not `, ` and not `, ` or not `, `(not ` | prefix `!` — `if !expr`, `and !expr`, `(!expr)` |
| `):match(`, `):len(`, `:read():` | one relation per line — never single-line method chains |
| `text = path:read()` | `path:read()` then `:match(pattern)` on next line — no transitive read binding |

**Path file audit uses boundary-curried relation edges and multiline subject-first chains.**
The path is the first curry boundary; threshold or pattern is the second. Each relation
owns its line; tail implicit return continues on the next line with a leading `:`:

```id
len(path) = (min: i64)
    path:read()
        :len() >= min

audit(path) = (pattern: str)
    path:read()
        :match(pattern)

hit(path) = (pattern: str)
    path:read()
        :match(pattern)

if !len(proof("resident"))(32)
    code = 1
if code == 0 and !audit(proof("resident"))("path:read%(")
    code = 2
```

Prefix `!` is the canonical negation face — never `not expr`, `if not`, `and not`, or `(not`.

**Boundary symbols are not strings.** `diff`, `io`, and `semantic` are symbols in the
curry slot — the same shape as `to(micron)(inch)` in relation law. The first
application selects the boundary; the second carries the body:

```id
scan(diff)(body) = ()
    # traverse unified diff; audit each added line

total = scan(diff)(files)

ingress(path) = ()
    path:len() >= 17 and path:sub(1, 17) == "scripts/ingress/"

hit(io) = (code: str)
    peek("io.", code)

dot(io) = (code: str)
    hit(io)(code)

view(edges) = ()
    "|bit/f64|f64/bit|bit/f32|f32/bit|i64/bit|"

bit = "scripts/proof/bit.id"
```

Line-level work inside a diff boundary uses **`audit(path, no, line)`** — never
`scanline`. Path-header recognition uses **`head(line)`** — never `diffhead`.
Bare-line `end` detection uses **`bare(code)`** — never `bareend`.
Ingress home membership uses **`ingress(path)`** — never `ingressonly` or
`only(ingress)(path)`; ingress is the subject.

Executable law sources: `gate/idiom.id`, `gate/host.id`,
`gate/path.id` (`scan(path)(body)` for path lists, `scan(diff)(body)` for
namediffs). Gate transport is stdin only — `stdin:read()` via pipe or shell
redirect (`< file`); no `os.args`, no bash wrappers, no `gatepath`, no `gate.sh`.
The `gate/idiom.id` direct-run blocker above remains the law/today delta. Run
other gates with **`idol run gate/<name>.id`** — never **`--backend=c`**. The
explicit graph-backed C realizer emits orthogonal source; it is not gate
admission, a direct-native workaround, or a proof path.
Commit admission runs through `.githooks/pre-commit` (shell orchestrator → direct-backend
`idol run gate/*`). Never `--backend=c` on gates.

Gate home (`gate/`). **`ls gate/` is authoritative; this table is a projection**
— it listed ten files while thirteen were present, so regenerate rather than
trust it. Three currently unlisted, measured: `graph.id` (temporary migration
firewall for graph identity / edge closure on added lines, GAP-124), `probe.id`
(the body of `gate.idiom` — no `main`, no wrapper), and `bytetest.id`, which is
itself a LAW-ONE path violation: `byte` + `test` glued into one stem, in the very
home that enforces the rule. `preflight.id` is DEPRECATED in its own header —
commit admission is `.githooks/pre-commit`.

| Gate | Role |
|---|---|
| `preflight.id` | DEPRECATED; admission is `.githooks/pre-commit` shell → direct `idol run gate/*` |
| `idiom.id` | Added-line lexical/canonical migration firewall |
| `admission.id` | Semantic-admission firewall on added lines |
| `host.id` | Host API debt on staged additions |
| `architecture.id` | Staged-index migration censuses (C0 §65 ratchet) |
| `path.id` | LAW-ONE path/name firewall |
| `census.id` | Path stem census |
| `catalog.id` | Admitted relation projection (tables; admission inlines) |
| `bootstrap.id` | Shared capture helpers for gate scripts |
| `build.id` | Zig build-step idiom wrapper (diff → `gate/idiom.id`) |

## Path and file names (law.path.name)

Project-controlled path components obey the same LAW-ONE as identifiers:

- **Forbidden:** `snake_case`, `camelCase`, `kebab-case`, mashed stems
  (`semantic_graph.id`, `readline.id`, `nativebackend.zig`)
- **Required:** one lowercase word per semantic home component, decomposed
  through hierarchy (`compiler/graph.id`, `read/line.id`, `native/backend.zig`)

Never use underscore separators in file or directory names. The stem projects
the semantic table or home name; qualification belongs in nested homes and
worlds, not punctuation in a single component.

Enforced on staged paths and added lines by `gate/path.id` (`sep`, `mash`,
`walk`, `verdict`). Positive control rejects `semantic_graph.id` and accepts
`compiler/graph.id`.

Before creating a project-owned path, classify semantic owner, projected home,
canonical one-word name, origin, and role. If decomposition is unclear, record
`PATH-SEMANTICS-BLOCKED` rather than minting a compound filename.

Callable bindings use result demand on the binder: `name: descriptor = (args) body`.
Never write suffix or header callable faces: `name = (): type`, `name = (args): type`,
or `name(): type` — migratable debt ratcheted by `gate/architecture.id` staged
census (callable.result.suffix), `examples/demand/result.id`, and `scripts/canon.id`.
Do not reintroduce a `suffix()` substring detector or `if !suffix(` / `if not suffix(` gate controls.
Length is subject-first: `value:len()` — never `size(x)`, `len(x)`, `rawlen(x)`,
`string.len(x)`, or `std.string.len(x)` in new canonical source.
Legacy suffix result annotations (`name(): descriptor`) are migratable debt only.

Before writing a nontrivial Idol expression, answer:

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
11. Does every applied key genuinely require evaluation, or is a stronger static
    field/projection face already known?
12. Is a boolean or negation erasing a semantic case, unknown state, fact, or
    transition that should be consumed directly?

Prefer the representation that preserves the most semantic information and the
largest lawful realization set with the least source ceremony. Static identity
uses `value.member`; computed aggregate projection uses `value[key]`; ordinary
application uses `value(args)`. No face chooses representation.

## Concurrent lanes

Five disjoint write lanes; do not overlap semantic ownership:

| Lane | Owner | Scope |
|---|---|---|
| Cursor | coordination / canonicality | claims, node dev admission, gates, release-readiness ledger |
| Codex | semantic graph producer | graph facts, application/relation/subject/pack authority |
| Poolside | realization / machine | demand → realization → machine lineage |
| Devin | self-host transfer | one executed production stage into `.id` |
| AGY | adversarial audit | read-heavy falsification; bounded mechanical repair only |

Read live claims before editing. Never restore shadow authorities removed by
another owner.

1. Read the local router and `docs/bootstrap.md`, then inspect
   `git status --short --branch`, recent commits, `tools/node/dev/claim list`, every
   current `gaps/GAP-*.md`, and `git stash list`. `orient` derives a nonzero P0
   census from those exact files; the files remain the routing evidence.
2. Claim exact paths through `tools/node/dev/claim acquire` before editing.
   Never edit a path owned by another live session.
3. Record numbered obligations in the existing `gaps/GAP-*.md` authority. Use
   `tools/node/dev/gap reserve`; do not create a second tracker or hand-allocate
   a number.
4. Serialize builds and benchmarks through `tools/node/dev/idol-lock`. Until a
   world-backed Idol coordinator is admitted, do not teach a `std.script` or
   MCP text wrapper as canonical authority. A concurrent benchmark is not
   evidence.
5. Commit only explicit owned pathspecs. Inspect the staged diff and the final
   commit before pushing. Never absorb, revert, format, or hide another agent's
   work. Before committing, answer the architectural review question in
   `docs/AGENT_ALIGNMENT.md` § Architectural mandate and run
   `sh gate/architecture-negative.sh` when touching sema, graph, or DNIR.
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

## Learned User Preferences

- Do not migrate development to `idollang/idol`; use the development repository reported by `tools/node/dev/repository` until explicit release-readiness authorization.
- Only create git commits when explicitly requested by the user.
- Do not implement or hand-edit lexical or tokenizer logic outside the Idol lexer source path (`lib/compiler/lexer.id`, `lib/compiler/token.id`).
- INFER-ONE / SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE / INTERMEDIATE-ZERO: no source spelling restates uniquely recoverable facts (subject, operands, demand, constraints, world/effect, stage, provenance, control-flow); projection/injection/capture/protocol/world satisfaction normally have zero source syntax; no canonical `value:to()` rung; no single-use bridge bindings; `@` only for anchors — never `@{...}` world/import/dependency lists; `IMPLEMENTATION-BLOCKED` not workaround canonization. Relation projection is not curry — declare `to(str) = (value)`, invoke `value:to(str)`; operation-first `to(str)(value)` is migratable debt. projection/injection/interjection are three uses of ordinary world/table semantics (select a fact / derive a world with added facts / evaluate a subtree under it), not new subsystems — no inject, scope, context, provider, registry, or dependency framework.
- Do not defer, stop, or idle-block mid-task; "you are never blocked" — drive durable end-to-end fixes toward SHC/FTCFTW and either resolve or record `IMPLEMENTATION-BLOCKED` rather than stalling. Zig is admissible as a bootstrap bridge where genuinely needed to reach SHC fastest; aggressively reconcile and delete ALL stale rules, prose, legacy code, and non-canonical edge/binding usage across the whole repo rather than preserving it. FTCFTW is an open-ended, proof-driven Pareto-dominance contract against the best known implementation plus the semantic/physical lower bound (not a scalar score, not merely "faster than C") — strictly improve every cost dimension where physically possible, equal the proven lower bound otherwise, and never lose without naming the exact tradeoff or unresolved fact. Realization is a semantic-to-physical optimizer over the whole machine/OS/hardware/workload stack, not code generation (`law.physical.open` PHYSICAL-SPACE-OPEN: representation/encoding, algorithm/data structure, precision, layout, instruction selection, scheduling, ABI, OS interface/syscall, concurrency, hardware placement, specialization, persistence, distribution, energy — future strategies admitted by the same rule); preserve ONLY what semantics make observable, since every accidental observable is a permanent optimization barrier (`law.observation.minimum` OBSERVATION-MINIMUM). FTCFTW is the whole frontier `R(S,W,T,E,P)` — every physically lawful realization preserving the required observations — not a checklist (`law.optimization.space` OPTIMIZATION-SPACE-COMPLETE, `docs/spec/law.md` §107); a candidate is admitted iff it preserves demanded observations under the current world, satisfies authority/effect/resource constraints, is verifiable, and improves the chosen Pareto frontier; every individual optimization is an instance discovered inside `R` on the frontier axes — never a new constitutional mechanism. Square-zero foundation: `law.observation.one` (OBSERVATION-ONE + BOUNDARY-ONE + physical-nonexistence `none`), `law.equivalence.observation`, `law.demand.derivative`, `law.relation.property`, `law.change.delta`, `law.uncertainty.algebra`, `law.optimizer.economy` (§104–§106). REALIZATION-CONTRACT (`law.realization.contract`, §108) corrects the premise further: FTCFTW is not compiler optimization but optimal verified realization under semantics/information/physics/economics/uncertainty over the full tuple `R(S,O,W,D,K,E,H,P,F,B)` — *whether any computation occurs at all* is a candidate strategy (lawful nonexecution: cached/theorem/materialized/world-fact answers, demand elimination, observer elimination). Lower bounds are information/communication/I-O/circuit/work-vs-span/physical-law, not instruction counts; architecture (process/thread/service/shard/boundary erasure+introduction) is realization; meta-cost is lifecycle-global (a 1 ns win costing 10 h to find for a once-run program is a loss). The ~24 axes: identity, observation, law, knowledge, uncertainty, demand, change, equivalence, information, work, communication, representation, architecture, placement, schedule, boundary, failure, resource, search, verification, evidence, cost, adaptation, meta-cost — all extensible.
- Gate `.id` helpers: boundary curry `len(path)(min)`, `audit(path)(pattern)`, `hit(path)(pattern)`; subject-first `path:flag(q)(no, code, pat, law, fix)`; one word per binding (decompose mashed compounds like `denyrows`/`gatehome`); multiline subject-first `path:read()` chains; stdin via `stdin:read()`; `idol run`/`idol check` only — no C, Lua, LLVM, or V realization may admit or prove a direct gate. The explicit graph-backed C source realizer remains orthogonal.
- LAW-ONE paths and bindings: one lowercase word per segment — no snake_case or mashed compounds; decompose through hierarchy (`compiler/graph.id`, not `semantic_graph.id`).
- Prefix `!` is canonical negation — never `if not`, `and not`, or `(not` in Idol source (gate detector prose may still quote those strings).
- Do not decide canonicality with string-detector or substring architecture (`codens`, `luahash`, `layout`, `has(...)` admission patterns); route through production lexer → parser → graph → obligations (`GAP-124`).
- Harness must reason in Idol (pre-task reduction, semantic diff, deletion order), not as a conventional coding agent; read `docs/spec/harness-projection.md` and `.agents/HARNESS.md` before choosing work; audit seams for BRIDGE-DEATH, UNKNOWN-ONE, OWNERSHIP-ZERO, and PROFILE-EVIDENCE before introducing bridges or helpers.
- Use `"{}"` text composition, not `..`; nested `{expr:to(str)}` inside string literals does not interpolate — build dynamic needles at expression level; `using`/`using(x)` forbidden — `use(x)` only; do not refactor `scripts/grammarconvergence.id` without explicit approval.
- No `std.*`, `table.*`, `string.*`, or `math.*` namespace dispatch — subject-first edges only (`text:match`, `xs:keys`); reject `callable`/`*able`/codec/encoding protocol identities and lexical-substitution migrations; prove semantic reduction (DELETE/DECOMPOSE before rename), not respelling; never `==` against bool/nil/0/1/true/false or other sentinels; `environment` is not a thing — use `os.env[k]`, `os.args[n]`, `io:read`/`io:write`. No `match`/`case`/`switch`/pattern-object subsystem — control flow is refinement `if` (subject evaluated exactly once; branch heads are constraints on the already-evaluated subject; multi-arm refinement is unordered with no first-match/most-specific/declaration-order/trait precedence; nested `if` expresses order). Express every design from the small irreducible basis (id, fact, binding, value, table, descriptor, world, home, projection, application, relation, able, pack, place, refinement, demand, effect, witness, stage, provenance, transformation, realization) and reject match/pattern/trait/interface/module/namespace/import/service/context/result/option/future/promise/async/stream/iterator/macro/unsafe/capability/reflection unless irreducibility is proven.

## Learned Workspace Facts

- Production lexical authority is `lib/compiler/lexer.id` and `lib/compiler/token.id`; `src/lexer_tokenize.c` is generated directly from `lib/compiler/lexer.id` with `dump-c --lib` — regenerate, never hand-edit; `src/lexer.zig` / `tokenizeHost()` are differential oracles only — not live production work. The obsolete `lib/compiler/host.id` wrapper and its unconsumed `duo_lexer_host_*` ABI are deleted.
- Executed SHC frontier is **S0** (lexer/token/span only); compiler B does not exist; next frontier is GAP-145 lexical identity → GAP-134 grammar roles.
- Blind-start constitution: read `docs/spec/canonical.md` before repository code; do not infer language law from Git frequency.
- Harness boot payload and dev tooling: `docs/spec/harness-projection.md` → `.agents/HARNESS.md` via `tools/node/dev/generate-harness`/`orient`; coordination under `tools/node/dev/`; canonical Devin/Codex skill sources at `.pi/skills/idol-dev/SKILL.md` (dev loop) and `.pi/skills/idol/SKILL.md` (authority projection), installed by `tools/node/dev/install-skills`.
- Bit view edges are the `to(bit)` relations in `scripts/proof/bit.id` (`@view`); the `lib/semantic/*` shadow registry is deleted and `resident-proof` checks both tracked-index and filesystem absence. Graph `NodeKind`/`EdgeKind` are physical tags only — never decide semantic validity/meaning from tags: tag narrows the candidate, exact facts validate meaning, never `tag == func` → function semantics (C0 laws APPLICATION-CONSUMER-ZERO, FACT-LOCALITY-ONE, GRAMMAR-ONE, CONTROL-PLANE-DERIVED-ZERO, TAG-AUTHORITY-ZERO, MODULE-ZERO, and the world/application closure AT-ONE, APPLICATION-ONE, WORLD-CLOSED).
- Bootstrap/dev binary is `./zig-out/bin/idol` (`idol check`, `idol run`); `orient`, `doctor`, and `probe-mcp` default to it; `idol check` reliable for teaching paths; `idol run` may fail on native linker-entry debt — `scripts/agent_smoke.id` check-only until entry resolves; proof scripts use `IDOL`/`./zig-out/bin/idol`.
- Native gate-transport ARM64 (`src/native_backend.zig`): when `gate_transport && body_has_call`, spill all GP locals to the prologue stack; run `materializePendingVarargs` before call setup (variadic holes like `snprintf` `%s`); regression at `scripts/proof/gatecap.id`. GAP-155 bootstrap faces live in `src/native_bootstrap.zig` (realization-owned); `dnir_lower` uses `native_bootstrap.applicationExpr` — ordinary module calls are not bootstrap.
- Concurrent write lanes Codex, Poolside, and Devin are frequently stale/not-live; verify `tools/node/dev/claim list` before relying on them and aggressively clear/claim stale claims rather than waiting (user repeatedly directs clearing stale claims).
- `scripts/census/foreign.id` persists repo/work paths via `/tmp/idol-foreign-*` shell indirection across `gatecap` calls until cross-call binding corruption is fixed.
- Migration law sources live under `gate/` (`idiom.id`, `path.id`, `host.id`, `architecture.id`, `census.id`, `admission.id`) — executable status, including the `idiom.id` blocker, is stated above; legacy `scripts/*gate.id` are debt; host boundary law is `docs/spec/host.md` (host firewall until `GAP-154`). Compound-word (LAW-ONE) vocabulary and logic already live in `gate/path.id` (`words` string plus `known()`/`sep()`/`mash()`/`tail()`) and `gate/idiom.id` (`words` plus `compound()`) — reuse them; enforce no compounds across the whole repo, decomposing each to existing edges/nodes, to hierarchy, or to elimination.
- Serialize heavy commands through `tools/node/dev/idol-lock` (shell mutex); MCP manifest servers are **`idol`** (raw-text bootstrap status/head/orient transport) and **`idol-native`** (exact clean root supplied by `IDOL_NATIVE_ROOT`: check/symbols/graph/run/gates/orient/sim/explain/fmt/asm) per `tools/node/dev/mcp.manifest.json` — no sibling-topology fallback exists, and the retired pre-rename transports were removed rather than disabled; integration gate `zig build mcp-gate` → `./tools/node/dev/mcp-gate`.
- Compiled Idol bootstrap quirks: `string.match` with `\t` patterns returns nil (use `string.find` + `string.char(9)`); `"\n"` may be literal backslash-n (use `string.char(10)` for line splits); file-scope `os.env[k]` may be empty at module init (defer env reads to runtime/bootstrap ingress).
