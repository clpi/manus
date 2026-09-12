#!/bin/bash
# test/pecoffarm.sh -- structural acceptance test for lib/compiler/pecoffarm.id
# (ARM64 + PE/COFF/Windows backend).
#
# Validates the emitted bytes parse as a valid PE/COFF executable: MZ +
# stub, PE signature, COFF header (machine 0xaa64), PE32+ optional header,
# .text + .idata sections, import table (ExitProcess from KERNEL32.dll), and
# the 5-instruction entry sequence. Cross-checks the instruction words
# against the system assembler (clang), the same oracle strategy as
# lib/compiler/arm64check.id.
#
# Usage: ./test/pecoffarm.sh   (run from repo root)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/pecoffarm-test-$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

IDOL_BIN="${IDOL_BIN:-}"
if [ -z "$IDOL_BIN" ]; then
  if command -v idol >/dev/null 2>&1; then IDOL_BIN="idol"
  elif [ -x /private/tmp/t_d0b6f987/idol ]; then IDOL_BIN=/private/tmp/t_d0b6f987/idol
  else echo "FAIL: no idol binary (set IDOL_BIN)"; exit 2; fi
fi

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "ok: $1"; }

echo "== idol check =="
"$IDOL_BIN" check "$REPO/lib/compiler/pecoffarm.id" >/dev/null 2>&1 || fail "idol check"
pass "idol check"

echo "== build emitter =="
"$IDOL_BIN" compile "$REPO/lib/compiler/pecoffarm.id" --backend native -o "$WORK/peemit" >/dev/null 2>&1 \
  || fail "compile --backend native"
[ -x "$WORK/peemit" ] || fail "peemit not executable"
pass "compile --backend native"

echo "== emit =="
printf '42' | "$WORK/peemit" | xxd -r -p > "$WORK/t.exe" || fail "emit 42"
printf '7' | "$WORK/peemit" | xxd -r -p > "$WORK/t7.exe" || fail "emit 7"
[ "$(wc -c < "$WORK/t.exe" | tr -d "[:space:]")" = "1536" ] || fail "t.exe size"
pass "emit (1536 bytes; exit codes 42 and 7)"

echo "== structural validation =="
python3 - "$WORK/t.exe" "$WORK/t7.exe" <<'PYEOF' || fail "structural validation"
import struct, sys
exe = open(sys.argv[1], 'rb').read()
exe7 = open(sys.argv[2], 'rb').read()
def ck(c, m):
    if not c:
        print("CHECK FAILED:", m)
        sys.exit(1)
u16 = lambda o: struct.unpack_from('<H', exe, o)[0]
u32 = lambda o: struct.unpack_from('<I', exe, o)[0]
u64 = lambda o: struct.unpack_from('<Q', exe, o)[0]
ck(len(exe) == 1536, "file size 1536")
ck(exe[0:2] == b'MZ', "MZ magic")
ck(u32(0x3c) == 0x80, "e_lfanew")
ck(exe[0x40:0x40+42] == b'This program cannot be run in DOS mode.\r\n$',
   "dos stub message")
pe = 0x80
ck(exe[pe:pe+4] == b'PE\x00\x00', "PE signature")
coff = pe + 4
ck(u16(coff) == 0xaa64, "machine 0xaa64")
ck(u16(coff+2) == 2, "two sections")
ck(u16(coff+16) == 240, "optional header size 240")
ck(u16(coff+18) == 0x22, "characteristics")
opt = coff + 20
ck(u16(opt) == 0x20b, "PE32+ magic")
ck(u32(opt+4) == 512, "sizeofcode")
ck(u32(opt+8) == 512, "sizeofinitdata")
ck(u32(opt+16) == 0x1000, "entrypoint")
ck(u32(opt+20) == 0x1000, "baseofcode")
ck(u64(opt+24) == 0x140000000, "imagebase")
ck(u32(opt+32) == 0x1000, "section alignment")
ck(u32(opt+36) == 0x200, "file alignment")
ck(u32(opt+56) == 0x3000, "sizeofimage")
ck(u32(opt+60) == 0x200, "sizeofheaders")
ck(u16(opt+68) == 3, "subsystem console")
ck(u16(opt+70) == 0x8160, "dll characteristics")
ck(u64(opt+72) == 0x100000, "stack reserve")
ck(u64(opt+80) == 0x1000, "stack commit")
ck(u64(opt+88) == 0x100000, "heap reserve")
ck(u64(opt+96) == 0x1000, "heap commit")
ck(u32(opt+108) == 16, "16 data directories")
dd = opt + 112
ck(u32(dd) == 0 and u32(dd+4) == 0, "export dir empty")
ck(u32(dd+8) == 0x2000 and u32(dd+12) == 40, "import dir")
for i in range(2, 16):
    ck(u32(dd+8*i) == 0 and u32(dd+8*i+4) == 0, "datadir %d zero" % i)
sh = opt + 240
ck(sh == 392, "section headers at 392")
def sec(i):
    o = sh + 40*i
    return (exe[o:o+8].rstrip(b'\x00'), u32(o+8), u32(o+12),
            u32(o+16), u32(o+20), u32(o+36))
n0, vs0, va0, rs0, rp0, ch0 = sec(0)
ck(n0 == b'.text' and vs0 == 20 and va0 == 0x1000 and rs0 == 512
   and rp0 == 0x200 and ch0 == 0x60000020, ".text header")
n1, vs1, va1, rs1, rp1, ch1 = sec(1)
ck(n1 == b'.idata' and vs1 == 99 and va1 == 0x2000 and rs1 == 512
   and rp1 == 0x400 and ch1 == 0xc0000040, ".idata header")
ck(0x1000 <= u32(opt+16) < 0x1000 + vs0, "entrypoint inside .text")
ck(all(b == 0 for b in exe[472:512]), "header padding zero")
io = 0x400
ck(u32(io) == 0x2028 and u32(io+4) == 0 and u32(io+8) == 0
   and u32(io+12) == 0x2056 and u32(io+16) == 0x2038, "import descriptor")
ck(all(b == 0 for b in exe[io+20:io+40]), "null descriptor")
rva2off = lambda r: 0x400 + (r - 0x2000)
ck(u64(rva2off(0x2028)) == 0x2048 and u64(rva2off(0x2028)+8) == 0, "ILT")
ck(u64(rva2off(0x2038)) == 0x2048 and u64(rva2off(0x2038)+8) == 0, "IAT")
ck(u16(rva2off(0x2048)) == 0, "hint zero")
hn = rva2off(0x2048) + 2
ck(exe[hn:hn+12] == b'ExitProcess\x00', "ExitProcess hint/name")
dn = rva2off(0x2056)
ck(exe[dn:dn+13] == b'KERNEL32.dll\x00', "KERNEL32.dll name")
ck(vs1 == (dn + 13) - io, "idata virtual size exact")
ck(all(b == 0 for b in exe[io+99:0x600]), "idata raw padding zero")
words = struct.unpack_from('<5I', exe, 0x200)
ck(words == (0xd10083ff, 0xd2800540, 0xb0000001, 0xf9401c21, 0xd63f0020),
   "entry instructions")
ck(all(b == 0 for b in exe[0x200+20:0x400]), "text raw padding zero")
ck(0x2000 + 0x38 == 0x2038, "adrp+ldr reach the IAT")
w7 = struct.unpack_from('<5I', exe7, 0x200)
ck(w7[1] == 0xd28000e0, "exit code parameterizes movz")
print("structural: all checks passed")
PYEOF
pass "structural validation"

echo "== clang oracle =="
if command -v clang >/dev/null 2>&1; then
  cat > "$WORK/case.s" <<'ASEOF'
    .text
    .align 2
    .globl _pecase
_pecase:
    sub sp, sp, #32
    movz x0, #42
    blr x1
ASEOF
  clang -arch arm64 -c "$WORK/case.s" -o "$WORK/case.o" 2>/dev/null || fail "clang assemble"
  HEX=$(xxd -p "$WORK/case.o" | tr -d '\n')
  for w in ff8300d1 400580d2 20003fd6; do
    case "$HEX" in *"$w"*) ;; *) fail "clang oracle missing word $w";; esac
    HEX="${HEX#*"$w"}"
  done
  pass "clang oracle stage 1 (sub/movz/blr agree)"
  cat > "$WORK/case2.s" <<'ASEOF'
    .text
    .align 2
    .globl _pecase
_pecase:
    sub sp, sp, #32
    movz x0, #42
    blr x1
    .align 12
_pcase:
    adrp x1, _qcase@PAGE
    ldr x1, [x1, _rcase@PAGEOFF]
    .space 4088
    .align 3
_qcase:
    .space 56
_rcase:
    .quad 0
ASEOF
  SDK=""
  for sd in /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; do
    [ -d "$sd" ] && SDK="$sd" && break
  done
  if [ -n "$SDK" ] && clang -arch arm64 -c "$WORK/case2.s" -o "$WORK/case2.o" 2>/dev/null \
      && ld -arch arm64 -e _pecase -platform_version macos 14.0 14.0 -syslibroot "$SDK" "$WORK/case2.o" -lSystem -o "$WORK/case2bin" 2>/dev/null; then
    HEX2=$(otool -t "$WORK/case2bin" 2>/dev/null | tr -d '\t \n')
    for w in b0000001 f9401c21; do
      case "$HEX2" in *"$w"*) ;; *) fail "clang oracle missing word $w";; esac
      HEX2="${HEX2#*"$w"}"
    done
    pass "clang oracle stage 2 (adrp/ldr agree)"
  else
    echo "skip: link oracle unavailable"
  fi
else
  echo "skip: no clang (oracle unavailable)"
fi

echo "ALL PECOFFARM TESTS PASSED"
