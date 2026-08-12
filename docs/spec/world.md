# Idol world and run projection

Apply with `docs/spec/host.md`, `docs/spec/source.md`, and C0 §67
(`law.projection.one`, `law.world.one`, `law.world.grant`, `law.shell.not.world`).

This document is normative teaching. It must pass SUBJECT-ONE and OPERATION-ONE
(`law.doc.teaching`). If it conflicts with C0, C0 wins.

## One projection algebra

World authority, shell interpretation, command values, endpoint I/O, and process
execution are **ordinary semantic facts** over one application algebra — not
separate namespace systems.

```text
relation · projection · subject · operands · result demand · descriptor · law
· world requirement · world witness · effect · origin · provenance
```

Physical realization comes later.

## Worlds are authority, not namespaces

A **world** grants irreducible authority required by a relation application.

Worlds are **not**:

- namespace imports
- module tables
- organizational receivers (`os.foo`, `io.bar`)
- method lookup targets

Do not bundle unrelated authority merely because a host API bundled it. Avoid
canonical monolithic `os` and `io` worlds when finer authority facts suffice:

```text
filesystem · process · environment · clock · network · device
```

World availability **validates** authority after semantic intent is resolved.
World availability must **never** choose conversion target, parser, relation, or
descriptor.

## Ambient world injection

A relation declares its world requirement. Current context supplies grants.

When exactly one compatible grant exists, inject the witness — source need not
name the world:

```id
file = path:open()
```

Graph facts: `open` subject `path`, world filesystem, witness `W`, result `file`.

Forbidden namespace receivers:

```id
fs.open(path)
io.open(path)
os.open(path)
```

## Ambient context values

When unique world context projects these values, prefer direct use:

```id
args(1)
env("KEY")
stdout:write(text)
clock:now()
stdin:read()
```

over organizational spellings:

```id
os.args(1)
os.env("KEY")
io:write(text)
```

**`stdout` is a possessed endpoint subject** — legitimate receiver for `write`.
**`io` is organizational authority** — not a substitute subject.

Bootstrap ingress may still use `io:read()` in gate transport until root
projection executes; that is not canonical teaching.

## Subject-first path and file relations

Path and file values possess relations directly:

```id
text = path:read()
path:open("w"):write(text)
src:copy(dst)
```

Audit `path:exists()` under PREDICATE-ZERO (`law.predicate.zero`): if existence
merely routes control flow, consume the richer path/state/result relation instead
of preserving a boolean helper API.

Forbidden on new canonical lines:

```id
os.args()
os.getenv(name)
environment("KEY")
io.read("*a")
io.write(data)
io.open(path, "r")
os.exit(1)
os.execute(cmd)
std.*
lib.*
process.run(...)
process.capture(...)
process.exit(...)
process = lib.process
```

## Shell and process (SHELL-NOT-WORLD)

Shell is **interpretation law**. Process is **authority**. Command is a **semantic
value**. Do not combine them into one namespace.

```text
shell law + command structure → command value
command:run() requires process world
```

`capture` is usually **run + output demand**, not a second execution relation.

```id
c = command("git status")
stream = c:open("r")
text = stream:read()
stream:close()
```

Not `io.popen`, not `process.capture`.

## Protocol constraints are projections

Relation constraints demand relation facts — not adjective protocols:

```id
consume = (source: read)
    source:read()
```

Not `source: readable`. Protocol satisfaction does **not** grant world authority.
Relation witness and world witness are separate.

## Gate transport (bootstrap only)

Gate scripts read stdin and optional path args through world relations — no shell
wrappers. Curried gate helpers (`len(path)(min)`) are **migration transport**,
not stylistic law — genuine curry only when the intermediate callable has semantic
value (`law.curry.structural`).

```id
path = args(1)
text = stdin:read()
if path:len() > 0
    text = path:read()
```

## STD-ZERO / LIB-ZERO

No canonical `std.*` or `lib.*` semantic hop. Repository `lib/` path is bootstrap
provenance only. If tooling cannot reach a binding without `lib.*`:
`SOURCE-PROJECTION-BLOCKED` — fix reachability, do not canonize the workaround.

## Enforcement

- `law.gate.projection` — REDUNDANT-PROJECTION-ZERO, FROM-ZERO, STD-ZERO,
  LIB-ZERO, WORLD-NAMESPACE-ZERO, PROTOCOL-ADJECTIVE-ZERO
- `gates/idiom.id`, `gates/host.id` — migration pressure on added lines
- Graph verdicts when GAP-124 closes

## Deletion gate

When GAP-124 graph obligations prove world authority on every edge, delete
lexical rows in favor of graph verdicts.
