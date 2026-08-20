---
name: idol
description: Idol language authority projection. Use for any question about Idol semantics, canonical source, compiler architecture, self-hosting, or FTCFTW. Routes to current authority and the bootstrap frontier. For edits, use the idol-dev skill.
license: MIT
---

# Idol language authority projection

**Idol** (`idol`, `.id`) is the language identity. The active development
repository is reported by `tools/node/dev/repository`; the release repository
remains untouched until release-readiness authorization.

This skill does not add law. It routes to the sole semantic law and its
operative projections.

## Authority order

1. `docs/spec/law.md` — supreme one-page law.
2. `AGENTS.md` — workflow and mechanical preflight.
3. `docs/spec/canonical.md` — blind-start constitution.
4. `docs/spec/agent.md` — sole new-agent bootstrap.
5. `docs/spec/constitution.md` — C0 semantic authority.
6. `CLAUDE.md` — operative projection of C0.
7. `docs/spec/source.md` — source/home/package/world closure.
8. `docs/spec/host.md` — host/shell/capability boundary.
9. `docs/spec/AUTHORITY.md`, `docs/bootstrap.md` — projection routing and executed frontier.
10. `.agents/AGENT_CANONICAL.md`, `.agents/AGENT_COORDINATION.md` — ownership.
11. Exact current `gaps/GAP-*.md` files for the frontier being touched.

## Non-negotiable invariants

- **No `std` namespace.** There is no `std.*`, `lib.*`, or `core.*` in canonical
  source, gates, agents, or teaching examples. Use layout-projected homes and
  worlds (`fs`, `json`, `os`, `io`) with subject-first relations.
- **No generated-C backend in source semantics.** `--backend=c` is a foreign CLI
  input projected to realization facts, not canonical source semantics. Prefer
  direct-native execution; use `idol run` and `idol check`, not `--backend=c`, for
  gates and proofs.
- **SOURCE-INFER-ONE.** If the graph can recover a fact uniquely, source should
  not spell it. No canonical `value:to()` rung; no single-use bridge bindings;
  no dependency syntax when use determines the dependency.
- **Relation identity owns operations.** Edges are structural roles
  (`subject`, `operand`, `result`, `binding`, `descriptor`, `projection`,
  `capture`, `world`, `witness`, `demand`, `provenance`, `realization`). No
  operational edge kinds (`call`, `run`, `read`, `write`, `parse`, `lower`,
  `emit`).
- **Identity is `id` only.** Names, paths, spans, source spelling, hashes,
  fingerprints, intern slots, opcodes, and pointers are provenance or
  acceleration, never semantic identity.
- **Filesystem is ingestion and provenance only.** After resolution, path has no
  semantic lookup authority. There is no module/import/namespace admission
  syntax.
- **Source has law; world has authority.** Exactly one source law owns each
  source position and the one grammar authority projects it into recognition.
  A world never switches parsers, a source law never grants execution
  authority, and foreign syntax never becomes a permanent semantic node kind.

## Canonical source faces

```id
x = value
x: descriptor = value
add = (a, b) a + b
value:validate():normalize()
env["HOME"]
arg[1]
table[key]
source:read()
stdout:write(text)
```

## What to do

- For **editing Idol source, gates, gaps, or compiler code**, invoke the
  `idol-dev` skill and follow its preflight/claim discipline.
- For **explaining a law, resolving a conflict, or deciding canonical form**,
  read the authority chain emitted by `tools/node/dev/repository authority`; a
  projection that conflicts with higher authority must be repaired.
- If a fact appears missing, first read the law and run the smallest research,
  differential, or measurement that can settle it. If it remains absent, fail
  closed and record the exact producer/consumer gap. Do not mint a helper,
  registry, context, or bridge to supply it.
