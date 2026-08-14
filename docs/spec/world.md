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

## Projection, injection, interjection

Projection, injection, and interjection are three uses of ordinary world/table
semantics — not three subsystems. See `docs/spec/law.md` §5a–§5f and C0
`law.projection.algebra`. No inject, scope, context, provider, registry, or
dependency framework is introduced.

```text
@x               access      select one exact static fact/member
@{ k = v }       inject      derive a closed world with exact fact deltas
thing@world      qualify     evaluate thing under world
thing@{ k = v }  interject   evaluate thing under an injected world
@k = v           mutate      obtain a world member as a place and mutate it
```

`@` is itself the accessor: write `@x`, never `@.x`; `@.x` and `@:x` are INVALID
because `@` already performs the access. `.` is one static step, always — one
filesystem child level or one static member — so `@x.y` is one world access then
one ordinary projection. A bare name may infer as a static access of the current
world when no lexical binding supplies the meaning:

```id
tax(sum)
```

resolves exactly as `@tax(sum)` when unique. Spell `@tax` only when the
distinction matters — for example a lexical `tax` shadows the ambient member.

Injection derives a new closed world; the source world is unchanged:

```id
trial = @{
    tax = (sum) 0
}
```

`trial` receives every current-world fact except that its `tax` projection is
the supplied value. Resolution does not search `trial` and then fall back to the
root world — the deltas are established when the world is formed. Empty injection
is identity, injecting the exact existing fact is idempotent, and a duplicate
member in one literal is an error.

Interjection needs no new syntax — `thing@{ k = v }` is `thing@(@{ k = v })`:

```id
sale.quote@{
    tax = (sum) 0
}(100)
```

runs `sale.quote(100)` under a derived world whose `tax` fact is replaced, then
the caller's world is unchanged.

## World qualification and scope

`thing@world` evaluates the whole expression world-relative:

```id
(sale.quote@trial)(100)
```

resolves `sale.quote` under `trial`, then applies. Inside, bare `@` is `trial`.
A world-qualified application threads its world through unresolved ambient
dependencies in that subtree without a runtime world argument. Dot binds after
qualification: `thing@world.member` is `(thing@world).member`; use
`thing@(world.member)` when the world expression is itself nested.

Lexical binding wins for a bare lexical name; `@x` accesses the world member
explicitly. There is no ambiguous search or fallback chain — the resolver sees
one closed lexical + world fact set once and records exact ids.

## Ambient mutation versus interjection

`@k = v` obtains a world member as a place and mutates it — legal only when the
application yields a place. Mutation is persistent and observed by every alias of
that world identity. Prefer interjection for scoped replacement:

```id
sale.quote@{
    fee = 0
}(100)
```

Mutate the ambient world only when the persistent state change is itself the
meaning, and pair the mutation with restoration when a scope is intended:

```id
prior = @fee
@fee = 0
amount = sale.quote(100)
@fee = prior
amount
```

Here `prior` and `amount` both carry independent meaning — INTERMEDIATE-ZERO
correctly keeps them, and no scope-helper identity is invented.

## Example world project

Physical tree — no package, import, require, module, namespace, or main
function; `main/` is the physical source root and `main/lib.id` its root table
body:

```text
market/
    main/
        lib.id
        tax.id
        trial.id
        pick.id
        sale/
            quote.id
```

```id
# main/tax.id — the file body is the value of root member tax
(sum) sum / 10
```

```id
# main/sale/quote.id — tax and fee infer as ambient world projections
(sum)
    sum + tax(sum) + fee
```

```id
# main/trial.id — a derived world replacing only tax
@{
    tax = (sum) 0
}
```

```id
# main/pick.id — interjection: quote under current world + fee = 0
()
    sale.quote@{
        fee = 0
    }(100)
```

```id
# main/lib.id — world composition without a dependency framework
fee = 5
retail = sale.quote(100)
waiver = (sale.quote@trial)(100)
coupon = pick()
gift = (pick@trial)()
{ retail, waiver, coupon, gift }
```

Semantically: `retail` uses root tax 10% and root fee 5; `waiver` uses `trial`
tax 0 with inherited fee 5; `coupon` uses root tax 10% with interjected fee 0;
`gift` runs `pick` under `trial`, so tax 0 then interjected fee 0. Yet the
machine program can collapse the whole chain to a known `tax` relation, a known
`fee`, and direct arithmetic — no runtime world object.

## Projection and injection edge cases

- Missing access (`@missing`) fails; there is no parent-directory, other-
  world, global-registry, library, or default-namespace fallback.
- A world cannot hold two incomparable static definitions for one member and
  silently choose — explicit disambiguation is required.
- `.` is never computed; a runtime key uses application `table(key)`.
- `able` is an inferred boundary constraint, not a world member — never inject it
  as a fact.
- Only a valid witness satisfies authority; a label, boolean, or string cannot
  manufacture it.

## Naming worlds and homes

Do not name a world or member after the fact it injects. Prefer a genuine domain
scenario world (`trial`) that injects `tax` inside it over a world named for
tax-freeness; inject `clock` rather than naming a member after a stand-in clock.
A name survives only if it is an independently meaningful entity — world
differences belong to world facts. Directories are static tables, not category
buckets: prefer paths whose every segment is a real projected entity
(`sale/quote.id`, `target/arm.id`).

## A world is a closed semantic table; authority is one fact class within it

A **world** is an ordinary closed semantic table under which meaning is resolved
(`docs/spec/law.md` §3 + World+projection add-on). It may contain values,
relations, descriptors, other worlds, stage/target facts, and authority facts.
**A world is not synonymous with authority** — authority is one class of fact
inside a world, and world availability *validates* that authority after intent is
resolved. `@` is the current world.

Worlds are **not**:

- authority objects (authority is a fact within the world, not its identity)
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
- `gate/idiom.id`, `gate/host.id` — migration pressure on added lines
- Graph verdicts when GAP-124 closes

## Deletion gate

When GAP-124 graph obligations prove world authority on every edge, delete
lexical rows in favor of graph verdicts.
