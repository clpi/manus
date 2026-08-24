#!/bin/sh
# gate/byteface/byteface.sh — GAP-145 / GAP-207: the byte face of a value must
# be ANSWERED or REFUSED, never guessed.
#
# ═══ WHY THIS FILE EXISTS AND THE OTHER THREE CONTROLS DID NOT SUFFICE ═════
#
# GAP-207 measured `s = 'abc' ; print(s .. "Z")` printing `4370531440Z` at
# exit 0 with no diagnostic — a fresh ASLR'd pointer on every run, rendered
# through `%lld` because `exprIsStr` answering "not text" was read downstream
# as "then an integer". Three instruments were run against it and all three
# were CLEAN while the program printed a pointer:
#
#   zig build unit-test              unchanged, same nine failures
#   compile-status sweep, 547 .id    zero diff
#   output differential, examples/   zero diff
#
# The third is the interesting one. It was a real output differential and it
# still saw nothing, because THE CORPUS CONTAINS NO PROGRAM OF THIS SHAPE: a
# name bound to a byte literal and then consumed. An output differential can
# only compare programs that exist. This file supplies the programs.
#
# ═══ WHAT IS ACTUALLY BEING MEASURED ═══════════════════════════════════════
#
# Not "does the compiler accept this". Both verdicts are lawful here:
#
#   ANSWER   the exact bytes, compared BYTE FOR BYTE against what is written
#            below. Not a substring, not a regex, not "contains abc".
#   REFUSE   a non-zero exit AND an empty stdout. A refusal that printed
#            something first has already emitted the wrong answer.
#
# The one verdict that is never lawful is the third: exit 0, and bytes on
# stdout that nobody can predict. Byte-for-byte comparison is what separates
# it from ANSWER, and the empty-stdout requirement is what separates it from
# REFUSE. A gate matching `abc` as a substring would have passed
# `4370531440Z` had the address happened to contain it, and a gate checking
# only the exit code would have passed it outright.
#
# ═══ THE DETECTOR IS CONTROLLED, NOT TRUSTED ═══════════════════════════════
#
# Every section below runs its comparator against the RECORDED ORIGINAL
# DEFECT — the literal transcript out of GAP-207 — and fails if the comparator
# reports agreement. A planted defect this gate invented would only prove the
# gate can see defects this gate imagines. The plant here is the measurement
# that caused the gap to be filed.
#
# ZERO SUBJECTS IS A FAILURE (GAP-201). Under `gate/vacuity.sh`'s EMPTY plant
# there is no compiler and this refuses at 2; under HOLLOW the compiler exists
# and answers nothing, so every ANSWER subject mismatches and this refuses at
# 1. Neither can be mistaken for agreement.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
cd "$root" || { echo "byteface: cannot enter root" >&2; exit 2; }

IDOL=${BYTEFACE_IDOL:-$root/zig-out/bin/idol}
if [ ! -x "$IDOL" ]; then
    printf 'byteface: no compiler at %s — nothing was measured\n' "$IDOL" >&2
    exit 2
fi

scratch=$(mktemp -d) || { echo 'byteface: cannot allocate scratch' >&2; exit 2; }
cleanup() { rm -rf -- "$scratch"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

violations=0
subjects=0

fail() {
    violations=$((violations + 1))
    printf 'byteface: FAIL %s\n' "$*"
}

# ── THE COMPARATOR, as a function, so the controls can call the same code ──
#
# It is deliberately not inlined into the subject loop. A control that
# re-implements the comparison proves nothing about the comparison that runs.
#
#   verdict_of EXPECTKIND EXPECTTEXT ACTUALSTATUS ACTUALOUT
#     -> prints 'agree' or a reason, exit status unused
verdict_of() {
    vk=$1
    vtext=$2
    vstatus=$3
    vout=$4
    vnamed=${5:-named}
    case "$vk" in
        answer)
            if [ "$vstatus" -ne 0 ]; then
                printf 'expected the answer [%s], got exit %s\n' "$vtext" "$vstatus"
                return 0
            fi
            if [ "$vout" != "$vtext" ]; then
                printf 'expected the answer [%s], got [%s]\n' "$vtext" "$vout"
                return 0
            fi
            printf 'agree\n'
            ;;
        refuse)
            if [ "$vstatus" -eq 0 ]; then
                printf 'expected a named refusal, got exit 0 and [%s]\n' "$vout"
                return 0
            fi
            if [ -n "$vout" ]; then
                printf 'refused at exit %s but printed [%s] first\n' "$vstatus" "$vout"
                return 0
            fi
            # A CRASH IS NOT A REFUSAL. Exit 139 with an empty stdout satisfies
            # both tests above and is the worst outcome in the set, so the
            # verdict asks the compiler to have SAID something. `duo_str_to_i64`
            # dereferencing a non-text subject is the recorded shape: exit 139,
            # reproduced 3 of 3, nothing on either stream.
            if [ "$vnamed" != 'named' ]; then
                printf 'exited %s with no diagnostic — a crash is not a refusal\n' "$vstatus"
                return 0
            fi
            printf 'agree\n'
            ;;
        *)
            printf 'unknown expectation kind [%s]\n' "$vk"
            ;;
    esac
}

# ── 1. the comparator is controlled on the recorded defect ─────────────────
#
# Three transcripts out of GAP-207's own table, plus the shape GAP-145 records
# for `v = "set" or "FB"`. Each MUST be convicted. If any is called 'agree'
# the comparator is broken and every number below it is worthless, so this
# section runs FIRST and aborts rather than continuing to a green report.
control_convictions=0
control_subjects=0
convict() {
    control_subjects=$((control_subjects + 1))
    cv=$(verdict_of "$1" "$2" "$3" "$4" "${5:-named}")
    if [ "$cv" = 'agree' ]; then
        printf 'byteface: CONTROL NOT CONVICTED — comparator called [%s] an agreement with [%s]\n' "$4" "$2" >&2
    else
        control_convictions=$((control_convictions + 1))
    fi
}
# GAP-207 run 1, run 2, run 3: three ASLR'd pointers through %lld, exit 0.
convict answer abcZ 0 '4370531440Z'
convict answer abcZ 0 '4342023280Z'
convict answer abcZ 0 '4372497520Z'
# The same class reached through `or`-selection, recorded on `exprIsStr`.
convict answer set 0 '4304880776'
# A refusal that emitted the wrong answer before refusing is still the wrong
# answer. Nothing in this repository had a control for that shape.
convict refuse '' 1 '4339188916Z'
# A SEGFAULT IS NOT A REFUSAL. Recorded shape: exit 139, empty on both streams.
convict refuse '' 139 '' silent
# And the honest verdicts must NOT be convicted, or the comparator is simply
# a constant `FAIL` and equally useless.
if [ "$(verdict_of answer abcZ 0 abcZ)" != 'agree' ]; then
    printf 'byteface: CONTROL BROKEN — comparator refuses a correct answer\n' >&2
    exit 2
fi
if [ "$(verdict_of refuse '' 1 '')" != 'agree' ]; then
    printf 'byteface: CONTROL BROKEN — comparator refuses a clean refusal\n' >&2
    exit 2
fi
if [ "$control_subjects" -eq 0 ] || [ "$control_convictions" -ne "$control_subjects" ]; then
    printf 'byteface: comparator control failed (%s/%s convicted) — measuring nothing\n' \
        "$control_convictions" "$control_subjects" >&2
    exit 2
fi

# ── 2. the subjects ────────────────────────────────────────────────────────
#
# `run_subject NAME EXPECTKIND EXPECTTEXT` reads the program on stdin.
#
# Stdout only. The compiler writes its build progress to stdout as indented
# ` > ` / ` ok ` lines and its diagnostics to stderr; the PROGRAM's own output
# is what remains, so those two prefixes are stripped and nothing else is.
run_subject() {
    sname=$1
    skind=$2
    stext=$3
    subjects=$((subjects + 1))
    sfile="$scratch/subject.id"
    cat > "$sfile"
    # NO PIPELINE. `$?` after `cmd | sed` is SED's status, and the first draft
    # of this file scored every refusal as exit 0 for exactly that reason —
    # the gate reporting a number it had not measured, in the gate written to
    # forbid it. The compiler puts its build progress and its diagnostics on
    # stderr, so the program's own bytes are stdout, unfiltered.
    # RUN FROM THE SCRATCH DIRECTORY. `idol run` writes the linked binary
    # beside the invocation, and a gate that drops `subject.out` into the
    # repository root is editing the tree it is measuring.
    ( cd "$scratch" && "$IDOL" run "$sfile" ) > "$scratch/out" 2> "$scratch/err"
    sstatus=$?
    sout=$(cat "$scratch/out")
    snamed=silent
    if grep -q 'error:' "$scratch/err"; then snamed=named; fi
    sv=$(verdict_of "$skind" "$stext" "$sstatus" "$sout" "$snamed")
    if [ "$sv" != 'agree' ]; then
        fail "$sname: $sv"
    fi
}

# THE GAP-207 PROGRAM ITSELF. A byte sequence has element descriptor `byte`
# and no textual law; `dnir.Value` has no member that carries one, so the
# lawful verdict is the named refusal. What it must never be is a pointer.
run_subject 'bound byte literal in a concat' refuse '' <<'IDL'
main: i64 = ()
    s = 'abc'
    print(s .. "Z")
    0
IDL

# FOUR SPELLINGS OF ONE FACT MUST GIVE ONE ANSWER. `const` / `local` /
# `global` already refused; the bare module binding was the fourth spelling
# and it printed an address, which is how one fact came to have two answers
# depending only on which keyword was written.
run_subject 'const-bound byte literal in a concat' refuse '' <<'IDL'
const j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'local-bound byte literal in a concat' refuse '' <<'IDL'
local j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'global-bound byte literal in a concat' refuse '' <<'IDL'
global j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'bare-bound byte literal in a concat' refuse '' <<'IDL'
j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL

# A byte sequence handed to `print` on its own already refused by name, and
# must keep doing so: the admission rule and the capability rule have to claim
# the SAME set, which is the failure GAP-204 names.
run_subject 'bound byte literal printed alone' refuse '' <<'IDL'
main: i64 = ()
    s = 'abc'
    print(s)
    0
IDL

# THE SAME FACT WITHOUT A NAME. `lowerPrintFormat` runs BEFORE the binop
# guard for a print argument, and `planConcat` folded the bytes of every
# quoted part into the format string without asking which face it had. So the
# unnamed spelling answered `abcZ` while the named one refused -- one fact,
# two answers, decided by whether the operand had been bound.
run_subject 'byte literal in a concat, unnamed' refuse '' <<'IDL'
main: i64 = ()
    print('abc' .. "Z")
    0
IDL
run_subject 'byte literal interpolation' refuse '' <<'IDL'
main: i64 = ()
    k = 1
    print('a {k} b')
    0
IDL

# ── the negative controls: what must NOT have moved ────────────────────────
#
# A repair that refuses everything is not a repair. Each of these is a shape
# the same predicates decide, and each must still ANSWER.
run_subject 'bound text in a concat' answer abcZ <<'IDL'
main: i64 = ()
    t = "abc"
    print(t .. "Z")
    0
IDL
run_subject 'text literals in a concat' answer abcZ <<'IDL'
main: i64 = ()
    print("abc" .. "Z")
    0
IDL
run_subject 'bound integer in a concat' answer 'n=7' <<'IDL'
main: i64 = ()
    n = 7
    print("n=" .. n)
    0
IDL
run_subject 'or-selected text' answer set <<'IDL'
main: i64 = ()
    v = "set" or "FB"
    print(v)
    0
IDL
run_subject 'interpolated integer' answer 'a 1 b' <<'IDL'
main: i64 = ()
    k = 1
    print("a {k} b")
    0
IDL

# ── 3. verdict ─────────────────────────────────────────────────────────────
if [ "$subjects" -eq 0 ]; then
    printf 'byteface: FAIL zero subjects — a gate that measures nothing is not a control (GAP-201)\n' >&2
    exit 1
fi
if [ "$violations" -ne 0 ]; then
    printf 'byteface: FAIL %s of %s subject(s); comparator convicted %s/%s recorded defects\n' \
        "$violations" "$subjects" "$control_convictions" "$control_subjects" >&2
    exit 1
fi
printf 'byteface: PASS %s subject(s); comparator convicted %s/%s recorded defects\n' \
    "$subjects" "$control_convictions" "$control_subjects"
exit 0
