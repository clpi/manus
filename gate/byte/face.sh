#!/bin/sh
# gate/byte/face.sh — GAP-145 / GAP-207: the byte face of a value must
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
#   zig build unit-test                    unchanged, same failures
#   compile-status sweep, whole corpus     zero diff
#   output differential, everything that   zero diff
#     compiles
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
# BYTE FOR BYTE MEANS FILES, NOT `$(...)`. The first version of this gate held
# both sides in shell variables, and POSIX command substitution STRIPS EVERY
# TRAILING NEWLINE — so `abcZ`, `abcZ\n` and `abcZ\n\n` were one value to a
# comparator whose own header claimed byte-for-byte. That is not academic
# here: `print` ends a line and `stdout:write` ends nothing, a distinction
# `lowerStreamWrite` exists to preserve and which was measured wrong once
# already (`stdout:write("A=V\n")` emitting two newlines). Every subject now
# names its ENDING and the two streams are compared with `cmp`.
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
    printf 'byte face: no compiler at %s — nothing was measured\n' "$IDOL" >&2
    exit 2
fi

# Every subject below is RUN and its printed answer compared. On a host with no
# direct-native realization `idol run` refuses before any program prints, and
# this gate reported nine lines of the form
#     FAIL byte payload written, unnamed: expected the answer [{"a":1}], got exit 1
# which reads as nine wrong answers from the byte face. It was one absent
# backend, named nowhere in the output.
. "$root/gate/realization/direct.sh"
direct_native_probe "$IDOL"
direct_available=1
if direct_native_absent; then
    direct_available=0
    direct_native_note 'the printed-answer comparison needs to EXECUTE each subject, and none can be built'
fi

# The wasm column measures the COMPILE-TIME byte-face verdict and needs only
# the compiler, which the check above already established. It is independent
# of the direct backend, so it runs on a host with no direct-native
# realization — the exact host where the direct column cannot. This is the
# column GAP-207's blocker names: the gate's PASS used to say nothing about
# the wasm answer because every subject went through `idol run`, the direct
# realization and only that one.
wasm_available=1

# The C column needs the compiler (already established) AND a C toolchain to
# link the artifact against the shim that carries its ABI. `cc` is not a
# guaranteed fact of a host, so the probe is the toolchain itself; without it
# the C verdict could not be executed and the column would be silent exactly
# where this host's only executable realization lives.
c_available=0
if command -v cc >/dev/null 2>&1 && [ -f "$root/tools/node/dev/grammar/idol_c_runtime_shim.c" ]; then
    c_available=1
fi

if [ "$direct_available" -eq 0 ] && [ "$wasm_available" -eq 0 ] && [ "$c_available" -eq 0 ]; then
    printf 'byte face: no realization to measure — nothing was measured\n' >&2
    exit 2
fi

scratch=$(mktemp -d) || { echo 'byte face: cannot allocate scratch' >&2; exit 2; }
cleanup() { rm -rf -- "$scratch"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

violations=0
subjects=0

fail() {
    violations=$((violations + 1))
    printf 'byte face: FAIL %s\n' "$*"
}

# ── THE COMPARATOR, as a function, so the controls can call the same code ──
#
# It is deliberately not inlined into the subject loop. A control that
# re-implements the comparison proves nothing about the comparison that runs.
#
#   verdict_of EXPECTKIND EXPECTTEXT ACTUALSTATUS ACTUALOUT
#     -> prints 'agree' or a reason, exit status unused
#   verdict_of EXPECTKIND WANTFILE GOTFILE ACTUALSTATUS [named|silent]
#     -> prints 'agree' or a reason
verdict_of() {
    vk=$1
    vwant=$2
    vgot=$3
    vstatus=$4
    vnamed=${5:-named}
    case "$vk" in
        answer)
            if [ "$vstatus" -ne 0 ]; then
                printf 'expected the answer [%s], got exit %s\n' "$(cat "$vwant")" "$vstatus"
                return 0
            fi
            if ! cmp -s "$vwant" "$vgot"; then
                printf 'expected the bytes [%s], got [%s] (%s vs %s bytes)\n' \
                    "$(cat "$vwant")" "$(cat "$vgot")" \
                    "$(wc -c < "$vwant" | tr -d ' ')" "$(wc -c < "$vgot" | tr -d ' ')"
                return 0
            fi
            printf 'agree\n'
            ;;
        refuse)
            if [ "$vstatus" -eq 0 ]; then
                printf 'expected a named refusal, got exit 0 and [%s]\n' "$(cat "$vgot")"
                return 0
            fi
            if [ -s "$vgot" ]; then
                printf 'refused at exit %s but printed [%s] first\n' "$vstatus" "$(cat "$vgot")"
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

# ── THE WASM COMPARATOR ────────────────────────────────────────────────────
#
# The direct column above measures the RUN answer. The wasm column measures
# the COMPILE-TIME byte-face verdict, which is the only thing a host with no
# wasm runner can still measure and the exact thing GAP-207's blocker says the
# gate was silent about: the wasm backend used to COMPILE `s = 'abc';
# print(s)` and print a data-segment offset at exit 0, while the direct
# backend refused it by name. The repair made wasm refuse at compile, so the
# wasm verdict is read off the compile status, not a run.
#
#   wasm_verdict EXPECTKIND ACTUALSTATUS ACTUALOUT ACTUALERR
#     -> prints 'agree' or a reason, exit status unused
wasm_verdict() {
    wk=$1
    wstatus=$2
    wout=$3
    werr=$4
    case "$wk" in
        refuse)
            if [ "$wstatus" -eq 0 ]; then
                printf 'wasm: expected a named refusal, got compile exit 0 (the pointer-print shape)\n'
                return 0
            fi
            if [ -s "$wout" ]; then
                printf 'wasm: refused at exit %s but wrote to stdout first\n' "$wstatus"
                return 0
            fi
            if ! grep -q 'error:' "$werr"; then
                printf 'wasm: exited %s with no diagnostic — a crash is not a refusal\n' "$wstatus"
                return 0
            fi
            printf 'agree\n'
            ;;
        answer)
            if [ "$wstatus" -ne 0 ]; then
                printf 'wasm: expected the byte face to compile, got exit %s\n' "$wstatus"
                return 0
            fi
            printf 'agree\n'
            ;;
        *)
            printf 'unknown wasm expectation kind [%s]\n' "$wk"
            ;;
    esac
}

# ── THE C COMPARATOR ────────────────────────────────────────────────────────
#
# The wasm column measures the wasm backend's compile-time verdict. The C
# route is the THIRD realization and the only one that EXECUTES on hosts with
# no direct-native machine; it compiled every byte-face print and rendered the
# pointer-shaped slot through `%lld` at exit 0 — measured at c0adff39 on this
# host: `s = 'abc' ; print(s)` printed `93827861911360`. Its compile-time
# verdict is read the same way wasm's is: an exit 0 on a refuse subject IS the
# pointer-print shape, and a refusal must be named.
#
#   c_verdict EXPECTKIND ACTUALSTATUS ACTUALOUT ACTUALERR
#     -> prints 'agree' or a reason, exit status unused
c_verdict() {
    ck=$1
    cstatus=$2
    cout=$3
    cerr=$4
    case "$ck" in
        refuse)
            if [ "$cstatus" -eq 0 ]; then
                printf 'c: expected a named refusal, got compile exit 0 (the pointer-print shape)\n'
                return 0
            fi
            if [ -s "$cout" ]; then
                printf 'c: refused at exit %s but wrote to stdout first\n' "$cstatus"
                return 0
            fi
            if ! grep -q 'error:' "$cerr"; then
                printf 'c: exited %s with no diagnostic — a crash is not a refusal\n' "$cstatus"
                return 0
            fi
            printf 'agree\n'
            ;;
        answer)
            if [ "$cstatus" -ne 0 ]; then
                printf 'c: expected the byte face to compile, got exit %s\n' "$cstatus"
                return 0
            fi
            printf 'agree\n'
            ;;
        *)
            printf 'unknown c expectation kind [%s]\n' "$ck"
            ;;
    esac
}

# `want NAME ENDING` writes the expected bytes from stdin-free arguments into a
# file. ENDING is `nl` for a line-ending egress (`print`) and `nonl` for one
# that ends nothing (`stdout:write`) — the distinction `$(...)` destroyed.
want_file() {
    wf=$1
    wtext=$2
    wend=${3:-nonl}
    if [ "$wend" = 'nl' ]; then
        printf '%s\n' "$wtext" > "$wf"
    else
        printf '%s' "$wtext" > "$wf"
    fi
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
    want_file "$scratch/cwant" "$2" "${6:-nl}"
    printf '%s' "$4" > "$scratch/cgot"
    cv=$(verdict_of "$1" "$scratch/cwant" "$scratch/cgot" "$3" "${5:-named}")
    if [ "$cv" = 'agree' ]; then
        printf 'byte face: CONTROL NOT CONVICTED — comparator called [%s] an agreement with [%s]\n' "$4" "$2" >&2
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
want_file "$scratch/cwant" abcZ nl
printf 'abcZ\n' > "$scratch/cgot"
if [ "$(verdict_of answer "$scratch/cwant" "$scratch/cgot" 0)" != 'agree' ]; then
    printf 'byte face: CONTROL BROKEN — comparator refuses a correct answer\n' >&2
    exit 2
fi
# AND IT MUST SEE THE ENDING. This is the defect the first version of this file
# carried: with `$(...)` on both sides, an extra trailing newline was invisible.
printf 'abcZ\n\n' > "$scratch/cgot"
if [ "$(verdict_of answer "$scratch/cwant" "$scratch/cgot" 0)" = 'agree' ]; then
    printf 'byte face: CONTROL BROKEN — comparator cannot see a trailing newline\n' >&2
    exit 2
fi
control_subjects=$((control_subjects + 1))
control_convictions=$((control_convictions + 1))
want_file "$scratch/cwant" '' nonl
: > "$scratch/cgot"
if [ "$(verdict_of refuse "$scratch/cwant" "$scratch/cgot" 1)" != 'agree' ]; then
    printf 'byte face: CONTROL BROKEN — comparator refuses a clean refusal\n' >&2
    exit 2
fi
if [ "$control_subjects" -eq 0 ] || [ "$control_convictions" -ne "$control_subjects" ]; then
    printf 'byte face: comparator control failed (%s/%s convicted) — measuring nothing\n' \
        "$control_convictions" "$control_subjects" >&2
    exit 2
fi

# ── 1b. the wasm comparator is controlled on the recorded defect ────────────
#
# The wasm column's comparator is controlled on the SAME recorded defect the
# direct column is: the wasm backend used to COMPILE `s = 'abc'; print(s)`
# (exit 0, no diagnostic) and print a data-segment offset at run time. A
# compile that succeeds on a byte-face print is the pointer-print shape, so
# the wasm comparator must convict a compile exit 0 on a refuse subject, and
# must NOT convict a clean named refusal. If it cannot tell those apart, the
# wasm column below is worthless.
wasm_control_convictions=0
wasm_control_subjects=0
wconvict() {
    wasm_control_subjects=$((wasm_control_subjects + 1))
    : > "$scratch/wcout"
    printf '%s' "$3" > "$scratch/wcerr"
    wcv=$(wasm_verdict "$1" "$2" "$scratch/wcout" "$scratch/wcerr")
    if [ "$wcv" = 'agree' ]; then
        printf 'byte face: WASM CONTROL NOT CONVICTED — comparator called [%s] an agreement with exit %s\n' "$1" "$2" >&2
    else
        wasm_control_convictions=$((wasm_control_convictions + 1))
    fi
}
# The recorded wasm defect: compile exit 0 on a byte-face print, no diagnostic.
wconvict refuse 0 ''
# A clean named refusal must NOT be convicted.
: > "$scratch/wcout"
printf 'error: wasm32-wasi: no native realization (UnsupportedProgram)\n' > "$scratch/wcerr"
if [ "$(wasm_verdict refuse 1 "$scratch/wcout" "$scratch/wcerr")" != 'agree' ]; then
    printf 'byte face: WASM CONTROL BROKEN — comparator refuses a clean named refusal\n' >&2
    exit 2
fi
wasm_control_subjects=$((wasm_control_subjects + 1))
wasm_control_convictions=$((wasm_control_convictions + 1))
# A byte-face egress that must still COMPILE (answer) must not be convicted.
if [ "$(wasm_verdict answer 0 "$scratch/wcout" "$scratch/wcerr")" != 'agree' ]; then
    printf 'byte face: WASM CONTROL BROKEN — comparator refuses a clean compile\n' >&2
    exit 2
fi
wasm_control_subjects=$((wasm_control_subjects + 1))
wasm_control_convictions=$((wasm_control_convictions + 1))
if [ "$wasm_control_subjects" -eq 0 ] || [ "$wasm_control_convictions" -ne "$wasm_control_subjects" ]; then
    printf 'byte face: wasm comparator control failed (%s/%s convicted) — measuring nothing\n' \
        "$wasm_control_convictions" "$wasm_control_subjects" >&2
    exit 2
fi

# ── 1c. the c comparator is controlled on the measured defect ───────────────
#
# The C route's defect is MEASURED at this host, not recorded from another
# backend: it compiled `s = 'abc' ; print(s)` at exit 0 and the linked binary
# printed a pointer as a decimal. The control plants exactly that transcript
# and refuses the comparator if it calls it agreement; a clean named refusal
# must NOT be convicted, and a byte egress that must still compile must not
# be either. If it cannot tell those apart, the c column below is worthless.
c_control_convictions=0
c_control_subjects=0
cconvict() {
    c_control_subjects=$((c_control_subjects + 1))
    : > "$scratch/ccout"
    printf '%s' "$3" > "$scratch/ccerr"
    ccv=$(c_verdict "$1" "$2" "$scratch/ccout" "$scratch/ccerr")
    if [ "$ccv" = 'agree' ]; then
        printf 'byte face: C CONTROL NOT CONVICTED — comparator called [%s] an agreement with exit %s\n' "$1" "$2" >&2
    else
        c_control_convictions=$((c_control_convictions + 1))
    fi
}
# The measured C defect: compile exit 0 on a byte-face print, no diagnostic,
# pointer rendered as a decimal by the linked binary.
cconvict refuse 0 ''
# A clean named refusal must NOT be convicted.
: > "$scratch/ccout"
printf 'error: c99-slice: print-byte-sequence (UnsupportedProgram)\n' > "$scratch/ccerr"
if [ "$(c_verdict refuse 1 "$scratch/ccout" "$scratch/ccerr")" != 'agree' ]; then
    printf 'byte face: C CONTROL BROKEN — comparator refuses a clean named refusal\n' >&2
    exit 2
fi
c_control_subjects=$((c_control_subjects + 1))
c_control_convictions=$((c_control_convictions + 1))
# A byte-face egress that must still COMPILE (answer) must not be convicted.
if [ "$(c_verdict answer 0 "$scratch/ccout" "$scratch/ccerr")" != 'agree' ]; then
    printf 'byte face: C CONTROL BROKEN — comparator refuses a clean compile\n' >&2
    exit 2
fi
c_control_subjects=$((c_control_subjects + 1))
c_control_convictions=$((c_control_convictions + 1))
if [ "$c_control_subjects" -eq 0 ] || [ "$c_control_convictions" -ne "$c_control_subjects" ]; then
    printf 'byte face: c comparator control failed (%s/%s convicted) — measuring nothing\n' \
        "$c_control_convictions" "$c_control_subjects" >&2
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
    send=${4:-nl}
    subjects=$((subjects + 1))
    sfile="$scratch/subject.id"
    cat > "$sfile"
    # NO PIPELINE AND NO COMMAND SUBSTITUTION ON THE OUTPUT. `$?` after
    # `cmd | sed` is SED's status, and the first draft of this file scored
    # every refusal as exit 0 for exactly that reason; `$(...)` then ate the
    # trailing newline that separates `print` from `stdout:write`. The
    # compiler puts its build progress and its diagnostics on stderr, so the
    # program's own bytes are stdout, unfiltered and uncopied.
    #
    # RUN FROM THE SCRATCH DIRECTORY: `idol run` writes the linked binary
    # beside the invocation, and a gate that drops `subject.out` into the
    # repository root is editing the tree it is measuring.
    if [ "$direct_available" -eq 1 ]; then
        ( cd "$scratch" && "$IDOL" run "$sfile" ) > "$scratch/out" 2> "$scratch/err"
        sstatus=$?
        want_file "$scratch/want" "$stext" "$send"
        snamed=silent
        if grep -q 'error:' "$scratch/err"; then snamed=named; fi
        sv=$(verdict_of "$skind" "$scratch/want" "$scratch/out" "$sstatus" "$snamed")
        if [ "$sv" != 'agree' ]; then
            fail "$sname: $sv"
        fi
    fi
    # The wasm column: the COMPILE-TIME byte-face verdict, measured on the same
    # subject. The direct column above runs the program; the wasm column asks
    # whether the wasm backend refuses the byte face BY NAME at compile, which
    # is the only thing a host with no wasm runner can still measure and the
    # exact thing GAP-207's blocker says the gate was silent about.
    if [ "$wasm_available" -eq 1 ]; then
        ( cd "$scratch" && "$IDOL" compile --backend=wasm --target=wasm32-wasi -o "$scratch/subject.wasm" "$sfile" ) \
            > "$scratch/wout" 2> "$scratch/werr"
        wstatus=$?
        wv=$(wasm_verdict "$skind" "$wstatus" "$scratch/wout" "$scratch/werr")
        if [ "$wv" != 'agree' ]; then
            fail "$sname (wasm): $wv"
        fi
    fi
    # The C column: the THIRD realization, and the one that EXECUTES on hosts
    # with no direct-native machine (this gate's own host is one). It compiled
    # every byte-face print and rendered the pointer-shaped slot through %lld
    # at exit 0 — the pointer-print class GAP-207 convicted on direct and
    # wasm, surviving here. Like wasm, its verdict is the COMPILE-TIME
    # byte-face decision; unlike wasm it produces a linkable artifact, so the
    # comparator also links and EXECUTES a compile that must answer, byte for
    # byte, against the shim that carries its ABI (measured, not assumed:
    # stdout:write of a byte payload answers `{"a":1}` on this route).
    if [ "$c_available" -eq 1 ]; then
        ( cd "$scratch" && "$IDOL" compile --backend=c --emit=c --target=c-source --entry main \
            -o "$scratch/subject.c" "$sfile" ) > "$scratch/cout" 2> "$scratch/cerr"
        cstatus=$?
        cv=$(c_verdict "$skind" "$cstatus" "$scratch/cout" "$scratch/cerr")
        if [ "$cv" != 'agree' ]; then
            fail "$sname (c): $cv"
        elif [ "$skind" = answer ]; then
            if ! cc -O2 "$scratch/subject.c" "$root/tools/node/dev/grammar/idol_c_runtime_shim.c" \
                -o "$scratch/subject.bin" > "$scratch/clang.out" 2> "$scratch/clang.err"; then
                fail "$sname (c): expected the answer, but the C source did not link: $(tail -1 "$scratch/clang.err")"
            elif ! ( cd "$scratch" && ./subject.bin ) > "$scratch/crun.out" 2> /dev/null; then
                fail "$sname (c): expected the answer, but the binary exited non-zero"
            else
                want_file "$scratch/cwant" "$stext" "$send"
                crv=$(verdict_of answer "$scratch/cwant" "$scratch/crun.out" 0)
                if [ "$crv" != 'agree' ]; then
                    fail "$sname (c): $crv"
                fi
            fi
        fi
    fi
}

# THE GAP-207 PROGRAM ITSELF. A byte sequence has element descriptor `byte`
# and no textual law; `dnir.Value` has no member that carries one, so the
# lawful verdict is the named refusal. What it must never be is a pointer.
run_subject 'bound byte literal in a concat' refuse '' nonl <<'IDL'
main: i64 = ()
    s = 'abc'
    print(s .. "Z")
    0
IDL

# FOUR SPELLINGS OF ONE FACT MUST GIVE ONE ANSWER. `const` / `local` /
# `global` already refused; the bare module binding was the fourth spelling
# and it printed an address, which is how one fact came to have two answers
# depending only on which keyword was written.
run_subject 'const-bound byte literal in a concat' refuse '' nonl <<'IDL'
const j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'local-bound byte literal in a concat' refuse '' nonl <<'IDL'
local j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'global-bound byte literal in a concat' refuse '' nonl <<'IDL'
global j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL
run_subject 'bare-bound byte literal in a concat' refuse '' nonl <<'IDL'
j = 'abc'
main: i64 = ()
    print(j .. "Z")
    0
IDL

# A byte sequence handed to `print` on its own already refused by name, and
# must keep doing so: the admission rule and the capability rule have to claim
# the SAME set, which is the failure GAP-204 names.
run_subject 'bound byte literal printed alone' refuse '' nonl <<'IDL'
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
run_subject 'byte literal in a concat, unnamed' refuse '' nonl <<'IDL'
main: i64 = ()
    print('abc' .. "Z")
    0
IDL
run_subject 'byte literal interpolation' refuse '' nonl <<'IDL'
main: i64 = ()
    k = 1
    print('a {k} b')
    0
IDL

# ── BYTE EGRESS: THE FACE THE COMPILER ITSELF RECOMMENDS ───────────────────
#
# `src/parser.zig` tells people, in a hint on a real diagnostic, that "a
# payload that is all braces and no holes -- JSON, a C body, an awk program --
# belongs in the byte face `'…'`". Writing bytes to a byte stream needs no
# textual law, so this is the one consuming position where the byte face must
# ANSWER rather than refuse -- and the literal spelling always did, while the
# BOUND spelling printed a decimal address at exit 0. The recommended idiom
# was the broken one.
run_subject 'byte payload written, unnamed' answer '{"a":1}' nonl <<'IDL'
main: i64 = ()
    stdout:write('{"a":1}')
    0
IDL
run_subject 'byte payload written, bound' answer '{"a":1}' nonl <<'IDL'
main: i64 = ()
    j = '{"a":1}'
    stdout:write(j)
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
run_subject 'bound text written' answer hello nonl <<'IDL'
main: i64 = ()
    j = "hello"
    stdout:write(j)
    0
IDL
run_subject 'bound integer written' answer 7 nonl <<'IDL'
main: i64 = ()
    n = 7
    stdout:write(n)
    0
IDL

# ── 3. verdict ─────────────────────────────────────────────────────────────
if [ "$subjects" -eq 0 ]; then
    printf 'byte face: FAIL zero subjects — a gate that measures nothing is not a control (GAP-201)\n' >&2
    exit 1
fi
if [ "$violations" -ne 0 ]; then
    printf 'byte face: FAIL %s of %s subject(s); comparator convicted %s/%s recorded defects; wasm comparator convicted %s/%s; c comparator convicted %s/%s\n' \
        "$violations" "$subjects" "$control_convictions" "$control_subjects" \
        "$wasm_control_convictions" "$wasm_control_subjects" \
        "$c_control_convictions" "$c_control_subjects" >&2
    exit 1
fi
# The columns actually measured are NAMED. A PASS that says nothing about a
# realization it did not measure is the silence GAP-207 records; the verdict
# line must distinguish a full agreement from a host that could only ask wasm
# or c.
column_list=
if [ "$direct_available" -eq 1 ]; then column_list="direct"; fi
if [ "$wasm_available" -eq 1 ]; then
    column_list=${column_list:+"$column_list and "}wasm
fi
if [ "$c_available" -eq 1 ]; then
    column_list=${column_list:+"$column_list and "}c
fi
printf 'byte face: PASS %s subject(s) on %s; comparator convicted %s/%s recorded defects; wasm comparator convicted %s/%s; c comparator convicted %s/%s\n' \
    "$subjects" "$column_list" "$control_convictions" "$control_subjects" \
    "$wasm_control_convictions" "$wasm_control_subjects" \
    "$c_control_convictions" "$c_control_subjects"
exit 0
