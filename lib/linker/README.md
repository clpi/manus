# Idol-Native Linker

Pure Idol implementation of ELF object emission, static linking, and archive production.

## Files

- `idol-linker.id` - Basic linker: concatenates hex code, emits ELF executable
- `linkfull.id` - Full linker with TEXT/SYM/REL parsing (in progress)
- `elfdef.id` - ELF constants and hex helpers
- `objemit.id` - ELF relocatable object emitter
- `link.id` - Linker library functions

## Backend Limitation

The Idol native backend (as of 2026-09-13) has a bug where user-defined
function applications can trigger DNB011 `application-realization-count`
refusal. This appears to be related to constant folding of simple function
bodies.

Workaround: Add a dummy `while i < 1` loop to function bodies to prevent
the optimizer from folding them. This is ugly but produces working code.

See: src/comptime.zig:2139, src/native.zig:12487

## Testing

The basic linker (`idol-linker.id`) successfully:
1. Reads hex-encoded ARM64 code from stdin
2. Wraps it in a valid ELF64 executable header
3. Outputs the binary via stdout

Verified: Output starts with 7f 45 4c 46 (.ELF magic)
