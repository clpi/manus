# Platform: ARM64 + Linux. STATUS: supported (static executables).
#
# Backend: Zig idol --backend native emits a static ELF64 executable directly
# (direct AArch64+ELF emission in src/native.zig: Linux _start stub, three
# PT_LOAD segments, emission-time relocation resolution). No Mach-O, no shim,
# no host toolchain, no libc. The emitted code is a leaf function returning
# its value in x0; the _start stub calls it and exits via the exit syscall.
# Runs ON the Linux host itself (r16); DNB004 no longer fires there.
# No relocatable objects, no archives: plat_idol_object produces the final
# static executable directly; plat_link copies it.
#
# Implements the bench/platforms/lib.sh interface. Source this file, do not
# execute it. Requires IDOL_BIN (Zig idol binary) to be set.

plat_triple="arm64-linux"
plat_status="supported"

plat_idol_object() { # $1 = src.id, $2 = dst (static ELF executable)
  : "${IDOL_BIN:?plat_idol_object: IDOL_BIN is not set}"
  if ! "$IDOL_BIN" compile "$1" --backend native --no-cache -o "$2" >/dev/null 2>&1; then
    return 1
  fi
  chmod +x "$2"
}

plat_link() { # $1 = object (already a static ELF), $2 = executable
  cp "$1" "$2" && chmod +x "$2"
}

plat_c_exe() { # $1 = src.c, $2 = executable (best available compiler, -O3)
  if command -v gcc >/dev/null 2>&1; then
    gcc -O3 "$1" -o "$2"
  elif command -v clang >/dev/null 2>&1; then
    clang -O3 "$1" -o "$2"
  else
    echo "plat_c_exe: no C compiler found" >&2
    return 1
  fi
}
