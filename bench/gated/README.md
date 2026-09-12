# Gated benchmark categories (`bench/gated`)

Future benchmark categories that **cannot be expressed in the Idol
compiled subset today**. Each has:

- `<name>.c` — the C oracle (runnable today; semantics frozen),
- `<name>.id.future` — the intended Idol source in *proposed* syntax,
  clearly marked; does NOT compile with the current compiler,
- a gating condition: the exact compiler feature that unlocks it.

Nothing here runs in `bench/run.sh` (no `.id` file exists, so the
correctness gate cannot pick it up). Adoption checklist per category:

1. Land the gating compiler feature in `lib/compiler/`.
2. Write the real `bench/programs/<name>.id`; verify exit-code equality
   against the frozen C oracle.
3. Move the row from the "gated" table to the extended-suite table in
   `bench/README.md`; run with `./run.sh --progs <name>`.
4. If the category beats/misses its oracle, update
   `docs/design/optimum.md` with the per-benchmark optimum.

## Categories

| program | stresses | gated on |
|---|---|---|
| `fp_dot` | floating-point multiply-add, 1M elements | float type + float arithmetic in the subset |
| `indirect` | indirect calls through a 4-entry dispatch table | function definitions + indirect calls |
| `strops` | byte-wise strlen/strcpy over 1 MB | byte-addressable memory (load/store) |
| `traverse` | linked-list walk, 1M nodes, pointer chasing | memory + pointers |
| `cache_seq` / `cache_stride` | memory hierarchy: stride-1 vs stride-64 walk over 64 MB | memory (array indexing) |

`cache_seq` vs `cache_stride` is the cache-friendly/cache-hostile pair:
identical work, different access pattern. The delta isolates the memory
hierarchy; a compiler that cannot see the pattern (no alias/memory
model yet) is expected to tie — the pair exists to catch regressions
and to reward a future memory optimizer honestly.
