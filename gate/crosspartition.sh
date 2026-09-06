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
# ═══ AND WHAT SHAPES EXIST HAS ONE PRODUCER: `materialize`'s OWN ARMS ══════
#
# The reverse direction needs an ENUMERATION of the shapes this file serves, and
# that enumeration was a second copy — `SHAPES='duo trio fan text'`, a constant
# beside the `case` that actually decides. This gate's own N4 section states the
# rule that breaks: "A fact with two producers is a fact that can be repaired in
# one of them, and that is what had happened." It had happened here, in the
# ratchet whose entire job is catching exactly this between two OTHER files.
#
# MEASURED, on aarch64-linux, by planting into a copy and reading the exit
# status against an undamaged copy's 3:
#
#   * a new `materialize` arm, absent from that constant and from the roster —
#     the shape is served, no row names it, and the reverse check does not look
#     for it because it consults the copy. Exit 3, indistinguishable from
#     undamaged. On macOS it is exit 0: four rows measured, green, and a shape
#     this file can build measured by nothing.
#   * a roster row naming `solo`, the POSITIVE CONTROL's shape. Which arms are
#     subjects and which are controls was written down nowhere, so the row was
#     accepted, and on macOS it answers 7, satisfies its pin, and is counted in
#     "N subject(s) examined" — a row that measures no reach at all, inflating
#     the one number this gate reports.
#
# Both are silent on EVERY host, which is what makes them this gate's own class
# rather than a host limit. The repair is that `materialize`'s arms ARE the
# enumeration: each carries `#shape:subject` or `#shape:control`, and the roll is
# read out of this file. An arm cannot be served without appearing in the roll,
# because the arm is the roll. Three things are then convicted with no compiler:
# an arm carrying no role (the marker itself going stale), a subject arm no row
# names, and a row naming a control arm.
#
# MEASURED, on aarch64-linux at 909f205d, by planting each into a copy and
# reading the exit status against an undamaged copy's 3: a bare arm, a row
# naming `solo`, and a new subject arm with no roster row each convict with
# exit 1, and so do both empty rolls — no arms read out of this file at all,
# and no arm left marked #shape:subject. No conviction names DNB004 or NOT
# MEASURED, so `gate/all.sh` files each as law and not as a host limit.
#
# THE ROLL'S OWN ALPHABET WAS THE SAME HIDING ONE LAYER DOWN. The readers match
# `^[a-z][a-z]*`, so an arm named outside it (`quad2`, `Duo`) is served by
# `materialize` and read by neither roll: with no roster row it exits 3 here
# and is green and unmeasured on macOS — measured, same plant-into-a-copy
# recipe, against a lowercase `quad` that convicts. Any served label outside
# one lowercase word is now itself a failure, so the arms are the enumeration
# with no silent qualifier left; only the `*)` catch-all is not a shape.
#
# AND A ROLL THAT COMES BACK EMPTY IS A FAILURE, never a clean run. A reverse
# check over zero shapes passes vacuously, which is GAP-201's rule one layer up
# from the roster: this file reading no arms out of itself would report agreement
# it never looked for.
#
# ═══ AND SO DOES THE PIN COLUMN'S DIRECTION: THE ARM WROTE THE SOURCE ══════
#
# The roster's first column had two producers and now has one. Its THIRD column
# still had two, and it is the column GAP-232's acceptance 2 rests on entirely:
# `text` requires `duo_str_to_i64` to be DEFINED because its reached partition
# converts text, and `duo`, `trio` and `fan` require the same symbol to be ABSENT
# because theirs do arithmetic. WHICH of those a shape is, is not the roster's
# fact — the `materialize` arm decides it, by writing a text literal into the
# reached partition or not writing one. The roster carried a second copy of that
# decision, in the one place where a wrong copy costs the most.
#
# MEASURED, on aarch64-linux, by planting into a copy of these two files and
# reading the exit status against an undamaged copy's 3:
#
#   * `duo` loses its `!duo_str_to_i64` entirely                      was exit 3
#   * all three absence pins are redirected to `!duo_str_sub`, a real
#     string-runtime symbol that no shape here ever reaches             was exit 3
#   * `text` loses the `duo_str_to_i64` presence pin                  was exit 3
#
# NONE OF THE THREE IS CAUGHT BY THE HOST-BOUND HALF EITHER, and that follows
# from `run_subject` rather than from any host: a pin can only refuse a subject it
# is ASKED to check, so deleting a pin or pointing it at a symbol no link line was
# going to carry cannot turn a passing measurement into a failing one anywhere.
# The second one is the sharpest, because `!duo_str_sub` reads as correct: it
# names a symbol that really is in `idol_str_runtime.o` and really is quoted in
# `gaps/GAP-232.md`'s own filing section, and it guards against a link line no arm
# here can produce. The selectivity argument the roster header calls load-bearing
# would be decoration, and every row would stay green.
#
# THE DERIVATION IS NARROW AND SAYS SO. A text literal in a partition other than
# the entry is the only route to the string runtime any arm here takes, so that
# literal is what the direction is read from. An arm that reached that runtime
# some other way would derive ABSENCE, be held to it, and fail at the pin — which
# is loud and repairable, and not the silent drift this removes.
#
# BOTH DIRECTIONS MUST BE REQUIRED OF SOMETHING, which is GAP-201's rule again at
# the level of the argument rather than the roster. If no subject's reached
# partition converts text, the presence direction is asked of no row and
# acceptance 2 has no positive side; if every subject's does, no row requires
# absence and the presence pin is satisfied by a compiler that puts all three
# bootstrap units on every link line without ever reading a `need`.
#
# ═══ AND WHICH RELATION A ROW PINS: THE ARM DECLARED IT ════════════════════
#
# The direction above is about ONE symbol, `duo_str_to_i64`. The column's other
# presence pins name RELATIONS, and that is the pin the section on what is
# measured calls the second one — the reached relation must be DEFINED in the
# image, so a correct answer cannot have come from anywhere but the partition
# under test. WHICH relation is not the roster's fact either: the arm declared it.
# That copy was the last one in this column, and it sat on the pin that makes
# every row's answer attributable.
#
# MEASURED, on aarch64-linux, by planting into a copy of these two files and
# reading the exit status against an undamaged copy's 3:
#
#   * `duo`'s `_helper__twice` redirected to `_main__main`             was exit 3
#   * `duo`'s reach pin deleted, leaving only `!duo_str_to_i64`        was exit 3
#   * `duo`'s two pins separated by a space rather than a comma, which
#     puts the reach pin in a fourth field this file never reads       was exit 3
#   * `text`'s `_helper__value` redirected to `_helper__twice`, a
#     relation that shape's partition does not declare                 was exit 3
#
# THE FIRST THREE ARE GREEN ON MACOS, NOT MERELY UNOBSERVED HERE. `_main__main` is
# defined by the subject's own entry, so it satisfies a presence pin in an image
# that proves nothing about the reach — the same shape of damage as pointing an
# absence pin at `!duo_str_sub`, one column-half over. A row left with absence pins
# alone has no reach pin to satisfy at all, and its exit status is a number a
# compiler that folded the call could answer; the third arrives at exactly that
# state through a whitespace typo rather than a deletion, which is the likelier
# route to it. The fourth is loud on macOS and silent here, so it is the one this
# adds a host to rather than a verdict.
#
# DECLARATION AND NOT CALL, and the narrowness is deliberate: any relation
# declared by a partition the arm wrote beyond the entry is admitted, and what is
# refused is a pin no reached partition could define. `duo_str_to_i64` is exempt
# because it is a bootstrap symbol rather than a relation, and it is the one such
# symbol this file names; a shape needing another would name it in the same place,
# which is this requirement one symbol further on rather than an exception to it.
#
# ═══ AND THE PREMISE UNDER BOTH: THE ENTRY NEEDS NOTHING ═══════════════════
#
# The two derivations above read the partitions an arm wrote BEYOND the entry,
# and they skipped the entry itself — `case ${src##*/} in main.id) continue`.
# Both are claims about a need that came from the REACH, and an entry's own needs
# go on the same link line, so both rest on a premise about the entry that was
# written only as prose inside the arms: "its entry only does arithmetic and needs
# no runtime of its own."
#
# NOTHING ASSERTED IT, and it fails silently in both directions:
#
#   * `text`'s entry converting text satisfies its PRESENCE pin out of the
#     entry's own need. The reached partition's need could stop reaching the link
#     line entirely and the row would not notice — which is the whole of GAP-232
#     acceptance 2. It is `_main__main` satisfying a reach pin, one column-half
#     over: the entry answering for what only the reach should.
#   * an arithmetic entry converting text derives ABSENCE and is WRONG to. A
#     correct compiler must carry the unit for that entry, so the row convicts
#     the producer it exists to measure.
#
# MEASURED, on aarch64-linux, by planting into a copy of this file and reading
# the exit status against an undamaged copy's 3:
#
#   * `text`'s entry given `"0":to(i64) +`                            was exit 3
#   * `duo`'s entry given `"0":to(i64) +`                             was exit 3
#
# THE FIRST IS NOT MERELY UNOBSERVED HERE, and that is an ARGUMENT FROM THE
# SOURCES rather than a macOS run — no such run is claimed. `"0":to(i64) +` adds
# zero, so `text`'s answer is still 43; `duo_str_to_i64` is still DEFINED, so its
# presence pin still holds; and the other three rows are untouched, so their
# absence pins still hold. Every check this file makes would pass, and the one row
# acceptance 2 rests on would have stopped resting on the reach. The entry is now
# READ rather than skipped, and no subject's entry may convert text.
#
# AND THAT RATCHET NEEDS NO COMPILER, SO IT RUNS BEFORE THE HOST IS CLASSIFIED.
# Every measurement below the classification needs macOS/aarch64 — the direct
# backend refuses every other host by name — and the ratchet used to sit below it
# too, reached only after the host had already been found capable. Measured on
# aarch64-linux: this file exited 3 NOT MEASURED without ever opening the roster,
# so a row naming a shape that no longer exists, a shape no row names, a
# malformed row, and a roster emptied to zero rows were all invisible on every
# host but one. Whether the roster agrees with this gate is a fact about THESE
# TWO FILES, not about a host, and it is now convicted wherever they are checked
# out. What remains host-bound is the half that genuinely is: compiled, run,
# answered, pins read.
#
# WHICH MEANT NOTHING IN AN UNBUILT TREE, because one line above the ratchet
# still required the compiler to EXIST. Measured on aarch64-linux with
# `zig-out/bin/idol` removed: a roster row naming a shape this file cannot
# materialize exited 3 saying the compiler is not executable, having never opened
# the roster — the same defect moved up by a few lines rather than removed. The
# `unbuilt` classification below is the one producer of "there is no compiler to
# ask", and it already answers exactly that, so the requirement now sits with it
# and nothing above the ratchet asks for a binary the ratchet never uses.
#
# SPLITTING IT DOES NOT WEAKEN THE ORDERING THE CONTROLS BELOW DEPEND ON. The
# ratchet WRITES subject sources and reports no subject's ANSWER; the roster it
# validated is handed to the measurement pass as `$work/measure`, so the rows are
# parsed by one producer and a row that survives validation and then goes
# unmeasured is itself a failure.
#
# ═══ THE CONTROLS ══════════════════════════════════════════════════════════
#
# A gate that refuses everything passes every ratchet it owns and measures
# nothing, and a gate that reads only exit status agrees with a compiler that
# links the world and computes garbage. The controls run BEFORE any subject is
# reported, each proving a different way to be wrong:
#
#   R  THE ROSTER RATCHET, and it is not in this list because it is not a
#      control: it asks nothing of the compiler, so it runs above the host
#      classification and convicts on hosts where nothing else here can. See
#      the roster section above.
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
# THIS FILE IS ITS OWN SHAPE ENUMERATION, so it has to be able to name itself.
# `materialize`'s case arms are the one producer of "what shapes exist and which
# of them are subjects"; a constant beside them was a second copy of that fact.
self=$here/$(basename -- "$0")
cd "$root" || { printf 'crosspartition: cannot enter root\n' >&2; exit 3; }

# `zig-out/bin/idol` AND NOT `out/bin/idol`. The latter is a stale artifact
# that has served as a false oracle in this tree before; it is not this build.
IDOL=${IDOL:-"$root/zig-out/bin/idol"}
roster=$here/crosspartition.subjects

# THE STRING RUNTIME'S ENTRY POINT, named once. `materialize`'s `text` arm reaches
# it (`"21":to(i64)`), the roster pins it in both directions, and control N4 pins
# it on the shared kind. It was written out at every one of those uses; the
# ratchet below reads the ROSTER's uses against the arms, so this file's own uses
# have to come from one place or the ratchet is checking a copy of itself.
str_unit_symbol=duo_str_to_i64

# NO `-x $IDOL` HERE. The ratchet below asks no compiler, and requiring one above
# it made every conviction it owns invisible in an unbuilt tree — measured. The
# `unbuilt` arm of the classification further down is the one producer of that
# fact and is where the requirement now lives.
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
#
# EVERY ARM CARRIES ITS ROLE, and the arms are the enumeration. `#shape:subject`
# is a roster row's shape; `#shape:control` is a shape only a control below
# materializes by name. `shape_roll` reads them back out of this file, so there is
# no second list to drift, and `shape_arms` reads them all — an arm added without
# a role is convicted rather than served silently.
materialize() {
    shape=$1
    dir=$2
    factor=${3:-2}
    mkdir -p "$dir" || return 1
    case $shape in
        duo) #shape:subject
            # One entry, one reached partition. 21 * 2 = 42.
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        trio) #shape:subject
            # TRANSITIVE. The entry never names `deeper`; only the partition it
            # reaches does. (21 + 1) * 2 = 44. A closure that stops at depth one
            # links `helper` and still fails at the linker on `deeper`.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  deeper.plus(x) * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        fan) #shape:subject
            # TWO partitions reached from one entry, so the link line has to
            # carry more than one extra object. 10 * 2 + (4 + 1) = 25.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(10) + deeper.plus(4)\n' >"$dir/main.id" || return 1
            ;;
        text) #shape:subject
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
        solo) #shape:control
            # No reach at all — the positive control's shape. IT IS NOT A ROSTER
            # SUBJECT: a row naming it would measure no cross-partition reach and
            # still be counted among "N subject(s) examined".
            printf 'main: i64 = ()\n  7\n' >"$dir/main.id" || return 1
            ;;
        *)
            return 2
            ;;
    esac
    return 0
}

# ── the shapes this file serves, read out of the arms that serve them ──────
# `shape_arms` is every case label in `materialize`; `shape_roll` is the subset
# carrying one role. Bounded to that function's own body, so the `case` statements
# elsewhere in this file are not mistaken for shapes.
shape_arms() {
    awk '
        /^materialize\(\) \{$/ { inside = 1; next }
        inside && /^\}$/       { inside = 0 }
        inside && $0 ~ /^ *[a-z][a-z]*\)/ { sub(/\).*/, ""); sub(/^ */, ""); print }
    ' "$self"
}
shape_roll() {
    awk -v want="$1" '
        /^materialize\(\) \{$/ { inside = 1; next }
        inside && /^\}$/       { inside = 0 }
        inside && $0 ~ ("^ *[a-z][a-z]*\\) *#shape:" want "$") { sub(/\).*/, ""); sub(/^ */, ""); print }
    ' "$self"
}
# Labels `shape_arms` cannot read are not "not shapes" — `materialize` serves
# them, so with no roster row they are green and unmeasured on macOS. The `*)`
# catch-all is the one label that is not a shape; anything else outside one
# lowercase word is refused rather than unread.
shape_stray() {
    awk '
        /^materialize\(\) \{$/ { inside = 1; next }
        inside && /^\}$/       { inside = 0 }
        inside && $0 ~ /^ *[^ ]+\)/ {
            label = $0; sub(/\).*/, "", label); sub(/^ */, "", label)
            if (label == "*") next
            if (label !~ /^[a-z][a-z]*$/) print label
        }
    ' "$self"
}

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
    #
    # STDIN IS CLOSED FOR THE SUBJECT, because the loop that calls this reads the
    # validated roster on stdin: a subject that read a byte would eat a row, and
    # the row would vanish between being named and being answered rather than
    # failing. No subject here reads stdin; the point is that it cannot.
    "$dir/prog" >/dev/null 2>&1 </dev/null
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

# ══ THE ROSTER RATCHET — NO COMPILER IS ASKED, SO NO HOST IS EXCUSED ═══════
# Whether `gate/crosspartition.subjects` agrees with this file is a fact about
# these two files. It was measured below the host classification, which on every
# host but macOS/aarch64 means never: this gate exited 3 having never opened the
# roster, so a row naming a shape that no longer exists, a shape no row names, a
# malformed row, and a roster emptied to zero rows (GAP-201, the rule the roster
# is a separate file FOR) were all unobservable outside one host.
#
# IT MATERIALIZES, AND REPORTS NO ANSWER. Writing a subject's sources needs
# nothing but a filesystem, and doing it here is what proves the shape EXISTS;
# every controls-before-subjects ordering below is untouched, because no subject
# is compiled, run or reported until they have all passed.
#
# ONE PARSE. The validated rows are written to `$work/measure` and the
# measurement pass reads THAT, so the roster's fields have one producer, and a
# row that passes here and is then not measured is a finding of its own.
#
# AND ONE PRODUCER OF THE SHAPES TOO. What this file can materialize, and which
# of those are subjects rather than controls, is read out of `materialize`'s own
# arms rather than from a constant beside them; see the section on that above for
# the two damages the constant hid on every host.
ratchet=0
rows=0
subjects=0
present=0
absent=0
named=''
: >"$work/measure" || exit 3

# ── the shape roll, before any row is read against it ──────────────────────
# Every arm of `materialize`, and the two roles split out of them. An arm with no
# role is a shape this file serves that neither roll knows about, which is the
# drift the roll exists to remove; an empty roll would make the coverage check
# below pass over nothing.
#
# SPACE-SEPARATED, DELIBERATELY. The membership tests below are `case " $roll "`
# against `*" $name "*`, and a roll still carrying its newlines matches only the
# name that happens to sit beside a space — measured, it convicted four correctly
# marked arms as unmarked, which is a checker that cannot be trusted either way.
arms=$(shape_arms | tr '\n' ' ')
subjectroll=$(shape_roll subject | tr '\n' ' ')
controlroll=$(shape_roll control | tr '\n' ' ')
# No silent qualifier on the enumeration: every label `materialize` serves is
# either a lawful shape in one roll or a failure here. A roster row naming a
# stray label cannot launder it — the label itself is refused first.
stray=$(shape_stray | tr '\n' ' ')
if [ -n "$stray" ]; then
    printf 'crosspartition: FAIL — materialize serves case label(s) no shape roll reads:%s; a served shape outside one lowercase word would go unmeasured.\n' \
        "$stray" >&2
    exit 1
fi
if [ -z "$arms" ]; then
    printf 'crosspartition: FAIL — read no shape arms out of %s; the roster coverage check would have passed over nothing.\n' \
        "$self" >&2
    exit 1
fi
if [ -z "$subjectroll" ]; then
    printf 'crosspartition: FAIL — no arm is marked #shape:subject, so no roster row could be required and 0 shapes would be covered.\n' >&2
    exit 1
fi
for arm in $arms; do
    case " $subjectroll $controlroll " in
        *" $arm "*) ;;
        *)
            printf 'crosspartition: FAIL — materialize serves shape %s and marks it neither #shape:subject nor #shape:control; the roll cannot require a row for it or refuse one.\n' \
                "$arm" >&2
            ratchet=$((ratchet + 1))
            ;;
    esac
done

while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|\#*) continue ;; esac
    rows=$((rows + 1))
    shape=$(printf '%s\n' "$line" | awk '{print $1}')
    expect=$(printf '%s\n' "$line" | awk '{print $2}')
    defines=$(printf '%s\n' "$line" | awk '{print $3}')
    if [ -z "$shape" ] || [ -z "$expect" ] || [ -z "$defines" ]; then
        printf 'crosspartition: FAIL — malformed roster row: %s\n' "$line" >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    # A CONTROL'S SHAPE IS NOT A SUBJECT. `solo` reaches nothing and is
    # materialized by control P by name; a row naming it would compile, run,
    # answer, satisfy a pin, and be counted among the subjects examined while
    # measuring no cross-partition reach at all.
    case " $controlroll " in
        *" $shape "*)
            printf 'crosspartition: FAIL — roster row names %s, which materialize marks #shape:control; it reaches nothing and would be counted as a subject.\n' \
                "$shape" >&2
            ratchet=$((ratchet + 1))
            continue
            ;;
    esac
    materialize "$shape" "$work/subject.$shape"
    case $? in
        0) ;;
        2)
            printf 'crosspartition: FAIL — roster names a shape this gate cannot materialize: %s\n' "$shape" >&2
            ratchet=$((ratchet + 1))
            continue
            ;;
        *)
            printf 'crosspartition: FAIL — cannot write subject %s\n' "$shape" >&2
            ratchet=$((ratchet + 1))
            continue
            ;;
    esac
    # ── the pin DIRECTION comes from the source the arm just wrote ──────────
    # `text` pins the string runtime PRESENT and the arithmetic shapes pin it
    # ABSENT, and which of those a shape is was copied into the roster from the
    # arm that decides it. The arm has just run, so its decision is on disk: a
    # text literal in a partition OTHER than the entry is the only route any arm
    # here takes to that runtime. Read it off the sources instead of trusting the
    # copy, and both directions become requirements rather than prose.
    #
    # THE SAME SOURCES DECIDE WHICH RELATION THE ROW MAY PIN, which is the other
    # half of this column and is collected here rather than in a second walk: the
    # relations a partition DECLARES are what a link line can define for it, and
    # the arm that wrote the declaration is the only producer of that fact. See
    # the check below the direction block.
    #
    # AND THE ENTRY IS READ RATHER THAN SKIPPED, because the whole column rests
    # on the entry needing NOTHING. See the check below the reach check.
    reachedsrc=0
    converts=0
    entryconverts=0
    reachedrelation=''
    for src in "$work/subject.$shape"/*.id; do
        [ -f "$src" ] || continue
        case ${src##*/} in
            main.id)
                if grep -q '"' "$src"; then entryconverts=1; fi
                continue
                ;;
        esac
        reachedsrc=$((reachedsrc + 1))
        if grep -q '"' "$src"; then converts=1; fi
        # `_<stem>__<relation>`, the path-independent tail `run_subject` matches.
        # THE SAME ALPHABET `shape_arms` READS, one lowercase word, because that
        # is what LAW-ONE admits as a relation name and what every arm writes.
        stem=${src##*/}
        stem=${stem%.id}
        for relation in $(sed -n 's/^\([a-z][a-z]*\):.*/\1/p' "$src"); do
            reachedrelation="$reachedrelation _${stem}__${relation}"
        done
    done
    if [ "$reachedsrc" -eq 0 ]; then
        printf 'crosspartition: FAIL — subject %s materializes no partition beyond its entry, so it measures no reach and no pin direction can be derived for it.\n' \
            "$shape" >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    # ── and the ENTRY must need the string runtime of its own accord NOT AT ALL ─
    # Every direction the block below derives is a claim about a need that came
    # from the REACH. The entry's own needs go on the link line too, and no arm's
    # entry converts text today — which is a fact written in the arms as prose
    # ("the entry only adds") and asserted nowhere. Both directions collapse if it
    # stops being true, and they collapse silently:
    #
    #   * a PRESENCE row whose entry converts text has its pin satisfied by that
    #     entry's own need. `text` would answer, define `duo_str_to_i64`, and be
    #     green on macOS while asserting nothing about a reached partition's need
    #     reaching the link line — which is the entirety of GAP-232 acceptance 2.
    #     It is the same damage as a reach pin naming `_main__main`, one
    #     column-half over: the ENTRY satisfying what only the reach should.
    #   * an ABSENCE row whose entry converts text derives a direction that is
    #     WRONG. A correct compiler must put the symbol on that link line, so the
    #     row would convict the thing it exists to measure.
    #
    # MEASURED, on aarch64-linux, by planting into a copy and reading the exit
    # status against an undamaged copy's 3: `text`'s entry given `"0":to(i64) +`
    # was exit 3, and so was `duo`'s. That the first would also pass on macOS is
    # derived from the sources — zero added leaves the answer at 43 and every pin
    # still holds — and not from a run; see the header section.
    if [ "$entryconverts" -eq 1 ]; then
        printf 'crosspartition: FAIL — subject %s has an ENTRY that converts a text literal, so the entry needs %s on its own.\n' \
            "$shape" "$str_unit_symbol" >&2
        printf 'crosspartition:   every pin direction here is derived from what the REACH needs; an entry that needs the same unit satisfies a presence pin without any reached need, and makes an absence pin refuse a correct link line.\n' >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    sawpresent=0
    sawabsent=0
    for pin in $(printf '%s\n' "$defines" | tr ',' ' '); do
        case $pin in
            "!$str_unit_symbol") sawabsent=1 ;;
            "$str_unit_symbol") sawpresent=1 ;;
        esac
    done
    if [ "$converts" -eq 1 ]; then
        why='its reached partition converts a text literal, so the object of that partition references it'
        want=$sawpresent
        other=$sawabsent
        wantpin=$str_unit_symbol
        otherpin="!$str_unit_symbol"
        present=$((present + 1))
    else
        why='no partition it reaches converts text, so nothing it links needs the string runtime'
        want=$sawabsent
        other=$sawpresent
        wantpin="!$str_unit_symbol"
        otherpin=$str_unit_symbol
        absent=$((absent + 1))
    fi
    if [ "$other" -eq 1 ] && [ "$want" -eq 1 ]; then
        printf 'crosspartition: FAIL — roster row %s pins %s in BOTH directions; one of the two is unsatisfiable, so the row cannot state what its link line must have carried.\n' \
            "$shape" "$str_unit_symbol" >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    if [ "$other" -eq 1 ]; then
        printf 'crosspartition: FAIL — roster row %s pins %s, and %s; the pin must be %s.\n' \
            "$shape" "$otherpin" "$why" "$wantpin" >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    if [ "$want" -ne 1 ]; then
        printf 'crosspartition: FAIL — roster row %s does not pin %s, and %s.\n' \
            "$shape" "$wantpin" "$why" >&2
        printf 'crosspartition:   a pin only refuses what it is asked to check, so this row asserts nothing about the union GAP-232 is about — on any host.\n' >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    # ── and WHICH relation a row pins comes from the same sources ────────────
    # The direction block above owns ONE symbol, `$str_unit_symbol`. Every other
    # presence pin in the column names a RELATION, and that is the pin this gate's
    # header calls its second one: the reached relation must be DEFINED in the
    # image, so that a correct answer cannot have come from anywhere but the
    # partition under test. Which relation that is, is decided by the arm that
    # declared it, and the roster carried a second copy of that decision.
    #
    # A pin can only refuse what it is asked to check, so a row that asks about a
    # relation NO reached partition declares asks nothing: a symbol the ENTRY
    # defines passes on every host and guards nothing, and a row carrying only
    # absence pins has no reach pin left to satisfy. Both are green everywhere.
    #
    # THE DERIVATION IS DECLARATION AND NOT CALL, deliberately narrow: a relation
    # declared by any partition the arm wrote beyond the entry is admitted, and
    # what is refused is a pin no reached partition could define. `$str_unit_symbol`
    # is exempt because it is a bootstrap symbol and not a relation, and it is the
    # only one this file names — a shape needing another would name it here beside
    # that one, which is the same requirement one symbol further on.
    sawreach=0
    strayed=''
    for pin in $(printf '%s\n' "$defines" | tr ',' ' '); do
        case $pin in
            !*) continue ;;
            "$str_unit_symbol") continue ;;
        esac
        case " $reachedrelation " in
            *" $pin "*) sawreach=$((sawreach + 1)) ;;
            *) strayed="$strayed $pin" ;;
        esac
    done
    if [ -n "$strayed" ]; then
        printf 'crosspartition: FAIL — roster row %s pins%s, which no partition it reaches declares; the partitions its arm wrote declare%s.\n' \
            "$shape" "$strayed" "$reachedrelation" >&2
        printf 'crosspartition:   a symbol its own ENTRY defines satisfies that pin on every host while guarding nothing, so the answer would no longer be attributable to the reach.\n' >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    if [ "$sawreach" -eq 0 ]; then
        printf 'crosspartition: FAIL — roster row %s pins no relation of any partition it reaches; the partitions its arm wrote declare%s.\n' \
            "$shape" "$reachedrelation" >&2
        printf 'crosspartition:   without that pin the row checks an exit status alone, which a compiler that never realized the reach can produce by folding.\n' >&2
        ratchet=$((ratchet + 1))
        continue
    fi
    named="$named $shape"
    subjects=$((subjects + 1))
    printf '%s %s %s\n' "$shape" "$expect" "$defines" >>"$work/measure"
done <"$roster"

# ── both pin directions are required of SOMETHING ──────────────────────────
# GAP-201's rule at the level of the argument rather than the roster. The
# presence pin and the absence pins are one claim in two halves: that the link
# line carried the unit the reached partition needed, and that it did not carry
# it for everyone. A roster where either half is asked of no row states the other
# half about a compiler that could never have read a `need`.
if [ "$present" -eq 0 ]; then
    printf 'crosspartition: FAIL — no subject requires %s to be DEFINED; nothing here would notice the need of a reached partition never reaching the link line.\n' \
        "$str_unit_symbol" >&2
    ratchet=$((ratchet + 1))
fi
if [ "$absent" -eq 0 ]; then
    printf 'crosspartition: FAIL — no subject requires %s to be ABSENT; the presence pin would be satisfied by a compiler that puts every bootstrap unit on every link line.\n' \
        "$str_unit_symbol" >&2
    ratchet=$((ratchet + 1))
fi

# ── the roster covers every subject arm, and only shapes that exist ────────
for shape in $subjectroll; do
    case " $named " in
        *" $shape "*) ;;
        *)
            printf 'crosspartition: FAIL — shape %s exists here and the roster does not name it; it would go unmeasured.\n' "$shape" >&2
            ratchet=$((ratchet + 1))
            ;;
    esac
done

# ── GAP-201: zero subjects is a failure, never a clean run ─────────────────
if [ "$subjects" -eq 0 ]; then
    printf 'crosspartition: FAIL — 0 subjects examined (roster held %s row(s)); absence of a subject is not absence of a defect.\n' \
        "$rows" >&2
    ratchet=$((ratchet + 1))
fi

if [ "$ratchet" -ne 0 ]; then
    printf 'crosspartition: FAIL — the roster and this gate disagree (%s finding(s)); no host had to compile anything for that to be wrong.\n' \
        "$ratchet" >&2
    exit 1
fi

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
for pin in _helper__value "$str_unit_symbol"; do
    if ! grep -q -- "$pin\$" "$work/defined"; then
        printf 'crosspartition control N4: FAIL — the dylib linked and does not DEFINE %s.\n' "$pin" >&2
        printf 'crosspartition:   one of the two things that producer carries — reached objects, or the units their needs select — did not reach this link line.\n' >&2
        exit 1
    fi
done

# ══ THE ROSTER, MEASURED ═══════════════════════════════════════════════════
# Every row here was validated and materialized by the ratchet above, which
# needed no host. What is left is the half that does: compile with
# `--backend=direct`, run, check the answer, read the pins.
examined=0
failed=0

while read -r shape expect defines; do
    examined=$((examined + 1))
    if run_subject "$work/subject.$shape" "$expect" "$defines"; then
        printf 'crosspartition: %-6s PASS  answer=%s defines=%s\n' "$shape" "$expect" "$defines"
    else
        printf 'crosspartition: %-6s FAIL  %s\n' "$shape" "$(cat "$work/why")" >&2
        failed=$((failed + 1))
    fi
done <"$work/measure"

# ── a validated row that goes unmeasured is a dropped subject ──────────────
# The ratchet counted the subjects it accepted; this pass counts the ones it
# actually measured. It is what holds the two passes to one number, so a future
# edit that skips a row here — a `continue` before `run_subject`, an early
# `break` — fails instead of quietly reporting a smaller roster as a clean run.
if [ "$examined" -ne "$subjects" ]; then
    printf 'crosspartition: FAIL — the ratchet accepted %s subject(s) and %s were measured.\n' \
        "$subjects" "$examined" >&2
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
