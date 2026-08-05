# Duo Language Reference

**Status:** Supported (user-facing). **Audience:** developers evaluating or writing Duo.

Duo is a Lua-compatible language with optional static types, `@comp.*` compile-time transforms, and native lowering to C (or WASM). Untyped `.lua` remains valid; `.duo` adds types and metaprogramming without a runtime VM.

## Quick start

```bash
zig build
./zig-out/bin/duo run examples/hello.duo
./zig-out/bin/duo check my_module.duo
```

## Canonical topics

| Topic | Document |
| --- | --- |
| Overview and idioms | [docs/src/overview.md](src/overview.md), [docs/src/idiomatic_duo.md](src/idiomatic_duo.md) |
| Types | [docs/src/types.md](src/types.md) |
| Functions (typed, generic, async) | [docs/src/functions.md](src/functions.md) |
| Pattern matching, enums, concepts | [docs/src/pattern_matching.md](src/pattern_matching.md), [docs/src/enums.md](src/enums.md), [docs/src/concepts.md](src/concepts.md) |
| Standard library | [lib/std.duo](../lib/std.duo), [docs/src/stdlib.md](src/stdlib.md) |
| Grammar rules (GR-*) | [docs/GRAMMAR_SPEC.md](GRAMMAR_SPEC.md) |
| Roadmap vs implemented | [docs/src/roadmap.md](src/roadmap.md) — **Experimental** sections are labeled there |

Full book-style index: [docs/src/SUMMARY.md](src/SUMMARY.md).

## What works today

- AOT compile `.duo` / `.lua` → native binary via generated C + `clang`
- Typed native paths (no `lua_Value` on annotated/comptime paths)
- `@comp.*` metaprogramming registry; `duo catalog` for machine-readable facts
- WASM (`wasm32-wasi`), `duo fmt`, `duo explain`, `duo realize` (Pass 8 partial)
- 40-benchmark performance gate vs hand-written C (`zig build bench`)

## Experimental / in progress

- Native exe backend (arm64 subset), semantic graph persistence, Ward Wasm runtime proof — see [docs/plans/SUMMARY.md](plans/SUMMARY.md). **Planned** items are not release-contract behavior.

## Internal / agent-facing (not public architecture)

Contributor agent rules live in [AGENTS.md](../AGENTS.md) and [.agents/](../.agents/) — not required to use Duo.
