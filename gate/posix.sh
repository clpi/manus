#!/bin/sh
# gate/posix.sh — every shell gate must PARSE in a strict POSIX shell.
#
# WHY THIS EXISTS, precisely. `gate/gap-145-consumer.sh` was reported PASSING
# with 13 checks. It was, under this machine's /bin/sh, which is bash 3.2 in
# POSIX mode. Under dash the same file is:
#
#     dash -n gate/gap-145-consumer.sh   ->  Syntax error: end of file unexpected, 2
#     dash    gate/gap-145-consumer.sh   ->  aborts after the Python section, 2
#
# One line held a backtick pair inside a DOUBLE-quoted argument. bash parses
# the substitution body lazily, so an unexecuted branch never complains; dash
# parses it eagerly and refuses the file. The last three checks and the final
# PASS line were unreachable, and `gate/all.sh` -- which runs `sh "$gate"` --
# would have recorded that gate as failed on every system whose /bin/sh is
# dash. The PASS was real here and false there, which is the worst of both.
#
# That is the same class the gate itself was written to count: a control that
# cannot fail. So the repair is not the one line. It is this file, which asks
# the strictest shell present whether every gate in the home can even be read.
set -u

root=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
cd "$root" || exit 2

# Strictest first. bash-as-sh is the WEAKEST answer here and says so, because a
# green run under a permissive parser is exactly what hid the defect above.
strict=""
for candidate in dash ash yash; do
    if command -v "$candidate" >/dev/null 2>&1; then
        strict=$candidate
        break
    fi
done
if [ -z "$strict" ] && command -v busybox >/dev/null 2>&1; then
    strict="busybox sh"
fi
weak=0
if [ -z "$strict" ]; then
    strict=sh
    weak=1
fi

# POSITIVE CONTROL, and it is the ORIGINAL DEFECT rather than an invented one.
# A parse checker that accepts everything reports a clean home; this proves the
# chosen shell rejects the exact shape that got through.
control=$(mktemp "${TMPDIR:-/tmp}/idol-posix-control.XXXXXX") || exit 2
trap 'rm -f -- "$control"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

{
    printf '%s\n' 'blind=0'
    printf '%s\n' 'if [ "$blind" -gt 0 ]; then'
    printf '%s\n' '    printf "quote-blind `.quoted =>` arms ROSE to $blind\n"'
    printf '%s\n' 'fi'
} >"$control"

if $strict -n "$control" 2>/dev/null; then
    printf 'posix gate: FAIL %s -n accepted the defect this gate exists to catch\n' "$strict" >&2
    printf 'posix gate:   a parse checker that accepts everything reports a clean home\n' >&2
    exit 1
fi

subjects=0
bad=0
failed=""
for gate in gate/*.sh; do
    [ -r "$gate" ] || continue
    subjects=$((subjects + 1))
    if ! err=$($strict -n "$gate" 2>&1); then
        bad=$((bad + 1))
        failed="$failed $gate"
        printf 'posix gate: FAIL %s does not parse under %s: %s\n' "$gate" "$strict" "$err" >&2
    fi
done

# A gate that examined zero subjects must FAIL (GAP-201). Vacuous green is the
# failure mode this whole file is about.
if [ "$subjects" -eq 0 ]; then
    printf 'posix gate: FAIL enumerated zero shell gates — NOT MEASURED\n' >&2
    exit 2
fi

if [ "$weak" -eq 1 ]; then
    printf 'posix gate: NOTE no strict POSIX shell found; checked with `sh`, which on this\n' >&2
    printf 'posix gate:   host may be bash in POSIX mode and parses lazily. Install dash.\n' >&2
fi

if [ "$bad" -ne 0 ]; then
    printf 'posix gate: FAIL %s of %s shell gate(s) do not parse under %s:%s\n' \
        "$bad" "$subjects" "$strict" "$failed" >&2
    exit 1
fi

printf 'posix gate: PASS — %s shell gate(s) parse under %s; control refused\n' \
    "$subjects" "$strict"
exit 0
