# Agent Instructions

## Authority

The language law has one home. Read these files before editing Idol (`.id`), in
this order:

1. `docs/spec/constitution.md` — C0, the sole semantic authority. It is
   structured law documentation, not executable source or a source template.
   **Idol algebra closure:** §67 (`law.semantic.universe` … `law.algebra.absolute`;
   adversarial controls in `law.gate.protocol`, `law.gate.algebra`,
   `law.gate.infer`, and `law.gate.convergence`). **Convergence closure:**
   `law.bridge.death`, `law.fallback.zero`, `law.fact.producer.one`,
   `law.system.invariant`, `law.unknown.one`, `law.profile.evidence`,
   `law.infer.contract` — see `docs/spec/harness-projection.md` § seam audit,
   § universal anti-drift rules, and § projection (PROJECTION-ONE). **Anti-drift:**
   `law.source.not.proof`, `law.repair.class`, `law.projection.one`,
   `law.from.zero`, `law.std.zero`, `law.lib.zero`, `law.world.one`,
   `law.projection.absolute`, `law.projection.repair`. **INFER-ONE:**
   `to` is a graph relation usually omitted from source when demand uniquely resolves
   (`law.infer.one`); census debt with `scripts/infer_census.id`; never bulk-delete.
   `law.infer.one` — write only facts not uniquely recoverable; query resolver
   before adding `:to(T)`. Re-pasted session prompts titled "algebra closure"
   are void; §67 is sole authority. The language is **Idol** only.
2. `CLAUDE.md` — the operative projection of C0.
3. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md`, `docs/spec/source.md`,
   `docs/spec/host.md`, `docs/spec/convergence-contract.md` (blocking execution
   contract), and the relevant projection in `docs/spec/`.
4. `.agents/AGENT_CANONICAL.md` and `.agents/AGENT_COORDINATION.md` — routing,
   ownership, and current obligations.

This file is only the agent workflow and mechanical preflight. It is not a
second language specification. If it conflicts with C0 or `CLAUDE.md`, stop,
report the conflict, and repair this projection. Git history is the sole
historical archive; the active tree is current Idol only (`law.zero.history`).

The language and project identity is **Idol** (`idol`, `.id`, repository `idollang/idol`).
Active development remains in this repository until release-readiness authorization;
see `.agents/RELEASE_READINESS.md`. Cursor routers live in `.cursor/rules/`;
executable canonicality lives under **`gates/`** (home hierarchy — not scattered
`scripts/*gate*` paths).

## Idol harness orientation

Harnesses must **reason in Idol**, not as conventional coding agents with Idol
syntax pasted onto output. This section is workflow routing only; harness
reasoning law lives elsewhere.

| Layer | Path | Role |
|---|---|---|
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
(`path:read()`, `json:encode`, `os.env[k]`, `io:read`). The `lib/std/` tree is
filesystem bootstrap provenance until renamed (GAP-157); it is not authority.

Every canonicality result has one of four states: `canonical`, `migratable`,
`vocabularyblocked`, `invalid`. Do not invent vocabulary to silence a gate.

Do not add a new Zig, C, Lua, shell, Python, or other foreign subsystem. Existing
foreign implementation is bootstrap debt. A foreign edit is admissible only
when an active gap and evidence show that it is the smallest bridge needed to
unlock its Idol replacement, or when it strictly removes foreign surface. Keep
the bridge local, preserve native performance, and move the authority into Idol
in the same vertical slice as soon as the compiler can express it.

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
- a literal string projected through `[]` when admitted named projection or a
  structured field exposes the same identity directly;
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
- `--` or Lua long comments instead of `#` comments — `gates/idiom.id` and `gates/path.id`
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

The current `gates/idiom.id` added-line check is migration pressure over
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
 cat "$gate" | "$repo/zig-out/bin/idol" run "$repo/gates/idiom.id"

`gates/architecture.id` reads the staged index, so run it after staging or let
the pre-commit hook run it. The hook also runs `gates/path.id` over every
staged added or renamed path and over every added line in project teaching and
implementation surfaces. Do not suppress, bypass, weaken, or route around a
finding. Safe formatting rewrites require proved semantic equivalence.
Intent-sensitive findings require a semantic repair, not a regex rewrite.

Path and home names obey the same LAW-ONE as source identifiers (`law.path.name`).
Concat/mashed file and directory names are never allowed — each semantic unit belongs
in its own home segment through hierarchy (`semantic/graph.id`), not a compound stem
(`semantic_graph.id`, `readline.id`, `nativebackend/`). Both `gates/path.id` and
`gates/idiom.id` reject separator violations, version taxonomy, mashed
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
Added-line host-pattern firewall: `gates/idiom.id` and `gates/host.id`
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

Authoritative implementations: `gates/idiom.id`, `gates/host.id`,
`gates/path.id` (`scan(path)(body)` for path lists, `scan(diff)(body)` for
namediffs). Gate transport is stdin only — `stdin:read()` via pipe or shell
redirect (`< file`); no `os.args`, no bash wrappers, no `gatepath`, no `gate.sh`.
Run gates with **`idol run gates/<name>.id`** — never **`--backend=c`** (C emit is bootstrap
debt for the compiler build, not gate admission).
Commit admission runs through `.githooks/pre-commit` (shell orchestrator → direct-backend
`idol run gates/*`). Never `--backend=c` on gates.

Gate home (`gates/`):

| Gate | Role |
|---|---|
| `preflight` | `.githooks/pre-commit` shell → direct `idol run gates/*` |
| `idiom.id` | Added-line lexical/canonical migration firewall |
| `admission.id` | Semantic-admission firewall on added lines |
| `host.id` | Host API debt on staged additions |
| `architecture.id` | Staged-index migration censuses (C0 §65 ratchet) |
| `path.id` | LAW-ONE path/name firewall |
| `census.id` | Path stem census |
| `catalog.id` | Admitted relation projection (tables; admission inlines) |
| `bootstrap.id` | Shared capture helpers for gate scripts |
| `build.id` | Zig build-step idiom wrapper (diff → `gates/idiom.id`) |

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
or `name(): type` — migratable debt ratcheted by `gates/architecture.id` staged
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
- INFER-ONE (`law.infer.one`): write only facts not uniquely recoverable from demand/descriptors/context; query resolver before `:to(T)`; prefer demand-implied results over explicit `return` or redundant conversions.
- Relation projection is not curry: declare `to(str) = (value)` and invoke `value:to(str)`; operation-first `to(str)(value)` is migratable debt only.
- Gate `.id` helpers: boundary curry `len(path)(min)`, `audit(path)(pattern)`, `hit(path)(pattern)` — not flat comma forms or bridge bindings; multiline subject-first `path:read()` chains, no `text = path:read()` transitive bindings; stdin via `io:read()` only; `idol run`/`idol check`, never `--backend=c`.
- Prefix `!` is canonical negation — never `if not`, `and not`, or `(not` in Idol source (gate detector prose may still quote those strings).
- Do not decide canonicality with string-detector or substring architecture (`codens`, `luahash`, `layout`, `has(...)` admission patterns); route through production lexer → parser → graph → obligations (`GAP-124`).
- Harness must reason in Idol (pre-task reduction, semantic diff, deletion order), not as a conventional coding agent; read `docs/spec/harness-projection.md` and `.agents/HARNESS.md` before choosing work; audit seams for BRIDGE-DEATH, UNKNOWN-ONE, OWNERSHIP-ZERO, and PROFILE-EVIDENCE before introducing bridges or helpers.
- Use `"{}"` text composition, not `..`; nested `{expr:to(str)}` inside string literals does not interpolate — build dynamic needles at expression level.
- No `std.*`, `table.*`, `string.*`, or `math.*` namespace dispatch — subject-first edges only (`text:match`, `xs:keys`); reject lexical-substitution migrations (`std.*`→`process.*`, `req`→`process = lib.process`); prove semantic reduction, not respelling; `environment` is not a thing — use `os.env[k]`, `os.args[n]`, `io:read`/`io:write`.
- `using`/`using(x)` forbidden — `use(x)` is the sole admitted compact lexical-admission face; do not refactor `scripts/grammarconvergence.id` without explicit approval.

## Learned Workspace Facts

- Production lexical authority is `lib/std/compiler/lexer.id` and `lib/std/compiler/token.id`; `src/duo_lexer_tokenize.c` is generated from `lib/std/compiler/host.id` — regenerate, never hand-edit; `src/lexer.zig` is a differential oracle only.
- Executed SHC frontier is **S0** (lexer/token/span only); compiler B does not exist; next frontier is GAP-145 lexical identity → GAP-134 grammar roles.
- Harness boot payload: `docs/spec/harness-projection.md` → `.agents/HARNESS.md` via `tools/node/dev/generate-harness` (`orient` regenerates).
- Dev and coordination tooling lives under `tools/node/dev/`; Codex agent skill is `idol-dev`.
- Gate boundary relation descriptors live in `lib/semantic/gate.id` (`len`, `audit`, `hit`, `scan`, `dot` — curry slots, not world relations).
- Reserved keyword `not` cannot be a table field name — census row is `debt.negation`, never `debt.not`.
- Bit view edges registered in `lib/semantic/ingest.id` as curried `view(edges)` pipe (separate from world `edges`); reverse is `restore` not `unpack`.
- Bit reinterpret proof: `scripts/proof/bit.id`; nominal `type bit = i64`; round-trip assertions; integer observation edge is `bit:to(i64)`.
- Bootstrap/dev binary is `./zig-out/bin/idol` (`idol check`, `idol run`); `orient`, `doctor`, and `probe-mcp` default to it; proof scripts use `IDOL`/`./zig-out/bin/idol` — not `DUO`/`bin/duo`.
- Authoritative migration gates live under `gates/` (`idiom.id`, `path.id`, `host.id`, `architecture.id`, `census.id`) — legacy `scripts/*gate.id` are debt, not authority; host boundary law is `docs/spec/host.md` (host firewall until `GAP-154`).
- MCP bootstrap lives under `tools/mcp/` (`shared.id`, `bench.id`, `lsp.id`, `gate.id`, `audit.id`, `eval.id`, `zls/bridge.id`); integration gate is `zig build mcp-gate` → `./zig-out/bin/idol run --backend=c tools/mcp/gate.id`.
- Compiled Idol bootstrap quirks: `string.match` with `\t` patterns returns nil (use `string.find` + `string.char(9)`); `"\n"` may be literal backslash-n (use `string.char(10)` for line splits); file-scope `os.env[k]` may be empty at module init (defer env reads to runtime/bootstrap ingress).
