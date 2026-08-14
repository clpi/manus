# Idol host boundary, home projection, capability and shell closure

Apply immediately to every active agent and every future agent.

This is a blocking architectural redirect.

Do not continue adding host API calls, host-shaped substitutes, spelling
detectors as authority, or transport-specific policy until this closure is
implemented and backfilled.

Repository historical host calls are migration provenance until classified and
moved to ingress/egress boundaries.

## Absolute root law

Idol source sees semantic values.

It does not see the host operating system API.

Idol has no canonical authority-bearing API trees for:

```text
os
io
proc
process
ir
runtime
system
std
core
shell
```

None of these exist in Idol source as namespace loaders, runtime tables, prelude
graphs, or wrappers to call. They are not migration targets and not bootstrap
substitutes. A spelling like `std.proc.capture` or `ir.node` does not become
lawful because it compiles or because nearby debt uses it.

Historical filesystem paths (`lib/…`) and realization encodings (DNIR) are
bootstrap or realization provenance only — delete or push outward, never extend.

Renaming host spellings without semantic decomposition is forbidden:

```text
os.args()        → os.args[n]   (table under os world — not a function call)
os.getenv(k)     → os.env[k] / os.env(k) / os.env[k] =
io.read()        → stdin:read() / path:read()  (read relation on subject)
io.write(x)      → sink:write(x)  (write relation on subject)
io.popen(cmd)    → structured command + process world
environment[k]   → os.env[k]    (environment is not a thing)
```

when the same host model remains underneath.

## Canonical execution model

Every Idol execution begins with a semantic root/home constructed by its
embedding, launcher, or build context.

The root may expose ordinary values such as:

```text
input
output
error
cwd
```

`args` and `env` are **ordinary tables under the `os` world** — not separate
root singletons and not an `environment` entity. Access:

```id
os.args[1]
os.env["KEY"]
```

ordinary anchored homes such as:

```text
app
codec
http
store
```

and worlds such as:

```text
fs
net
process
clock
random
```

Exact names come from current vocabulary authority — not from this projection.

The root is a graph context.

It is not a runtime namespace object.

## Arguments (`os.args`)

Command-line arguments are supplied as an ordinary table under the `os` world.

Wrong:

```id
args = os.args()
command = args[1]    # bare table without os world when argv is meant
```

Canonical:

```id
command = os.args[1]
target = os.args[2]
```

Launcher ingress:

```text
host argv → foreign provenance → os.args table under os world
```

After ingress, provenance (POSIX, WASI, MCP, test harness) is not visible in
source.

## Environment (`os.env`)

`environment` is **not a thing**. Environment is the ordinary `env` table under
the `os` world — index, call, and assign like any table field.

Wrong:

```id
mode = os.getenv("IDOLTREE")
mode = environment["IDOLTREE"]
```

Canonical:

```id
mode = os.env["IDOLTREE"]
os.env["KEY"] = value
os.env(key) = value
```

Foreign `getenv` / `environ` / `GetEnvironmentVariable` are bootstrap ingress
only. Build world != program world.

## Endpoints and `io` world I/O

Do not standardize architecture around stdin-only.

Launcher may project `input`, `output`, `error` endpoint values. The `io`
world exposes subject-first relations:

Wrong:

```id
line = io.read()
io.write(result)
```

Canonical:

```id
line = stdin:read()
out:write(result)
```

Relation is protocol: `source: read` not `source: readable` (`law.protocol.one`).
RETRACTED under world reconciliation v2. This read: "World dot forms such as
`io:read()` are ingress debt — subject-first `stdin:read()` / `path:read()` /
`sink:write(value)` only." v2 rules the other way: `io` is an ordinary world
VALUE, a table, and a legitimate subject, so `io:read()` and `io:write(x)` are
canonical. `stdin`/`stdout`/`stderr` are host provenance and realization, not
native semantic concepts.

What survives unchanged is the part that was never about `io`: the DOT form is
still wrong, because a home is not a namespace. `io.read(x)` is debt;
`io:read()` is not. Where a stream is the real subject, it stays the subject —
`file:write(data)`, not `io:write(file, data)`.

MCP stdin/stdout pipes are realization choices for an invocation — not
language architecture.

## Process execution

`popen` is not an Idol relation.

Decompose into:

```text
command value (executable, arguments, environment, cwd, endpoints)
process world
run relation
result/status/effects/witness
```

Historical:

```id
pipe = io.popen("git status")
text = pipe:read_all()
```

Semantic migration direction (conceptual — use admitted vocabulary):

```id
git = command("git", "status")
result = git:run()
text = result.output
```

If vocabulary lacks the relation: `SEMANTIC-VOCABULARY-BLOCKED`. Do not invent
another host wrapper.

Direct command and shell expression remain semantically distinct. Do not convert
every command into `/bin/sh -c ...`.

## Shell home

Shell behavior is expressed through execution home/context.

There is no shell mode keyword, no `use shell`, no hidden global shell flag.

The launcher constructs a shell home:

```text
ordinary program home projections
+ command-resolution projection
+ shell-provided process/environment/fs worlds
+ input/output/error endpoints
```

Changing home is a launcher/embedding operation — not canonical source syntax.

Bare command resolution exists only when the active home carries command
projection:

```text
ordinary lexical binding
→ ordinary home binding
→ anchored semantic roots
→ canonical vocabulary
→ shell command projection (shell home only)
→ failure
```

A real Idol binding wins over shell fallback.

Ordinary home without command projection: unknown bare command → unresolved
identity. It does NOT silently run an executable.

## Core vocabulary

Do not create a `core` namespace.

Core vocabulary means canonical semantic identity authority at compiler
construction — not a table source traverses.

Wrong:

```id
core.len(x)
core.fs.read(path)
core.process.run(cmd)
```

Correct meaning:

```text
canonical relation len / read / run reachable from root projection
```

## Projection and home algebra

See `docs/spec/source.md` for file/home/package closure.

Summary invariants:

- No module system, import, use, using, inject, admit, open, include.
- Selective visibility is scope/home construction at owner boundaries.
- Cross projection preserves one semantic identity with distinct witnesses.
- Union/intersection/subtraction/restriction are reachability descriptions —
  not runtime merge tables unless demand requires materialization.
- Worlds provide authority; homes provide reach; bindings provide names.

## Backend selection

`--backend=c` and similar CLI spellings are foreign launcher input projected to
target/realization facts — not canonical semantic switches inside `.id`.

C emission is migration/compatibility realization — not native semantic backend
identity.

## Bootstrap adapter law

At the outer foreign boundary a temporary adapter may still use host APIs if:

- classified bootstrap
- foreign call isolated
- semantic result established immediately
- downstream never sees the host API
- deletion gate recorded

Push foreignness outward. Host mechanisms belong at ingress or egress — never in
the semantic middle.

Migration wrappers that still call host APIs underneath are forbidden unless they
establish the semantic boundary and name a deletion gate.

## Durable enforcement

Lexical ratchets on **added lines** are temporary migration firewalls only:

- `gate/host.id` — blocks new host API spellings on staged additions
- `scripts/ingress/` home — bootstrap foreign ingress boundary (`input.id`, `output.id`, `arg.id`)

`gate/architecture.id` must **not** host `hostread`, `hostargs`, `hostenv`, or
other host spelling census rows. That is the same antipattern as `suffix()`,
`readface`, and admission string detectors. Host semantic verdicts belong to
GAP-124 graph obligations.

Production authority:

- native graph must not contain host namespace authority
- environment reads require environment facts + world
- process execution requires structured command + process world
- argument access resolves root-projected args value
- shell command fallback requires shell home + command projection

Spelling mutation must not evade these invariants.

## Agent pre-write law

Before writing code involving argv, env, filesystem, process, pipe, shell,
transport, terminal, command, cwd, PATH, or backend, state:

```text
semantic subject
canonical relation
world requirement
home/root projection
foreign ingress/egress boundary
demand
possible zero-cost realization
```

If unavailable: `SEMANTIC-VOCABULARY-BLOCKED` or `IMPLEMENTATION-BLOCKED`.

Do not reach for host APIs.

## Absolute closure

```text
There is no native os.args()    — use os.args[n] under os world
There is no native os.getenv   — use os.env[k]; environment is not a thing
There is no native io.read     — use stdin:read() / path:read(); never readable adjective
There is no native popen       — commands are structured values under process authority
There is no stdin-only architecture — input/output/error are endpoint values
There is no core namespace     — vocabulary is direct canonical reachability
There is no module/import/use/using/inject — homes establish reachability
Shell is a home, not a mode bit — bare commands resolve only under shell home
Host APIs exist only at ingress/egress realization boundaries
```

Pipeline:

```text
.id → graph → demand → realization → machine
```

FTCFTW.
