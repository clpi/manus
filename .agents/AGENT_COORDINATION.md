# Duo agent coordination

Epoch 2. This file is **durable**: what the subsystems are, who owns them, and
the four protocol rules that were each bought with a real incident. It is not a
control plane and must not become one again.

The previous version was 4619 lines of claims, leases, an open-gap queue and a
reverse-chronological session log, all tracked and all rewritten every session.
It is frozen at
[`docs/history/agent-coordination-2026-07-to-08.md`](../docs/history/agent-coordination-2026-07-to-08.md)
— historical evidence, never authority.

**Rule of thumb: if a line would be stale in a week, it does not belong in a
tracked file.** Session state goes in `.agents/session/`, which is gitignored.

## Where things go now

| | |
|---|---|
| **Law** | `CLAUDE.md` (operative) · `docs/spec/pass100.md` · `docs/spec/AUTHORITY.md` |
| **Corpus classification** | `docs/spec/corpus.md` — read by `zig build audit100` |
| **Open gaps** | `gaps/GAP-0NN.md`, one file per gap. Check the directory immediately before claiming a number; parallel sessions collide on it |
| **Perf ledger** | `docs/performance.md` |
| **Foreign-code adjudication** | `docs/foreign_code_ledger.md` · `src/removal_ledger.zig` |
| **Live claims, leases, scratch** | `.agents/session/` — **untracked** |
| **What happened** | `git log`. It already has the diffs |

## Subsystems and owners

Owner means: the file that decides. Change the decision there, not at a call
site that happens to be easier to reach.

| Subsystem | Owns the decision | Notes |
|---|---|---|
| CLI, driver | `src/main.zig` | entry point, subcommand dispatch |
| Lex → parse | `src/pass3*.zig`, `lib/std/compiler/lexer.duo`, `lib/std/compiler/parser.duo` | the Duo-side pair is the self-hosting target (SH-03/SH-04) |
| Semantic analysis | `src/sema.zig`, `src/semantic_context.zig`, `src/pass12*.zig` | |
| Boxed IR | `src/pass4*.zig` | the `lua_Value` path; hot code must not reach it |
| C backend | `src/codegen.zig` | the fallback that always works, and therefore the one that hides bugs |
| Direct native (ARM64) | `src/native_backend.zig`, `src/duo_native_ir.zig`, `src/dnir_lower.zig` | `DUO_DNIR_TRACE=1` names the exact bail site |
| Standard library | `lib/std/**` | Duo source; a parse error here takes down every dependent |
| Token/opcode tables | `src/token_classify_gen.zig`, `src/wasm_semantic_gen.zig` | generate `lib/std/token/classify.duo`, `lib/std/wasm/*`. Fix the generator |
| Gates and benchmarks | `scripts/**` | all Duo; see the gate table below |
| Build graph | `build.zig` | every gate is a step here or it does not exist |
| LSP / MCP servers | `tools/lsp/`, `tools/mcp/` | version-locked to the compiler on purpose |
| ward (WASM runtime) | `ext/ward/` | downstream consumer; it is evidence Duo builds real systems software, so it should build against released behaviour |

`wart` (`~/x/wart`, Zig) is the reference implementation ward is measured
against and is **read-only from here** — an oracle does not share a repo with
the thing it validates.

## Gates

| Step | Asks |
|---|---|
| `zig build agent-smoke` | tier-0: hygiene + stdlib + meta. Run before every commit |
| `zig build audit100` | Pass 100 deny table over the canonical corpus; ratchets per row |
| `zig build repo-hygiene` | forbidden root artifacts and tracked agent noise |
| `zig build language-census` | tracked non-Duo source; ratchets sh/py debt |
| `zig build native-census` | native coverage over the reachable set |
| `zig build test` | unit + compile-fail |
| `zig build bench` | perf. Never in parallel with another agent |

## The four rules

Each of these is here because it already cost somebody a day.

**1. `git stash` is banned.** Not as a tree-cleaner, not to dodge a conflict.
A stash is invisible to `git status`, so parallel agents keep building against
stale copies and the work vanishes; recovering one cost a 23-file rescue.
Commit on a branch, or write a visible `.patch`. `git stash list` stays empty.

**2. Commit with explicit pathspecs.** `git commit -- <paths>`, never
`git add -A`, never `git checkout .`, never a blind `git stash pop`. Other
sessions stage work in the same index; a sweep-commit has twice left HEAD
non-building. Verify with `git show --stat` that only your hunks landed.

**3. Serialize heavy builds.** Concurrent `zig build` corrupts `.zig-cache`
and produces flaky "module not found" / "C compiler failed" that pass on a
clean re-run. Take the lock:

```
duo run scripts/duo_lock.duo -- zig build bench
duo run scripts/duo_lock.duo status          # who holds it
```

From Duo, `std.script.lock_cmd` / `locked_run` wrap the same mutex.
(`scripts/duo_lock.sh` no longer exists — RL-13 retired it.)

**4. Positive-control every zero.** A gate reporting 0 findings is usually
broken, not clean. This repo has shipped gates that scored a confident 0/N
because a path was relative, because `std.os.getenv` returned `""` instead of
nil, or because an unquoted glob expanded to nothing. Prove the detector can
fire before you believe it did not.

## Before you start

1. Read `CLAUDE.md`. It is the operative law and it changed at epoch 2.
2. Check `gaps/` for the thing you are about to rediscover.
3. Check `git log --oneline -20` and `git status` — other sessions are live.
4. Claim shared files in `.agents/session/` if your tooling supports it, and
   say so in the commit message either way.
