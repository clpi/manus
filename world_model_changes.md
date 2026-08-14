# World Model Changes — Eliminating String Maps and Host Semantic Selection

## P0-A — Effect→World Facts Mapping

The canonical effectful relations and their exact authority requirements:

| Canonical Relation | Subject | World | Authority Requirement | Graph Fact |
|-------------------|---------|-------|----------------------|------------|
| `env("HOME")` | `env` | `os` | `os.env` table under `os` world | `os:env(key)` application |
| `args(1)` | `args` | `os` | `os.args` table under `os` world | `os:args(n)` application |
| `stdin:read()` | `stdin` | `io` | `io.stdin` endpoint under `io` world | `stdin:read()` application |
| `stdout:write(text)` | `stdout` | `io` | `io.stdout` endpoint under `io` world | `stdout:write(text)` application |
| `stderr:write(text)` | `stderr` | `io` | `io.stderr` endpoint under `io` world | `stderr:write(text)` application |
| `path:read()` | `path` | `fs` | `fs.read` relation under `fs` world | `path:read()` application |
| `path:write()` | `path` | `fs` | `fs.write` relation under `fs` world | `path:write()` application |
| `path:open()` | `path` | `fs` | `fs.open` relation under `fs` world | `path:open()` application |
| `path:exists()` | `path` | `fs` | `fs.exists` relation under `fs` world | `path:exists()` application |
| `command:run()` | `command` | `process` | `process.run` relation under `process` world | `command:run()` application |
| `path:stat()` | `path` | `fs` | `fs.stat` relation under `fs` world | `path:stat()` application |
| `path:mkdir()` | `path` | `fs` | `fs.mkdir` relation under `fs` world | `path:mkdir()` application |

**CRITICAL:** NO relation→"io"/"process"/"filesystem" string maps. Authority requirement is FACT/ID based.

---

## P0-B — World as Role, Not Object Taxonomy

**DELETE/PREVENT** these object taxonomies when they merely group authority facts:
- World (as class/kind)
- ReadonlyWorld
- FileWorld  
- Sandbox
- Capability
- Provider
- Service
- HostContext
- WorldRegistry
- `io`, `os`, `fs` as namespace dispatchers

**World is ROLE:** authority-bearing facts/witnesses.

---

## P0-G — Shell is Interpretation Law, Not Runtime Ontology

Shell is interpretation law for bare commands. Process is authority for structured execution.

```text
shell law + command structure → command value
command:run() requires process world
```

Shell home is a **context boundary**, not a runtime object.

---

## No String World Maps

The following patterns are VIOLATIONS that must be eliminated:

### VIOLATION: Namespace-first dispatch
```
io.read(source)      WRONG — io is namespace, not world
os.getenv(key)       WRONG — os is namespace, not world  
fs.open(path)        WRONG — fs is namespace, not world
```

### CORRECT: Subject-first relations
```
source:read()        CORRECT — stdin is actual subject
os.env["KEY"]        CORRECT — os.env is world-typed table
path:open()          CORRECT — path is actual subject
```

---

## Current String Map Violations (from hostcensus)

Total violations: 13,030

| Pattern | Count | Status |
|---------|-------|--------|
| `std.` | 12,140 | Migration debt |
| `os.execute` | 39 | VIOLATION |
| `io.popen` | 49 | VIOLATION |
| `io.read(` | 29 | VIOLATION |
| `io.write(` | 106 | VIOLATION |
| `io.open(` | 48 | VIOLATION |
| `os.getenv(` | 56 | VIOLATION |
| `os.args(` | 18 | VIOLATION |
| `proc.` | 83 | VIOLATION |
| `core.` | 25 | VIOLATION |

---

## Implementation Changes Required

### 1. lib/os.id — Environment and Arguments

**Current (VIOLATION):**
```id
getenv(name: str): any
    if name == nil
        return ""
    v = os.env(name)  # Uses os.env as function namespace
    ...
end

args(): any
    os.args              # Returns table but name is wrong
end
```

**Required:**
```id
# Environment access under os world
env: str = (key: str)
    os.env[key]  # Table access under os world

# Arguments under os world
args: any = (n: i64)
    os.args[n]   # Table access under os world
```

**Why this is correct:**
- `os.env` is a launcher-projected world table (`docs/spec/host.md`)
- `os.args` is a launcher-projected world table (`docs/spec/host.md`)
- No namespace dispatch — direct subject access

---

### 2. lib/fs.id — File System Relations

**Current (VIOLATION):**
```id
mkdir(path: str): bool
    if path == nil return false end
    return @c.emit("mkdir(path, 0777) == 0")  # Direct host syscall
end

mkdirall(path: str): bool
    if path == nil return false end
    os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")  # Shell API
end

read_dir(path: str): any
    f = io.popen("ls -1A '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null", "r")  # Shell API
    ...
end

path: str:len(): i64
    f = io.popen("stat -c%s '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null", "r")  # Shell API
    ...
end
```

**Required:**
```id
# These should be projections onto fs world relations
exists: bool = (path: str)
    path:exists()  # Subject-first: path possesses exists relation

mkdir: bool = (path: str)
    path:mkdir()   # Subject-first: path possesses mkdir relation

read_dir: any = (path: str)
    path:list()    # Subject-first: path possesses list relation

stat: i64 = (path: str)
    path:stat()    # Subject-first: path possesses stat relation
```

**Why this is correct:**
- `path` is the actual subject of the relations
- filesystem authority is an application witness, not a relation-row `world = "fs"` string
- No shell commands, no `@c.emit`, no host API calls in the source

---

### 3. lib/os/process.id — Process Execution

**Current (VIOLATION):**
```id
start(proc: any, config: any): any
    full_cmd = config.cmd
    for arg in config.args
        full_cmd = full_cmd .. " " .. arg:to(str)
    end
    env_prefix = ""
    for k, v in config.env
        env_prefix = env_prefix .. k .. "=" .. v:to(str) .. " "
    end
    handle = io.popen(env_prefix .. full_cmd .. " 2>&1 & echo $!")  # Shell API!
    ...
end

run(cmd: str, args: any): any
    ...
    f = io.popen(full_cmd .. " 2>&1; echo \"\\n$?\"", "r")  # Shell API!
    ...
end
```

**Required:**
```id
# Process world with structured command
command: { line: str, args: any, env: any, cwd: str } = (line: str, args: any?, env: any?, cwd: str?)
    { 
        line = line,
        args = args or {},
        env = env or {},
        cwd = cwd or nil
    }

run: { outcome: str, status: i64 } = (cmd: command)
    # Implementation in host runtime using proper process API
    # NOT shell commands
    ...

# Evidence/capture as execution result
output: str = (cmd: command)
    result = cmd:run()
    result.output
```

**Why this is correct:**
- `command` is a structured value with proper attributes
- `run` is a semantics operation on the command value
- Process world provides the authority
- No shell escape hatch

---

### 4. lib/script.id — BOOTSTRAP DEBT (DELETE)

This file is FROZEN DEBT per GAP-155. It must:

1. NOT be used for normal Idol code
2. Be replaced by `scripts/ingress/` boundary for bootstrap needs
3. Eventually be deleted or migrated

---

## Host Boundary Authority (P0-E)

**The host decides what to PROVIDE at the boundary. Idol decides what to USE.**

### Host Provides (at startup):
- `os.args` — argument table
- `os.env` — environment table  
- `stdin` — input endpoint
- `stdout` — output endpoint
- `stderr` — error endpoint
- `cwd` — current working directory

### Idol Uses:
```id
# Environment
home = os.env["HOME"]   # Table access under os world

# Arguments  
program = os.args[1]    # Table access under os world

# stdin
text = stdin:read()     # Subject-first relation

# stdout
stdout:write(text)      # Subject-first relation
```

**Host must NOT decide which relation runs, which world is used, which target.**
The host only provides the world tables and endpoints. The semantic authority
belongs to the graph.

---

## Positive Controls

To demonstrate correct world authority, these patterns must work:

```id
# Environment access - os world
os.env["HOME"]:to(str)

# Arguments - os world
os.args[1]:to(str)

# File read - fs world  
path:read()

# File write - fs world
path:write(data)

# Process run - process world
cmd = command("git", ["status"], nil, nil)
result = cmd:run()
```

Negative controls (must be rejected):
- `os.getenv("HOME")` - forbidden host API
- `io.read()` - forbidden namespace dispatch
- `io.popen(...)` - forbidden shell API
- `os.execute(...)` - forbidden host API
- `@c.emit("mkdir(...")` - forbidden host API

---

## Migration Path

### Phase 1: Gate Enforcement
- `gate/host.id` continues to block new violations
- No new `os.args()`, `os.getenv()`, `io.read()`, etc. added

### Phase 2: Library Rewrite
- Rewrite `lib/fs.id` to use subject-first relations
- Rewrite `lib/os/process.id` to use process world
- Keep `lib/script.id` frozen (GAP-155)

### Phase 3: Runtime Bridge Implementation
- Host runtime provides proper `fs` world implementation
- Host runtime provides proper `process` world implementation
- Shell bridges become optional, not required

### Phase 4: Bridge Deletion (GAP-155 Closure)
- Delete `lib/script.id`
- Remove `gate/bootstrap.capture` from normal use (keep for gates only)
- Shell bridges have deletion conditions met

---

## Conclusion

The world model change eliminates string-based namespace dispatch by:

1. Making worlds literal `os`, `io`, `fs`, `process` table values provided at execution
2. Making every effectful operation a subject-first relation on a possessed value
3. Eliminating host API calls from project library code
4. Moving shell execution to structured command world with proper authority

This achieves the mission: **world authority is exact graph data, not host/platform machinery.**