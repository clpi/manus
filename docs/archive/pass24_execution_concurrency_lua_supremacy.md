# Pass 24 — Execution Graph, Call Supremacy, Lua Superset Maximization, and Concurrency Architecture

**Status:** Design constitution (2026-08-05). P0 partially landed; P1–P12 open.  
**Mission:** One canonical semantic program model where ordinary Duo calls, Lua-compatible syntax, shell boundaries, and concurrency directives lower through a **single execution graph** — with explicit realization selection, zero-allocation paths where proven, and permanent Lua superset status.

**This document is the authoritative Pass 24 specification.** It reconciles call ergonomics, long strings, Lua compatibility, shell invocation, structured concurrency, automatic parallelism, streams, scheduling, hardware realization, tooling, implementation order, and proofs. It **resolves conflicts** rather than stacking proposals.

---

## Validate (when implemented)

```bash
zig build lua-superset-gate    # P0–P1 invariants today
zig build pass24-gate          # future: full pass exit criteria
duo catalog | jq '.pass24'
```

| Artifact | Owner |
| --- | --- |
| Superset compatibility matrix | `docs/catalogs/lua_superset_compatibility.md` |
| Superset construct registry | `src/lua_superset_catalog.zig` |
| Superset + corpus gates | `src/lua_superset_gate.zig`, `src/lua_superset_corpus.zig` |
| Pass 24 catalog (future) | `src/pass24_catalog.zig` |
| Call + execution graph (future) | `src/semantic_graph.zig`, `src/dnir_lower.zig`, `src/realization.zig` |

---

## Table of contents

1. [Governing philosophy](#1-governing-philosophy)
2. [Non-negotiable invariants](#2-non-negotiable-invariants)
3. [Rejected alternatives](#3-rejected-alternatives)
4. [Call architecture](#4-call-architecture)
5. [Lua superset maximization](#5-lua-superset-maximization)
6. [Long strings, long comments, and shell boundaries](#6-long-strings-long-comments-and-shell-boundaries)
7. [Unified execution architecture](#7-unified-execution-architecture)
8. [Concurrency surface](#8-concurrency-surface)
9. [Automatic parallelism and cost modeling](#9-automatic-parallelism-and-cost-modeling)
10. [Effects, alias analysis, and data-race freedom](#10-effects-alias-analysis-and-data-race-freedom)
11. [Communication: streams, channels, selection](#11-communication-streams-channels-selection)
12. [Scheduling, representation, and hardware realization](#12-scheduling-representation-and-hardware-realization)
13. [Determinism, replay, failure, and cancellation](#13-determinism-replay-failure-and-cancellation)
14. [Performance: beating Go honestly](#14-performance-beating-go-honestly)
15. [Cross-system integration matrix](#15-cross-system-integration-matrix)
16. [Tooling: LSP, MCP, formatter, Tree-sitter, diagnostics](#16-tooling-lsp-mcp-formatter-tree-sitter-diagnostics)
17. [Ambiguity analysis](#17-ambiguity-analysis)
18. [Compatibility, migration, and syntax classification](#18-compatibility-migration-and-syntax-classification)
19. [Complete examples](#19-complete-examples)
20. [Implementation ordering](#20-implementation-ordering)
21. [Benchmarks and vertical proofs](#21-benchmarks-and-vertical-proofs)
22. [Success criteria](#22-success-criteria)
23. [Prohibited outcomes](#23-prohibited-outcomes)
24. [Relation to other passes](#24-relation-to-other-passes)

---

## 1. Governing philosophy

Duo is **not** Lua with Go concurrency pasted on top. It is **Lua semantics elevated into a compiler-owned execution graph** capable of producing — from the same compact program — a coroutine, direct call, SIMD loop, multicore task graph, GPU kernel, process pipeline, or remote computation.

Three permanent commitments override feature velocity:

1. **Maximize Lua, do not minimize it.** Every valid Lua 5.5 program should remain valid Duo with equivalent observable semantics unless a documented superset exception applies.
2. **One execution architecture.** Coroutines, tasks, futures, channels, parallel loops, GPU kernels, and shell pipelines are **realizations of the same semantic region + call + effect graph**, not separate permanent runtime languages.
3. **Ordinary values stay ordinary.** First-class functions and closures remain values. Invocation is **explicit** at the syntax level except in delimited **command invocation contexts** (shell), never by silently redefining bare identifiers.

**Canonical does not mean exclusive.** Duo may prefer denser forms (`if ready run() end`) while permanently accepting Lua-canonical equivalents (`if ready then run() end`). The formatter may project canonical Duo; the compiler must not treat accepted Lua syntax as doomed compatibility debris.

---

## 2. Non-negotiable invariants

| ID | Invariant |
| --- | --- |
| P24-I01 | `[[ ... ]]` and the full long-bracket family are **Lua long-string syntax**, never shell conditionals, never deprecated, never context-dependent reinterpretation |
| P24-I02 | Long comments `--[[ ... ]]`, `--[=[ ... ]=]`, … follow Lua delimiter matching exactly |
| P24-I03 | Bare identifier `a` denotes **value reference** (callable or not), never silent invocation |
| P24-I04 | `a()` is zero-argument invocation; `a x`, `a x, y` are parenless invocations with arguments |
| P24-I05 | `obj:method()`, `obj:method x` are receiver calls; `obj:method` without args is a **method value** reference |
| P24-I06 | Parenthesized Lua calls `f(a, b)` remain first-class forever |
| P24-I07 | No mandatory `async`/`await` keywords; execution policy belongs to call site or enclosing region |
| P24-I08 | Spawned tasks are **structurally scoped** by default; detachment is explicit and capability-gated |
| P24-I09 | Effects and alias facts drive scheduling legality; the compiler must not assume safety it cannot prove |
| P24-I10 | No `lua_Value` on typed/comptime paths (inherits Pass 4/22/23) |
| P24-I11 | Parallelism is selected by **cost model + contracts**, not by syntax alone |
| P24-I12 | Ward and self-hosting proofs use **general Duo mechanisms** — no Ward-private concurrency hooks |

---

## 3. Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| **Bare `a` always invokes** when `a` is callable | Destroys Lua first-class function semantics; breaks `callback = print`, `items:each print`, passing callbacks, storing handlers in tables |
| **`[[ ... ]]` as Duo/bash conditional** | Conflicts with Lua long strings; breaks `@c.emit`, templates, embedded source, shell raw boundaries |
| **Deprecating `then`, `do`, `local function` because Duo has shorter forms** | Token reduction alone is insufficient; violates superset maximization (Pass 24 §18) |
| **Separate permanent systems for goroutines / async / channels / parallel loops** | Prevents unified optimization, fusion, static scheduling, and explainability |
| **Mandatory `await` keyword** | Adds ceremony; waiting is ordinary call/projection on task values |
| **Channels as the only composition mechanism** | Go-centrism; Duo composes through calls, streams, regions, and race/selection |
| **Global shell command rules for all identifiers** | `pwd` as command in shell context ≠ redefining `pwd` identifier in ordinary Duo code |
| **Parallelize whenever legal** | Violates latency, power, transfer-cost, and determinism contracts |
| **Rust-like ownership ceremony on every program** | Conflicts with Lua ergonomics; use progressive knowledge instead |
| **Benchmark tricks without semantic equivalence** | Invalidates Go comparison claims (§21) |

---

## 4. Call architecture

### 4.1 Semantic model

Every call site produces a **CallObject** in the semantic graph:

```
CallObject
├── callee descriptor (value, method, command, intrinsic)
├── argument pack (positional, named, spread)
├── effect summary (pure, IO, suspend, device, …)
├── staging (runtime, comptime, shell boundary)
├── return pack expectation
└── invocation form (paren, parenless, receiver, command)
```

Calls are not “functions only.” A shell command, GPU launch, channel send, and ordinary function call are the **same node kind** with different realizations.

### 4.2 Surface syntax (resolved)

| Form | Meaning | Lua compatible |
| --- | --- | --- |
| `a` | Retrieve value bound to `a` (may be callable) | ✅ |
| `a()` | Invoke value with zero arguments | ✅ |
| `a(x)` | Invoke with parenthesized arguments | ✅ |
| `a x` | Parenless invoke, one argument | Duo extension |
| `a x, y` | Parenless invoke, multiple arguments | Duo extension |
| `obj:method()` | Receiver call, zero args | ✅ |
| `obj:method x` | Parenless receiver call | Duo extension |
| `obj:method` | Method value / field access | ✅ |
| `print 'hi'` | String-literal call sugar | Duo extension |
| `pwd` | **Only in command invocation context** (§4.4) | Shell |

**Critical reconciliation:** Interactive shell may treat `pwd` as a zero-argument command. Ordinary Duo code treats `pwd` as a variable reference unless explicitly in a **command region** established by shell/session descriptors.

### 4.3 First-class functions must keep working

```duo
items:each print          -- pass print as callable value
callback = print          -- store function reference
handlers.Save = save      -- table of callbacks
map(items, transform)     -- higher-order call
local f = compute
f()                       -- invoke stored function
x = f                     -- retrieve without invoking
```

Silent invocation of bare `f` would break every pattern above.

### 4.4 Command invocation context (shell)

Pass 15 semantic shell establishes **command regions** where:

- Zero-argument commands (`pwd`, `clear`) resolve through command descriptors
- Parenless tails attach to command heads under capability rules
- Raw shell crosses explicit boundaries (`shell [=[ … ]=]`, foreign process nodes)

Command rules **do not** alter ordinary expression parsing outside command regions. Lexer tokens are identical; **semantic context** disambiguates.

**Integration:** `src/command_descriptor.zig`, Pass 15 WS3 execution context, Pass 24 call objects tagged `staging = shell`.

### 4.5 Lowering consequences

| Layer | Consequence |
| --- | --- |
| Lexer | No token repurposing; long brackets remain strings |
| Parser | Parenless call form extends `parse_suffixed_expr`; no bare-name invoke |
| Sema | CallObject with invocation form; effect inference per callee |
| Graph | `calls` edges with argument pack nodes |
| DNIR | Direct call, indirect call, command launch, fused pipeline |
| Codegen | Native C call, lua_invoke fallback, process spawn, GPU launch |

---

## 5. Lua superset maximization

### 5.1 Governing rule

> Every valid Lua 5.5 program should remain a valid Duo program with equivalent observable semantics unless a documented, unavoidable conflict makes that impossible.

Duo may add: denser syntax, static knowledge, native representations, `@comp.*` transforms, concurrency regions, parenless calls. Duo must **not subtract** Lua surface casually.

### 5.2 Syntax classification (permanent)

| Class | Meaning |
| --- | --- |
| `DUO_CANONICAL` | Formatter default for new `.duo` |
| `LUA_CANONICAL` | Accepted forever; may not be formatter default |
| `LUA_AND_DUO_CANONICAL` | Both valid permanently |
| `DUO_EXTENSION` | Not in Lua; no breakage of Lua programs |
| `LEGACY_DUO_EXPERIMENT` | Migration documented |
| `ACTUALLY_DEPRECATED` | Requires six-part superset exception (§18) |
| `INVALID` | Rejected |

**Deprecation threshold — all must be true:**

1. Genuine semantic or grammatical conflict  
2. Contextual disambiguation cannot solve reliably  
3. Preserving blocks higher-value Duo capability  
4. Migration is exact and automatic  
5. Compatibility mode remains where practical  
6. Documented as superset exception  

Formatter preference, token reduction, and aesthetics **alone are insufficient**.

### 5.3 Complete Lua surface (minimum matrix)

The compatibility matrix in `docs/catalogs/lua_superset_compatibility.md` must cover at minimum:

- Long strings and long comments (all delimiter levels)
- Short quoted strings and escape semantics
- Function declarations (`function`, `local function`, anonymous)
- Duo bare/assign forms (extension, not replacement)
- Local/global bindings, lexical scope, `_ENV`
- Table constructors, metatables, all standard metamethods
- Multiple returns, varargs, adjustment rules
- Numeric and generic `for`, `while`, `repeat … until`
- `if`, `elseif`, `then`, `do`, `end`
- Labels and `goto`
- Method declarations and calls (`:`)
- Concatenation, length, bitwise ops, integer rules
- Coroutines (`coroutine.*`, yield, resume)
- Error behavior (`error`, `pcall`, `xpcall` where supported)
- Dynamic loading (`require`, `load` — as supported)
- Lua 5.5 facilities (close variables, etc. — tracked per readiness)

**Evidence requirement:** No claim of full compatibility without corpus + differential tests (`src/lua_superset_corpus.zig` → reference Lua runner).

### 5.4 Canonical vs accepted examples

Both remain valid permanently:

```duo
-- Duo-canonical
if ready
    run()
end

-- Lua-canonical (LUA_AND_DUO_CANONICAL)
if ready then
    run()
end
```

Pass 21 keyword registry: `then` lifecycle is **compatibility**, not deprecation.

---

## 6. Long strings, long comments, and shell boundaries

### 6.1 Lua long-bracket family

All forms are `LUA_AND_DUO_CANONICAL`:

```lua
[[simple]]
[=[
contains ]] without closing
]=]
[==[
contains ]=] and more
]==]
--[[ block comment ]]
--[=[ comment with ]] inside ]=]
```

Delimiter level `n` = number of `=` characters; opening and closing must match exactly (Lua semantics).

### 6.2 Uses (never weaken)

Long strings are essential for: `@c.emit` / `@c.include`, embedded source, SQL, regex, templates, test fixtures, compiler snapshots, documentation blocks, **raw shell fragments at explicit boundaries**, generated code, foreign metaprograms.

### 6.3 Shell boundary example (delimiter discipline)

When Bash text contains `]]`, use level ≥ 1:

```duo
script = [=[
if [[ -f "$file" ]]; then
    echo "$file"
fi
]=]
```

- Outer `[=[ … ]=]` = Duo long string  
- Inner `[[ … ]]` = Bash text, not parsed by Duo  
- Level-0 `[[ … ]]` remains valid when content contains no unescaped `]]`

### 6.4 Bash-style conditionals in Duo

Use ordinary Duo expressions — never repurposed long brackets:

```duo
if path.exists
    ...
end

if count > 3 and name:matches(glob"*.duo")
    ...
end
```

---

## 7. Unified execution architecture

### 7.1 One graph, many realizations

Do **not** create separate permanent semantic systems for: coroutines, async functions, futures, promises, goroutines, tasks, threads, worker pools, parallel loops, channels, actors, SIMD, GPU kernels, remote work, pipeline stages.

Converge on:

```
ExecutionRegion
├── enclosing scope + structured lifetime
├── calls + return packs
├── effects + capabilities
├── dependency edges + ordering constraints
├── alias / conflict facts
├── execution freedoms (may overlap, must serialize, …)
├── scheduling candidates
├── continuation state (when suspension possible)
├── target capabilities (CPU, GPU, NUMA, …)
└── selected realization + provenance
```

### 7.2 Physical realizations (compiler-selected)

| Realization | When |
| --- | --- |
| Inline sequential | Cheap, proven safe, small input |
| Direct call / fused graph | Static dependency known |
| Stackless coroutine | Suspension with known shape |
| Stackful coroutine | Dynamic Lua coroutine interop |
| Work-stealing task | Independent CPU work, proven non-aliasing |
| SIMD / vector loop | Numeric map/reduce, legal reorder |
| GPU kernel | Size + transfer cost + device contract |
| OS process / remote | Foreign boundary, explicit capability |
| Compile-time evaluation | Pure, budgeted staging |
| Streaming pipeline | Producer/consumer with backpressure facts |

Lua coroutines remain supported; known coroutines may specialize to state machines or eliminated iterators.

---

## 8. Concurrency surface

### 8.1 Design principles

- Execution policy uses **`@` compiler-visible transforms** on ordinary calls/regions
- No async function kind required
- Waiting = ordinary call/projection (`job:value()`, not mandatory `await`)
- Structural scope owns child tasks by default
- Detach is exceptional, capability-gated

### 8.2 Core `@` forms (canonical family)

| Form | Role |
| --- | --- |
| `@spawn expr` | Semantic task value; structured scope |
| `@all … end` / `@all f(), g()` | Lexical fork/join; ordered return pack |
| `@race … end` / `@race.first_success` | First qualifying completion; explicit policies |
| `@parallel for … end` | Parallel-eligible loop region |
| `@parallel coll:map f` | Parallel mapping (exact spelling via grammar audit) |
| `@parallel coll:reduce init, op` | Parallel reduction with numeric laws |
| `@serial region` | Force sequential realization |
| `@detach … end` | Exceptional fire-with-owner; explicit shutdown |
| `@deterministic region` | Contract: stable outcome / replayable schedule |
| `@replayable region` | Semantic event recording for replay |

Exact names reconcile with `@comp.*` catalog; `@comp.why.parallel(region)` etc. explain decisions.

### 8.3 Task value model

```duo
job = @spawn fetch url
response = job:value()        -- canonical wait
page, failure = job:value()   -- variant / failure pack when typed
```

Task carries: result descriptor, failure variants, effects, cancellation capability, lifetime scope, candidate realizations, provenance, scheduling state when materialized.

### 8.4 Structured `@all`

```duo
user, posts, settings = @all
    load_user id
    load_posts id
    load_settings id
end
```

Semantics: sibling calls, source-order return pack, effect/alias legality for overlap, aggregate failure policies, structural cancellation.

### 8.5 `@race` policies

```duo
result = @race.first_success
    cache:get key
    origin:get key
    timeout 2s
end
```

Policies must distinguish: success-first, completion-first, timeout vs cancel, loser cleanup obligations. Nondeterminism is explicit and queryable.

### 8.6 Parallel collections

```duo
results = @parallel items:map transform
total = @parallel values:reduce 0, add
```

Order preservation, failure policy, and numeric laws (associativity, commutativity, FP strictness) are **descriptor facts**, not ad hoc runtime behavior.

---

## 9. Automatic parallelism and cost modeling

### 9.1 Derivation without source change

```duo
results = items
    :map decode
    :filter valid
    :map transform
```

Compiler may realize as: sequential fused loop, SIMD fused loop, multicore partition, GPU kernel, compile-time pipeline, streaming graph — **same source**.

Derivation requires: independence proof or guarded fallback, cost model approval, contract compliance (determinism, FP laws).

### 9.2 `@all` lowering cases (explicit)

For `a, b = @all compute_a input, compute_b input`:

| Case | Condition | Lowering |
| --- | --- | --- |
| 1 | Both cheaper inline | Sequential direct calls |
| 2 | One heavy, one light | Inline + one worker task |
| 3 | Both heavy, static graph | Two worker submissions, join |
| 4 | Vectorizable same pass | SIMD combination |
| 5 | Compile-time pure | Comptime results |
| 6 | Device-eligible + size | GPU / accelerator |

Selection uses: task creation cost, sync cost, transfer cost, expected work, cache footprint, contention, determinism contract, target topology.

### 9.3 Break-even rule

**Parallel must not blindly mean more threads.** The compiler rejects or serializes when estimated benefit < threshold (latency budget, input size, startup cost, power cap).

Expose: `@comp.why.parallel(r)`, `@comp.why.serial(r)`, `@comp.why.not.gpu(r)`, `@comp.why.not.simd(r)`.

---

## 10. Effects, alias analysis, and data-race freedom

### 10.1 Effect facts drive scheduling

Relevant effects: pure, alloc, local mutation, shared mutation, atomic, filesystem, network, process, suspend, device transfer, foreign call, blocking, nondeterminism, clock, randomness, cancellation, trap.

Dependency graph derives: may overlap, must order, conflicts, retriable, idempotent, migratable.

### 10.2 Progressive safety (no Rust ceremony on every program)

```
dynamic shared state
  → observed aliases
  → guarded checks
  → ownership regions
  → sealed non-aliasing regions
  → static race freedom
  → synchronization elimination
```

Classifications: immutable, task-local, scope-local, uniquely referenced, shared read-only, atomic shared, synchronized, dynamically shared.

When facts insufficient: reject mandatory parallelization, insert guard, select sequential, require explicit unsafe/atomic policy — **with explanation**.

---

## 11. Communication: streams, channels, selection

### 11.1 Semantic streams

Stream = element descriptor + buffering + ordering + backpressure + closure + failure + cancellation + producer/consumer effects + location + representation candidates.

May realize as: fused iterator, coroutine handoff, ring buffer, lock-free queue, bounded channel, OS pipe, network transport, GPU buffer, compile-time sequence.

### 11.2 Explicit channels

```duo
events = Channel[Event](capacity = 64)
events:send event
event = events:receive()
events:close()
```

Eliminate when producer-consumer topology is static (§19.2).

### 11.3 Selection via `@race`

```duo
event = @race
    messages:receive()
    shutdown:receive()
    timeout 1s
end
```

Reuse race semantics; avoid copying Go’s `select` keyword kingdom.

---

## 12. Scheduling, representation, and hardware realization

### 12.1 Scheduler candidates (not baked into language semantics)

No scheduler; compile-time static schedule; inline cooperative executor; single-thread event loop; work-stealing pool; target thread pool; real-time FP scheduler; GPU launch planner; distributed adapter; host-provided scheduler.

Small programs must not link a large scheduler. Static graphs lower to direct calls + joins with **effectively zero** generic scheduler overhead.

### 12.2 Elimination targets

| Materialization | Eliminate when |
| --- | --- |
| Heap task object | Lexical lifetime, no escape, static schedule |
| Independent stack | No suspension required |
| Scheduler | Static dependency graph |
| Channel | Known producer-consumer fusion |
| Atomics | Proven non-aliasing / immutability |
| Sync primitives | Dependencies already establish order |
| Return pack allocation | Fixed shape proven |
| Cancellation state | No child tasks / deterministic region |
| Thread pool startup | Work below granularity threshold |
| Device transfer | CPU cheaper by model |

### 12.3 Hardware descriptors

Target facts: core count, P/E cores, NUMA, cache hierarchy, vector width, atomics, memory ordering, GPU/accelerators, topology costs. Same concurrency source specializes per target.

---

## 13. Determinism, replay, failure, and cancellation

### 13.1 Contracts

```duo
@deterministic @parallel for item in items
    process item
end
```

Record only necessary semantic events for replay — not every instruction.

### 13.2 Failure categories (non-conflated)

Operation failure, cancellation, timeout, panic/trap, child aggregate failure, scheduler failure, device failure — surfaced through ordinary variant/return-pack architecture.

### 13.3 Cancellation

Structural: parent owns propagation unless overridden. `@all` policies: cancel siblings on first failure, collect all failures, partial completion, transactional all-or-nothing — descriptor-backed, inspectable.

---

## 14. Performance: beating Go honestly

Duo wins through **semantic knowledge and realization selection**, not benchmark tricks.

Required comparison dimensions (§21): spawn/join, lexical fork/join, producer-consumer, bounded channel throughput, fan-out/in, parallel map/reduce, I/O multiplexing, cancellation, timeout race, mixed CPU/IO, suspended-task overhead, scheduler contention, memory per task, deterministic replay overhead, startup/binary size, static schedule elimination, SIMD vs task parallelism, GPU where appropriate.

Every report includes: exact semantics, hardware, worker settings, allocations, sync ops, latency/throughput distribution, correctness validation.

---

## 15. Cross-system integration matrix

| Subsystem | Pass 24 consequence |
| --- | --- |
| **Lexer** | Long brackets unchanged; no shell token repurposing |
| **Parser** | Call forms §4; concurrency regions as `@` transforms; command context from Pass 15 |
| **Canonical syntax graph** | Invocation form on call nodes; classification §18 |
| **Semantic graph** | ExecutionRegion, CallObject, TaskEntity, StreamEntity |
| **Effects** | Scheduling legality, capability gates |
| **Alias / region analysis** | Parallel legality, race freedom, elimination |
| **Continuations** | Coroutine / task / stackless representations |
| **Return packs** | `@all`, failures, parallel reductions |
| **Variants / failures** | Task results, race outcomes |
| **Transformation registry** | `@spawn`, `@all`, `@race`, `@parallel` as registered transforms |
| **Realization planning** | Case analysis §9.2, hardware §12 |
| **DNIR / LIR / machine IR** | Direct calls, tasks, SIMD, GPU lowers |
| **Runtime profiles** | Pay-for-use scheduler linking |
| **Stdlib** | Channels, streams as ordinary modules |
| **Shell (Pass 15)** | Command context §4.4; pipelines share execution graph |
| **Package / build** | Capability-aware build graph |
| **Self-hosted compiler** | Parallel compile units as proof |
| **Ward** | Wasm threads/atomics via general mechanisms |
| **Formatter** | Canonical projection; preserve Lua on request |
| **Tree-sitter / LSP / MCP** | §16 |
| **Debugger / profiler** | Task scope, causality, deadlock diagnostics |
| **CI** | `pass24-gate`, Go benchmark suite, superset corpus |

---

## 16. Tooling: LSP, MCP, formatter, Tree-sitter, diagnostics

### 16.1 LSP must expose

Task scope, task result descriptor, inferred effects, possible overlap, alias conflicts, cancellation path, selected scheduler, task representation, parallelization blockers, ordering guarantees, deterministic status, allocation/sync cost estimates.

Diagnostics examples:

```
parallel region writes overlap field buffer[i]
cannot prove disjoint iteration ownership — falling back to sequential
bare identifier 'f' is value reference; use f() or f arg to invoke
```

### 16.2 MCP must expose

Execution graph, task dependency graph, conflict graph, scheduling candidates, selected realization, why parallel/serial, why task allocated, why channel materialized, why GPU/SIMD rejected, cancellation propagation, nondeterminism sources, replay requirements, benchmark evidence.

### 16.3 Formatter

- Default `.duo`: Duo-canonical projection (may omit `then`, `local`)
- `--lua-compat` or explicit mode: preserve Lua-canonical forms
- Never rewrite `[[ long strings ]]` delimiter levels or content

### 16.4 Tree-sitter

Grammar reflects both Lua-canonical and Duo-canonical forms; no deleted long-bracket nodes.

---

## 17. Ambiguity analysis

| Ambiguity | Resolution |
| --- | --- |
| `f x` — call vs space-separated expressions | Parenless invoke when callee syntactically callable in value position; `f` alone remains value |
| `add(x, y)` statement vs bare function | Typed param required for bare func (GRAMMAR_SPEC); untyped uses `fun` |
| `[[` — long string vs indexing | Lexer long-bracket algorithm; never bash conditional |
| Shell `pwd` vs variable `pwd` | Command invocation context (Pass 15), not global parse change |
| `@spawn f x` vs `@spawn (f x)` | `@spawn` binds to call expression; grammar doc + tests |
| Parallel vs deterministic | `@deterministic` contract overrides default freedoms |
| FP reduce reorder | Numeric law descriptors; strict modes preserve order |

---

## 18. Compatibility, migration, and syntax classification

See `docs/catalogs/lua_superset_compatibility.md` for the living matrix.

**Pass 21 reconciliation:** “Retire `then`” in Pass 21 means **formatter de-emphasis**, not `ACTUALLY_DEPRECATED`. Registry lifecycle = `lua_compatibility`. Pass 24 supersedes any doc implying `then` is obsolete.

**Migration:** Duo extensions never require rewriting valid Lua. Opt-in formatters and linters may suggest Duo-canonical forms.

---

## 19. Complete examples

### 19.1 Structured fetch dashboard

```duo
fetch_dashboard = (user_id)
    user_job = @spawn api:user user_id
    posts_job = @spawn api:posts user_id
    stats_job = @spawn analytics:summary user_id
    user, posts, stats = @all
        user_job:value()
        posts_job:value()
        stats_job:value()
    end
    Dashboard{
        user
        posts
        stats
    }
end
```

Lowering: three tasks if IO-bound + overlap legal; inline sequential if latency model prefers; static join without heap tasks if lifetimes lexical.

### 19.2 Parallel document pipeline

```duo
summaries = @parallel documents
    :map read
    :map parse
    :filter .valid
    :map summarize
```

Candidates: sequential fused loop → SIMD text scan → multicore by document → streaming if inputs are lazy.

### 19.3 Bounded producer-consumer (and channel elimination)

```duo
jobs = Channel[Job](capacity = 256)
results = Channel[Result](capacity = 256)
workers = @all for _ = 1, target.cpu.count
    @spawn
        for job in jobs
            results:send process job
        end
    end
end
for input in inputs
    jobs:send Job{input}
end
jobs:close()
for result in results
    consume result
end
```

When topology + lifetimes are static, compiler fuses to direct worker loop **without materializing channels**.

### 19.4 Deterministic parallel reduction

```duo
total = @deterministic @parallel values:reduce 0, (a, b) a + b
```

Associativity + determinism contract required; tree reduction with fixed order when specified.

### 19.5 Heterogeneous image pipeline

```duo
pixels = @parallel image.pixels
    :map linearize
    :map tone_map
    :map encode
```

Realization: scalar loop (tiny images), SIMD (medium), GPU (large + transfer win).

### 19.6 Structured failure with `@race`

```duo
page, failure = @race.first_success
    cache:get key
    origin:get key
    timeout 2s
end
if failure
    return nil, failure
end
page
```

### 19.7 Shell + concurrency

```duo
repositories = gh repo list --json name,url
results = @parallel repositories
    :map (repo)
        @all
            git clone repo.url
            metadata:fetch repo.name
        end
    end
```

Command descriptors + execution graph unify shell and native concurrency.

### 19.8 First-class callbacks (must not break)

```duo
handlers = { Save = save, Load = load }
items:each handlers.Save
callback = print
callback "hello"
```

Bare `callback` retrieves value; `callback "hello"` parenless-invokes; `callback()` zero-arg invokes.

---

## 20. Implementation ordering

| Phase | Scope | Depends on |
| --- | --- | --- |
| **P0** | Long brackets, superset gate, `then`/Lua classification fix | — |
| **P1** | Lua 5.5 corpus + differential tests | P0 |
| **P2** | Call architecture spec in graph (CallObject, invocation form) | P0 |
| **P3** | ExecutionRegion + TaskEntity in semantic graph | P2, Pass 22 |
| **P4** | `@spawn`, `@all`, `@race` transforms + structured scope | P3 |
| **P5** | `@parallel` regions + legality + sequential fallback | P3, effects |
| **P6** | Cost model + `@comp.why.*` | P5 |
| **P7** | Streams + channels + fusion elimination | P4–P6 |
| **P8** | Determinism, replay, failure variants | P4 |
| **P9** | Scheduler/representation candidates | P5–P7 |
| **P10** | Hardware / GPU / SIMD realization | P9, Pass 22 |
| **P11** | LSP/MCP/tooling surfaces | P4–P10 |
| **P12** | Go benchmarks + Ward/self-host proofs | P4–P11 |

Current repo status: **P0 partial**, **P1 partial** (`lua_superset_corpus.zig`), P2+ design only.

---

## 21. Benchmarks and vertical proofs

### 21.1 Go equivalence suite (required before superiority claims)

1. Task spawn/completion  
2. Lexical fork/join  
3. Producer-consumer pipeline  
4. Bounded channel throughput  
5. Fan-out/fan-in  
6. Parallel map  
7. Parallel reduction  
8. I/O multiplexing  
9. Cancellation  
10. Timeout race  
11. Mixed CPU/IO  
12. Many suspended tasks (where semantic)  
13. Small-task overhead  
14. Scheduler contention  
15. Memory per suspended task  
16. Deterministic replay overhead  
17. Startup/binary size  
18. Static schedule with scheduler elimination  
19. SIMD vs task parallelism  
20. GPU realization (where appropriate)

### 21.2 Ward proofs (general mechanisms only)

Parallel Wasm module compilation, concurrent function-tier compilation, work-stealing independent units, parallel validation, Wasm threads/atomics, deterministic replay of host nondeterminism, parallel test execution, concurrent code-cache population.

---

## 22. Success criteria

Pass 24 completes when all hold:

1. Long-bracket family preserved with Lua delimiter semantics  
2. Superset matrix covers full Lua surface with test evidence  
3. Bare identifiers remain value references; invocation explicit  
4. Parenless and parenthesized calls coexist with Lua  
5. Single execution graph lowers all concurrency forms  
6. `@spawn`/`@all`/`@race`/`@parallel` work on ordinary calls  
7. No mandatory async/await  
8. Structured task scope by default; explicit detach  
9. Effects + alias drive scheduling; unexplained parallel rejected  
10. Channels/streams fusible when topology static  
11. Scheduler/task/channel elimination proven on static graphs  
12. `@comp.why.*` explains major decisions  
13. LSP/MCP expose graph facts  
14. Go benchmark suite passed with semantic equivalence  
15. Ward proofs use no private hooks  
16. Formatter canonical without deprecating Lua  
17. Zero `lua_Value` regression on typed paths  
18. `zig build pass24-gate` green  

---

## 23. Prohibited outcomes

- Bare callable auto-invocation globally  
- `[[ … ]]` as non-string syntax  
- Deprecating Lua syntax for formatter convenience alone  
- Second concurrent runtime semantic model  
- Ward-only concurrency hooks  
- Silent FP reorder breaking contracts  
- Parallelism without cost model approval  
- Claiming Go superiority without §21 evidence  
- Channels required for all composition  
- Fire-and-forget tasks without owner/capability  

---

## 24. Relation to other passes

| Pass | Relationship |
| --- | --- |
| **Pass 15** | Semantic shell; command invocation context §4.4 |
| **Pass 21** | Keyword lifecycle; formatter vs deprecation reconciliation §18 |
| **Pass 22** | Semantic graph, realization, hardware — execution graph substrate |
| **Pass 23** | Call syntax, methods, return packs, protocols — CallObject foundation |
| **Pass 25** | Views, lifetimes, provenance — `@all` disjointness proofs §25 in Pass 25 constitution |
| **Pass 9/16** | Ward / self-hosted proofs §21.2 |
| **Pass 4** | Native lowering, no lua_Value |

**Supersedes:** compressed addenda that implied `then` deprecation or bare-name invocation. **`docs/plans/lua_superset_concurrency_supremacy.md`** is now an index pointing here.

---

*Pass 24 is the design constitution and execution prompt for agents. Implementation claims must cite gate IDs and benchmark evidence — not architecture prose alone.*
