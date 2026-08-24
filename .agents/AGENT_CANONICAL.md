# Idol agent router

`AGENTS.md` is the repository entry point — including **Idol harness
orientation** (harness routing, not C0). This file is its stable path
router; it contains no language law and no volatile project status.

## One law

| Purpose | Path |
|---|---|
| Supreme compact law | `docs/spec/law.md` |
| Structured expansion / `law.*` owner | `docs/spec/constitution.md` |
| Idol algebra closure (C0 §67) | `docs/spec/constitution.md` §67 · `law.gate.protocol` · `law.gate.algebra` · `law.gate.infer` · `law.gate.convergence` |
| Convergence meta-invariants (SHC seams) | C0 §67 · `law.bridge.death` … `law.gate.convergence` · harness § seam audit |
| Harness reasoning (stable template) | `docs/spec/harness-projection.md` |
| Harness boot payload (generated) | `.agents/HARNESS.md` |
| Durable root orientation | `AGENTS.md` § Idol harness orientation |
| Source/home/package/world closure | `docs/spec/source.md` |
| Host boundary / shell / capability closure | `docs/spec/host.md` |
| Operative projection | `CLAUDE.md` |
| Grammar projection | `docs/spec/grammar.md` |
| Source-family classification | `docs/spec/corpus.md` |
| Authority and migration protocol | `docs/spec/AUTHORITY.md` |
| Executed compiler frontier | `docs/bootstrap.md` |
| Progress metrics dashboard | `docs/METRICS.md` |
| Priority compass | `docs/AGENT_ALIGNMENT.md` |
| Architecture injection (agent orientation) | `.agents/ARCHITECTURE_INJECTION.md` |
| Optimization frontier census (research map) | `docs/history/optimization-frontier-census.md` |
| Tech debt + FTCFTW workstream | `.agents/TECH_DEBT_WORKSTREAM.md` |
| Ownership and gates | `.agents/AGENT_COORDINATION.md` |
| Release readiness ledger | `.agents/RELEASE_READINESS.md` |
| MCP setup | `.agents/AGENT_INTEGRATION.md` |
| Performance evidence | `docs/performance.md` |
| Open obligations | exact current `gaps/GAP-*.md` files |

The constitution is structured law documentation, not executable source or a
pattern library. Canonical implementation uses `.id`. No pass document or
historical corpus file is an authority.

## Session start

1. Read `AGENTS.md` (orientation + mechanical preflight), the constitution,
   `CLAUDE.md`, `.agents/ARCHITECTURE_INJECTION.md`, `docs/AGENT_ALIGNMENT.md`,
   `docs/bootstrap.md`, and the scope-specific authority. Consult
   `docs/history/optimization-frontier-census.md` before proposing new optimizer
   subsystems or IRs.
2. Run `tools/node/dev/orient` and inspect its exact authority/frontier output.
3. Inspect `git status --short --branch`, current HEAD, recent commits,
   `tools/node/dev/claim list`, every current `gaps/GAP-*.md`, and `git stash list`.
   Verify the executed frontier in `docs/bootstrap.md` against production.
4. Treat `tools/node/dev/orient` as a derived census only; route work from the
   exact gap files and live claim result. Reserve new numbers with
   `tools/node/dev/gap reserve`.
5. Claim exact paths with `tools/node/dev/claim acquire` before editing.
6. Run heavy gates through the repository lock and record the inner outcome.
   The MCP health gate is
   `repo="$(git rev-parse --show-toplevel)" && "$repo/tools/node/dev/idol-lock" -- zig build mcp-gate`.
   The lock wrapper is coordination transport, not semantic authority.
7. Commit only explicit owned paths and release only your own claims.

The language identity is **Idol** (`idol`, `.id`, repository `idollang/idol`).
Semantic law lives in `docs/spec/constitution.md` (C0). Do not migrate to the
release repository until `.agents/RELEASE_READINESS.md` authorizes release.
The claim wrapper remains bootstrap transport until the graph-owned
coordination world closes. It is not language semantics and is not duplicated
inside MCP.

No import or admission syntax in canonical source — reachability is scope and
home projection (`docs/spec/source.md`, `GAP-153`).

`std` is migration distribution, not a semantic namespace. `std.script` is
frozen debt. New canonical `std.*` calls, APIs, generated source, and onboarding
examples are forbidden; missing subject/world vocabulary blocks rather than
creating another helper root.

PREDICATE-ZERO is also fail-closed: subject-first spelling does not admit a
boolean helper when a semantic fact, case, transition, world, descriptor,
demand, or realization fact owns the meaning. Preserve unknown and absence;
missing vocabulary blocks rather than producing a helper predicate.

## Fail closed

If law conflicts, status cannot be verified, vocabulary is missing, or another
owner has not exposed a required fact: stop, record the exact blocker, and do
not create a substitute authority.