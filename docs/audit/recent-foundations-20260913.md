# Audit: Recent Foundations (2026-09-13)

## Scope
- fd82b54b: Parser foundation (lib/compiler/nparse.id)
- 569f9dc4: Native linker/object foundation (lib/linker/)
- f6f6b7da: Timing builtins (src/idol_io_runtime.zig)
- 3ac94a4d: ARM64 textual optimizations (lib/compiler/opt/)

## 1. Parser Foundation (nparse.id, 561 lines)

### What works
- Tokenizer: handles ints, floats, strings, identifiers, keywords, operators
- Pratt expression parser with precedence table (precof)
- S-expression output for expressions
- Right-associativity for ^ and ..

### What's broken
- AST constructors (mkint, mkfloat, mkstr, mkbool, mknil, mkname) are DEAD CODE
  - Defined at lines 10-26 but never called
  - Parser functions return str, not ast
  - The ast type (lines 1-8) is unused
- Statement parsing is stubs:
  - if returns (if cond ...) — body not parsed (line 522)
  - while returns (while cond ...) — body not parsed (line 526)
  - Declaration returns (decl name ...) — type not parsed (line 534)

### What's missing
- Full grammar coverage: no function definitions, no table literals, no method calls
- No corpus differential run
- No integration with compiler pipeline

### Soundness issues
- CRITICAL: This is not a parser. It is an expression pretty-printer.
- Output is strings, not structured AST. Cannot be used for semantic analysis.
- The main function (lines 505-514) is a test harness, not a compiler entry.

## 2. Linker Foundation (lib/linker/)

### What works
- link.id: ELF64 executable emitter from hex-encoded code
  - Takes hex string via stdin, emits ELF with single PT_LOAD segment
  - AArch64 only (e_machine = 183)
- objemit.id: ELF relocatable object emitter
  - emitobj(text, syms, rels, strtab) builds .o with .text, .rela.text, .symtab, .strtab
- archive.id: ar archive emitter (Unix static library format)
  - Reads NAME:/DATA: lines, emits archive with headers
- elfdef.id: ELF utilities (hex encode/decode, readu32/64, findstr)

### What's broken
- README.md references non-existent files:
  - idol-linker.id (not in directory)
  - linkfull.id (not in directory, described as "in progress")
- README documents DNB011 workaround (while i < 1) which was removed in 6cc6e8ee

### What's missing
- Actual linking: NO symbol resolution, NO relocation application
- Multi-object input: link.id takes single hex blob, not multiple .o files
- Undefined symbol handling: none
- Mach-O support: none (ELF only)
- x86_64 support: none (AArch64 only, hardcoded e_machine=183)
- linkfull.id: referenced but does not exist

### Soundness issues
- CRITICAL: link.id is NOT a linker. It is an executable emitter.
  - Name is misleading. It wraps code bytes in ELF headers.
  - No linking semantics are implemented.
- objemit.id emits object files but there is no assembler producing the inputs.
- archive.id emits archives but has no symbol index (no ranlib equivalent).

## 3. Timing Builtins (src/idol_io_runtime.zig)

### What works
- procrun(prog, args, input): fork/pipe/execvp, no shell
  - Args are 0x1f-delimited (no shell injection)
  - Returns code-newline-stdout — code first avoids escaping issues
  - Exit codes: 0-255 normal, -N signal N, -999 spawn failure
- monotime(): CLOCK_MONOTONIC_RAW via clock_gettime_nsec_np (macOS)
  - Monotonic, not affected by NTP (good for benchmarks)
- filesize(path): returns byte size or -1 on failure
- sha256file(path): SHA-256 hex or empty string on failure
  - Correctly in Zig (not Idol) because file bytes are not NUL-safe through string runtime

### What's broken
- None found in implementation logic.

### What's missing
- Documentation: stderr is NOT captured (goes to parent stderr)
- NUL-byte limitation: child output with NUL bytes will truncate in Idol strings

### Soundness issues
- procrun argv_buf fixed at 34 entries: silent -999 return on overflow (not an error)
  - For timing harness, this could cause confusing failures with many args
- monotime uses macOS-specific clock_gettime_nsec_np
  - Portability: Linux needs different API
- readFd dynamically grows buffer (good) but NUL bytes in output cause truncation
  - Acceptable for text-output timing harness, but should be documented

## 4. ARM64 Textual Optimizations (lib/compiler/opt/)

### What works
- popcount.id: Recognizes 6-line SWAR idiom via magic constants
  - 6148914691236517205, 3689348814741910323, 1085102592571150095
  - Plus / 256, / 65536, / 4294967296
- bitrev.id: Recognizes 6-line bit-reverse loop (31-bit shape)
- native.id markers:
  - __popcount_neon(arg): FMOV D16,X9; CNT 8B; ADDV; FMOV Xr,D16 (correct sequence)
  - __bitrev_parallel(arg): RBIT X10,X9; LSR Xr,X10,#33 (correct for 31-bit)

### What's broken
- Marker names __popcount_neon, __bitrev_parallel violate no-underscore rule
- Textual matching, not semantic: operates on string representations

### What's missing
- Graph-owned fact integration: these are string pattern matches, not graph idioms
- General shapes: bitrev only handles 31-bit; popcount only handles 6-step (no mask check)
- Register liveness: uses fixed X9, X10, V16 with no safety check

### Soundness issues
- CRITICAL (popcount): Recognizer does NOT verify the 7th mask step
  - The SWAR idiom without trailing mask leaves garbage in upper 57 bits
  - Production Zig backend requires the mask (fixed in b6c6800f)
  - This textual version is UNSOUND: will produce wrong results for unmasked idiom
- CRITICAL (register safety): Fixed registers X9, X10, V16 with no liveness check
  - If these registers hold live values, they will be clobbered
- HIGH (variable identity): popcount.id extracts varname from line 0 but does NOT verify
  lines 1-5 operate on the same variable. Only checks constants appear.
- HIGH (fragility): bitrev.id hardcodes 31-bit shape. xvar extraction parses strings.
- ARCHITECTURAL CONFLICT:
  - Textual string matching conflicts with graph-owned-fact architecture
  - Markers are magic strings, not semantic identities
  - Production backend (Zig) has sound implementations; these are restricted-route only
  - Per user directive: restricted-route gains do not count as production progress

## Summary of Critical Issues

1. Parser is not a parser: nparse.id produces S-expression strings, not AST. AST constructors are dead code. Statement bodies are stubs.
2. Linker is not a linker: link.id is an executable emitter. No symbol resolution or relocation. README references missing files.
3. Popcount recognizer unsound: Missing 7th mask step check. Will miscompile unmasked SWAR idiom.
4. Register safety: ARM64 markers use fixed registers without liveness checks.
5. Architectural conflict: Textual recognizers vs graph-owned facts. Markers violate naming rules.

## Recommendations

1. Parser: Rewrite to produce actual AST (use the defined ast type). Implement full statement parsing. Run corpus differential.
2. Linker: Rename link.id to exeemit.id (honest name). Implement actual symbol resolution and relocation, or document as emitter only.
3. Popcount: Add 7th step mask verification, or decline unmasked idioms. Fix register allocation.
4. ARM64 opts: Migrate to graph-owned idiom facts. Remove underscore markers. Or quarantine as non-production experiment.
