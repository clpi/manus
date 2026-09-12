| field | value |
|---|---|
| title | elfx86 emit benchmark |

| # | directive |
|---|---|
| 1 | Date: 2026-09-11. |
| 2 | Host: Mac mini (arm64, Darwin) via `idol compile --backend native`. |
| 3 | Scope: x86_64 encoder library (`lib/compiler/x86.id`) and x86_64+ELF64/Linux direct backend (`lib/compiler/elfx86.id`) only. |
| 4 | The bench harness (`bench/run.sh`) is arm64-Darwin-only and was not modified; these are standalone measurements. |

| section |
|---|---|
| What is measured |

| # | directive |
|---|---|
| 1 | `compile`: `idol compile lib/compiler/elfx86.id --backend native -o emit` (builds the emitter itself; cold vs warm shown separately). |
| 2 | `emit`: running the emitter on the division demo program (`a = 20 / b = 6 / c = a / b / c`); it writes 1130 lowercase hex chars to stdout (565-byte ELF64 executable). |
| 3 | `check`: `test/elfx86.sh` — `idol check` on both files, 23/23 encoder vectors vs clang, ELF structural validation, and clang oracle on emitted `.text` for the arithmetic, division, and countdown-loop demos. |

| section |
|---|---|
| Results |

| metric | value |
|---|---|
| compile, cold (compiler-reported) | 0.34–0.44 s |
| compile, warm cache | ~0.01 s (incremental cache hit) |
| emit run (median of 5) | 0.01–0.02 s wall (first cold run 0.32 s) |
| output size | 565 bytes for the division demo (120 headers + 36 .text + 48 symtab + 8 strtab + 33 shstrtab + 320 section headers) |
| encoder vectors | 23/23 match clang byte-for-byte |
| structural assertions | ELF magic, class 64, type EXEC, machine x86_64, entry 0x400078, PT_LOAD R+X, 5 sections (.text/.symtab/.strtab/.shstrtab), .text vaddr == entry, _start symbol value/size — all pass |
| clang oracle | p1/p2 `.text` byte-identical to clang-assembled equivalents; p3/p4 countdown-loop patterns (counter init, decrement, jne back-edge, exit epilogue) present |

| section |
|---|---|
| Honesty notes |

| # | directive |
|---|---|
| 1 | No Linux/x86_64 execution target exists on the build machine, so there is no runtime timing of the emitted ELF; correctness is structural plus byte-exact `.text` against the clang oracle. |
| 2 | The demo programs exit via the Linux x86_64 syscall ABI (`mov rdi,rax; mov rax,60; syscall`); p1 exits 42, p2 exits 3 (20/6). |
| 3 | Warm-cache compile time is reported as observed, not as a claim about the compiler's general speed. |
| 4 | Two defects found during verification were fixed in `elfx86.id` before measurement: a 3-argument `divrr` call that silently dropped the divisor (new `div3` relation), and a `while` loop at end-of-input that lost its back-edge (sentinel close pass). A direct-backend refusal (DNB011) on a `breg()`-bound variable used as a call argument was worked around by inlining the call at the use site; the underlying graph-backend limitation is unchanged. |
