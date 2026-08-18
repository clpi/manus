# Idol release readiness ledger

This is a release-gating checklist, not semantic law and not live project status.
Active development stays in **`clpi/idol`**. **`idollang/idol`** remains untouched
until every blocker below is closed and explicit release authorization is recorded.

## Repository separation

| Requirement | Status |
|---|---|
| A configured development remote names `clpi/idol` during concurrent work | **required** — verified from the manifest and live remotes by `tools/node/dev/repository check` |
| Release repo `idollang/idol` receives no development commits | **open** — do not push dev work there |
| Release migration runbook exists as a dedicated future operation | **open** |
| `tools/node/dev/doctor` admits only a checkout with the configured development repository | **met** — release identity cannot satisfy the development check |

## Authority and orientation

| Requirement | Status |
|---|---|
| Single MCP manifest at `tools/node/dev/mcp.manifest.json` | **candidate implemented** — aggregate admission remains open |
| Single config generator `tools/node/dev/generate-configs` | **candidate implemented** — aggregate admission remains open |
| `orient` / `doctor` / `setup` derive live facts from current tree | **met** — verify on each clone |
| Cursor rules remain routers under C0; no client-specific constitution | **met** — 9 scoped rules |
| Language identity projects as Idol / `.id` without implying release-repo migration | **in progress** — reconcile projections |

## Canonicality and gates

| Requirement | Status |
|---|---|
| Update-face law owned by C0, projected by `AGENTS.md`; lexical implementation at `gate/idiom.id` | **blocked** — direct run refuses at DNB001 `concat`; static scans are not semantic proof |
| Graph-owned canonicalizer for update-face equivalence | **blocked** — `GAP-145`, `GAP-134`, `GAP-124` |
| Pre-commit / semantic gates pass on release candidate tree | **open** — requires clean aggregate run at candidate HEAD |
| Canonicality split enforced: new debt = 0 vs existing corpus debt tracked separately | **in progress** — see `docs/METRICS.md` |
| No second idiom/canonicality authority in clients | **met** — derive from repository gates |

## Semantic and SHC closure

| Requirement | Status |
|---|---|
| Exact-gap P0 census trustworthy (`GAP-131`) | **met** — retired MCP census deleted; `orient` derives `activep0` from exact gap headers |
| Executed self-host frontier meets release bar in `docs/bootstrap.md` | **open** |
| Production graph facts consumed without source-text reconstruction | **open** — Codex/Poolside lanes |
| FTCFTW evidence bundle for release candidate | **open** |

## Client node dev health

| Requirement | Status |
|---|---|
| Fresh clone: `tools/node/dev/setup` → generated MCP projections → doctor PASS | **open** — re-verify after each node dev change |
| Codex/Cursor MCP initialize probes pass on release candidate | **open** |
| Devin projection routes through `AGENTS.md` and node dev only | **met** at `HEAD` |

## Authorization

Release migration to `idollang/idol` requires an explicit authorization record
(named release operator, candidate commit, aggregate gate evidence, and signed
acceptance that this ledger is complete). Until then, treat any
`idollang/idol` push as out of policy.

## SHC frontend dependency (implementation lane — not Cursor)

Parser authority transfer (`GAP-134`) is **blocked upstream** until the lexical
→ grammar-role prerequisite closes. Order is fixed:

1. `gaps/GAP-145.md` — distinct lexical token identities (text, bytes, compat
   literals/comments, shebang, reserved backtick) without delimiter-text
   inference.
2. Generated grammar-role projection — `lib/token/grammarrole.id` from
   `src/grammar_roles.zig` / `idol token-tables emit`; no parser-local spelling
   tables.
3. Immutable token-pack view — `lib/compiler/token_view.id` and host
   `src/token_view.zig` for observation/lookahead.
4. `gaps/GAP-134.md` — first bounded production parser recognition slice.

**Owner:** Devin / SHC frontend lane. **Cursor does not implement this chain.**
Status and closure evidence live in the gaps and bootstrap ledger, not here.

## Agent lanes (disjoint write ownership)

| Lane | Scope |
|---|---|
| **Cursor** | Coordination, release-readiness ledger, node dev admission routers only |
| **Devin** | Lexical identity → grammar-role SHC prerequisite (`GAP-145` → `GAP-134` input) |
| **Poolside** | Realization / machine / FTCFTW |
| **AGY** | Adversarial audit / evidence truth |
| **Codex** | Semantic graph producer (when active) |

Claim exact paths before write. No broad cleanup. No release migration.

## Current node dev admission notes (2026-08-11)

| Check | Status |
|---|---|
| `tools/node/dev/orient` | **met** — derives `clpi/idol`, `idollang/idol`, and the authority order from the tracked manifest |
| `tools/node/dev/doctor` | **fail** — see blockers below |
| Single MCP manifest | **met** — `tools/node/dev/mcp.manifest.json` only |
| Cursor rules as routers | **met** — 9 scoped `.mdc`, all under 50 lines except always-on (21 lines) |

Doctor failures observed on this checkout (not an exhaustive census): pinned tool
version drift (zig, cursor, cursor-agent); stale compiler artifact vs
`src/dnir_lower.zig`; `gate/idiom.id` / `scripts/idol_lock.id` referenced
by doctor and coordination docs but **absent on disk** (only `.id` variants
present); aggregate build gates blocked (`src/sema.zig` compile error); MCP raw
initialize probe fail per `orient`. These are release/coordination blockers, not
permission to duplicate manifests or client constitutions.
