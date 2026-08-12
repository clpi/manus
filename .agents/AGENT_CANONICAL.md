# Idol agent router

`AGENTS.md` is the repository entry point — including **Idol harness
orientation** (harness routing, not C0). This file is its stable path
router; it contains no language law and no volatile project status.

## One law

| Purpose | Path |
|---|---|
| Sole semantic law | `docs/spec/constitution.md` |
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
   `CLAUDE.md`, `docs/AGENT_ALIGNMENT.md`, `docs/bootstrap.md`, and the
   scope-specific authority.
2. Call `duo_agent_session_start(agent_id="your-id")` on `duo-bench`.
3. Inspect `git status --short --branch`, current HEAD, recent commits,
   `duo_dev_claim_files`, every current `gaps/GAP-*.md`, and `git stash list`.
   Verify the executed frontier in `docs/bootstrap.md` against production.
4. Treat the session-start gap summary as incomplete until `GAP-131` closes;
   route work from the exact gap files and live claim result.
5. Claim exact paths with `duo_dev_claim_acquire` before editing.
6. Run heavy gates through the repository lock and record the inner outcome.
   The MCP health gate is
   `repo="$(git rev-parse --show-toplevel)" && "$repo/zig-out/bin/duo" run --backend=c "$repo/scripts/duo_lock.id" -- zig build mcp-gate`.
   The `.id` lock entry is executed bootstrap transport, not self-hosting proof.
7. Commit only explicit owned paths and release only your own claims.

The language identity is **Idol** (`idol`, `.id`). Semantic law lives in
`docs/spec/constitution.md` (C0). Branding is not ontology.
Active development repository is `clpi/duo`. Future release repository is
`idollang/idol`; do not migrate development there until
`.agents/RELEASE_READINESS.md` authorizes release. The physical `duo` command
and `duo-*` MCP names are bootstrap aliases. Historical Idol, Duo, Duon, and
`.duo` paths are migration provenance.

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
