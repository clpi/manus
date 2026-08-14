# shellstatus Antipattern Analysis — Constitution Compliant

## Constitution Violation

`shellstatus` violates the Idol Blind-Start Constitution:

1. **COLLISION-ZERO**: "bridge/adapter/registry" as roles are forbidden
2. **P0-G**: "Shell is interpretation law, not runtime ontology"
3. **LAW-ONE**: compound `shellstatus` violates naming law
4. **NO STRING MATCHING**: shell escape patterns should not be semantic selection

## The Compound Name Problem

From IDOL BLIND-START CONSTITUTION:
> "Decompose compounds into `pipe`, `walk(q)`, `stride`, `waive`, `resident`."

**`shellstatus` = `shell` + `status`** is a compound mash.

**Lawful alternatives:**
- `run_status` (status is the semantic subject)
- `exit_code` (the semantic fact being measured)
- `command_status` (if command owns status)

## The Bridge Ontology Problem

**Constitution:**
> "The role is forbidden, not the word."

The pattern `gate/bootstrap.shellstatus()` embeds:
- A bootstrap namespace (implying bridge ontology)
- Shell command execution (shell as semantic world)
- Status extraction via escape hatch

This is **acceptable as bootstrap infrastructure** (foreign boundary),
but **unacceptable in project Idol source** as semantic authority.

## What is LAWFUL (Bootstrap Boundary)

Per constitution: "describing a currently executed bounded foreign/bootstrap boundary"

```c
// src/idol_io_bootstrap.c - NATIVE REALIZATION
int64_t idol_os_execute(const char* cmd) {
    int rc = system(cmd);
    return WIFEXITED(rc) ? WEXITSTATUS(rc) : 1;
}

char* idol_process_capture(const char* cmd) {
    FILE* f = popen(cmd, "r");
    char* out = idol_io_read_fd(fileno(f));
    pclose(f);
    return out;
}
```

This C code is the **foreign realization layer** - acceptable as physical
projection of graph facts.

## What is UNLAWFUL (Project Source)

```
# shell status bridge
gate/bootstrap.shellstatus("test -e path") == 0

# shell capture bridge  
gate/bootstrap.capture("git status")

# shell execution
os.execute("make build")
io.popen("ls -la")
```

These embed shell/foreign authority in Idol source.

## Proper World Model Replacements

### File Existence
**UNLAWFUL:**
```
if gate/bootstrap.shellstatus("test -e '{path}'") == 0
```

**LAWFUL:**
```
if path:exists()  # fs world provides authority
```

### Command Execution
**UNLAWFUL:**
```
rc = gate/bootstrap.shellstatus("git status")
if rc != 0
    fail(test_failed)
```

**LAWFUL:**
```
cmd = command("git", ["status"], nil, nil)
result = cmd:run()
if result.status != 0
    fail(test_failed)
# result.output contains stdout/stderr
# result.status is exact exit code
```

### Build Verification
**UNLAWFUL:**
```
if gate/bootstrap.shellstatus("{bin} run {f}") != 0
```

**LAWFUL:**
```
cmd = command(bin, ["run", f], nil, nil)
result = cmd:run()
if result.status != 0
    fail(build_failed)
```

## The World Model

Per IDOL BLIND-START CONSTITUTION:
> "World is a role: authority-bearing facts/witnesses."

**World tables (provided at execution):**
- `os.env` - environment table
- `os.args` - argument table
- `fs` - file system world (pending implementation)
- `io` - endpoint world (stdin/stdout/stderr)
- `process` - process world (pending implementation)

**Relations on world tables:**
- `os.env["KEY"]` - table access
- `path:exists()` - fs world relation
- `path:read()` - fs world relation
- `command:run()` - process world relation
- `stdin:read()` - io world relation
- `stdout:write(text)` - io world relation

**NO namespace dispatch:** `fs.exists(path)` is wrong. `path:exists()` is correct.

## Bridge Definition (Idol vs Foreign)

**Foreign bridge** (acceptable at bootstrap boundary):
- C FFI imports
- Shell escape hatches
- Process execute at ingress/egress

**Idol semantic** must use:
- Graph facts for authority
- Subject-first relations
- World witness at execution

## Migration Path

### Phase 1: Acceptance
- `gate/bootstrap.*` remains bootstrap boundary
- Scripts using shellstatus accepted as transitional

### Phase 2: Implementation
- Add `process` world with `command` relation
- Add `fs` world with `exists`, `read`, `write`, `open`
- Gate scripts use world authority

### Phase 3: Deletion
- Delete `shellstatus` when process world exists
- Gate/bootstrap.id has explicit deletion gate
- All scripts migrated to world authority

## Positive Controls

Gate must verify:
1. `path:exists()` resolves fs.world requirement
2. `command:run()` resolves process.world requirement
3. `os.env["KEY"]` resolves os.world requirement
4. `stdin:read()` resolves io.stdin requirement

## Negative Controls  

Gate must reject:
1. New `shellstatus` aliases
2. New `os.execute()` usage
3. New `io.popen()` usage
4. Compound bridge/adapter names in project Idol

## Deletion Gate Record

For `shellstatus`:

| Field | Value |
|-------|-------|
| **Responsibility** | Extract shell command exit status |
| **Facts Carried** | Exit code 0/1 (lossy: no exact code) |
| **Semantic Authority** | NONE - shell interpretation law |
| **Replacement Owner** | Process world `command:run()` |
| **Deletion Prerequisite** | Process world with `run.status` fact |
| **Positive Control** | `path:exists()`, `command:run()` |
| **Negative Control** | LAW-ONE compound name, COLLISION-ZERO bridge role |

---

## Summary

`shellstatus` is an antipattern because:

1. **Compound violation** - `shell` + `status` mash
2. **Bridge ontology** - implies forbidden bridge role
3. **Shell authority** - uses shell as semantic world
4. **Lossy semantics** - 0/1 exit, not exact code
5. **Bootstrap boundary** - acceptable only in gate scripts

The proper solution is **process world authority** with `command:run()` that
returns exact exit codes and output through semantic relations, not shell
escape hatches.