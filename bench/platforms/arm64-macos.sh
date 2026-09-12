# Platform: ARM64 + macOS (Apple Silicon). STATUS: supported.
# Backend: lib/compiler/native.id emits ARM64 Mach-O relocatable objects;
# linked with the system linker against libSystem (final path: direct
# executable emission without ld is in progress; the benchmark measures
# the compiler's code, not the linker).
# Compilers: idol (this repo), clang -O3 (Xcode), gcc -O3 (where installed).
