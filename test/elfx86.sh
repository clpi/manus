#!/bin/bash
# test/elfx86.sh -- acceptance test for lib/compiler/x86.id (x86_64 encoders)
# and lib/compiler/elfx86.id (x86_64 + ELF64/Linux direct backend).
#
# Part 1: idol check on both files.
# Part 2: differential test of the 44 encoder vectors in x86.id's main
# against the system assembler (clang -arch x86_64 -mavx2 -mbmi2); every vector must
# match byte-for-byte (same oracle strategy as lib/compiler/arm64check.id).
# Part 3: build the elfx86 emitter (--backend native) and compile four
# demo programs to ELF64; python3 validates ELF structure (magic, class,
# type, machine, entry, PT_LOAD, 5 section headers, .text vaddr == entry,
# _start symbol) and checks .text bytes against clang-assembled
# equivalents for the arithmetic and division programs, plus loop-shape
# patterns for the countdown-while programs.
#
# Usage: ./test/elfx86.sh   (run from repo root)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/elfx86-test-$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

IDOL_BIN="${IDOL_BIN:-}"
if [ -z "$IDOL_BIN" ]; then
  if command -v idol >/dev/null 2>&1; then IDOL_BIN="idol"
  elif [ -x "$REPO/zig-out/bin/idol" ]; then IDOL_BIN="$REPO/zig-out/bin/idol"
  else echo "FAIL: no idol binary (set IDOL_BIN)"; exit 2; fi
fi

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "ok: $1"; }

echo "== idol check =="
"$IDOL_BIN" check "$REPO/lib/compiler/x86.id" >/dev/null 2>&1 || fail "idol check x86.id"
"$IDOL_BIN" check "$REPO/lib/compiler/elfx86.id" >/dev/null 2>&1 || fail "idol check elfx86.id"
pass "idol check (x86.id, elfx86.id)"

echo "== build backends =="
"$IDOL_BIN" compile "$REPO/lib/compiler/x86.id" --backend native -o "$WORK/x86vec" >/dev/null 2>&1 \
  || fail "compile x86.id --backend native"
"$IDOL_BIN" compile "$REPO/lib/compiler/elfx86.id" --backend native -o "$WORK/elfx86bin" >/dev/null 2>&1 \
  || fail "compile elfx86.id --backend native"
[ -x "$WORK/x86vec" ] || fail "x86vec not executable"
[ -x "$WORK/elfx86bin" ] || fail "elfx86bin not executable"
pass "compile --backend native"

echo "== differential: 44 encoder vectors vs clang =="
"$WORK/x86vec" > "$WORK/vec.txt" || fail "run x86vec"
n=0
bad=0
while IFS= read -r line; do
  n=$((n + 1))
  asm=${line%%|*}
  want=${line##*|}
  asm=$(printf '%s' "$asm" | sed 's/^ *//;s/ *$//')
  want=$(printf '%s' "$want" | sed 's/^ *//;s/ *$//' | tr 'A-F' 'a-f')
  printf '.text\n.globl _f\n_f:\n%s\n' "$asm" > "$WORK/v.s"
  if ! clang -arch x86_64 -mavx2 -mbmi2 -c "$WORK/v.s" -o "$WORK/v.o" 2>/dev/null; then
    echo "ASM-FAIL [$n]: $asm"; bad=$((bad + 1)); continue
  fi
  got=$(otool -t "$WORK/v.o" | awk 'NR>2{for(i=2;i<=NF;i++) printf "%s",$i}')
  wantlen=${#want}
  got=$(printf '%s' "$got" | cut -c1-"$wantlen")
  if [ "$got" != "$want" ]; then
    echo "MISMATCH [$n]: $asm (want $want got $got)"; bad=$((bad + 1))
  fi
done < "$WORK/vec.txt"
[ "$n" = "44" ] || fail "expected 44 vectors, got $n"
[ "$bad" = "0" ] || fail "$bad/$n vector mismatches"
pass "44/44 encoder vectors match clang byte-for-byte"

echo "== emit ELF64 demos =="
printf 'x = 40 + 2\nx\n' | "$WORK/elfx86bin" | xxd -r -p > "$WORK/p1.elf" || fail "emit p1"
printf 'a = 20\nb = 6\nc = a / b\nc\n' | "$WORK/elfx86bin" | xxd -r -p > "$WORK/p2.elf" || fail "emit p2"
printf 'i = 0\nwhile i < 3\n    i = i + 1\n' | "$WORK/elfx86bin" | xxd -r -p > "$WORK/p3.elf" || fail "emit p3"
printf 'i = 0\nwhile i < 3\n    i = i + 1\nx = 9\nx\n' | "$WORK/elfx86bin" | xxd -r -p > "$WORK/p4.elf" || fail "emit p4"
printf 'a = 0 - 20\nb = a / 3\nc = a / 7\nd = a / 8\ne = b / 10\ne\n' | "$WORK/elfx86bin" | xxd -r -p > "$WORK/p5.elf" || fail "emit p5"
pass "emit (5 programs)"

echo "== structural validation + clang oracle =="
python3 - "$WORK/p1.elf" "$WORK/p2.elf" "$WORK/p3.elf" "$WORK/p4.elf" "$WORK/p5.elf" <<'PYEOF' || fail "structural validation"
import struct, sys, subprocess

def ck(c, m):
    if not c:
        print("CHECK FAILED:", m); sys.exit(1)

def parse_elf(path):
    ex = open(path, 'rb').read()
    ck(ex[0:4] == b'\x7fELF', path + ": elf magic")
    ck(ex[4] == 2, "class 64"); ck(ex[5] == 1, "data le")
    ck(ex[6] == 1, "version"); ck(ex[7] == 0, "osabi sysv")
    ck(struct.unpack_from('<H', ex, 16)[0] == 2, "type exec")
    ck(struct.unpack_from('<H', ex, 18)[0] == 62, "machine x86_64")
    entry = struct.unpack_from('<Q', ex, 24)[0]
    ck(entry == 0x400078, "entry 0x400078")
    phoff = struct.unpack_from('<Q', ex, 32)[0]
    shoff = struct.unpack_from('<Q', ex, 40)[0]
    ck(phoff == 64, "phoff 64")
    ck(struct.unpack_from('<I', ex, phoff)[0] == 1, "pt_load")
    ck(struct.unpack_from('<I', ex, phoff+4)[0] == 5, "flags r+x")
    ck(struct.unpack_from('<Q', ex, phoff+16)[0] == 0x400000, "vaddr")
    ck(struct.unpack_from('<H', ex, 60)[0] == 5, "5 sections")
    shstr = struct.unpack_from('<H', ex, 62)[0]
    shstr_off = struct.unpack_from('<Q', ex, shoff + shstr*64 + 24)[0]
    def sname(i):
        o = struct.unpack_from('<I', ex, shoff + i*64)[0]
        e = ex.index(b'\0', shstr_off + o)
        return ex[shstr_off+o:e].decode()
    ck([sname(i) for i in range(5)] == ['', '.text', '.symtab', '.strtab', '.shstrtab'],
       "section names")
    t_off = struct.unpack_from('<Q', ex, shoff + 1*64 + 24)[0]
    t_sz = struct.unpack_from('<Q', ex, shoff + 1*64 + 32)[0]
    ck(t_off == 120, "text file offset 120")
    ck(struct.unpack_from('<Q', ex, shoff + 1*64 + 16)[0] == entry, "text vaddr == entry")
    s_off = struct.unpack_from('<Q', ex, shoff + 2*64 + 24)[0]
    st_name, _, _, _, st_value, st_size = struct.unpack('<IBBHQQ', ex[s_off+24:s_off+48])
    ck(st_value == entry and st_size == t_sz, "_start value/size")
    str_off = struct.unpack_from('<Q', ex, shoff + 3*64 + 24)[0]
    ck(ex[str_off+st_name:str_off+st_name+6] == b'_start', "_start name")
    return ex[t_off:t_off+t_sz]

def clang_bytes(asm):
    with open('/tmp/elfx86-o.s', 'w') as f:
        f.write('.text\n.globl _f\n_f:\n' + asm + '\n')
    subprocess.run(['clang', '-arch', 'x86_64', '-c', '/tmp/elfx86-o.s',
                    '-o', '/tmp/elfx86-o.o'], check=True, capture_output=True)
    out = subprocess.run(['otool', '-t', '/tmp/elfx86-o.o'],
                         capture_output=True, text=True).stdout
    hx = ''
    for ln in out.split('\n')[2:]:
        f = ln.split()
        if len(f) > 1:
            hx += ''.join(f[1:])
    return hx

t1 = parse_elf(sys.argv[1])
w1 = clang_bytes('movl $42, %r12d\nmovq %r12, %rax\nmovq %rax, %rdi\nmovl $60, %eax\nsyscall\n')
ck(t1.hex() == w1, "p1 .text vs clang")

t2 = parse_elf(sys.argv[2])
w2 = clang_bytes('movl $20, %r12d\nmovl $6, %r13d\nmovq %r12, %rax\ncqo\n'
                 'idivq %r13\nmovq %rax, %r14\nmovq %r14, %rax\n'
                 'movq %rax, %rdi\nmovl $60, %eax\nsyscall\n')
ck(t2.hex() == w2, "p2 .text vs clang (division)")

t3 = parse_elf(sys.argv[3]).hex()
ck('41b803000000' in t3, "p3 loop counter init r8=3")
ck('4983e801' in t3, "p3 loop decrement sub r8,1")
ck('75fa' in t3, "p3 loop back-edge jne")
ck(t3.endswith('4889c7b83c0000000f05'), "p3 exit epilogue")
t5 = parse_elf(sys.argv[5]).hex()
ck('5655555555555555' in t5, "p5 hoisted magic /3")
ck('2549922449922449' in t5, "p5 hoisted magic /7")
ck('6766666666666666' in t5, "p5 hoisted magic /10")
ck('49f7ec' in t5, "p5 magic imul /3")
ck('49f7ed' in t5, "p5 magic imul /7")
ck('49f7ee' in t5, "p5 magic imul /10")
ck('48c1ea3d' in t5, "p5 pow2 /8 bias shr 61")
ck('f7f' not in t5, "p5 no idivq")
ck('4898' not in t5, "p5 no cqo")

t4 = parse_elf(sys.argv[4]).hex()
ck('4983e801' in t4 and '75fa' in t4, "p4 loop closed before trailing code")
ck(t4.endswith('4889c7b83c0000000f05'), "p4 exit epilogue")
print("structural + oracle checks passed")
PYEOF
pass "structural validation + clang oracle"

echo "ALL TESTS PASSED"
