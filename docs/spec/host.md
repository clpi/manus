| field | value |
|---|---|
| title | Idol host boundary, home projection, capability and shell closure |

| # | directive |
|---|---|
| 1 | Apply immediately to every active agent and every future agent. |

| # | directive |
|---|---|
| 1 | This is a blocking architectural redirect. |

| # | directive |
|---|---|
| 1 | Do not continue adding host API calls, host-shaped substitutes, spelling detectors as authority, or transport-specific policy until this closure is implemented and backfilled. |

| # | directive |
|---|---|
| 1 | Repository historical host calls are migration provenance until classified and moved to ingress/egress boundaries. |

| section |
|---|---|
| Absolute root law |

| # | directive |
|---|---|
| 1 | Idol source sees semantic values. |

| # | directive |
|---|---|
| 1 | It does not see the host operating system API. |

| # | directive |
|---|---|
| 1 | Idol has no canonical authority-bearing API trees for: |

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

| # | directive |
|---|---|
| 1 | None of these exist in Idol source as namespace loaders, runtime tables, prelude graphs, or wrappers to call. |
| 2 | They are not migration targets and not bootstrap substitutes. |
| 3 | A spelling like `std.proc.capture` or `ir.node` does not become lawful because it compiles or because nearby debt uses it. |

| # | directive |
|---|---|
| 1 | Historical filesystem paths (`lib/…`) and realization encodings (DNIR) are bootstrap or realization provenance only — delete or push outward, never extend. |

| # | directive |
|---|---|
| 1 | Renaming host spellings without semantic decomposition is forbidden: |

```text
os.args()        → os.args[n]   (computed projection on the table under os world)
os.getenv(k)     → os.env[k] / os.env[k] =
io.read()        → stdin:read() / path:read()  (read relation on subject)
io.write(x)      → sink:write(x)  (write relation on subject)
io.popen(cmd)    → structured command + process world
environment[k]   → os.env[k]    (environment is not a thing)
```

| # | directive |
|---|---|
| 1 | when the same host model remains underneath. |

| # | directive |
|---|---|
| 1 | `path:read()` on an absent or unreadable path FAILS CLOSED: the runtime refuses with an identity-first diagnostic naming the cause and the path (`read-refused:absent:<path>` / `read-refused:io:<path>`) and a nonzero exit, because an absent file is not a value and NULL-as-`str` was measured undefined behaviour (`law.id.one`: downstream semantic use fails closed when the required facts are absent; refusal pinned by `gate/readpath.sh`). |
| 2 | A structured absent\|present outcome family that lets source observe absence as a value remains open under `GAP-154`/`GAP-118` and is not admitted by this refusal. |

| section |
|---|---|
| Canonical execution model |

| # | directive |
|---|---|
| 1 | Every Idol execution begins with a semantic root/home constructed by its embedding, launcher, or build context. |

| # | directive |
|---|---|
| 1 | The root may expose ordinary values such as: |

```text
input
output
error
cwd
```

| # | directive |
|---|---|
| 1 | `args` and `env` are **ordinary tables under the `os` world** — not separate root singletons and not an `environment` entity. |

```id
os.args[1]
os.env["KEY"]
```

| # | directive |
|---|---|
| 1 | ordinary anchored homes such as: |

```text
app
codec
http
store
```

| # | directive |
|---|---|
| 1 | and worlds such as: |

```text
fs
net
process
clock
random
```

| # | directive |
|---|---|
| 1 | Exact names come from current vocabulary authority — not from this projection. |

| # | directive |
|---|---|
| 1 | The root is a graph context. |

| # | directive |
|---|---|
| 1 | It is not a runtime namespace object. |

| section |
|---|---|
| Arguments (`os.args`) |

| # | directive |
|---|---|
| 1 | Command-line arguments are supplied as an ordinary table under the `os` world. |

| # | directive |
|---|---|

```id
args = os.args()
command = args(1)    # bare value without an os namespace when argv is meant
```

| # | directive |
|---|---|
| 1 | Canonical: |

```id
command = os.args[1]
target = os.args[2]
```

| # | directive |
|---|---|
| 1 | Launcher ingress: |

```text
host argv → foreign provenance → os.args table under os world
```

| # | directive |
|---|---|
| 1 | After ingress, provenance (POSIX, WASI, MCP, test harness) is not visible in source. |

| section |
|---|---|
| Environment (`os.env`) |

| # | directive |
|---|---|
| 1 | `environment` is **not a thing**. |
| 2 | Environment is the ordinary `env` table under the `os` world — project, read, and assign like any table field. |

| # | directive |
|---|---|

```id
mode = os.getenv("IDOLTREE")
mode = environment["IDOLTREE"]
```

| # | directive |
|---|---|
| 1 | Canonical: |

```id
mode = os.env["IDOLTREE"]
os.env["KEY"] = value
os.env[key] = value
```

| # | directive |
|---|---|
| 1 | Foreign `getenv` / `environ` / `GetEnvironmentVariable` are bootstrap ingress only. |
| 2 | Build world != program world. |

| section |
|---|---|
| Endpoints and `io` world I/O |

| # | directive |
|---|---|
| 1 | Do not standardize architecture around stdin-only. |

| # | directive |
|---|---|
| 1 | Launcher may project `input`, `output`, `error` endpoint values. |
| 2 | The `io` world exposes subject-first relations: |

| # | directive |
|---|---|

```id
line = io.read()
io.write(result)
```

| # | directive |
|---|---|
| 1 | Canonical: |

```id
line = stdin:read()
out:write(result)
```

| # | directive |
|---|---|
| 1 | Relation is protocol: `source: read` not `source: readable` (`law.protocol.one`). |
| 2 | RETRACTED under world reconciliation v2. |
| 3 | This read: "World dot forms such as `io:read()` are ingress debt — subject-first `stdin:read()` / `path:read()` / `sink:write(value)` only." v2 rules the other way: `io` is an ordinary world VALUE, a table, and a legitimate subject, so `io:read()` and `io:write(x)` are canonical. `stdin`/`stdout`/`stderr` are host provenance and realization, not native semantic concepts. |

| # | directive |
|---|---|
| 1 | What survives unchanged is the part that was never about `io`: the DOT form is still wrong, because a home is not a namespace. `io.read(x)` is debt; `io:read()` is not. |
| 2 | Where a stream is the real subject, it stays the subject — `file:write(data)`, not `io:write(file, data)`. |

| # | directive |
|---|---|
| 1 | MCP stdin/stdout pipes are realization choices for an invocation — not language architecture. |

| section |
|---|---|
| Process execution |

| # | directive |
|---|---|
| 1 | `popen` is not an Idol relation. |

| # | directive |
|---|---|
| 1 | Decompose into: |

```text
command value (executable, arguments, environment, cwd, endpoints)
process world
run relation
result/status/effects/witness
```

| # | directive |
|---|---|
| 1 | Historical: |

```id
pipe = io.popen("git status")
text = pipe:read_all()
```

| # | directive |
|---|---|
| 1 | Semantic migration direction (conceptual — use admitted vocabulary): |

```id
git = command("git", "status")
result = git:run()
text = result.output
```

| # | directive |
|---|---|
| 1 | If vocabulary lacks the relation: `SEMANTIC-VOCABULARY-BLOCKED`. |
| 2 | Do not invent another host wrapper. |

| # | directive |
|---|---|
| 1 | Direct command and shell expression remain semantically distinct. |
| 2 | Do not convert every command into `/bin/sh -c ...`. |

| section |
|---|---|
| Shell interpretation and command reach |

| # | directive |
|---|---|
| 1 | Shell is command interpretation law. |
| 2 | It is not a source law, grammar, home, world, authority grant, mode keyword, or hidden global flag. |
| 3 | Possessing shell law never changes which grammar recognizes source. |

| # | directive |
|---|---|
| 1 | A launcher may independently provide ordinary command-provider reach, process, filesystem and environment authority witnesses, and input/output/error endpoints according to policy. |
| 2 | Bundling those facts for an interactive launch does not make shell interpretation their owner and does not make the bundle a privileged semantic container. |

| # | directive |
|---|---|
| 1 | Bare command resolution exists only when an exact command provider is reached: |

```text
ordinary lexical binding
→ ordinary home binding
→ anchored semantic roots
→ canonical vocabulary
→ exact reached command-provider projection
→ failure
```

| # | directive |
|---|---|
| 1 | A real Idol binding wins over command-provider projection. |

| # | directive |
|---|---|
| 1 | No reached provider: unknown bare command → unresolved identity. |
| 2 | Multiple incomparable providers → ambiguity. |
| 3 | Execution additionally requires exact process authority. |
| 4 | Failure to resolve never falls back to opaque shell text. |

| section |
|---|---|
| Core vocabulary |

| # | directive |
|---|---|
| 1 | Do not create a `core` namespace. |

| # | directive |
|---|---|
| 1 | Core vocabulary means canonical semantic identity authority at compiler construction — not a table source traverses. |

| # | directive |
|---|---|

```id
core.len(x)
core.fs.read(path)
core.process.run(cmd)
```

| # | directive |
|---|---|
| 1 | Correct meaning: |

```text
canonical relation len / read / run reachable from root projection
```

| section |
|---|---|
| Projection and home algebra |

| # | directive |
|---|---|
| 1 | See `docs/spec/source.md` for file/home/package closure. |

| # | directive |
|---|---|
| 1 | Summary invariants: |

| # | directive |
|---|---|
| 1 | No module system, import, use, using, inject, admit, open, include. |
| 2 | Selective visibility is scope/home construction at owner boundaries. |
| 3 | Cross projection preserves one semantic identity with distinct witnesses. |
| 4 | Union/intersection/subtraction/restriction are reachability descriptions — not runtime merge tables unless demand requires materialization. |
| 5 | Worlds provide authority; homes provide reach; bindings provide names. |

| section |
|---|---|
| Backend selection |

| # | directive |
|---|---|
| 1 | `--backend=c` and similar CLI spellings are foreign launcher input projected to target/realization facts — not canonical semantic switches inside `.id`. |

| # | directive |
|---|---|
| 1 | C emission is migration/compatibility realization — not native semantic backend identity. |

| section |
|---|---|
| Bootstrap adapter law |

| # | directive |
|---|---|
| 1 | At the outer foreign boundary a temporary adapter may still use host APIs if: |

| # | directive |
|---|---|
| 1 | classified bootstrap |
| 2 | foreign call isolated |
| 3 | semantic result established immediately |
| 4 | downstream never sees the host API |
| 5 | deletion gate recorded |

| # | directive |
|---|---|
| 1 | Push foreignness outward. |
| 2 | Host mechanisms belong at ingress or egress — never in the semantic middle. |

| # | directive |
|---|---|
| 1 | Migration wrappers that still call host APIs underneath are forbidden unless they establish the semantic boundary and name a deletion gate. |

| section |
|---|---|
| Durable enforcement |

| # | directive |
|---|---|
| 1 | Lexical ratchets on **added lines** are temporary migration firewalls only: |

| # | directive |
|---|---|
| 1 | `gate/host.id` — blocks new host API spellings on staged additions |
| 2 | `scripts/ingress/` home — bootstrap foreign ingress boundary (`input.id`, `output.id`, `arg.id`) |

| # | directive |
|---|---|
| 1 | `gate/architecture.id` must **not** host `hostread`, `hostargs`, `hostenv`, or other host spelling census rows. |
| 2 | That is the same antipattern as `suffix()`, `readface`, and admission string detectors. |
| 3 | Host semantic verdicts belong to GAP-124 graph obligations. |

| # | directive |
|---|---|
| 1 | Production authority: |

| # | directive |
|---|---|
| 1 | native graph must not contain host namespace authority |
| 2 | environment reads require environment facts + world |
| 3 | process execution requires structured command + process world |
| 4 | argument access resolves root-projected args value |
| 5 | structured command execution requires exact provider reach plus independent process authority |

| # | directive |
|---|---|
| 1 | Spelling mutation must not evade these invariants. |

| section |
|---|---|
| Agent pre-write law |

| # | directive |
|---|---|
| 1 | Before writing code involving argv, env, filesystem, process, pipe, shell, transport, terminal, command, cwd, PATH, or backend, state: |

```text
semantic subject
canonical relation
world requirement
home/root projection
foreign ingress/egress boundary
demand
possible zero-cost realization
```

| # | directive |
|---|---|
| 1 | If unavailable: `SEMANTIC-VOCABULARY-BLOCKED` or `IMPLEMENTATION-BLOCKED`. |

| # | directive |
|---|---|
| 1 | Do not reach for host APIs. |

| section |
|---|---|
| Absolute closure |

```text
There is no native os.args()    — use os.args[n] under os world
There is no native os.getenv   — use os.env[k]; environment is not a thing
There is no native io.read     — use stdin:read() / path:read(); never readable adjective
There is no native popen       — commands are structured values under process authority
There is no stdin-only architecture — input/output/error are endpoint values
There is no core namespace     — vocabulary is direct canonical reachability
There is no module/import/use/using/inject — homes establish reachability
Shell is interpretation law, not source law, grammar, home, world, or authority
Bare commands resolve only through exact reached providers; execution separately requires process authority
Host APIs exist only at ingress/egress realization boundaries
```

| # | directive |
|---|---|
| 1 | Pipeline: |

```text
.id → graph → demand → realization → machine
```

| # | directive |
|---|---|
