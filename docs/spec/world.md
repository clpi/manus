| field | value |
|---|---|
| title | Idol world and run projection |

| # | directive |
|---|---|
| 1 | Apply with `docs/spec/host.md`, `docs/spec/source.md`, and C0 §67 (`law.projection.one`, `law.world.one`, `law.world.grant`, `law.shell.not.world`). |

| # | directive |
|---|---|
| 1 | This document is normative teaching. |
| 2 | It must pass SUBJECT-ONE and OPERATION-ONE (`law.doc.teaching`). |
| 3 | If it conflicts with C0, C0 wins. |

| section |
|---|---|
| One projection algebra |

| # | directive |
|---|---|
| 1 | World authority, shell interpretation, command values, endpoint I/O, and process execution are **ordinary semantic facts** over one application algebra — not separate namespace systems. |

```text
relation · projection · subject · operands · result demand · descriptor · law
· world requirement · world witness · effect · origin · provenance
```

| # | directive |
|---|---|
| 1 | Physical realization comes later. |

| section |
|---|---|
| Projection, injection, interjection |

| # | directive |
|---|---|
| 1 | Projection, injection, and interjection are three uses of ordinary world/table semantics — not three subsystems. |
| 2 | See `docs/spec/law.md` §5a–§5f and C0 `law.projection.algebra`. |
| 3 | No inject, scope, context, provider, registry, or dependency framework is introduced. |

```text
@x               access      select one exact static fact/member
@{ k = v }       inject      derive a closed world with exact fact deltas
thing@world      qualify     evaluate thing under world
thing@{ k = v }  interject   evaluate thing under an injected world
@k = v           mutate      obtain a world member as a place and mutate it
@(expr)          stage       apply the current world to an expression — that
                             expression resolved under it, at the stage the
                             world carries
```

| # | directive |
|---|---|
| 1 | The last row is the one that keeps `@` a single algebra. |
| 2 | Compile-time evaluation is not a directive and not a sixth mechanism: stage is a fact a world carries (`law.md` §6), so evaluating at the compile stage is evaluating under a world whose stage fact is `comp`, and |

```text
@(expr)  ==  expr@{ stage = compile }
```

| # | directive |
|---|---|
| 1 | is an identity between two spellings. `@` + pack derives a world; `@` + expression resolves that expression under the world — one prefix meaning, one application algebra, two operand kinds. |
| 2 | Two consequences are worth spelling out. |
| 3 | An operation whose entire content is "do this at compile time" is an ordinary relation applied under a stage-delta world, so `@comp.*` has somewhere lawful to go. |
| 4 | And a value that does not exist at the compile stage is simply not a fact of that world, refused by the same no-fallthrough rule as any other derived-world lookup rather than by a special compile-time-constant diagnostic. |
| 5 | See C0 `law.stage.world`. |

| # | directive |
|---|---|
| 1 | `expr@{ stage = compile }` is the canonical face and `@(expr)` is retained compatibility with exact provenance; both build one node, and the printer writes back the one that was written. |
| 2 | The algebra's identities are executable on running programs — `sh gate/world/stage.sh`: |

```id
print(@(1 + 2))                                        # 3
print((1 + 2)@{ stage = compile })                     # 3, same node
print(5@{})                                            # 5   derive(W, {}) = W
print((1 + 2)@{ stage = compile }@{ stage = compile })  # 3   reinjection is idempotent
print(@(cwd()))                                        # refused: absent at this stage
```

| # | directive |
|---|---|
| 1 | The last line is the one that shows a stage was involved at all. `cwd()` runs perfectly well; it is simply not a fact of the compile-stage world, and the derived world does not fall through to the one it was derived from. |

| # | directive |
|---|---|
| 1 | Only the stage delta resolves today. `expr@{ tax = 1 }` refuses and names the missing fact — `WorldFact` carries no parent and no fact-delta range, so a world derived on an ordinary member cannot be represented (gap[203] closure item 1). |
| 2 | A duplicate member in one literal is an error, and a positional entry names no fact. |

| # | directive |
|---|---|
| 1 | `@` is itself the accessor: write `@x`, never `@.x`; `@.x` and `@:x` are INVALID because `@` already performs the access. `.` is one static step, always — one filesystem child level or one static member — so `@x.y` is one world access then one ordinary projection. |
| 2 | A bare name may infer as a static access of the current world when no lexical binding supplies the meaning: |

```id
tax(sum)
```

| # | directive |
|---|---|
| 1 | resolves exactly as `@tax(sum)` when unique. |
| 2 | Spell `@tax` only when the distinction matters — for example a lexical `tax` shadows the ambient member. |

| # | directive |
|---|---|
| 1 | Injection derives a new closed world; the source world is unchanged: |

```id
trial = @{
    tax = (sum) 0
}
```

| # | directive |
|---|---|
| 1 | `trial` receives every current-world fact except that its `tax` projection is the supplied value. |
| 2 | Resolution does not search `trial` and then fall back to the root world — the deltas are established when the world is formed. |
| 3 | Empty injection is identity, injecting the exact existing fact is idempotent, and a duplicate member in one literal is an error. |

| # | directive |
|---|---|
| 1 | Interjection needs no new syntax — `thing@{ k = v }` is `thing@(@{ k = v })`: |

```id
sale.quote@{
    tax = (sum) 0
}(100)
```

| # | directive |
|---|---|
| 1 | runs `sale.quote(100)` under a derived world whose `tax` fact is replaced, then the caller's world is unchanged. |

| section |
|---|---|
| World qualification and scope |

| # | directive |
|---|---|
| 1 | `thing@world` evaluates the whole expression world-relative: |

```id
(sale.quote@trial)(100)
```

| # | directive |
|---|---|
| 1 | resolves `sale.quote` under `trial`, then applies. |
| 2 | Inside, bare `@` is `trial`. |
| 3 | A world-qualified application threads its world through unresolved ambient dependencies in that subtree without a runtime world argument. |
| 4 | Dot binds after qualification: `thing@world.member` is `(thing@world).member`; use `thing@(world.member)` when the world expression is itself nested. |

| # | directive |
|---|---|
| 1 | Lexical binding wins for a bare lexical name; `@x` accesses the world member explicitly. |
| 2 | There is no ambiguous search or fallback chain — the resolver sees one closed lexical + world fact set once and records exact ids. |

| section |
|---|---|
| Ambient mutation versus interjection |

| # | directive |
|---|---|
| 1 | `@k = v` obtains a world member as a place and mutates it — legal only when the application yields a place. |
| 2 | Mutation is persistent and observed by every alias of that world identity. |
| 3 | Prefer interjection for scoped replacement: |

```id
sale.quote@{
    fee = 0
}(100)
```

| # | directive |
|---|---|
| 1 | Mutate the ambient world only when the persistent state change is itself the meaning, and pair the mutation with restoration when a scope is intended: |

```id
prior = @fee
@fee = 0
amount = sale.quote(100)
@fee = prior
amount
```

| # | directive |
|---|---|
| 1 | Here `prior` and `amount` both carry independent meaning — INTERMEDIATE-ZERO correctly keeps them, and no scope-helper identity is invented. |

| section |
|---|---|
| Example world project |

| # | directive |
|---|---|
| 1 | Physical tree — no package, import, require, module, namespace, or main function; `main/` is the physical source root and `main/lib.id` its root table body: |

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

| # | directive |
|---|---|
| 1 | Semantically: `retail` uses root tax 10% and root fee 5; `waiver` uses `trial` tax 0 with inherited fee 5; `coupon` uses root tax 10% with interjected fee 0; `gift` runs `pick` under `trial`, so tax 0 then interjected fee 0. |
| 2 | Yet the machine program can collapse the whole chain to a known `tax` relation, a known `fee`, and direct arithmetic — no runtime world object. |

| section |
|---|---|
| Projection and injection edge cases |

| # | directive |
|---|---|
| 1 | Missing access (`@missing`) fails; there is no parent-directory, other- world, global-registry, library, or default-namespace fallback. |
| 2 | A world cannot hold two incomparable static definitions for one member and silently choose — explicit disambiguation is required. |
| 3 | `.` is never computed; a runtime aggregate key uses projection `table[key]`. |
| 4 | `able` is an inferred boundary constraint, not a world member — never inject it as a fact. |
| 5 | Only a valid witness satisfies authority; a label, boolean, or string cannot manufacture it. |

| section |
|---|---|
| Naming worlds and homes |

| # | directive |
|---|---|
| 1 | Do not name a world or member after the fact it injects. |
| 2 | Prefer a genuine domain scenario world (`trial`) that injects `tax` inside it over a world named for tax-freeness; inject `clock` rather than naming a member after a stand-in clock. |
| 3 | A name survives only if it is an independently meaningful entity — world differences belong to world facts. |
| 4 | Directories are static tables, not category buckets: prefer paths whose every segment is a real projected entity (`sale/quote.id`, `target/arm.id`). |

| section |
|---|---|
| A world is a closed semantic table; authority is one fact class within it |

| # | directive |
|---|---|
| 1 | A **world** is an ordinary closed semantic table under which meaning is resolved (`docs/spec/law.md` §3 + World+projection add-on). |
| 2 | It may contain values, relations, descriptors, other worlds, stage/target facts, and authority facts. **A world is not synonymous with authority** — authority is one class of fact inside a world, and world availability *validates* that authority after intent is resolved. `@` is the current world. |

| # | directive |
|---|---|
| 1 | Worlds are **not**: |

| # | directive |
|---|---|
| 1 | authority objects (authority is a fact within the world, not its identity) |
| 2 | namespace imports |
| 3 | module tables |
| 4 | organizational receivers (`os.foo`, `io.bar`) |
| 5 | method lookup targets |

| # | directive |
|---|---|
| 1 | Do not bundle unrelated authority merely because a host API bundled it. |
| 2 | Avoid canonical monolithic `os` and `io` worlds when finer authority facts suffice: |

```text
filesystem · process · environment · clock · network · device
```

| # | directive |
|---|---|
| 1 | World availability **validates** authority after semantic intent is resolved. |
| 2 | World availability must **never** choose conversion target, parser, relation, or descriptor. |

| section |
|---|---|
| Ambient world injection |

| # | directive |
|---|---|
| 1 | A relation declares its world requirement. |
| 2 | Current context supplies grants. |

| # | directive |
|---|---|
| 1 | When exactly one compatible grant exists, inject the witness — source need not name the world: |

```id
file = path:open()
```

| # | directive |
|---|---|
| 1 | Graph facts: `open` subject `path`, world filesystem, witness `W`, result `file`. |

| # | directive |
|---|---|
| 1 | Forbidden namespace receivers: |

```id
fs.open(path)
io.open(path)
os.open(path)
```

| section |
|---|---|
| Ambient context values |

| # | directive |
|---|---|
| 1 | When unique world context projects these values, prefer direct use: |

```id
args[1]
env["KEY"]
stdout:write(text)
clock:now()
stdin:read()
```

| # | directive |
|---|---|
| 1 | over organizational spellings: |

```id
os.args[1]
os.env["KEY"]
io:write(text)
```

| # | directive |
|---|---|
| 1 | RETRACTED under world reconciliation v2. |
| 2 | This read: "**`stdout` is a possessed endpoint subject** — legitimate receiver for `write`. **`io` is organizational authority** — not a substitute subject." v2 rules that `io` IS an ordinary world value and a legitimate subject, and that `stdout` is host provenance rather than a native semantic concept. |
| 3 | A stream that genuinely is the subject still takes the relation — `file:write(data)` — but `io:write(x)` is canonical for a stream-less write. |

| # | directive |
|---|---|
| 1 | Bootstrap ingress may still use `io:read()` in gate transport until root projection executes; that is not canonical teaching. |

| section |
|---|---|
| Subject-first path and file relations |

| # | directive |
|---|---|
| 1 | Path and file values possess relations directly: |

```id
text = path:read()
path:open("w"):write(text)
src:copy(dst)
```

| # | directive |
|---|---|
| 1 | Audit `path:exists()` under PREDICATE-ZERO (`law.predicate.zero`): if existence merely routes control flow, consume the richer path/state/result relation instead of preserving a boolean helper API. |

| # | directive |
|---|---|
| 1 | Forbidden on new canonical lines: |

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

| section |
|---|---|
| Shell and process (SHELL-NOT-WORLD) |

| # | directive |
|---|---|
| 1 | Shell is **interpretation law**. |
| 2 | Process is **authority**. |
| 3 | Command is a **semantic value**. |
| 4 | Do not combine them into one namespace. |

```text
shell law + command structure → command value
command:run() requires process world
```

| # | directive |
|---|---|
| 1 | `capture` is usually **run + output demand**, not a second execution relation. |

```id
c = command("git status")
stream = c:open("r")
text = stream:read()
stream:close()
```

| # | directive |
|---|---|
| 1 | Not `io.popen`, not `process.capture`. |

| section |
|---|---|
| Protocol constraints are projections |

| # | directive |
|---|---|
| 1 | Relation constraints demand relation facts — not adjective protocols: |

```id
consume = (source: read)
    source:read()
```

| # | directive |
|---|---|
| 1 | Not `source: readable`. |
| 2 | Protocol satisfaction does **not** grant world authority. |
| 3 | Relation witness and world witness are separate. |

| section |
|---|---|
| Gate transport (bootstrap only) |

| # | directive |
|---|---|
| 1 | Gate scripts read stdin and optional path args through world relations — no shell wrappers. |
| 2 | Curried gate helpers (`len(path)(min)`) are **migration transport**, not stylistic law — genuine curry only when the intermediate callable has semantic value (`law.curry.structural`). |

```id
path = args(1)
text = stdin:read()
if path:len() > 0
    text = path:read()
```

| section |
|---|---|
| STD-ZERO / LIB-ZERO |

| # | directive |
|---|---|
| 1 | No canonical `std.*` or `lib.*` semantic hop. |
| 2 | Repository `lib/` path is bootstrap provenance only. |
| 3 | If tooling cannot reach a binding without `lib.*`: `SOURCE-PROJECTION-BLOCKED` — fix reachability, do not canonize the workaround. |

| section |
|---|---|
| Enforcement |

| # | directive |
|---|---|
| 1 | `law.gate.projection` — REDUNDANT-PROJECTION-ZERO, FROM-ZERO, STD-ZERO, LIB-ZERO, WORLD-NAMESPACE-ZERO, PROTOCOL-ADJECTIVE-ZERO |
| 2 | `gate/idiom.id`, `gate/host.id` — migration pressure on added lines |
| 3 | Graph verdicts when GAP-124 closes |

| section |
|---|---|
| Deletion gate |

| # | directive |
|---|---|
| 1 | When GAP-124 graph obligations prove world authority on every edge, delete lexical rows in favor of graph verdicts. |
