# pecoffarm emit benchmark

| # | directive |
|---|---|
| 1 | ARM64 + PE/COFF/Windows backend (`lib/compiler/pecoffarm.id`): cost of building the emitter and emitting a PE/COFF executable. |
| 2 | 2026-09-11. |

## Environment

- Host: Mac mini, Apple Silicon (arm64), macOS
- Idol CLI: `/private/tmp/t_d0b6f987/idol` (repo at `85886ee3`)
- Emitter built with `idol compile lib/compiler/pecoffarm.id --backend native`
  (direct emission: no C, no assembler, no linker in the emit path)

## Methodology

- Compile time: wall clock of a cold `idol compile pecoffarm.id --backend
  native -o peemit` (fresh filename to defeat the CLI build cache),
  `/usr/bin/time -p`.
- Emit time: 60 runs of `peemit` (stdin `42`), best and median of
  wall-clock per run, output length asserted at 3072 hex chars each run.
- Output: PE/COFF executable bytes via `xxd -r -p`.
- Correctness: `test/pecoffarm.sh` (structural parse of every header field
  + import table + entry instructions, and a clang assembler oracle for all
  5 emitted instruction words). All checks pass.

## Results

| metric | value |
|---|---|
| `idol compile pecoffarm.id --backend native` (cold) | 90 ms wall |
| emit 1536-byte PE as hex (best of 60) | 1.7 ms |
| emit 1536-byte PE as hex (median of 60) | 2.1 ms |
| emitted executable size | 1536 bytes |
| `idol check lib/compiler/pecoffarm.id` | clean, no errors |

| # | directive |
|---|---|
| 1 | The emitter binary itself is ~53 KB. |
| 2 | Emission is string concatenation of 3072 hex chars; there is no optimization to measure yet — the backend emits a fixed 5-instruction entry program. |

## What the emitter produces

| # | directive |
|---|---|
| 1 | A 1536-byte PE/COFF for AArch64, laid out as: |

- DOS header (64 B, `MZ`, `e_lfanew = 0x80`) + 64 B stub
- PE signature, COFF header (`Machine = 0xaa64`, 2 sections)
- PE32+ optional header (`Magic = 0x20b`, entry `0x1000`,
  image base `0x140000000`, section/file alignment `0x1000`/`0x200`,
  subsystem console, import directory at RVA `0x2000`)
- `.text` (RVA `0x1000`, executable+readable) and `.idata` (RVA `0x2000`,
  read/write for IAT binding)
- Import table: one descriptor importing `ExitProcess` by name (hint 0)
  from `KERNEL32.dll`, with ILT and IAT

| # | directive |
|---|---|
| 1 | Entry program (20 bytes at RVA `0x1000`): |

```
sub sp, sp, #32      ; d10083ff — 32-byte shadow space (Windows ARM64 ABI)
movz x0, #42        ; d2800540 — first integer argument in x0
adrp x1, #1         ; b0000001 — page of the IAT (0x1000 -> 0x2000)
ldr x1, [x1, #0x38] ; f9401c21 — load ExitProcess address from IAT
blr x1             ; d63f0020 — call it; never returns
```

## ARM64 Windows ABI notes

- Integer arguments go in x0-x7 (up to 8); the exit code is the first and
  only argument, so it goes in x0. Floating-point would use v0-v7.
- The caller reserves 32 bytes of shadow space (home area) on the stack
  for the callee's use: `sub sp, sp, #32` before the call. Small leaf
  routines sometimes skip it, but the ABI requires it and the emitter
  follows the ABI.
- The PE entry point is called by the loader with no arguments and does
  not return to the loader; the process terminates via `ExitProcess`.
  No CRT startup object is linked — the entry point IS the program.

## Import choice: ExitProcess from kernel32

| # | directive |
|---|---|
| 1 | `ExitProcess` (kernel32.dll) is the documented way for a raw PE entry point to terminate the process with a status code. |
| 2 | Alternatives considered: `RtlExitUserProcess` (ntdll, lower-level, less documented for direct use) and returning from the entry point (undefined without CRT — the loader expects the entry not to return). |
| 3 | ExitProcess is the minimal, documented, CRT-free termination path, so the import table carries exactly one function from exactly one DLL. |

## Backend quirk found (for the compiler workstream)

| # | directive |
|---|---|
| 1 | While building this, `hlen = pe:len() / 2` — `:len()` on the ~944-char concatenated header string — hung the compiled emitter (killed under the C backend; silent empty output under `--backend native`). `:len()` on shorter strings in the same program works. |
| 2 | The emitter now computes the header length from layout constants (`64 + 64 + 4 + 20 + 240 + 80`) instead. |
| 3 | Root cause not diagnosed; flagging for the compiler fixes workstream, not worked around beyond the constant. |

## Gaps (stated plainly)

- No Windows ARM64 machine is available, so the emitted executable has
  never been executed. Validation is structural (every header field,
  section, import-table entry, and RVA parsed and asserted) plus a
  differential oracle: all 5 instruction words were assembled
  independently with the system clang and match bit-for-bit, including
  the linked adrp/ldr pair resolving to the IAT.
- The emitter currently produces one fixed program shape (exit code via
  stdin). General codegen reuse goes through `peexe(codehex)`, which
  takes arbitrary ARM64 code hex and wraps it in the same container.
