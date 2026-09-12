# L6/L7 Hermes bridges: Idol reimplementation roadmap

Status: 2026-09-11 — full reimplementation NOT yet feasible. Maximal
Idol-expressible decision core is implemented in `lib/live/` (see below);
this doc specifies the exact language gaps and the dependency-ordered
feature list required to complete the port.

## 1. What the Python bridges do

- `idol_live_adaptive_routing.py` (L6): reads provider history from
  SQLite (`kanban.db`, table `tasks`), scores each certified
  (provider, model) by `success_rate / p50_latency`, picks the best with
  5% exploration, sets `provider_override`/`model_override` on ready
  tasks. Fail-closed: routes only to prepaid-certified pairs listed in
  `prepaid-route-policy.json`. Dry-run by default (`--apply` to write).
- `idol_live_semantic_cache.py` (L7): normalizes completed-task text,
  SHA-256 fingerprints for exact dedup, Jaccard word-set similarity with
  0.9 threshold for near-dedup, matches pending tasks against the
  completed cache. Writes hit-rate state JSON. Dry-run by default.

## 2. What is implemented in Idol now

`lib/live/route.id` — L6 pure decision kernel (canonical Idol, integer
I/O, `idol check` clean):

| function | contract |
|---|---|
| `score(done, total, plat)` | fixed-point x1e6 of `done/total/max(plat,1)`; 0 when `total == 0`. Mirrors Python `score()`. |
| `pick(ta, sa, tb, sb)` | pairwise route choice returning 0/1: prefers the candidate with history (`t > 0`), else higher score, ties go to the first. Mirrors `route_task` selection order. |
| `lcg(seed)` | deterministic PRNG step `seed * 1103515245 + 12345`. |
| `explore(seed)` | 1 when the draw falls in the 5% exploration band, else 0. Mirrors `rng.random() < 0.05`. |
| `routeopen(n)` | 1 when `n > 0` else 0 — the fail-closed gate: zero certified routes means refuse to route. |

`lib/live/cache.id` — L7 pure decision kernel:

| function | contract |
|---|---|
| `fpeq(a, b)` | 1 on exact integer-fingerprint match (exact-dedup hit). |
| `near(inter, union)` | 1 when Jaccard `inter/union >= 0.9`, computed as `inter * 10 >= union * 9`; empty/empty counts as similar. Mirrors the 0.9 threshold. |
| `wasted(n)` | `n - 1` for duplicate groups larger than 1, else 0. Mirrors the wasted-runs estimate. |
| `popcount(w)` | bit count of a non-negative integer word-set mask; the integer primitive a future string layer feeds into `near`. |

Fixed-point convention: scores are scaled by 1,000,000; callers compare
scaled values directly, never floats. RNG parity with CPython's Mersenne
Twister is intentionally NOT required — only the 5% rate contract.

Verified: `idol check lib/live/route.id`, `idol check lib/live/cache.id`
both pass; behavior asserted via `idol run` on a temp harness (see §5).

## 3. Exact language gaps (why the full port is blocked)

The only Idol-to-machine path today is `lib/compiler/native.id`, whose
v5 input language is: assignments, integer literals, `+ - * /`,
`while x < y` loops, single-operator expressions, no function
definitions or calls, no `if`, no string type, no input, and exit-code
as the sole output. Verified by reading the compiler's statement parser
(`native.id` main loop: `while` detection scans for byte 60 `<`;
assignment handling splits on a single `=`).

Neither bridge can be expressed in v5 because both require, at minimum:

1. **Strings** — provider/model names, task titles, SQL text, JSON text.
   No string type exists in v5; canonical Idol has a string type but no
   executed path from it to machine code for these programs.
2. **File I/O beyond exit codes** — read `prepaid-route-policy.json`,
   write `adaptive-routing.json` / `semantic-cache.json`. v5 cannot read
   or write anything.
3. **SQLite** — `lib/sqlite.id` declares `@ffi` bindings to libsqlite3,
   but the S0 bootstrap has no executed FFI call path; `idol run`
   executing a real query is unproven.
4. **JSON parsing** — `lib/json.id` exists as source but likewise has no
   executed path; and it needs (1) and (2) first.
5. **String normalization** — lowercase, regex (`t_[a-f0-9]+`,
   number/whitespace collapsing) for L7; needs (1) plus regex or
   equivalent primitives.
6. **Hashing** — SHA-256 for L7 fingerprints (or a specified integer
   fingerprint the Idol side owns end-to-end).
7. **CLI args / stdout / wall clock / OS RNG** — the bridges take
   `--apply/--limit/--seed/--threshold`, print decisions, and check
   certificate `valid_until` against `time.time()`.
8. **HTTP client** — not needed by these two bridges (they touch only
   SQLite/JSON/files), listed for completeness of the live stack.

## 4. Dependency-ordered feature list to complete the port

1. String type + ops (concat, length, compare, split, case-fold) in an
   executed backend.
2. File read/write syscalls reachable from Idol.
3. JSON parse/emit over (1)+(2).
4. Executed SQLite path (FFI or builtin) for SELECT/UPDATE on `tasks`.
5. Regex or the string primitives to hand-roll L7 normalization.
6. Integer hash / SHA-256 for fingerprints.
7. CLI args, stdout, clock, OS-seeded RNG.
8. Port orchestration loops over query rows into `lib/live/route.id`
   / `lib/live/cache.id`, preserving: fail-closed certified gate,
   prepaid-only routing, dry-run default.
9. Retire the Python bridges only after byte-parity dry-run comparison
   on live data.

## 5. Verification performed

- `idol check` clean on both new files (host compiler
  `zig-out/bin/idol`, 2026-09-11).
- Behavioral test: temp file concatenating both modules plus a `main`
  with 20 assertions, compiled with
  `idol compile --backend native --target native-exe` and executed —
  exit 0. Assertions: `score(8,10,200)` = 4000, `score(0,0,5)` = 0,
  `score(5,10,0)` = 500000 (latency floor), `pick` prefers history then
  score with first-wins ties, `routeopen(0)` = 0, `near(9,10)` = 1,
  `near(8,10)` = 0, `near(0,0)` = 1, `wasted(3)` = 2,
  `popcount(11)` = 3, and `explore` returns only 0/1 with exactly 50
  hits over seeds 1..1000 (the 5% contract; i64 wraparound confirmed).
- Idolic invariants on new Idol code: zero comments, no underscores,
  lowercase one-word names; files placed per `subject:edge`
  (`live` subject: `route` ~ `live/provider/adaptive`,
  `cache` ~ `live/infer/prefetch`).
- Python bridges untouched and still running; no credentials touched;
  routing stays prepaid-only by construction (candidates passed to
  `pick` must come from the certified set).

## 6. Sibling audit coordination

A sibling agent is auditing spec compliance including L6/L7-in-Idol
feasibility. No findings were on `main` at implementation time; this
roadmap is written to be cross-checked against theirs. If their audit
lands first, reconcile §3 against it before starting §4.
