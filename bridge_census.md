# P0-F Bridge Census — SURVIVING BRIDGES

## Abstract

This document audits all surviving bridges in the Idol compiler, providing:
- Responsibility
- Exact facts carried  
- Semantic authority (none/bounded)
- Replacement owner
- Deletion prerequisite
- Positive control
- Negative control

Per LXXXII. BRIDGE-DEATH in docs/spec/agent.md: A temporary physical bridge requires:
1. Exact responsibility
2. Exact facts crossing
3. Semantic authority classification
4. Replacement owner
5. Deletion prerequisite
6. Positive control
7. Negative control

---

## 1. Lexer/Tokenizer Bridges

### 1.1 lexer_bridge.zig

**File:** `src/lexer_bridge.zig`

**Responsibility:** Production lexer routing; maps generated lexer output to bootstrap lexer input.

**Exact Facts Carried:**
- Token kind classifications from generated C lexer
- Source law classification (.idol, .lua, unknown)

**Semantic Authority:** NONE — pure realization acceleration. The generated C lexer produces tokens; this bridges them to the Idol Token type.

**Replacement Owner:** Direct lexer front-end integration

**Deletion Prerequisite:** N/A — This is a necessary realization layer between generated C lexer and Idol parser. The `g` token (generated native) split is a legitimate bootstrap bridge per GAP-121.

**Positive Control:** `test "lexer_bridge: production split"` verifies generated native path is used

**Negative Control:** `test "lexer_bridge: suffix classifies"` verifies canonical vs foreign source classification

---

### 1.2 keyword_bridge.zig  

**File:** `src/keyword_bridge.zig`

**Responsibility:** Production keyword classification through generated classifier.

**Exact Facts Carried:**
- Keyword token classifications
- Token kind mappings

**Semantic Authority:** NONE — realizes keyword taxonomy into TokenKind enum.

**Replacement Owner:** Direct parser recognition

**Deletion Prerequisite:** N/A — Generated keyword classifier projection.

**Positive Control:** `test "keyword bridge: production keywords"` verifies correct keyword mappings

**Negative Control:** `test "keyword bridge: production keywords"` rejects non-keywords

---

## 2. Foreign Import Bridges

### 2.1 foreign_adapter.zig

**File:** `src/foreign_adapter.zig`

**Responsibility:** Adapt C import SIM entities into Duo compiler foreign descriptors.

**Exact Facts Carried:**
- C entity declarations (structs, functions)
- ABI metadata (pass_by, calling convention)
- Origin artifact provenance

**Semantic Authority:** NONE — This is **foreign-to-canonical projection machinery**, not an adapter. It converts foreign C declarations into graph descriptors. Per LXXXI, foreign representations normalize exactly once.

**Replacement Owner:** None needed — this IS the foreign projection.

**Deletion Prerequisite:** N/A — Legitimate foreign projection layer.

**Positive Control:** `gate/host.id` rejects `@c.emit` in source files (keeps host APIs at boundary)

**Negative Control:** None this is the proper boundary layer

**Note:** The mission correctly identifies that "adapter identity is not acceptable" but this file is NOT an adapter — it's a projection. No change needed.

---

## 3. Shell Bridges (Bootstrap Ingress)

### 3.1 shell_host.zig

**File:** `src/shell_host.zig`

**Responsibility:** Cross-platform host shell escape hatch for shell() primitive and ! prefix.

**Exact Facts Carried:**
- argv for raw shell evaluation
- Host OS-specific shell invocation

**Semantic Authority:** FOREIGN REALIZATION — implements `shell()` primitive at REPL/run boundary.

**Replacement Owner:** Shell home + command projection (once GAP-155 closes)

**Deletion Prerequisite:** GAP-155 — Shell is interpretation law, not runtime ontology. Structured command world must be in place.

**Positive Control:** REPL documentation shows `!` prefix usage

**Negative Control:** Gate prevents new host API usages via `gate/host.id`

---

### 3.2 shell_session.zig

**File:** `src/shell_session.zig`

**Responsibility:** Persistent semantic shell session history, export, snapshot.

**Exact Facts Carried:**
- REPL command history
- Session export module
- Snapshot management

**Semantic Authority:** FOREIGN EGRESS — MCP/LSP transport boundary.

**Replacement Owner:** MCP/LSP transport layer using graph facts

**Deletion Prerequisite:** GAP-167 — bridge forwarding layer needs graph-owned replacement

**Positive Control:** MCP manifest includes shell session infrastructure

**Negative Control:** None yet — bridge egress layer

---

### 3.3 host_run.zig

**File:** `src/host_run.zig`

**Responsibility:** Compile-time shell command execution for @run, @c.include, etc.

**Exact Facts Carried:**
- Command output for compile-time evaluation
- Exit status

**Semantic Authority:** BOOTSTRAP INGRESS — compile-time only. Foreign command execution at AST boundary.

**Replacement Owner:** Graph execution or dedicated compile-time command world

**Deletion Prerequisite:** GAP-154 — host boundary must move to execution configuration

**Positive Control:** Compile-time command execution patterns

**Negative Control:** None — bootstrap boundary

---

## 4. Process/Filesystem Bridge DEBT

### 4.1 lib/os/process.id

**File:** `lib/os/process.id`

**Responsibility:** Process management through shell wrappers.

**Exact Facts Carried:**
- `io.popen` calls
- `os.execute` calls
- Shell command strings

**Semantic Authority:** VIOLATION — Should use world authority (process run), not host shell.

**Replacement Owner:** Process world with `command:run()` relation

**Deletion Prerequisite:** GAP-155 — structured command + process world must be implemented

**Positive Control:** `gate/host.id` rejects new `os.execute`, `io.popen`

**Negative Control:** `gate/host.id:103` - `host.execute` violation

**Actions Required:**
1. Replace `start()` implementation with `command:run()`
2. Replace `wait()` with process world status
3. Remove `io.popen`, `os.execute` usage
4. Implement proper process world witness

---

### 4.2 lib/fs.id (top-level)

**File:** `lib/fs.id`

**Responsibility:** File system helpers through shell commands.

**Exact Facts Carried:**
- `io.popen` shell commands
- `os.execute` shell commands  
- `@c.emit` mkdir syscall

**Semantic Authority:** VIOLATION — Should use world authority (fs world), not host shell.

**Replacement Owner:** Proper fs world with `path:read()`, `path:write()` relations

**Deletion Prerequisite:** GAP-154 — filesystem world authority must be implemented

**Positive Control:** `gate/host.id` rejects new `os.execute`, `io.popen`

**Negative Control:** `gate/host.id:100-105` - various host API violations

**Actions Required:**
1. Replace `path:len()` with proper file stat relation
2. Replace `read_file()`/`write_file()` with `path:read()`/`path:write()`
3. Remove shell command wrappers (`mkdir`, `cp`, `ls`, etc.)
4. Implement proper fs world bridge in host execution

---

### 4.3 lib/script.id

**File:** `lib/script.id`

**Responsibility:** Bootstrap tooling bridge (FROZEN).

**Exact Facts Carried:**
- `os:execute` shell calls
- `io.popen` capture
- `@c.emit` setenv/unsetenv

**Semantic Authority:** BOOTSTRAP DEBT — forbidden source per GAP-155.

**Replacement Owner:** `scripts/ingress/` boundary home

**Deletion Prerequisite:** GAP-155 — gate/bootstrap capture until graph-owned run

**Positive Control:** `gate/host.id` blocks `os.execute`, `io.popen`

**Negative Control:** Documentation states "frozen — delete under GAP-157"

**Actions Required:** DELETE or migrate to `scripts/ingress/` boundary

---

### 4.4 lib/env.id

**File:** `lib/env.id`

**Responsibility:** Environment table helpers.

**Exact Facts Carried:**
- `os.env[name]` projection

**Semantic Authority:** BORDERLINE — uses `os.env[name]` projection but this projects to `os` world table.

**Replacement Owner:** Keep as projection helper, but ensure world facts are clear

**Deletion Prerequisite:** None if using `os.env["key"]` pattern

**Positive Control:** `os.env[name]` returns table value

**Negative Control:** Ensure no `os.getenv()` calls

---

## 5. Bridge Summary Table

| Bridge | Status | Authority | Action |
|--------|--------|-----------|--------|
| lexer_bridge.zig | KEEP | None (realization) | No change |
| keyword_bridge.zig | KEEP | None (realization) | No change |
| foreign_adapter.zig | KEEP | None (projection) | Rename "adapter" concept |
| shell_host.zig | KEEP | Foreign | Deletion gate: GAP-155 |
| shell_session.zig | KEEP | Foreign | Deletion gate: GAP-167 |
| host_run.zig | KEEP | Bootstrap | Deletion gate: GAP-154 |
| lib/os/process.id | VIOLATION | Host API debt | Rewrite for process world |
| lib/fs.id | VIOLATION | Host API debt | Rewrite for fs world |
| lib/script.id | DEBT | Bootstrap | DELETE or migrate |
| lib/env.id | OK | World projection | Review pattern |

---

## P0-G — Shell Bridge Classification

Shell is interpretation law, not runtime ontology.

**DO:**
- Structured command semantics first
- Shell home + command projection for bare external commands
- Shell as execution context, not API

**DON'T:**
- Host-shell string pipelines in native gates/compiler
- Shell as semantic world
- Direct shell API calls in library code

---

## P0-H — Nil/Failure Distinctions

Maintain clear distinctions:
- `nil` = Idol absence value (semantic)
- `false` = boolean false (semantic)
- `0` = integer zero (semantic)
- `""` = empty text (semantic)
- Missing witness = semantic failure (execution time)

---

## P0-I — No Parent/Fallback

Once witness resolved:
- NO world lookup downstream
- NO parent environment
- NO service locator
- NO fallback host world

---

## Deletion Roadmap

1. **Short Term (GAP-124 + GAP-154):**
   - Implement graph world authority facts
   - Add semantic gates for world requirements
   - Keep host checks as lexical firewall

2. **Medium Term (GAP-155):**
   - Rewrites `lib/os/process.id` for process world
   - Rewrites `lib/fs.id` for fs world
   - Migrate `lib/script.id` to `scripts/ingress/`

3. **Long Term:**
   - Delete shell bridges when shell home + command projection is stable
   - Remove all host API usage from project library code
   - Zero host API debt via GAP-154 ratchet

---

## Conclusion

The bridge census reveals:

1. **Foreign projection bridges** (lexer, keyword, foreign_adapter) are legitimate realization layers with zero semantic authority.

2. **Shell bridges** are bootstrap ingress/egress at the host boundary.

3. **Library bridge debt** (`lib/os/process.id`, `lib/fs.id`, `lib/script.id`) are VIOLATIONS that need rewriting for proper world authority.

4. **No string world maps** - world authority is in graph facts, not namespace strings.

5. **f(`env`, `args`)** are correct subject-first relations under `os` world table.

The mission's core requirement — "host/platform machinery has ZERO semantic selection authority" — means the host decides execution parameters (argv, cwd, etc.) but the Idol program's semantic meaning (which relation, which world) is determined by graph facts, not host API calls.