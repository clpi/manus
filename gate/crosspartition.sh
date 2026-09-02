#!/bin/sh
# gate/crosspartition.sh — a program is REALIZED over every source partition it
# reaches, on the `--backend=direct` native route.
#
# ═══ THE FAILURE THIS PINS, quoted from the tree's own record ══════════════
#
# `gaps/GAP-134.md` records it as still open:
#
#     Undefined symbols for architecture arm64:
#       "_idol_token_grammarrole__rolebeginexpr", referenced from: …
#     error: native linker failed
#
# Reach was already established. Resolution found the file, sema parsed the
# declaration, the graph carried the foreign home, and the definer and the
# caller already derived the SAME mangled string from the same two facts
# because both go through `home_resolve.relationSymbol`. NOBODY EVER COMPILED
# THE REACHED PARTITION and put it on the link line. Every piece except that
# one already worked, which is why the failure surfaced at the linker rather
# than anywhere a compiler diagnostic could explain it.
#
# The C transfer route closed its half of this and has `gate/lower/fallback.sh`
# holding it closed. The direct native route closed its half with
# `main.reachedHomeClosure` and landed with NO GATE AT ALL — its evidence was
# prose in a commit message. This file is that missing instrument.
#
# ═══ WHAT IS MEASURED, AND WHY IT IS EXECUTION AND NOT INSPECTION ══════════
#
# Every subject is COMPILED WITH `--backend=direct` AND RUN, and its answer is
# checked against a number that only the reached partition can produce. A
# scan of the link line, or an `nm` of the entry object, would agree with a
# compiler that linked the right files and realized them wrongly. An answer
# does not.
#
# `nm` IS STILL READ, as a SECOND pin and never as the first: the reached
# relation must be DEFINED (`T`) in the linked image. A subject that answers
# correctly with the definition absent would mean the answer came from
# somewhere other than the partition under test — constant folding, a stale
# artifact, an aliased binary — and this column is what tells those apart from
# the thing being claimed. A pin written `!name` inverts it and requires the
# symbol to be ABSENT, which is how a subject states what its link line must NOT
# have been given; see the `text` shape below for what that is for.
#
# ═══ THE SUBJECT ROSTER IS A FILE, so zero subjects is reachable ═══════════
#
# GAP-201: a gate examining zero subjects must FAIL. That rule is only worth
# anything if zero is a state this gate can actually be in, so the roster lives
# in `gate/crosspartition.subjects` rather than in this script. A run that
# cannot read it, or reads no rows from it, exits non-zero saying so.
#
# The roster is checked BOTH WAYS. A row naming a shape this script cannot
# materialize fails, so the roster cannot name subjects that quietly stop
# existing; and a shape this script can materialize that the roster does not
# name fails, so a subject cannot be dropped from measurement by deleting one
# line. It is a ratchet, not a list.
#
# ═══ THE CONTROLS ══════════════════════════════════════════════════════════
#
# A gate that refuses everything passes every ratchet it owns and measures
# nothing, and a gate that reads only exit status agrees with a compiler that
# links the world and computes garbage. The controls run BEFORE any subject is
# reported, each proving a different way to be wrong:
#
#   P  POSITIVE. A SINGLE-partition program must compile and answer. Nothing
#      here is about cross-partition reach, so if this cannot pass, the
#      compiler under test is not measurable and the gate says NOT MEASURED
#      instead of reporting a cross-partition finding it did not earn. This is
#      what stops "refuse everything" from being a pass.
#
#      AND "NOT MEASURED" IS DECIDED BEFORE IT, NOT BY IT. Whether this host
#      realizes the executable kind at all is `gate/realization/direct.sh`'s
#      fact, and that library answers `no` (DNB004 — a host limit) apart from
#      `broken` (failed for another reason — a defect). Control P used to
#      collapse both into exit 3, so a direct backend that miscompiles a
#      three-line program was reported as an unmeasurable host. The
#      classification runs first; control P's own failure is now a FAIL.
#
#   N1 NEGATIVE, THE CHECKER SEES A WRONG ANSWER. The two-partition subject is
#      materialized with the reached partition DAMAGED — `x * 3` where the
#      expected answer wants `x * 2` — and the SAME `run_subject` used for real
#      subjects is required to report failure. If it reports success, this file
#      is not reading answers and every green row below is worthless.
#
#   N2 NEGATIVE, THE REACH IS NOT OPTIONAL. The same subject with the reached
#      partition REMOVED must fail to produce a working program. A compiler
#      that silently drops an unrealizable input and links anyway reproduces
#      the undefined symbol one layer further from its cause, which is the
#      fail-open this whole path exists to remove.
#
#   N3 NEGATIVE, BOTH PIN DIRECTIONS REFUSE. The `nm` column decides the
#      `text` row and the selectivity of the other three, so a pin reader that
#      never refuses would make all four decorations. See the `text` section.
#
#   P2 POSITIVE, FOR THE SECOND ARTIFACT KIND. Control P established that this
#      host realizes an EXECUTABLE. N4 measures a SHARED LIBRARY, which is a
#      DIFFERENT realization — `resolveCompileBackend` answers `native-dylib`
#      rather than `native-exe`, and the link step differs too, since the shared
#      line carries `-dynamiclib`. P therefore decides measurability for the
#      wrong kind. P2 asks the same question P asks, of the kind N4 actually
#      uses, and it also proves this file can READ symbols out of that kind.
#
#   N4 THE OTHER ARTIFACT KIND THAT LINKS. Every subject in the roster is an
#      EXECUTABLE; a shared library links too, and its line was built by a
#      SECOND producer that answered the literal `&.{}`. See below.
#
# ═══ TWO ARTIFACT KINDS LINK, AND ONE PRODUCER DECIDES BOTH ════════════════
#
# `main.directLinkLine` is that producer: bootstrap units selected from the
# union of an artifact's own needs and its reached partitions', plus those
# partitions' objects. Control N4 is what holds it to one.
#
# It was TWO. The executable's line learned to carry the union; the shared
# library's was handed `&.{}`, so a dylib got neither the units its own object
# referenced nor the partitions it reached — with the need list computed and
# sitting unread in its artifact — and `-dynamiclib` defaults to
# `-undefined error`, so both went undefined at the linker by symbol name.
# A fact with two producers is a fact that can be repaired in one of them, and
# that is what had happened.
#
# N4's module is GAP-232's own shape moved to the shared kind: the dylib's
# exported relation reaches a sibling partition, and that partition is what
# converts text. Both outputs of the producer are pinned in one link — the
# reached partition's OBJECT by `_helper__value`, the unit its need selects by
# `duo_str_to_i64` — because passing the needs while dropping the objects, or
# the reverse, are independent ways to be wrong.
#
# IT IS A CONTROL AND NOT A ROSTER ROW because a dylib is not run and this
# gate's subjects are ANSWERS. The roster's second column is an exit status;
# this measurement has none, and giving it a fake one would put an unrunnable
# row in a file whose whole contract is compiled, run, answered.
#
# AND BECAUSE IT HAS NO ANSWER, ITS ENTIRE VERDICT IS `nm`. That is what control
# P2 exists for. N4's only two ways to observe are "did the link succeed" and
# "does the reader find these symbols", and BOTH have a host-shaped failure that
# is not the producer:
#
#   * the shared kind is a distinct realization from the executable one, so a
#     host that links an exe and not a library refuses here for a reason that
#     has nothing to do with a link line;
#   * `nm -g` does not read every shared object. Measured on aarch64-linux: a
#     STRIPPED ELF shared object answers `nm -g` with "no symbols" while `nm -D`
#     lists every exported one. A reader asking only `-g` would report a library
#     that defines both pinned symbols as defining neither.
#
# Either one, uncontrolled, makes N4 print that `main.directLinkLine` is not
# feeding the shared line — naming a producer it never reached. P2 turns both
# into NOT MEASURED, which is what they are.
#
# AND IT DOES NOT TURN EVERYTHING INTO NOT MEASURED, which is the opposite
# failure and the more expensive one. The refusal is classified by the DNB004
# identity, and a shared compile that fails for any OTHER reason — or reports
# success and writes no library — is a FAIL on a host where control P realized
# an executable. `gate/realization/direct.sh` separates `no` from `broken` for
# exactly this reason and its header says why: a defect must not wear a host
# limit's excuse.
#
# ═══ A REACHED PARTITION'S OWN BOOTSTRAP NEEDS, the `text` shape ═══════════
#
# Where the three arithmetic shapes above ask whether the reached partition is
# COMPILED AND LINKED, `text` asks whether what that partition NEEDS is. Its
# reached relation converts text (`"21":to(i64)`), which references
# `duo_str_to_i64` from `idol_str_runtime.o`; its entry does arithmetic on the
# result and needs no runtime of its own. `directLinkInputs` used to be handed
# the ENTRY's `artifact.need` alone — the recursive realization kept each reached
# artifact's BYTES and dropped its needs — so this shape failed at the linker:
#
#     _idol_<…>_helper__value   DEFINED (the reach, which the shapes above pin)
#     _duo_str_to_i64           UNDEFINED, referenced from the reached
#                               partition's own object
#
# That was GAP-232, and `main.reachedHomeClosure` now carries objects and needs
# out as ONE value because they are one fact: what the link line must carry.
#
# ITS CALL BOUNDARY IS DELIBERATELY `duo`'s. One i64 argument, one i64 result,
# so the ONLY thing that differs between `duo` and `text` is that the reached
# partition needs a bootstrap unit. Had this shape also passed a `str` across the
# boundary, a failure could have been argument lowering rather than the link
# line, and the subject would not isolate the variable it exists for.
#
# AND THE UNION MUST BE SELECTIVE, which is why `duo`, `trio` and `fan` each
# carry `!duo_str_to_i64`. A compiler that materialized all three bootstrap
# units on every link line would satisfy `text` and prove nothing — the pin
# would be true of a compiler that had never read a `need` at all. The absence
# rows are what make the presence row mean something.
#
# ═══ SOURCE PATH ═══════════════════════════════════════════════════════════
#
# The mangled symbol embeds the SOURCE PATH, so `_idol_<dirs>_helper__twice`
# is not stable across work directories and is never compared as a whole
# string; only its path-independent tail is. Nothing here byte-compares two
# artifacts, precisely because the path that would have to be held fixed is
# the one this gate randomizes.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'crosspartition: cannot enter root\n' >&2; exit 3; }

# `zig-out/bin/idol` AND NOT `out/bin/idol`. The latter is a stale artifact
# that has served as a false oracle in this tree before; it is not this build.
IDOL=${IDOL:-"$root/zig-out/bin/idol"}
roster=$here/crosspartition.subjects

if [ ! -x "$IDOL" ]; then
    printf 'crosspartition: NOT MEASURED — compiler is not executable: %s\n' "$IDOL" >&2
    exit 3
fi
if [ ! -r "$roster" ]; then
    printf 'crosspartition: FAIL — subject roster is unreadable: %s (0 subjects examined)\n' "$roster" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.crosspartition.XXXXXX") || exit 3
# A PRIVATE SCRATCH ROOT. `src/scratch.zig` routes the executable cache,
# intermediate objects and logs through TMPDIR, so pointing it inside `$work`
# gives this run a cache no other lane can name and no other lane can evict —
# the same reason `gate/cache-home.sh` does it.
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the shapes ─────────────────────────────────────────────────────────────
# Each writes ONE entry `main.id` plus the partitions it reaches, into $1.
# `damage` is the N1 control's hook: it is the empty string for a real subject
# and a factor for the deliberately-wrong one, so the control travels through
# the same materializer as the thing it is controlling for.
materialize() {
    shape=$1
    dir=$2
    factor=${3:-2}
    mkdir -p "$dir" || return 1
    case $shape in
        duo)
            # One entry, one reached partition. 21 * 2 = 42.
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        trio)
            # TRANSITIVE. The entry never names `deeper`; only the partition it
            # reaches does. (21 + 1) * 2 = 44. A closure that stops at depth one
            # links `helper` and still fails at the linker on `deeper`.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  deeper.plus(x) * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        fan)
            # TWO partitions reached from one entry, so the link line has to
            # carry more than one extra object. 10 * 2 + (4 + 1) = 25.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(10) + deeper.plus(4)\n' >"$dir/main.id" || return 1
            ;;
        text)
            # THE REACHED PARTITION NEEDS A BOOTSTRAP UNIT and the entry needs
            # none. `"21":to(i64)` references `duo_str_to_i64`, which lives in
            # `idol_str_runtime.o`; the entry only adds. 21 + 11 * 2 = 43.
            #
            # The boundary is `duo`'s exactly — one i64 in, one i64 out — so the
            # only variable between the two shapes is the reached need. Passing
            # a `str` across the boundary instead would have made an argument
            # lowering defect indistinguishable from a link-line defect.
            printf 'value: i64 = (x: i64)\n  "21":to(i64) + x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.value(11)\n' >"$dir/main.id" || return 1
            ;;
        solo)
            # No reach at all — the positive control's shape.
            printf 'main: i64 = ()\n  7\n' >"$dir/main.id" || return 1
            ;;
        *)
            return 2
            ;;
    esac
    return 0
}
SHAPES='duo trio fan text'

# ── quoting a compiler log into a CONVICTION ───────────────────────────────
# `gate/all.sh` reads a failing gate's log and counts it HOST-BOUND rather than
# a law violation when that log names the unsupported-target refusal identity.
# That is the RIGHT answer for every NOT MEASURED path here, and the wrong one
# for every FAIL: a conviction that quotes a compiler log naming that identity —
# or that names it in its own prose — is filed as a host limit and vanishes from
# the law total. A gate that cannot convict is the fail-open this whole file is
# about, one layer up.
#
# MEASURED, on aarch64-linux, by feeding this file's own output to that exact
# grep: the `broken` conviction above matched it, and so did control P2's FAIL
# sentence, which carried the token in prose on the DYLIB path — the half of
# GAP-232 that needs macOS to execute and would therefore have been laundered
# the first time it ever convicted.
#
# THE SUBSTITUTION IS IDENTITY-PRESERVING, not a redaction: the code and the
# error it maps are one fact — `gate/realization/direct.sh` documents the pair —
# so a reader learns exactly as much from the source-level name, and the
# enumerator stops reading a defect as a host.
log_tail() {
    tail -3 "$1" | tr '\n' ' ' | sed 's/DNB004/error.UnsupportedTarget/g'
}

# ── one subject, measured ──────────────────────────────────────────────────
# Compiles `$1/main.id` with `--backend=direct`, runs it, and requires the exit
# status to equal `$2`. `$3` is a comma-separated pin list read against the
# linked image: a bare name must be DEFINED in it, and `!name` must be ABSENT
# from it.
#
# Writes its own account to `$work/why` so the caller can print WHAT went wrong
# rather than only that something did. Returns 0 only on a full pass.
run_subject() {
    dir=$1
    expect=$2
    defines=$3
    : >"$work/why"

    if ! ( CDPATH='' cd -- "$dir" && "$IDOL" compile --backend=direct main.id -o prog ) \
        >"$work/compile.log" 2>&1
    then
        printf 'compile failed: %s' "$(log_tail "$work/compile.log")" >"$work/why"
        return 1
    fi
    if [ ! -x "$dir/prog" ]; then
        printf 'compile reported success and produced no executable' >"$work/why"
        return 1
    fi
    # A CRASH IS NOT AN ANSWER. 128+n is a signal, and reading one as an exit
    # status would let a segfaulting program match a numeric expectation.
    "$dir/prog" >/dev/null 2>&1
    got=$?
    if [ "$got" -gt 125 ]; then
        printf 'program did not answer (status %s — signal or exec failure)' "$got" >"$work/why"
        return 1
    fi
    if [ "$got" != "$expect" ]; then
        printf 'answered %s, expected %s' "$got" "$expect" >"$work/why"
        return 1
    fi
    if [ -n "$defines" ]; then
        # PATH-INDEPENDENT TAIL ONLY. The full symbol carries the work
        # directory, which changes every run.
        nm -g "$dir/prog" 2>/dev/null | awk '$2 == "T" { print $3 }' >"$work/defined"
        for pin in $(printf '%s\n' "$defines" | tr ',' ' '); do
            case $pin in
                !*)
                    if grep -q -- "${pin#!}\$" "$work/defined"; then
                        printf 'answered %s but %s is DEFINED in the image; this link line was not selective, so a presence pin elsewhere would prove nothing' \
                            "$got" "${pin#!}" >"$work/why"
                        return 1
                    fi
                    ;;
                *)
                    if ! grep -q -- "$pin\$" "$work/defined"; then
                        printf 'answered %s but %s is not DEFINED in the image' \
                            "$got" "$pin" >"$work/why"
                        return 1
                    fi
                    ;;
            esac
        done
    fi
    return 0
}

# ══ THE EXECUTABLE KIND IS CLASSIFIED BEFORE CONTROL P IS READ ═════════════
# `gate/realization/direct.sh` is the ONE PRODUCER of "can this host realize a
# direct-native artifact", and it answers four ways, not two: `yes`, `no`
# (refused BY NAME with DNB004 — a host limit), `unbuilt`, and `broken` (failed
# for some OTHER reason — a defect that must not wear a host limit's excuse).
# Control P below was written against a two-way world: ANY failure printed NOT
# MEASURED and exited 3. So a direct backend that is present and WRONG — one
# that miscompiles `main: i64 = ()\n 7`, or reports success and writes no
# executable — was reported as an unmeasurable host, which is the same fail-open
# this file's own P2 section condemns in one sentence: "a defect must not wear a
# host limit's excuse".
#
# IT IS ALSO THE SECOND-PRODUCER CLASS THIS GATE EXISTS FOR. `main.directLinkLine`
# had to become one producer because a fact with two can be repaired in one of
# them; the DNB004 identity read is that same fact, and this gate was reading it
# in its own words while the library that owns it sat unsourced.
#
# THE PROBE ASKS THE COMPILER AND NOT `uname`, so this does not hardcode
# Darwin/arm64 and does not go stale the day another host realizes natively.
. "$root/gate/realization/direct.sh"
direct_native_probe "$IDOL"
case ${IDOL_DIRECT_NATIVE:-} in
    yes) ;;
    no)
        direct_native_note 'every subject and control here (each needs a direct-native artifact that links and answers)'
        exit 3
        ;;
    unbuilt)
        printf 'crosspartition: NOT MEASURED — no compiler to ask: %s\n' "$IDOL" >&2
        exit 3
        ;;
    *)
        # `broken`, or a classification this file does not know. Either way it is
        # NOT a host limit, and exiting 3 here is how a real defect would have
        # been spelled as an excuse.
        printf 'crosspartition: FAIL — the direct backend failed on a trivial program and NOT by name, so this is a defect and not a host limit: %s\n' \
            "${IDOL_DIRECT_NATIVE_WHY:-no reason recorded}" >&2
        printf 'crosspartition:   a refusal by name (the identity `directDiagnostic(error.UnsupportedTarget)` emits) is a host limit and exits 3; anything else is the compiler under test.\n' >&2
        exit 1
        ;;
esac

# ══ CONTROL P — a single partition compiles, links and answers ═════════════
# ITS FAILURE IS NOW A FAIL, because the classification above already answered
# the question that used to make it a skip. The probe established that this host
# realizes an executable and writes a non-empty one; what is left for control P
# to add is the ANSWER, and a three-line single-partition program that links here
# and does not answer 7 is the compiler under test, not the host.
materialize solo "$work/ctl.solo" || {
    printf 'crosspartition: NOT MEASURED — cannot write the positive control\n' >&2
    exit 3
}
if ! run_subject "$work/ctl.solo" 7 ''; then
    printf 'crosspartition control P: FAIL — a single-partition program does not compile and answer here, on a host that realized the trivial direct-native probe: %s\n' \
        "$(cat "$work/why")" >&2
    printf 'crosspartition:   nothing this gate reports about cross-partition reach would be earned, and this is a defect and not a host limit.\n' >&2
    exit 1
fi

# ══ CONTROL N1 — the checker sees a wrong answer ═══════════════════════════
materialize duo "$work/ctl.wrong" 3 || {
    printf 'crosspartition: NOT MEASURED — cannot write the negative control\n' >&2
    exit 3
}
if run_subject "$work/ctl.wrong" 42 '_helper__twice'; then
    printf 'crosspartition control N1: FAIL — a reached partition answering 63 was accepted as 42.\n' >&2
    printf 'crosspartition:   this file is not reading answers; every row below would be worthless.\n' >&2
    exit 1
fi

# ══ CONTROL N2 — a missing reached partition is not silently dropped ═══════
materialize duo "$work/ctl.gone" || {
    printf 'crosspartition: NOT MEASURED — cannot write the fail-closed control\n' >&2
    exit 3
}
rm -f "$work/ctl.gone/helper.id"
if run_subject "$work/ctl.gone" 42 ''; then
    printf 'crosspartition control N2: FAIL — the entry produced a working 42 with its reached partition deleted.\n' >&2
    printf 'crosspartition:   the reach is being ignored, not realized.\n' >&2
    exit 1
fi

# ══ CONTROL N3 — both pin directions actually fire ═════════════════════════
# The `text` shape's whole claim rests on `nm` pins, and a pin reader that never
# refuses would make every one of them decoration. Both directions are exercised
# against the POSITIVE control's image, which answers 7 either way, so only the
# pin can decide the outcome.
if run_subject "$work/ctl.solo" 7 '_no__image__defines__this'; then
    printf 'crosspartition control N3: FAIL — a presence pin naming a symbol no image defines was accepted.\n' >&2
    printf 'crosspartition:   the defined-relation column is not being read; the text shape would prove nothing.\n' >&2
    exit 1
fi
if run_subject "$work/ctl.solo" 7 '!_main__main'; then
    printf 'crosspartition control N3: FAIL — an absence pin was accepted against an image that DEFINES the symbol.\n' >&2
    printf 'crosspartition:   the selectivity pins on duo/trio/fan are not being read.\n' >&2
    exit 1
fi

# ── the defined symbols of a shared library ────────────────────────────────
# ONE READER, used by control P2 and control N4 alike, for the same reason N1
# travels through `materialize`: a control that observes the artifact differently
# from the thing it is controlling for proves nothing about it. P2's whole claim
# is that THIS function can read THIS kind of artifact, so N4 has to be the
# caller it makes that claim on behalf of.
#
# BOTH `-g` AND `-D`, and that is measured rather than assumed. On aarch64-linux
# a stripped ELF shared object answers `nm -g` with "no symbols" while `nm -D`
# still lists every exported one; on a Mach-O host `-g` is the one that answers
# and an unsupported `-D` contributes nothing. Reading both means the pins see a
# defined symbol wherever either tool can see it, instead of the intersection of
# two platforms' defaults. Only PRESENCE pins are read from this — a union is the
# conservative direction for those, where for an absence pin it would not be.
dylib_defines() {
    { nm -g "$1" 2>/dev/null; nm -D "$1" 2>/dev/null; } |
        awk '$2 == "T" { print $3 }' | sort -u
}

# ══ CONTROL P2 — the second artifact kind is realizable, and readable ══════
# AFTER P AND BEFORE N4. P proved an EXECUTABLE compiles, links and answers
# here; N4 measures a SHARED LIBRARY, which `resolveCompileBackend` sends to
# `native-dylib` and which links through a different line. P cannot decide
# whether that kind is measurable, and N4 has no answer to fall back on, so
# without this control every host-shaped refusal below is printed as a finding
# about `main.directLinkLine`.
#
# ITS MODULE REACHES NOTHING AND NEEDS NOTHING, deliberately. Everything N4 is
# about is a link line carrying what the compiled module does not contain, so a
# probe carrying any of that could fail for exactly the reason N4 exists to
# find, and this control would swallow the finding instead of enabling it. It
# asks two things only: does this host emit a shared library at all, and can
# `dylib_defines` see a symbol inside one.
mkdir -p "$work/ctl.onlylib" 2>/dev/null &&
    printf 'exported: i64 = (x: i64)\n  x + 1\n' >"$work/ctl.onlylib/only.id" || {
    printf 'crosspartition: NOT MEASURED — cannot write the shared-kind positive control\n' >&2
    exit 3
}
if ! ( CDPATH='' cd -- "$work/ctl.onlylib" && "$IDOL" compile --backend=direct --emit dylib only.id -o only.dylib ) \
    >"$work/compile.log" 2>&1
then
    # DNB004 OR NOT, AND THE DIFFERENCE IS THE WHOLE VERDICT. Control P already
    # established that this host realizes an executable, so a refusal here is
    # either the shared KIND being unsupported where the executable kind is —
    # a host limit, NOT MEASURED — or the compiler failing for some other
    # reason, which is a defect and must not wear a host limit's excuse. The
    # refusal is read as the identity `gate/realization/direct.sh` reads,
    # DNB004 from `directDiagnostic(error.UnsupportedTarget)`, and not as prose;
    # measured on aarch64-linux it names the target `native-dylib`, which is why
    # the two kinds cannot share one probe.
    if grep -q 'DNB004' "$work/compile.log"; then
        # RAW TAIL, DELIBERATELY, and the only one left in this file. This branch
        # is a NOT MEASURED, so `gate/all.sh` reading the identity out of the log
        # and filing this run as host-bound is the CORRECT outcome. `log_tail` is
        # for convictions; routing this line through it would hide the very fact
        # that makes the classification right.
        printf 'crosspartition control P2: NOT MEASURED — this host emits no shared library, though control P got an executable: %s\n' \
            "$(tail -3 "$work/compile.log" | tr '\n' ' ')" >&2
        printf 'crosspartition:   the shared kind is its own realization (native-dylib, linked with -dynamiclib); nothing control N4 could say about main.directLinkLine would be earned here.\n' >&2
        exit 3
    fi
    printf 'crosspartition control P2: FAIL — the shared compile of a module that reaches nothing failed, and not by name: %s\n' \
        "$(log_tail "$work/compile.log")" >&2
    printf 'crosspartition:   control P realized an executable here, so this is a defect and not a host limit.\n' >&2
    exit 1
fi
if [ ! -s "$work/ctl.onlylib/only.dylib" ]; then
    # `-s` AND NOT `-f`. `gate/vacuity.sh` found this exact hole in
    # `gate/realization/direct.sh` by planting a compiler that is `exit 0` and
    # nothing else: an empty file satisfies `-f`, so a host with no realization
    # would be classified as having one. And this is a FAIL, not NOT MEASURED —
    # the compiler REPORTED SUCCESS, which is `broken` in that file's
    # vocabulary and never a host limit.
    printf 'crosspartition control P2: FAIL — the shared compile reported success and produced no library.\n' >&2
    exit 1
fi
if ! dylib_defines "$work/ctl.onlylib/only.dylib" | grep -q -- '_only__exported$'; then
    printf 'crosspartition control P2: NOT MEASURED — a shared library linked here and this file cannot read its own exported relation out of it.\n' >&2
    printf 'crosspartition:   control N4 has no answer to check and decides entirely from this reader, so it would report a symbol it cannot see as a link line that was never given one.\n' >&2
    exit 3
fi

# ══ CONTROL N4 — the other artifact kind that links ════════════════════════
# AFTER CONTROLS P AND P2, DELIBERATELY. Between them they establish that this
# host realizes both artifact kinds and that this file can read symbols out of
# the one measured here, which is what makes a refusal below attributable to the
# producer rather than to the host or to `nm`.
mkdir -p "$work/ctl.shared" 2>/dev/null &&
    printf 'value: i64 = (x: i64)\n  "21":to(i64) + x\n' >"$work/ctl.shared/helper.id" &&
    printf 'call: i64 = (x: i64)\n  helper.value(x)\n' >"$work/ctl.shared/lib.id" || {
    printf 'crosspartition: NOT MEASURED — cannot write the shared-kind control\n' >&2
    exit 3
}
if ! ( CDPATH='' cd -- "$work/ctl.shared" && "$IDOL" compile --backend=direct --emit dylib lib.id -o lib.dylib ) \
    >"$work/compile.log" 2>&1
then
    printf 'crosspartition control N4: FAIL — a shared library does not link over what it reaches, on a host where control P2 linked one that reaches nothing: %s\n' \
        "$(log_tail "$work/compile.log")" >&2
    printf 'crosspartition:   the shared link line is not coming from main.directLinkLine.\n' >&2
    exit 1
fi
if [ ! -s "$work/ctl.shared/lib.dylib" ]; then
    # `-s`, for the reason control P2 states: an empty file satisfies `-f`, so a
    # compiler that is `exit 0` and nothing else would reach the pins below and
    # be reported as a link line missing its symbols.
    printf 'crosspartition control N4: FAIL — the shared compile reported success and produced no library.\n' >&2
    exit 1
fi
dylib_defines "$work/ctl.shared/lib.dylib" >"$work/defined"
for pin in _helper__value duo_str_to_i64; do
    if ! grep -q -- "$pin\$" "$work/defined"; then
        printf 'crosspartition control N4: FAIL — the dylib linked and does not DEFINE %s.\n' "$pin" >&2
        printf 'crosspartition:   one of the two things that producer carries — reached objects, or the units their needs select — did not reach this link line.\n' >&2
        exit 1
    fi
done

# ══ THE ROSTER ═════════════════════════════════════════════════════════════
examined=0
failed=0
rows=0
named=''

while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|\#*) continue ;; esac
    rows=$((rows + 1))
    shape=$(printf '%s\n' "$line" | awk '{print $1}')
    expect=$(printf '%s\n' "$line" | awk '{print $2}')
    defines=$(printf '%s\n' "$line" | awk '{print $3}')
    if [ -z "$shape" ] || [ -z "$expect" ] || [ -z "$defines" ]; then
        printf 'crosspartition: FAIL — malformed roster row: %s\n' "$line" >&2
        failed=$((failed + 1))
        continue
    fi
    dir=$work/subject.$shape
    materialize "$shape" "$dir"
    case $? in
        0) ;;
        2)
            printf 'crosspartition: FAIL — roster names a shape this gate cannot materialize: %s\n' "$shape" >&2
            failed=$((failed + 1))
            continue
            ;;
        *)
            printf 'crosspartition: FAIL — cannot write subject %s\n' "$shape" >&2
            failed=$((failed + 1))
            continue
            ;;
    esac
    named="$named $shape"
    examined=$((examined + 1))
    if run_subject "$dir" "$expect" "$defines"; then
        printf 'crosspartition: %-6s PASS  answer=%s defines=%s\n' "$shape" "$expect" "$defines"
    else
        printf 'crosspartition: %-6s FAIL  %s\n' "$shape" "$(cat "$work/why")" >&2
        failed=$((failed + 1))
    fi
done <"$roster"

# ── the roster covers every shape, and only shapes that exist ──────────────
for shape in $SHAPES; do
    case " $named " in
        *" $shape "*) ;;
        *)
            printf 'crosspartition: FAIL — shape %s exists here and the roster does not name it; it would go unmeasured.\n' "$shape" >&2
            failed=$((failed + 1))
            ;;
    esac
done

# ── GAP-201: zero subjects is a failure, never a clean run ─────────────────
if [ "$examined" -eq 0 ]; then
    printf 'crosspartition: FAIL — 0 subjects examined (roster held %s row(s)); absence of a subject is not absence of a defect.\n' \
        "$rows" >&2
    exit 1
fi

printf 'crosspartition: %s subject(s) examined, %s failed — cross-partition realization on --backend=direct.\n' \
    "$examined" "$failed"
if [ "$failed" -ne 0 ]; then
    printf 'crosspartition: FAIL\n' >&2
    exit 1
fi
printf 'crosspartition: OK.\n'
exit 0
