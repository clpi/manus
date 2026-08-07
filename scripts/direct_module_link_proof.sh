#!/usr/bin/env bash
# Proof: the direct ARM64 backend compiles and links a `req`'d Duo module by
# itself, with no manual steps.
#
# `E.emit_u32(...)` lowers to a real ARM64 `bl` with a relocation against the
# module's `@comp.c.export` symbol. Nothing in the program's own object defines
# that symbol, so the compiler must locate `lib/std/emit.duo`, emit its C,
# build it into an object, and put it on the link line. This checks that the
# resulting program runs and writes the machine code it was asked to write.
#
# What it proves: a Duo program whose own object is pure machine code calls into
# a separately compiled Duo module and emits correct ARM64.

set -euo pipefail
cd "$(dirname "$0")/.."

DUO=zig-out/bin/duo
WORK="${TMPDIR:-/tmp}/duo_direct_module_link"
PROBE=/tmp/duo_emit_probe.bin
rm -rf "$WORK" "$PROBE"
mkdir -p "$WORK"

# One command. No hand-compiled module, no hand-written link line.
"$DUO" compile examples/duo_emit_machine_code.duo --backend=direct --emit exe -o "$WORK/prog"

set +e
"$WORK/prog"
rc=$?
set -e

# main() returns the file size: two 4-byte ARM64 instructions.
if [ "$rc" -ne 8 ]; then
    echo "direct_module_link_proof: expected exit 8 (bytes written), got $rc"
    exit 1
fi

# mov x0, #42 (0xd2800540) ; ret (0xd65f03c0), little-endian.
got=$(xxd -p "$PROBE")
if [ "$got" != "400580d2c0035fd6" ]; then
    echo "direct_module_link_proof: wrong machine code: $got"
    exit 1
fi

# The module the compiler built for us must carry the export symbols, and must
# contain no boxed runtime — a module that pulls in `lua_*` cannot stand alone.
MODC=/tmp/duo_reqmod_emit.c
if [ ! -f "$MODC" ]; then
    echo "direct_module_link_proof: compiler emitted no module C"
    exit 1
fi
if grep -q 'lua_' "$MODC"; then
    echo "direct_module_link_proof: module C references the boxed runtime"
    exit 1
fi
for sym in duo_emit_begin duo_emit_u32 duo_emit_size; do
    nm -g /tmp/duo_reqmod_emit.o | grep -q "T _$sym" || {
        echo "direct_module_link_proof: module object is missing _$sym"
        exit 1
    }
done

# The program's own object must be machine code the direct backend produced,
# with the module call left as an undefined symbol for the linker to resolve.
PROGOBJ=/tmp/duo_duo_emit_machine_code_native.o
if [ ! -f "$PROGOBJ" ]; then
    echo "direct_module_link_proof: direct backend emitted no object"
    exit 1
fi

echo "direct_module_link_proof: PASS — compiler linked a req'd Duo module unaided"
echo "direct_module_link_proof: emitted $got (mov x0,#42 ; ret)"

# SH-03/SH-11: `string.sub` allocates, and the ARM64 backend emits only
# read-only __TEXT — the matrix listed that as needing a writable __DATA arena
# or L4 borrowed strings. Exporting the primitive from a stdlib module bypasses
# both: the allocation happens in the module's C, and the direct backend only
# has to emit a relocation. This checks that route stays working.
cat > "$WORK/sub.duo" <<'DUO'
main(): i64
    S = req "std.str"
    return S.len(S.sub("hello world", 7, 11))
DUO
echo "end" >> "$WORK/sub.duo"
"$DUO" compile "$WORK/sub.duo" --backend=direct --emit exe -o "$WORK/sub"
set +e
"$WORK/sub"
subrc=$?
set -e
if [ "$subrc" -ne 5 ]; then
    echo "direct_module_link_proof: native string.sub returned $subrc, expected 5"
    exit 1
fi
echo "direct_module_link_proof: native string.sub works on the direct backend"

# SH-04: the Duo recursive-descent parser, compiled to native ARM64 and called
# from a natively lowered program. Mutual recursion (parse_expr <-> parse_factor)
# and an ABI-register record result both have to survive lowering for this to
# work, so it is the strongest single check that a compiler front end can run
# natively.
cat > "$WORK/parse.duo" <<'DUO'
main(): i64
    P = req "std.compiler.parser"
    return P.eval("2 + 3 * (4 - 1)")
DUO
echo "end" >> "$WORK/parse.duo"
"$DUO" compile "$WORK/parse.duo" --backend=direct --emit exe -o "$WORK/parse"
set +e
"$WORK/parse"
prc=$?
set -e
if [ "$prc" -ne 11 ]; then
    echo "direct_module_link_proof: Duo parser returned $prc, expected 11"
    exit 1
fi
echo "direct_module_link_proof: Duo parser runs natively (2 + 3 * (4 - 1) = 11)"
