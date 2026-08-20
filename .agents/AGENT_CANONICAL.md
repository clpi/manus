[/Volumes/d 1/x/idol/.agents/AGENT_CANONICAL.md#E524]
1:# Idol agent router
2:
3:`AGENTS.md` is the repository entry point — including **Idol harness
4:orientation** (harness routing, not C0). This file is its stable path
5:router; it contains no language law and no volatile project status.
6:
7:## One law
8:
9:| Purpose | Path |
10:|---|---|
11:| Supreme compact law | `docs/spec/law.md` |
| Structured expansion / `law.*` owner | `docs/spec/constitution.md` |
12:| Idol algebra closure (C0 §67) | `docs/spec/constitution.md` §67 · `law.gate.protocol` · `law.gate.algebra` · `law.gate.infer` · `law.gate.convergence` |
13:| Convergence meta-invariants (SHC seams) | C0 §67 · `law.bridge.death` … `law.gate.convergence` · harness § seam audit |
14:| Harness reasoning (stable template) | `docs/spec/harness-projection.md` |
15:| Harness boot payload (generated) | `.agents/HARNESS.md` |
16:| Durable root orientation | `AGENTS.md` § Idol harness orientation |
17:| Source/home/package/world closure | `docs/spec/source.md` |
18:| Host boundary / shell / capability closure | `docs/spec/host.md` |
19:| Operative projection | `CLAUDE.md` |
20:| Grammar projection | `docs/spec/grammar.md` |
21:| Source-family classification | `docs/spec/corpus.md` |
22:| Authority and migration protocol | `docs/spec/AUTHORITY.md` |
23:| Executed compiler frontier | `docs/bootstrap.md` |
24:| Progress metrics dashboard | `docs/METRICS.md` |
25:| Priority compass | `docs/AGENT_ALIGNMENT.md` |
26:| Architecture injection (agent orientation) | `.agents/ARCHITECTURE_INJECTION.md` |
27:| Optimization frontier census (research map) | `docs/history/optimization-frontier-census.md` |
28:| Tech debt + FTCFTW workstream | `.agents/TECH_DEBT_WORKSTREAM.md` |
29:| Ownership and gates | `.agents/AGENT_COORDINATION.md` |
30:| Release readiness ledger | `.agents/RELEASE_READINESS.md` |
31:| MCP setup | `.agents/AGENT_INTEGRATION.md` |
32:| Performance evidence | `docs/performance.md` |
33:| Open obligations | exact current `gaps/GAP-*.md` files |
34:
35:The constitution is structured law documentation, not executable source or a
36:pattern library. Canonical implementation uses `.id`. No pass document or
37:historical corpus file is an authority.
38:
39:## Session start
40:
41:1. Read `AGENTS.md` (orientation + mechanical preflight), the constitution,
42:   `CLAUDE.md`, `.agents/ARCHITECTURE_INJECTION.md`, `docs/AGENT_ALIGNMENT.md`,
43:   `docs/bootstrap.md`, and the scope-specific authority. Consult
44:   `docs/history/optimization-frontier-census.md` before proposing new optimizer
45:   subsystems or IRs.
46:2. Run `tools/node/dev/orient` and inspect its exact authority/frontier output.
47:3. Inspect `git status --short --branch`, current HEAD, recent commits,
48:   `tools/node/dev/claim list`, every current `gaps/GAP-*.md`, and `git stash list`.
49:   Verify the executed frontier in `docs/bootstrap.md` against production.
50:4. Treat `tools/node/dev/orient` as a derived census only; route work from the
51:   exact gap files and live claim result. Reserve new numbers with
52:   `tools/node/dev/gap reserve`.
53:5. Claim exact paths with `tools/node/dev/claim acquire` before editing.
54:6. Run heavy gates through the repository lock and record the inner outcome.
55:   The MCP health gate is
56:   `repo="$(git rev-parse --show-toplevel)" && "$repo/tools/node/dev/idol-lock" -- zig build mcp-gate`.
57:   The lock wrapper is coordination transport, not semantic authority.
58:7. Commit only explicit owned paths and release only your own claims.
59:
60:The language identity is **Idol** (`idol`, `.id`, repository `idollang/idol`).
61:Semantic law lives in `docs/spec/constitution.md` (C0). Do not migrate to the
62:release repository until `.agents/RELEASE_READINESS.md` authorizes release.
63:The claim wrapper remains bootstrap transport until the graph-owned
64:coordination world closes. It is not language semantics and is not duplicated
65:inside MCP.
66:
67:No import or admission syntax in canonical source — reachability is scope and
68:home projection (`docs/spec/source.md`, `GAP-153`).
69:
70:`std` is migration distribution, not a semantic namespace. `std.script` is
71:frozen debt. New canonical `std.*` calls, APIs, generated source, and onboarding
72:examples are forbidden; missing subject/world vocabulary blocks rather than
73:creating another helper root.
74:
75:PREDICATE-ZERO is also fail-closed: subject-first spelling does not admit a
76:boolean helper when a semantic fact, case, transition, world, descriptor,
77:demand, or realization fact owns the meaning. Preserve unknown and absence;
78:missing vocabulary blocks rather than producing a helper predicate.
79:
80:## Fail closed
81:
82:If law conflicts, status cannot be verified, vocabulary is missing, or another
83:owner has not exposed a required fact: stop, record the exact blocker, and do
84:not create a substitute authority.