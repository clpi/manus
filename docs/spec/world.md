# Idol world invocation law

Apply with `docs/spec/host.md` and `docs/spec/source.md`.

## Law

`os` and `io` are **worlds** (authority carriers), not namespaces or runtime
module tables.

**No `std` anywhere.** The `std` table, namespace, and `std.*` spellings are
deleted (GAP-157). Vocabulary is layout-projected homes and worlds only.

`args` is an ordinary table under the `os` world — not a host function call,
not a separate root singleton, not `environment`.

### Forbidden

```id
os.args()
os.getenv(name)
environment["KEY"]
environment:at("KEY")
io.read("*a")
io.write(data)
io.open(path, "r")
os.exit(1)
os.execute(cmd)
std.io.open(path)
std.os.getenv(name)
@c.emit("...")
@comp.c.emit("...")
lua_io_read(...)
[[ long bracket strings ]]
```

Dot before `(` on a world name is namespace-method syntax — it erases world
authority.

Bare root spellings without world grounding when `os` world is required:

```id
args[1]          # when meaning host argv — use os.args[1]
mode = getenv(x) # use os.env[x]
```

Foreign realization (`@c*`, `@comp.c*`, explicit `lua_*` spellings) in Idol
source is forbidden. The compiler owns lowering; source states semantic demand
only.

### Allowed — `os` world table projection

```id
command = os.args[1]
target = os.args[2]

mode = os.env["IDOLTREE"]
flag = os.env(key)
os.env["KEY"] = value
os.env(key) = value
```

### Allowed — path subject-first relations

Path values possess fs relations; read through subject-first method chains:

```id
path:read()
    :match(pattern)
path:read()
    :len() >= min
scratch:open("w")
src:copy(dst)
path:exists()
path:remove()
```

Gate path-boundary helpers curry the path string first, then the criterion:

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
if code == 0 and !audit(proof["resident"])("path:read%(")
if code == 0 and hit(proof["remove"])("fs:")
```

Never flat `len(path, min)`, `audit(path, pattern)`, `hit(path, pattern)`, or
`len: bool = (path, min)` bridge bindings. Break read chains across lines — no
`:read():match` on one line, no `text = path:read()` transitive bindings.

Prefix `!` is canonical negation — `if !expr`, `and !expr`, `(!expr)`. Never
`if not`, `and not`, `or not`, or `(not expr)` on added teaching lines.

`io:read()` with no path remains the stdin endpoint for gate transport only.

### Allowed — `io` world subject-first relations

```id
line = io:read()
io:write(text)
```

Possessed handles keep subject-first edges:

```id
f:read("a")
f:close()
```

## Gate transport (Idol only)

Diff and IDOLGATE gates read input through world relations only — no shell
wrappers, no `gate.sh`, no `gatepath`:

```id
path = os.args[1]
text = io:read()
if path:len() > 0
    text = io:read(path)
```

Process census uses `command` + `c:open("r")` from `lib/process.id` — never
`popen` / `io:popen` spellings.


`popen` is not an Idol relation. Open a stream across the process boundary on
the command subject:

```id
c = command("git status")
stream = c:open("r")
text = stream:read("*a")
stream:close()
```

Wrong:

```id
f = io.popen("git status", "r")
f = io:popen(cmd, "r")
```

Implementation vocabulary: `lib/process.id` (`command`, `capture`).


## Enforcement

- `scripts/idiomgate.id` — `law.world.dot` + foreign-zero firewall on added lines
- `gates/host.id` — same on staged additions
- `scripts/semanticgate.id` — monotone baselines; only descend

## Deletion gate

When GAP-124 graph obligations prove world authority on every edge, delete
lexical rows in favor of graph verdicts.
