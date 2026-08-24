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

here=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(unset CDPATH; cd -- "$here/.." && pwd) || exit 2
# THE SWEEPER'S OWN ROOT-RELATIVE PATH, resolved HERE and not later. The floor
# below has to exclude this file from its own population, and a path derived
# after the `cd` would be resolved against the wrong directory — the first
# attempt did exactly that and made a `cd` fail with a shell error.
self=${here#"$root"/}/$(basename -- "$0")
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

# THE POPULATION MUST BE ABLE TO REACH ZERO, and the one guarded below could
# not. The floor asks `subjects -eq 0`, and `gate/posix.sh` IS one of the
# gates this loop enumerates, so in every tree where the file exists to run at
# all, `subjects` is at least 1. The GAP-201 guard was STRUCTURALLY
# UNREACHABLE — written down, cited, and incapable of firing.
#
# WIDENING THE GLOB DID NOT TOUCH THIS, and the two repairs are worth keeping
# apart. The paragraph below fixed an UNDER-MEASUREMENT: the sweep could not
# see six of its subjects. This fixes a floor that cannot reach zero, and a
# floor that cannot reach zero over 43 subjects still cannot reach zero over
# 52. `gate/vacuity.sh` planted this gate alone in an otherwise empty tree,
# after the widening, and got
#
#     posix gate: PASS — 1 shell gate(s) parse under dash; control refused
#
# a clean sweep over a home holding nothing but the sweeper. So PEERS is the
# guarded quantity: subjects other than this file. That count reaches zero
# exactly when the gate home is not there, which is the fact worth refusing
# on. Every gate found is still parsed, this file included; only the FLOOR
# moved, so it now fires everywhere the old one would have, and in one case
# the old one could not.
#
# `$self` is the root-relative path resolved at the top of this file, not the
# literal `gate/posix.sh`: a copy of this file at another depth must still be
# recognised as the sweeper rather than counting itself as a peer and refilling
# the hole.
subjects=0
peers=0
bad=0
failed=""
for gate in gate/*.sh gate/*/*.sh; do
    [ -r "$gate" ] || continue
    subjects=$((subjects + 1))
    [ "$gate" = "$self" ] || peers=$((peers + 1))
    if ! err=$($strict -n "$gate" 2>&1); then
        bad=$((bad + 1))
        failed="$failed $gate"
        printf 'posix gate: FAIL %s does not parse under %s: %s\n' "$gate" "$strict" "$err" >&2
    fi
done

# A gate that examined zero subjects must FAIL (GAP-201). Vacuous green is the
# failure mode this whole file is about, and the only count that can answer
# for it is the one this file does not supply itself.
if [ "$peers" -eq 0 ]; then
    printf 'posix gate: FAIL enumerated %s shell gate(s), none besides %s — NOT MEASURED\n' \
        "$subjects" "$self" >&2
    printf 'posix gate:   a parse sweep whose only subject is the sweeper has measured nothing\n' >&2
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

printf 'posix gate: PASS — %s shell gate(s) parse under %s, %s of them besides %s; control refused\n' \
    "$subjects" "$strict" "$peers" "$self"
exit 0
