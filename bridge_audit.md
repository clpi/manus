# Bridge Audit Report — WORLD/EFFECT Authority, Host/Foreign Ingression, Bridge Deletion

**Status:** ANALYSIS — Bridge inventory and authority requirements documented

**Mission:** Make effectful Idol source look like ordinary Idol while ensuring world
authority is exact graph data and host/platform machinery has ZERO semantic
selection authority.

---

## P0-A — Effect→World Facts

For every effectful canonical relation, derive exact authority requirement in semantic resolution.

### Core Effectful Canonical Relations

| Relation | Subject | World | Authority Requirement | Graph Fact |
|----------|---------|-------|----------------------|------------|
| `env["HOME"]` | `env` | `os` | `os.env` table fact under `os` world | computed projection |
| `args[1]` | `args` | `os` | `os.args` table fact under `os` world | computed projection |
| `stdin:read()` | `stdin` | `io` | `io.stdin` endpoint fact | `io.stdin:read()` application |
| `stdout:write(text)` | `stdout` | `io` | `io.stdout` endpoint fact | `io.stdout:write(text)` application |
| `stderr:write(text)` | `stderr` | `io` | `io.stderr` endpoint fact | `io.stderr:write(text)` application |
| `path:read()` | `path` | `fs` | `fs.read` relation fact | `path:read()` application |
| `path:open()` | `path` | `fs` | `fs.open` relation fact | `path:open()` application |
| `path:write()` | `path` | `fs` | `fs.write` relation fact | `path:write()` application |
| `command:run()` | `command` | `process` | `process.run` relation fact | `command:run()` application |

**CRITICAL:** No relation→"io"/"process"/"filesystem" string maps. Authority requirement must be fact/id based.

### World Witness Facts

World witness attaches to exact application. Known witness = direct realization.

### P0-B — World Witness

| Application | Witness Type | Source |
|-------------|--------------|--------|
| `env("HOME")` | `os.env` table | Runtime-launched execution |
| `args(1)` | `os.args` table | Runtime-launched execution |
| `stdin:read()` | `stdin` endpoint | Runtime-launched execution |
| `stdout:write(text)` | `stdout` endpoint | Runtime-launched execution |
| `path:read()` | `fs.read` relation | File system access |
| `command:run()` | `process.run` relation | Shell/process execution |

### P0-C — No World Object Taxonomy

Delete/prevent these when they merely group authority facts:
- `World` - NOT a class hierarchy
- `ReadonlyWorld` - NOT a type
- `FileWorld` - NOT a type  
- `Sandbox` - NOT a type
- `Capability` - NOT a type
- `Provider` - NOT a type
- `Service` - NOT a type
- `HostContext` - NOT a type
- `WorldRegistry` - NOT a type

Restriction = witness absent. These are mere organizational constructs.

### P0-D — Platform Tables

`os/io` may be ordinary tables exposing values:
```
os.env    # table: key → value
os.args   # table: n → arg
io.stdin  # endpoint value
io.stdout # endpoint value  
io.stderr # endpoint value
```

**These are values, not API namespaces.** Meaningful relation is on possessed subject:
- `stdin:read` — subject-first
- `stdout:write` — subject-first

### P0-E — Foreign Boundary

Host implementation realizes already-selected semantic operation.

Host must NOT decide:
- which relation
- which world  
- which fallback
- which target semantics
- which descriptor

Foreign normalization ONCE: foreign facts → canonical graph facts.

---

## Bridge Census

### 1. foreign_adapter.zig

| Attribute | Value |
|-----------|-------|
| **File** | `src/foreign_adapter.zig` |
| **Responsibility** | Adapt C import SIM entities into compiler foreign descriptors |
| **Exact Facts Carried** | Entity declarations (structs, functions) from C headers |
| **Semantic Authority** | NONE — this is foreign→canonical projection |
| **Replacement Owner** | Compiler front-end SIM layer |
| **Deletion Prerequisite** | N/A — this IS the foreign projection machinery |
| **Positive Control** | `gate/idiom.id` rejects `@c.emit` in source |
| **Negative Control** | `gate/host.id` rejects `std.` namespace patterns |

**Verdict:** This is NOT an "adapter ontology debt" as mentioned in the mission. It is legitimate **foreign projection machinery** that converts C header declarations into graph facts. The file name contains "adapter" but the role is pure projection. **Should NOT be deleted.**

### 2. shell_host.zig

| Attribute | Value |
|-----------|-------|
| **File** | `src/shell_host.zig` |
| **Responsibility** | Cross-platform host shell escape hatch |
| **Exact Facts Carried** | argv for raw shell evaluation |
| **Semantic Authority** | FOREIGN REALIZATION — implements `shell()` primitive |
| **Replacement Owner** | Shell home + command projection |
| **Deletion Prerequisite** | GAP-155 — shell is interpretation law, not runtime ontology |
| **Positive Control** | `scripts/ingress/` is sole bootstrap foreign ingress |
| **Negative Control** | `gate/host.id` blocks new `os.execute` etc. |

**Verdict:** Legitimate host realization for REPL shell interface. Deletion conditional on graph world facts for structured command execution.

### 3. shell_session.zig

| Attribute | Value |
|-----------|-------|
| **File** | `src/shell_session.zig` |
| **Responsibility** | Persistent semantic shell session |
| **Exact Facts Carried** | History, export, snapshot |
| **Semantic Authority** | FOREIGN EGRESS — MCP/LSP transport |
| **Replacement Owner** | MCP transport layer |
| **Deletion Prerequisite** | GAP-124 graph world-boundary obligations |
| **Positive Control** | None |
| **Negative Control** | None |

**Verdict:** Bridge for MCP/LSP transport. Needs deletion gate per GAP-167.

### 4. lexer_bridge.zig / keyword_bridge.zig

| Attribute | Value |
|-----------|-------|
| **File** | `src/lexer_bridge.zig`, `src/keyword_bridge.zig` |
| **Responsibility** | Generated lexer routing and keyword classification |
| **Exact Facts Carried** | Token kinds, keyword classifications |
| **Semantic Authority** | NONE — pure realization acceleration |
| **Replacement Owner** | Lexer front-end |
| **Deletion Prerequisite** | None — these are realization helpers |
| **Positive Control** | None |
| **Negative Control** | None |

**Verdict:** These are NOT semantic bridges — they are **realization acceleration layers**. They project generated C/Zig lookups into the lexer. No deletion needed.

### 5. host_run.zig

| Attribute | Value |
|-----------|-------|
| **File** | `src/host_run.zig` |
| **Responsibility** | Compile-time shell command execution |
| **Exact Facts Carried** | Command output |
| **Semantic Authority** | BOOTSTRAP INGRESS — compile-time only |
| **Replacement Owner** | Graph execution or runtime command world |
| **Deletion Prerequisite** | GAP-154 — host boundary closure |
| **Positive Control** | None |
| **Negative Control** | None |

**Verdict:** Bootstrap ingress for compile-time commands. Needs deletion gate.

### 6. lib/os/process.id

| Attribute | Value |
|-----------|-------|
| **File** | `lib/os/process.id` |
| **Responsibility** | Process management via shell commands |
| **Exact Facts Carried** | Process execution, pipes |
| **Semantic Authority** | VIOLATION — uses `io.popen`, `os.execute` |
| **Replacement Owner** | `process` world with `command:run()` |
| **Deletion Prerequisite** | GAP-154 / GAP-155 — structured command world |
| **Positive Control** | `gate/host.id` blocks new violations |
| **Negative Control** | None |

**Verdict:** MAJOR BRIDGE DEBT. Uses host shell APIs instead of world authority. Needs replacement with properly attributed process world.

### 7. lib/fs.id

| Attribute | Value |
|-----------|-------|
| **File** | `lib/fs.id` |
| **Responsibility** | File system helpers |
| **Exact Facts Carried** | File operations via shell |
| **Semantic Authority** | VIOLATION — uses `io.popen`, `os.execute`, `@c.emit` |
| **Replacement Owner** | Proper `fs` world with `path:read()`, `path:write()` |
| **Deletion Prerequisite** | GAP-154 — filesystem world authority |
| **Positive Control** | `gate/host.id` blocks new violations |
| **Negative Control** | None |

**Verdict:** MAJOR BRIDGE DEBT. Contains shell command wrappers that should use world authority.

### 8. lib/script.id

| Attribute | Value |
|-----------|-------|
| **File** | `lib/script.id` |
| **Responsibility** | Bootstrap tooling bridge |
| **Exact Facts Carried** | Shell command execution |
| **Semantic Authority** | BOOTSTRAP DEBT — forbidden |
| **Replacement Owner** | Direct execution boundaries |
| **Deletion Prerequisite** | GAP-155 — gate/scripts/ingress ownership |
| **Positive Control** | `gate/host.id` blocks `os.execute` |
| **Negative Control** | None |

**Verdict:** FROZEN DEBT per GAP-155. Should not be used.

---

## P0-G — Shell

Shell is interpretation law, not runtime ontology.

**Avoid host-shell string pipelines in native gates/compiler.** Structured command semantics first.

If bootstrap requires shell:
- Current explicit bridge debt only
- Deletion prerequisite required

**Current usage:**
- `lib/os/process.id` uses shell via `io.popen`
- `lib/fs.id` uses shell via `io.popen`
- `lib/script.id` uses shell via `os.execute`

These are **VIOLATIONS** that need to be replaced with proper world/authority models.

---

## P0-H — NIL / FAILURE

Do not collapse:
- unavailable witness
- nil
- empty string
- process status
- semantic failure

Foreign status is evidence, not automatically semantic outcome.

---

## P0-I — No Parent/Fallback

Once witness resolved:
- NO world lookup downstream
- No parent environment
- No service locator
- No fallback host world
- No module/namespace fallback

---

## FTCFTW

Known authority should cost zero abstraction:
- runtime world objects = 0
- runtime capability dict = 0
- service/context lookup = 0
- world dispatch = 0

**Track every surviving runtime world lookup and exact uncertainty requiring it.**

---

## Hostcensus Results

Current violations (from `./tools/node/dev/hostcensus`):

```
os_args_call        VIOLATION  18  os.args(
os_getenv           VIOLATION  56  os.getenv(
environment_bracket VIOLATION   8  environment[
environment_colon   VIOLATION   4  environment:
io_read_dot         VIOLATION  29  io.read(
io_write_dot        VIOLATION 106  io.write(
io_open_dot         VIOLATION  48  io.open(
io_popen            VIOLATION  49  io.popen
popen               MIGRATION   51  popen(
os_execute          VIOLATION  39  os.execute
getenv              MIGRATION 150  getenv(
std_dot             VIOLATION 12140  std.
proc_dot            VIOLATION  83  proc.
use_paren           VIOLATION  74  use(
using_paren         VIOLATION   3  using(
core_dot            VIOLATION  25  core.

Total: 13,030 violations+migration hits
```

Canonical targets growing:
```
os_args_table   CANONICAL  17  os.args[
os_env_table    CANONICAL  21  os.env[
os_env_call     CANONICAL  64  os.env(
io_read_rel     CANONICAL  34  io:read
io_write_rel    CANONICAL  11  io:write
```

---

## Recommendations

### 1. foreign_adapter.zig — KEEP
This is legitimate foreign projection machinery. Rename from "adapter" to "projection" is purely semantic -- functionally it's a `duo_foreign_project` that converts C declarations to graph descriptors.

### 2. lib/fs.id — REWRITE
Replace shell-command implementations with proper world relations:
- `path:read()` should use world file authority
- `path:write()` should use world file authority
- Remove shell command wrappers

### 3. lib/os/process.id — REWRITE
Replace with structured command world:
- `command("git", "status")` creates command value
- `command:run()` executes under process world
- No `io.popen`, no `os.execute`

### 4. lib/script.id — DELETE/FROZEN
This is bootstrap debt. Use `scripts/ingress/` boundary instead.

### 5. lib/env.id — REWRITE
Replace `os.env(name)` with `os.env["name"]` or `os.env(name)` pattern.

### 6. lib/io.id — REWRITE
These are utility wrappers, not world relations. The canonical form is `subject:relation()`.

---

## SHC — Host OS Syscalls/Clibc/WASI

May remain FOREIGN REALIZATION.

But Idol must own:
- effect classification
- authority requirement  
- witness selection
- failure semantics
- relation identity

Moving syscall execution into Idol is less important than moving semantic authority.

---

## Conclusion

The world model requires:
1. Exact graph facts for authority requirements
2. No string-based world dispatch
3. World as role (authority-bearing facts/witnesses), not class hierarchy
4. All bridges documented with deletion prerequisites
5. No semantic selection authority at host boundary

The current `foreign_adapter.zig` is NOT the problem -- it's a legitimate projection. The real bridge debt is in the std library files that use host APIs instead of proper world authority.