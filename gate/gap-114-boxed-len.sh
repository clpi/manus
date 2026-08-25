#!/bin/sh
# GAP-114 value gate: a boxed call answer reaching `:len()` must report its real
# byte length, never 0 — and `raw:sub(1, raw:len() - 1)` must therefore trim.
#
# WHY BY VALUE. The defect this pins produced a PLAUSIBLE STRING: an
# unannotated binding stayed boxed, the buffer-typed length intrinsic
# (`lua_str_buf_len_i64`) answered 0 for it, `raw:len() - 1` became -1, and
# `sub(1, -1)` is the documented whole-string face — no compile error, no
# runtime error, one extra trailing byte. The generated C read correctly.
# Only a value assertion convicts it, which is §3 measurement honesty
# verbatim: verify by VALUE, never by "it compiled". The shape half (the
# lowering names `lua_any_len_i64`, never the buffer face, for an unnarrowed
# receiver) is pinned in src/codegen.zig; this gate is the executed half.
#
# EXECUTION PATH, and why it is `dump-c` + cc. The defect lived in the
# compatibility C backend's intrinsic selection, so the generated-C realization
# is the exact exercised path this evidence binds to (generated-C evidence is
# not direct-native evidence). On this host the direct backend has no native
# realization (DNB004) and `--backend=c` emits portable source only, so the
# gate compiles the emitted C with the system compiler and runs the result —
# the same bridge gate/gap-141-runtime-temp.sh executes through.

set -eu

root=${GAP114_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap114.XXXXXX")

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'gap-114-boxed-len gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
command -v "$cc" >/dev/null 2>&1 || fail "C compiler is unavailable: $cc"

control=$work/control.id
boxed=$work/boxed.id

# POSITIVE CONTROL: the compiler statically knows the subject is a str.
cat >"$control" <<'PROBE'
main: i64 = ()
    s = "/tmp/xyz"
    print(s:len())
    t = s:sub(1, s:len() - 1)
    print(t:len())
    0
PROBE

# THE DEFECT'S SHAPE: the subject arrives BOXED from a call answer, through an
# unannotated binding. Historically `:len()` here answered 0 and the trim
# silently returned the whole string.
cat >"$boxed" <<'PROBE'
main: i64 = ()
    fh = io.popen("printf %s /tmp/xyz", "r")
    raw = fh:read("a")
    fh:close()
    print(raw:len())
    trimmed = raw:sub(1, raw:len() - 1)
    print(trimmed:len())
    0
PROBE

run_probe() {
    src=$1
    label=$2
    cfile=$work/$label.c
    bin=$work/$label.bin
    log=$work/$label.log
    errlog=$work/$label.err
    (CDPATH='' cd -- "$work" && "$idol" dump-c "$src") >"$cfile" 2>"$errlog" \
        || { cat "$errlog" >&2; fail "$label did not emit C"; }
    "$cc" "$cfile" -o "$bin" -lm 2>"$errlog" \
        || { cat "$errlog" >&2; fail "$label emitted C that $cc refused"; }
    "$bin" >"$log" 2>"$errlog" \
        || { cat "$log" "$errlog" >&2; fail "$label did not run"; }
    printf '8\n7\n' | cmp -s - "$log" || {
        cat "$log" "$errlog" >&2
        fail "$label values diverged from 8 then 7 (a 0 here is the GAP-114 silent length collapse)"
    }
}

run_probe "$control" control
run_probe "$boxed" boxed

# The shape fact, asserted against the exact C this run executed: the boxed
# probe's lowering must never select the buffer-typed length intrinsic at a
# call site. Its definition may appear in the runtime preamble; a CALL of it
# against the boxed subject is the defect.
if grep -E 'lua_str_buf_len_i64\(raw' "$work/boxed.c" >/dev/null 2>&1; then
    fail "boxed probe lowers :len() through the buffer intrinsic again"
fi

printf 'gap-114-boxed-len gate: PASS\n'
