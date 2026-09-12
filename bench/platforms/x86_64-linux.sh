# Platform shim: x86_64 + Linux. STATUS: planned (stub).
#
# Backend needed: ELF object emission for x86_64 in lib/compiler/.
# Implements the bench/platforms/lib.sh interface as stubs (return 3).
# Source this file, do not execute it.
#
# To enable (backend agent):
#   1. Implement x86_64+ELF object emission in lib/compiler/
#      (ELF header, .text section, symbol table with the entry symbol;
#      see the Mach-O header construction at the end of native.id's main
#      for the pattern to mirror).
#   2. Implement below:
#        plat_idol_object() { "$IDOL_NATIVE" < "$1" | xxd -r -p > "$2"; }
#        plat_link()        { ld -m elf_x86_64 "$1" -o "$2"; }    # or cc
#        plat_c_exe()       { gcc -O3 "$1" -o "$2"; }             # or clang
#      Entry symbol: decide `_idolmain` vs `idolmain` per platform ABI and
#      document it here. SysV calling convention: return value in %rax.
#   3. Set plat_status="supported".
#   4. Remove the host abort in bench/run.sh for the x86_64-Linux uname pair.

plat_triple="x86_64-linux"
plat_status="planned"

plat_idol_object() {
  echo "not implemented: x86_64-linux plat_idol_object" >&2
  return 3
}

plat_link() {
  echo "not implemented: x86_64-linux plat_link" >&2
  return 3
}

plat_c_exe() {
  echo "not implemented: x86_64-linux plat_c_exe" >&2
  return 3
}
