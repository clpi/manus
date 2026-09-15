# Platform shim: ARM64 + Linux. STATUS: supported (static executables).
#
# Backend: Zig idol --backend native emits AArch64 Mach-O; this shim extracts
# the __text section, prepends a Linux _start stub (bl; mov x8,#93; svc #0),
# and wraps it in a static ELF64 executable (layout ports lib/linker/link.id).
# The emitted code is a leaf function returning its value in x0; the stub
# calls it and exits via the Linux exit syscall with x0 as the status.
# No relocatable objects, no archives: plat_idol_object produces the final
# static executable directly; plat_link copies it.
#
# Implements the bench/platforms/lib.sh interface. Source this file, do not
# execute it. Requires IDOL_BIN (Zig idol binary) to be set.
# Cross-compilation: the Mach-O step runs on macOS (DNB004 blocks --backend
# native on Linux hosts); the resulting ELF runs on ARM64 Linux (r16).

plat_triple="arm64-linux"
plat_status="supported"

plat_idol_object() { # $1 = src.id, $2 = dst (static ELF executable)
  : "${IDOL_BIN:?plat_idol_object: IDOL_BIN is not set}"
  local work macho
  work="$(mktemp -d)" || return 1
  macho="$work/p.macho"
  if ! "$IDOL_BIN" compile "$1" --backend native --no-cache -o "$macho" >/dev/null 2>&1; then
    rm -rf "$work"; return 1
  fi
  if ! _plat_macho2elf "$macho" "$2"; then
    rm -rf "$work"; return 1
  fi
  rm -rf "$work"
  chmod +x "$2"
}

_plat_macho2elf() { # $1 = macho, $2 = elf (internal)
  python3 - "$1" "$2" << 'PYEOF'
import struct, subprocess, sys, re
macho, out = sys.argv[1], sys.argv[2]
info = subprocess.run(['otool', '-l', macho], capture_output=True, text=True)
m = re.search(r'sectname __text.*?offset (\d+).*?size (0x[0-9a-f]+)', info.stdout, re.S)
if not m:
    sys.exit('no __text found')
off, size = int(m.group(1)), int(m.group(2), 16)
with open(macho, 'rb') as f:
    f.seek(off)
    code = f.read(size)
stub = struct.pack('<III', 0x94000003, 0xD2800BA8, 0xD4000001)  # bl+12; mov x8,#93; svc #0
payload = stub + code
base, ho = 0x400000, 120
total, entry = ho + len(payload), base + ho
eh = struct.pack('<16sHHIQQQIHHHHHH', b'\x7fELF' + bytes([2,1,1,0]) + b'\x00'*8,
                 2, 183, 1, entry, 64, 0, 0, 64, 56, 1, 64, 0, 0)
ph = struct.pack('<IIQQQQQQ', 1, 5, 0, base, base, total, total, 0x10000)
with open(out, 'wb') as f:
    f.write(eh + ph + payload)
PYEOF
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
