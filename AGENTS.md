# Agent Instructions

## Performance Work

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.
