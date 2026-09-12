# Platform shim: x86_64 + Windows. STATUS: planned (stub).
#
# Backend needed: PE/COFF object emission for x86_64 in lib/compiler/.
# Implements the bench/platforms/lib.sh interface as stubs (return 3).
# Source this file, do not execute it.
#
# To enable (backend agent):
#   1. Implement x86_64+PE/COFF object emission in lib/compiler/
#      (COFF header, .text section, symbol table with the entry symbol).
#   2. Implement below:
#        plat_idol_object() { "$IDOL_NATIVE" < "$1" | xxd -r -p > "$2"; }
#        plat_link()        { link "$1" /OUT:"$2" ...; }  # MSVC link, or lld-link
#        plat_c_exe()       { cl /O2 "$1" /Fe"$2"; }      # or clang-cl
#      Entry symbol and subsystem: document the choices here. Note the
#      process exit code is still the observable; document how the entry
#      point returns it (ExitProcess vs ret from main).
#   3. Set plat_status="supported".
#   4. Remove the host abort in bench/run.sh for the x86_64-Windows uname pair.

plat_triple="x86_64-windows"
plat_status="planned"

plat_idol_object() {
  echo "not implemented: x86_64-windows plat_idol_object" >&2
  return 3
}

plat_link() {
  echo "not implemented: x86_64-windows plat_link" >&2
  return 3
}

plat_c_exe() {
  echo "not implemented: x86_64-windows plat_c_exe" >&2
  return 3
}
