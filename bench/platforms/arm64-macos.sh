# Platform shim: ARM64 + macOS (Apple Silicon). STATUS: supported.
#
# Backend: lib/compiler/native.id emits ARM64 Mach-O relocatable objects;
# linked with the system linker against libSystem. (The final linker-free
# executable path is separate work; the benchmark measures the compiler's
# code, not the linker.)
#
# Implements the bench/platforms/lib.sh interface. Source this file, do not
# execute it. Requires IDOL_NATIVE to be set (nativebench binary).

plat_triple="arm64-macos"
plat_status="supported"

plat_idol_object() { # $1 = src.id, $2 = dst object
  : "${IDOL_NATIVE:?plat_idol_object: IDOL_NATIVE is not set}"
  "$IDOL_NATIVE" < "$1" | xxd -r -p > "$2"
}

plat_link() { # $1 = object, $2 = executable
  local sdk
  sdk="$(xcrun --show-sdk-path)" || return 1
  ld -arch arm64 -e _idolmain -platform_version macos 14.0 14.0 \
     -syslibroot "$sdk" "$1" -lSystem -o "$2"
}

plat_c_exe() { # $1 = src.c, $2 = executable (best available compiler, -O3)
  if command -v clang >/dev/null 2>&1; then
    clang -O3 "$1" -o "$2"
  elif command -v gcc >/dev/null 2>&1; then
    gcc -O3 "$1" -o "$2"
  else
    echo "plat_c_exe: no C compiler found" >&2
    return 1
  fi
}
