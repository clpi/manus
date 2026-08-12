# Agent Instructions

## Authority

The language law has one home. Read these files before editing Idol, in this
order:

1. `docs/spec/constitution.md` — C0, the sole semantic authority. It is
   structured law documentation, not executable source or a source template.
2. `CLAUDE.md` — the operative projection of C0.
3. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md`, `docs/spec/source.md`,
   `docs/spec/host.md` (host boundary / shell / capability closure), and the
   relevant projection in `docs/spec/`.
4. `.agents/AGENT_CANONICAL.md` and `.agents/AGENT_COORDINATION.md` — routing,
   ownership, and current obligations.

This file is only the agent workflow and mechanical preflight. It is not a
second language specification. If it conflicts with C0 or `CLAUDE.md`, stop,
report the conflict, and repair this projection. Repository history and the
legacy corpus are migration evidence, never authority.

The language and project identity is **Idol** (`idol`, `.id`). Active development
happens in **`clpi/duo`**. The future release repository **`idollang/idol`** is
untouched until explicit release-readiness authorization; see
`.agents/RELEASE_READINESS.md`. Historical Idol, Duo, Duon, `.id`, and the
`duo` bootstrap executable are development/migration provenance only. Cursor
routers live in `.cursor/rules/`; executable canonicality remains in
`scripts/idiomgate.id` and `scripts/semanticgate.id`.

## Monoglot boundary

The destination is an Idol compiler, standard vocabulary, build, tools, gates,
and documentation projections implemented in Idol.

Do not add a new Zig, C, Lua, shell, Python, or other foreign subsystem. Existing
foreign implementation is bootstrap debt. A foreign edit is admissible only
when an active gap and evidence show that it is the smallest bridge needed to
unlock its Idol replacement, or when it strictly removes foreign surface. Keep
the bridge local, preserve native performance, and move the authority into Idol
in the same vertical slice as soon as the compiler can express it.

Never route a typed or compile-time value through a boxed compatibility value.
The semantic value and its native realization remain distinct; compatibility
front ends do not own Idol meaning.

## Semantic-first correctness

Never translate a C, Rust, Python, Lua, or conventional compiler pattern into
Idol syntax. Begin with the semantic operation the program requests. Express it
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

Each file owns one semantic concept. Each Idol identifier is one lowercase
semantic word. An underscore or uppercase letter in an Idol identifier is never
canonical. **No `std` anywhere** — not a namespace, table, prelude, path to
call, or migration alias. Vocabulary reaches through layout/home/world
projection (`fs:read`, `json:encode`, `os.env[k]`, `io:read`). Never write
`std.*`. Never teach or copy `std.*` from nearby debt. The `lib/std/` tree is
filesystem bootstrap provenance until renamed (GAP-157); it is not authority.
Do not replace `std` with another universal namespace: possessed values supply
subjects; authority belongs to worlds; qualification belongs in facts. If the required
relation or world is not admitted, report `SEMANTIC-VOCABULARY-BLOCKED` instead
of adding a helper.

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
- a `use(` / `using(` / `import` / `inject` / `admit` / `include` admission face —
  visibility is scope reachability; change scope facts at the owner boundary;
- a literal string projected through `[]` when admitted named projection or a
  structured field exposes the same identity directly;
- a mashed gate-scan compound (`scandiff`, `scanline`, `diffhead`, `bareend`, or
  any `scan+*` binding name);
- a string where a boundary symbol belongs in a curried scan (`scan("diff")` —
  write `scan(diff)(body)`; `diff` and `path` are symbols in the curry slot, not
  string literals).

After parsing, describe meaning in semantic terms. Parser terms such as
statement, loop node, binary expression, or call expression are valid only
while discussing recognition. Later boundaries must expose the actual relation,
values, conditional demand, dependencies, carried values, worlds, result
demand, places, proofs, provenance, and realization facts.

## Mechanical preflight

The grammar is closed. New capability does not justify a token, sigil,
directive, keyword, or special AST ontology.

A changed canonical `.id` line, or touched historical `.id` line, is rejected
when it introduces any of these forms:

- an identifier containing an underscore or uppercase letter;
- `end`, a semicolon, `then`, or `do` instead of offside structure;
- `--` or Lua long comments instead of `#` comments — `idiomgate` and `gates/path`
  reject dash comments on every added line;
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
- a new foreign source file.

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

The current `scripts/idiomgate.id` added-line check is migration pressure over
text, not semantic proof and not permission to rewrite. Its
`law.update.face` finding identifies only a candidate expanded face. Existing
compound forms, distinct left/right subjects, declarations, and unwitnessed
computed places remain negative controls. Semantic classification, a
graph-owned canonicalizer, and formatting for this equivalence remain blocked
by `GAP-145`, `GAP-134`, and `GAP-124`.

Before staging Idol source, run the repository-native idiom check over the exact
working-tree diff:

    repo="$(git rev-parse --show-toplevel)"
 gate="$(mktemp -t idolgate)" && trap 'rm -f "$gate"' EXIT
 git diff -U0 -- '*.id' '*.id' > "$gate"
 cat "$gate" | "$repo/zig-out/bin/idol" run "$repo/scripts/idiomgate.id"

`scripts/semanticgate.id` reads the staged index, so run it after staging or let
the pre-commit hook run it. The hook also runs `gates/path.id` over every
staged added or renamed path and over every added line in project teaching and
implementation surfaces. Do not suppress, bypass, weaken, or route around a
finding. Safe formatting rewrites require proved semantic equivalence.
Intent-sensitive findings require a semantic repair, not a regex rewrite.

Path and home names obey the same LAW-ONE as source identifiers (`law.path.name`).
Concat/mashed file and directory names are never allowed — each semantic unit belongs
in its own home segment through hierarchy (`semantic/graph.id`), not a compound stem
(`semantic_graph.id`, `readline.id`, `nativebackend/`). Both `gates/path.id` and
`scripts/idiomgate.id` reject separator violations, version taxonomy, mashed
compounds in diff path headers, directory components, filename stems, and added-line
tokens, and namespace-first calls (`string.*`, `std.string.*`, `table.*`, `math.*`,
`std.*`) on every staged added line in project surfaces.
Do not mash compound names, strip punctuation, or invent loader syntax. Native
resolution uses source layout, scope, and worlds (`docs/spec/source.md`,
`GAP-153`). Do not add `req`, `require`, `import`, `module`, `namespace`, `include`, `use(`,
`using(`, `inject`, `admit`, or privileged `*bind` edges to new canonical source.
Reachability is scope and home projection only (`docs/spec/source.md`, `GAP-153`).
No admission syntax makes already-known bindings visible — change scope facts at
the owner boundary instead.

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
Added-line host-pattern firewall: `scripts/idiomgate.id` and `gates/host.id`
(temporary until graph enforcement, `GAP-154`).

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
| `viewrouter`, `fsrouter`, `corerouter` | `router(view)(view[home])` / `router(proof)(proof[home])` |
| `viewproof` | `view = router(proof)(proof["view"])` — slot name matches home key |
| `zig-out/bin/duo` | `zig-out/bin/idol` — public command identity is `idol` |
| `ingestbody`, `graphbody`, `bitbody`, `censusbody`, `zerostdbody`, `verdictbody` | `router(semantic)(semantic[home])` — never home+body mash |
| `recordbody`, `worldbody`, `removebody`, `mkdirbody` | `router(proof)(proof[home])` — never home+body mash |
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

if !len(proof["resident"])(32)
    code = 1
if code == 0 and !audit(proof["resident"])("path:read%(")
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

view = { census = "lib/semantic/census.id", ingest = "lib/semantic/ingest.id" }
```

Line-level work inside a diff boundary uses **`audit(path, no, line)`** — never
`scanline`. Path-header recognition uses **`head(line)`** — never `diffhead`.
Bare-line `end` detection uses **`bare(code)`** — never `bareend`.
Ingress home membership uses **`ingress(path)`** — never `ingressonly` or
`only(ingress)(path)`; ingress is the subject.

Authoritative implementations: `scripts/idiomgate.id`, `gates/host.id`,
`gates/path.id` (`scan(path)(body)` for path lists, `scan(diff)(body)` for
namediffs). Gate transport is stdin only — `io:read()` via pipe or shell
redirect (`< file`); no `os.args`, no bash wrappers, no `gatepath`, no `gate.sh`.
Run gates with **`idol run gate.id`** — never **`--backend=c`** (C emit is bootstrap
debt for the compiler build, not gate admission).
Commit admission runs through `scripts/preflight.id` (`.githooks/pre-commit`
execs it).

## Path and file names (law.path.name)

Project-controlled path components obey the same LAW-ONE as identifiers:

- **Forbidden:** `snake_case`, `camelCase`, `kebab-case`, mashed stems
  (`semantic_graph.id`, `readline.id`, `nativebackend.zig`)
- **Required:** one lowercase word per semantic home component, decomposed
  through hierarchy (`semantic/graph.id`, `read/line.id`, `native/backend.zig`)

Never use underscore separators in file or directory names. The stem projects
the semantic table or home name; qualification belongs in nested homes and
worlds, not punctuation in a single component.

Enforced on staged paths and added lines by `gates/path.id` (`sep`, `mash`,
`walk`, `verdict`). Positive control rejects `semantic_graph.id` and accepts
`semantic/graph.id`.

Before creating a project-owned path, classify semantic owner, projected home,
canonical one-word name, origin, and role. If decomposition is unclear, record
`PATH-SEMANTICS-BLOCKED` rather than minting a compound filename.

Callable bindings use result demand on the binder: `name: descriptor = (args) body`.
Never write suffix or header callable faces: `name = (): type`, `name = (args): type`,
or `name(): type` — migratable debt ratcheted by `scripts/semanticgate.id` staged
census (callable.result.suffix), `examples/spec100/result.id`, and `scripts/canon.id`.
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
11. Does every `[]` key genuinely require evaluation, or is a stronger static
    field/projection face already known?
12. Is a boolean or negation erasing a semantic case, unknown state, fact, or
    transition that should be consumed directly?

Prefer the representation that preserves the most semantic information and the
largest lawful realization set with the least source ceremony. Static identity
looks static; computed identity uses `[]`; neither face chooses representation.

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

1. Read the local router and `docs/bootstrap.md`, then call
   `duo_agent_session_start` and inspect `git status --short --branch`, recent
   commits, `duo_dev_claim_files`, every current `gaps/GAP-*.md`, and
   `git stash list`. Until `GAP-131` closes, the session gap summary is
   incomplete; the exact gap files and live claim result remain the routing
   evidence.
2. Claim exact paths with `duo_dev_claim_acquire` before editing. Never edit a
   path owned by another live session.
3. Use `duo_agent_gaps_update` for numbered obligations. Do not create a second
   tracker or hand-allocate a gap.
4. Serialize builds and benchmarks through the locked MCP build tools. Until a
   world-backed Idol coordinator is admitted, do not teach a `std.script`
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

## Learned User Preferences

- Do not migrate development to `idollang/idol`; keep active work in `clpi/duo` until explicit release-readiness authorization.
- Do not implement or hand-edit lexical or tokenizer logic outside the Idol lexer source path (`lib/std/compiler/lexer.id`, `lib/std/compiler/token.id`).
- Do not use `ALU_OPS` or lookup-table dispatch for JIT lowering; specialize each opcode at its ALU or compare edge.
- Prefer demand-based implicit results over explicit `return` in `.id` helpers where control flow allows.
- Do not commit unless explicitly requested.
- Gate `.id` helpers: boundary curry `len(path)(min)`, `audit(path)(pattern)`, `hit(path)(pattern)` — not flat comma forms or bridge bindings; multiline subject-first `path:read()` chains, no `text = path:read()` transitive bindings; stdin via `io:read()` only; `idol run`/`idol check`, never `--backend=c`.
- Prefix `!` is canonical negation — never `if not`, `and not`, or `(not` in Idol source (gate detector prose may still quote those strings).
- Do not decide canonicality with string-detector or substring architecture (`codens`, `luahash`, `layout`, `has(...)` admission patterns); route through production lexer → parser → graph → obligations (`GAP-124`).
- Do not use Python for migration, census, or gate tooling; implement in Idol only.
- Use `"{}"` text composition in Idol source, not `..` concatenation.
- No `std.*`; `environment` is not a thing — use `os.env[k]`, `os.args[n]`, subject-first `io:read`/`io:write` and `hay:has(needle)`.
- `using(x)` is lexical admission compression only—not import, module, or loader syntax; bit view reverse is `restore` not `unpack`; do not refactor `scripts/grammarconvergence.id` without explicit approval.

## Learned Workspace Facts

- Production lexical authority is `lib/std/compiler/lexer.id` and `lib/std/compiler/token.id`.
- `src/duo_lexer_tokenize.c` is generated bootstrap from `lib/std/compiler/host.id`; regenerate it instead of hand-editing trivia or token logic there.
- `src/lexer.zig` is a differential oracle only, not production lexical authority.
- Dev and coordination tooling lives under `tools/node/dev/` (not mashed `devnode` paths).
- Path LAW-ONE gate is `gates/path.id`; host-pattern firewall is `gates/host.id` (until `GAP-154`).
- Gate boundary relation descriptors live in `lib/semantic/gate.id` (`len`, `audit`, `hit`, `scan`, `dot` — curry slots, not world relations).
- Reserved keyword `not` cannot be a table field name — census row is `debt.negation`, never `debt.not`.
- Bit view edges registered in `lib/semantic/ingest.id` as curried `view(edges)` pipe (separate from world `edges`).
- Bit reinterpret proof: `scripts/proof/bit.id`; nominal `type bit = i64`; round-trip assertions; `to(i64)(bit)` is integer observation edge.
- Bootstrap compiler binary: `zig-out/bin/idol` (`idol check`, `idol run`). `duo` is migration provenance only.
- Proof scripts use `IDOL` env / `./zig-out/bin/idol` — not `DUO` / `bin/duo`.
- Host boundary authority is `docs/spec/host.md`; read before argv, env, I/O, process, pipe, shell, or transport work.
