| field | value |
|---|---|
| title | pecoffx86 emit benchmark |

| # | directive |
|---|---|
| 1 | Date: 2026-09-11. |
| 2 | Host: Mac mini (arm64, Darwin) via `idol compile --backend native`. |
| 3 | Scope: x86_64 PE/COFF backend (`lib/compiler/pecoffx86.id`) only. |
| 4 | The bench harness (`bench/run.sh`) is arm64-Darwin-only and was not modified; these are standalone measurements. |

| section |
|---|---|
| What is measured |

| # | directive |
|---|---|
| 1 | `compile`: `idol compile lib/compiler/pecoffx86.id --backend native -o emit` (builds the emitter itself; cold vs warm cache shown separately). |
| 2 | `emit`: running the emitter; it writes 3072 lowercase hex chars to stdout (1536-byte PE/COFF executable). |
| 3 | `check`: `python3 test/pecoffx86/check.py` — 89 structural assertions plus a pefile second oracle. |

| section |
|---|---|
| Results |

| metric | value |
|---|---|
| compile, cold (median of 5) | 0.10 s |
| compile, warm cache | ~0.00 s (incremental cache hit) |
| emit run (median of 5) | 0.023 s (0.0224–0.0245 s) |
| output size | 1536 bytes (512 headers + 512 .text + 512 .idata) |
| structural assertions | 89/89 pass |
| pefile oracle | parses: machine 0x8664, entry 0x1000, 2 sections, imports kernel32.dll!ExitProcess |

| section |
|---|---|
| Honesty notes |

| # | directive |
|---|---|
| 1 | No Windows execution target exists on the build machine, so there is no runtime timing of the emitted .exe; correctness is structural only. |
| 2 | The demo program computes ((6*7)+2)-2 = 42 in rax and exits via kernel32!ExitProcess with code 42 (MS x64 ABI: rcx = code, 32-byte shadow space, `call qword [rip+disp32]` through the IAT). |
| 3 | Warm-cache compile time is reported as observed, not as a claim about the compiler's general speed. |
