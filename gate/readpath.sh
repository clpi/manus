#!/bin/sh
# gate/readpath.sh — path:read() on an absent file REFUSES; a present file
# answers its exact bytes.
#
#   sh gate/readpath.sh
#
# AN ABSENT FILE IS NOT A VALUE. `src/idol_io_runtime.zig` `idol_io_read_path`
# used to answer NULL on every failure leg, and that NULL flowed into Idol
# `str` and became `strlen(NULL)` — the measured UB in gaps/GAP-145.md
# ("Ordered-work item 1"), where a program observing the missing-file result
# printed NOTHING AT ALL at exit 0. The repair is fail-closed (`law.id.one`:
# downstream semantic use fails closed when the required facts are absent):
# every leg now refuses with an identity-first diagnostic on stderr,
# `read-refused:<cause>:<path>`, and exits nonzero.
#
# §1 is the refusal; §2 is its positive control. A refusal probe alone cannot
# distinguish "absent fails closed" from "read is broken for every input", so
# §2 reads a file whose bytes this gate wrote — trailing newline deliberately
# absent, compared with cmp against a FILE, not $(...), which strips it.
#
# The structured absent|present outcome family (source-observable absence)
# remains OPEN under GAP-154/GAP-118. This gate pins the refusal, not that.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "readpath: no compiler at $idol" >&2; exit 2; }

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

# Both probes EXECUTE a direct-backend binary. One producer for the host fact.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the fail-closed refusal and its positive control are read from an EXECUTED binary that cannot be built'
    exit 2
fi

fail=0
note() { printf 'readpath: %s\n' "$1"; }
bad()  { printf 'readpath: FAIL — %s\n' "$1" >&2; fail=1; }

# ─── subject ───────────────────────────────────────────────────────────────
# One program, path from os.env so one binary serves both probes and the
# compiler cannot fold the answer.
cat > "$work/readpath.id" <<'ID'
main: i64 = ()
    p: str = os.env["READPATH_SUBJECT"]
    body: str = p:read()
    stdout:write(body)
    0
ID

if ! "$idol" compile "$work/readpath.id" -o "$work/readpath.bin" >"$work/compile.log" 2>&1; then
    cat "$work/compile.log" >&2
    bad 'readpath.id did not compile — the subject does not exist, so nothing below is measured'
    exit 1
fi

# ─── §1 absent path refuses, by name, on stderr, silent on stdout ──────────
absent="$work/does-not-exist.txt"
set +e
READPATH_SUBJECT="$absent" "$work/readpath.bin" >"$work/absent.out" 2>"$work/absent.err"
code=$?
set -e
if [ "$code" -eq 0 ]; then
    bad "§1 absent path answered exit 0 with $(wc -c < "$work/absent.out") stdout byte(s) — an absent file scored as a value"
elif [ -s "$work/absent.out" ]; then
    bad '§1 absent path refused but wrote stdout bytes first — the refusal leaked a partial value'
elif ! grep -Fq "read-refused:absent:$absent" "$work/absent.err"; then
    cat "$work/absent.err" >&2
    bad '§1 absent path refused without naming the cause and path (read-refused:absent:<path>)'
else
    note "§1 absent path refuses, exit $code, cause and path named on stderr"
fi

# ─── §2 positive control: a present file answers its exact bytes ───────────
present="$work/present.txt"
printf 'alpha\nbeta' > "$present"
set +e
READPATH_SUBJECT="$present" "$work/readpath.bin" >"$work/present.out" 2>"$work/present.err"
code=$?
set -e
if [ "$code" -ne 0 ]; then
    cat "$work/present.err" >&2
    bad "§2 present file refused (exit $code) — the fail-closed leg fires on a file that is there"
elif ! cmp -s "$present" "$work/present.out"; then
    bad '§2 present file did not answer its exact bytes'
elif [ -s "$work/present.err" ]; then
    bad '§2 present file answered but also wrote stderr — a diagnostic with no failure'
else
    note '§2 present file answers its exact bytes, stderr silent'
fi

[ "$fail" -eq 0 ] || exit 1
note 'PASS'
