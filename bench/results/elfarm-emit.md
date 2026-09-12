# elfarm emit benchmark

| # | directive |
|---|---|
| 1 | ARM64 + ELF/Linux backend (`lib/compiler/elfarm.id`): cost of building the emitter and emitting a static AArch64 ELF executable. |
| 2 | 2026-09-12. |

## Environment

- Host: Mac mini, Apple Silicon (arm64), macOS
- Idol CLI: repo at `7503ff27`
- Emitter built with `idol compile lib/compiler/elfarm.id --backend native`
  (direct emission: no C, no assembler, no linker in the emit path)

## Methodology

- Compile time: wall clock of a cold `idol compile elfarm.id --backend
  native -o elfarm` (fresh filename to defeat the CLI build cache),
  `/usr/bin/time -p`.
- Emit time: 5 runs of `elfarm` (stdin: 486-char Mach-O hex of `42`),
  wall-clock per run, output length asserted at 1184 hex chars each run.
- Output: static ELF bytes via `python3 -c bytes.fromhex`.
- Correctness: `test/elfarmtest.id` (15 structural checks: ELF magic,
  e_machine, e_entry, entry stub words, code bytes, `_start`/`idolmain`
  symbols, section names). All checks pass. `readelf -h/-S/-l` validates
  the 592-byte output as ELF64 LE AArch64 EXEC with 1 PT_LOAD and 5
  section headers at the computed offsets.

## Results

| metric | value |
|---|---|
| `idol compile elfarm.id --backend native` (cold) | 170 ms wall |
| emit 592-byte ELF as hex (per run) | < 1 ms |
| emitted executable size (8-byte code) | 592 bytes |
| emitted executable size (empty code) | 584 bytes |
| `idol check lib/compiler/elfarm.id` | clean, no errors |
| `test/elfarmtest.id` | 15/15 pass, exit 0 |

| # | directive |
|---|---|
| 1 | The emitter binary itself is ~68 KB. |
| 2 | Emission is string concatenation of 1184 hex chars; there is no optimization to measure yet — the backend wraps the `.text` extracted from native.id's Mach-O object in a fixed ELF64 container with a 3-instruction `_start` stub. |

## What the emitter produces

- ELF64 header: `EM_AARCH64`, `ET_EXEC`, entry `0x400078`
- One `PT_LOAD` (R+E), vaddr `0x400000`, align `0x10000`
- `.text`: `bl idolmain`; `movz x8,#93`; `svc #0`; then the extracted code
- `.symtab`: null, `_start`, `idolmain` (global)
- `.strtab`, `.shstrtab`
- Linux ABI: `idolmain` returns value in `x0`; `_start` exits via
  syscall 93 with that value as the status

## Notes

- The emitter reuses native.id's ARM64 encoders by extracting the
  already-encoded `.text` bytes from its Mach-O object output; it does
  not reimplement instruction encoding. The hex helpers (`hex`, `pair`,
  `half`, `word`, `quad`) are minimal formatting utilities for ELF
  structure emission.
- QEMU user-mode execution validation was attempted but the host QEMU
  (8.2.2) fails to load even textbook minimal AArch64 ELFs in this
  environment; execution correctness rests on `readelf` structural
  validation and byte-exact instruction verification of the 5 emitted
  words (`bl`, `movz x8,#93`, `svc`, `movz x0,#42`, `ret`).
