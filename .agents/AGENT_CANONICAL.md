# Idsem agent router

`AGENTS.md` is the repository entry point. This file is its stable path router;
it contains no language law and no volatile project status.

## One law

| Purpose | Path |
|---|---|
| Sole semantic law | `docs/spec/constitution.md` |
| Operative projection | `CLAUDE.md` |
| Grammar projection | `docs/spec/grammar.md` |
| Source-family classification | `docs/spec/corpus.md` |
| Authority and migration protocol | `docs/spec/AUTHORITY.md` |
| Priority compass | `docs/AGENT_ALIGNMENT.md` |
| Executed compiler frontier | `docs/bootstrap.md` |
| Ownership and gates | `.agents/AGENT_COORDINATION.md` |
| MCP setup | `.agents/AGENT_INTEGRATION.md` |
| Performance evidence | `docs/performance.md` |
| Open obligations | `gaps/GAP-0NN.md` |

The constitution is structured law documentation, not executable source or a
pattern library. Canonical implementation uses `.id`. No pass document or
historical corpus file is an authority.

## Session start

1. Read `AGENTS.md`, the constitution, `CLAUDE.md`,
   `docs/AGENT_ALIGNMENT.md`, `docs/bootstrap.md`, and the scope-specific
   authority.
2. Call `duo_agent_session_start(agent_id="your-id")` on `duo-bench`.
3. Inspect `git status --short --branch`, current HEAD, recent commits, live
   claims, open gap files, and `git stash list`.
4. Treat the session-start open-P0 count as incomplete until `GAP-131` closes.
5. Claim exact paths with `duo_dev_claim_acquire` before editing.
6. Run heavy gates through the repository lock and record the inner outcome.
7. Commit only explicit owned paths and release only your own claims.

The current physical `duo` command and `duo-*` MCP names are bootstrap aliases.
They do not rename Idsem or authorize new `.duo` implementation.

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
