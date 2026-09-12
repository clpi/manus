#!/bin/bash
# bench/platforms/lib.sh — platform shim loader and interface contract.
#
# A platform shim is a shell file `bench/platforms/<arch>-<os>.sh` that is
# SOURCED (never executed) and provides the following interface:
#
#   plat_triple                       # e.g. "arm64-macos"
#   plat_status                       # "supported" | "planned"
#   plat_idol_object SRC.id DST        # compile Idol source -> relocatable object
#   plat_link OBJ EXE                 # link relocatable object -> executable
#   plat_c_exe SRC.c EXE              # compile C source -> executable (-O3)
#
# Environment:
#   IDOL_NATIVE   path to the nativebench binary (built from
#                 lib/compiler/native.id). Must be set before calling
#                 plat_idol_object.
#
# Conventions:
#   - Every plat_* function returns 0 on success, non-zero on failure.
#   - A "planned" shim defines the same functions as stubs that print
#     "not implemented: <triple>" to stderr and return 3, plus comments
#     describing exactly what the backend agent must fill in.
#   - Shims never build the compiler themselves; they consume IDOL_NATIVE.
#   - Shims are backend-agnostic glue: object format, entry symbol, and
#     system libraries live here, codegen lives in lib/compiler/.
#
# Usage:
#   source bench/platforms/lib.sh
#   SHIM="$(plat_shim)" || exit 3
#   IDOL_NATIVE=/path/to/nativebench source "$SHIM"
#   plat_idol_object prog.id prog.o && plat_link prog.o prog.exe
#
# To add a backend (sibling agents): copy the nearest stub, implement the
# three functions, set plat_status="supported", and remove the host abort
# in bench/run.sh for your uname pair. Nothing else needs to change.

plat_detect() { # -> "<arch>-<os>" matching bench/platforms/<triple>.sh
  local arch os
  arch="$(uname -m)"
  os="$(uname -s)"
  case "$arch" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64)  arch="x86_64" ;;
  esac
  case "$os" in
    Darwin)  os="macos" ;;
    Linux)   os="linux" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) os="windows" ;;
  esac
  printf '%s-%s' "$arch" "$os"
}

plat_shim() { # -> path of this host's shim, or "" + return 3 if none
  local libdir triple path
  libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  triple="$(plat_detect)"
  path="$libdir/$triple.sh"
  if [ -f "$path" ]; then
    printf '%s' "$path"
    return 0
  fi
  echo "plat_shim: no shim for $triple" >&2
  return 3
}
