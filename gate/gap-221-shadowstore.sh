#!/bin/sh
# gate/gap-221-shadowstore.sh — GAP-221 regression control.
#
# WHAT THIS GATE MAY CLAIM, AND WHAT IT MAY NOT.
#
# It pins the DELETION WITNESS, and it pins THE FOUR ANSWERS whenever the head
# can produce them. It shipped claiming more than it did: every arm was a text
# scan over `src/dnir_lower.zig`, no program ran, and `gaps/ROOT-PROGRAM.md`
# recorded it as the gate that "pins the answer". The repair it certified was
# landed with "Fixture execution requires backend support" written in its own
# commit message (`4a0b2eef`), so the one thing nobody had was the answer. A
# gate that reports PASS about a question it never asked is how that happens,
# and arm 2 exists so that this one cannot.
#
#   sh gate/gap-221-shadowstore.sh
#
# ARM 1  DELETION WITNESS. `moduleFieldWord` answers the descriptor and the
#        storage key together, so no by-spelling `storageKey` consult stands
#        after the binding decision, and the retired spelling-guard is gone.
#        This is a text scan and says so; it is migration pressure, not an
#        equivalence proof.
#
# ARM 2  THE ACCEPTANCE RUN, PROBED RATHER THAN ASSUMED. The four fixtures are
#        compiled and run and must print the values they carry. Two separate
#        things stop that on the head this was written against, and the arm
#        names WHICH rather than reporting one refusal:
#
#          * PARSE. At 2954038e the `.id` grammar refuses a descriptor, a typed
#            binding, a subject relation and two bare relations in one file, so
#            all four fixtures refuse at 3:1, 18:1, 21:1 and 15:1 (GAP-145).
#          * REALIZATION. On an aarch64 Linux host the direct backend answers
#            DNB004 for `native-exe` and the C realizer emits portable source
#            only, so no `.id` program executes here AT ALL — `print(7)` does
#            not. This is the "Fixture execution requires backend support"
#            `4a0b2eef` wrote down, and it is a host fact, not this gap's.
#
#        Neither is claimed as a pass. The moment both lift, this arm is the
#        pin this gap has asked for since it was filed, with no edit here.
#
#        ARM 2 IS FALSIFIABLE ON A HEAD THAT CANNOT RUN A SINGLE FIXTURE. Its
#        comparison is exercised by a positive control before the loop, because
#        an arm that can only report BLOCKED is an arm nobody has checked.
#
# THE GRAPH-LEVEL CONTROL IS NOT HERE, ON PURPOSE. The question
# `moduleFieldWord`'s guard actually asks — does this body's `base` denote the
# module's binding — is measured by the unit test
# `dnir_lower: GAP-221 a module field base is unresolvable from a relation body`,
# which `zig build unit-test` carries. Running a fifteen-minute test build from
# inside a roster gate would block every lane to re-measure what the standing
# test already measures.

set -eu

root=${GAP221_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'gap-221-shadowstore gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap221.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'gap-221-shadowstore gate: FAIL %s\n' "$1" >&2
    exit 1
}

zig build >/dev/null 2>&1 || fail "compiler build failed"
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol"

# ======================== ARM 1: DELETION WITNESS ==========================
# A text scan. It cannot prove the two stores agree; it can prove the retired
# shape is not spelled here any more, which is all it claims.

if grep -q "fn bodyDeclaresBinding" src/dnir_lower.zig; then
    fail "bodyDeclaresBinding still exists (deletion witness unmet)"
fi

if ! grep -q "bindingNamedIn" src/dnir_lower.zig; then
    fail "bindingNamedIn not found (binding-identity approach missing)"
fi

if ! grep -q "moduleFieldWord.*struct { RT, \[\]const u8 }" src/dnir_lower.zig; then
    fail "moduleFieldWord does not return struct with type and storage key"
fi

if grep -A5 "moduleFieldWord" src/dnir_lower.zig | grep -q "ctx.module_globals.storageKey"; then
    fail "ctx.module_globals.storageKey still used after moduleFieldWord (two-store shape persists)"
fi

printf 'gap-221-shadowstore gate: arm 1 deletion witness held (text scan)\n'

# ===================== ARM 2: THE ACCEPTANCE RUN ===========================
# `examples/shadowstore.id` and `examples/shadow.id` prove the shadow is
# respected; `examples/shadow_field_storage.id` and
# `examples/keyed_table_write_wins.id` prove storage is still granted where it
# is genuinely owned. All four, or the gap's acceptance is unmet.

# THE COMPARISON, AND ITS CONTROL. `answers` is the whole judgement arm 2
# makes, so it is exercised on a known-agreeing and a known-disagreeing pair
# before any fixture reaches it. Without this the arm is unfalsifiable on a head
# where every fixture is BLOCKED — which is this head.
answers() {
    [ "$1" = "$2" ]
}

if ! answers "7 99 7" "7 99 7"; then
    fail "comparison control: an agreeing pair was called a mismatch"
fi
if answers "7 99 7" "7 99 1"; then
    fail "comparison control: the shadow's 1 was accepted as the module's 7"
fi

blocked=0
answered=0

for fixture in \
    examples/shadowstore.id \
    examples/shadow.id \
    examples/shadow_field_storage.id \
    examples/keyed_table_write_wins.id
do
    [ -f "$fixture" ] || fail "acceptance fixture is missing: $fixture"
    name=$(basename "$fixture" .id)
    want=$(sed -n 's/^# expect: *//p' "$fixture" | head -1)
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"

    if ! "$idol" compile --backend=direct "$fixture" -o "$work/$name.out" \
        >"$work/$name.compile" 2>&1
    then
        # PARSE REFUSAL IS THE HEAD'S, NOT THIS FIXTURE'S. Distinguish it from a
        # compile failure that WOULD be this gap's, so a real regression here
        # can never hide behind the grammar being down.
        why=$(grep -m1 'error:' "$work/$name.compile" | head -1)
        case $why in
            *'at this token edge'*|*'expected expression'*)
                printf 'gap-221-shadowstore gate: BLOCKED %s refuses at parse — %s\n' \
                    "$fixture" "$why"
                blocked=$((blocked + 1))
                continue
                ;;
            *DNB004*)
                printf 'gap-221-shadowstore gate: BLOCKED %s has no realization on this host — %s\n' \
                    "$fixture" "$why"
                blocked=$((blocked + 1))
                continue
                ;;
            *)
                fail "$fixture did not compile — $why"
                ;;
        esac
    fi

    # The status is the PROGRAM's, so it is read before anything is piped: a
    # `$?` taken after `| tr` is the status of `tr`, which is always 0 and would
    # pass a fixture that crashed after printing.
    if "$work/$name.out" >"$work/$name.stdout" 2>"$work/$name.err"; then
        code=0
    else
        code=$?
    fi
    got=$(tr '\n' ' ' <"$work/$name.stdout" | sed 's/ *$//')
    [ "$code" = 0 ] || fail "$fixture exited $code (stdout '$got')"
    # The controlled comparison, not a second one written out longhand beside it.
    answers "$got" "$want" || fail "$fixture answered '$got', wants '$want'"
    answered=$((answered + 1))
done

if [ "$blocked" -gt 0 ]; then
    printf 'gap-221-shadowstore gate: arm 2 NOT MEASURED — %d of 4 fixtures could not be run on this head\n' \
        "$blocked"
    printf 'gap-221-shadowstore gate: the answer is UNPINNED here; %d of 4 answered\n' "$answered"
    printf 'gap-221-shadowstore gate: PASS (arm 1 only — arm 2 blocked, not passed)\n'
    exit 0
fi

printf 'gap-221-shadowstore gate: arm 2 all 4 acceptance answers held\n'
printf 'gap-221-shadowstore gate: PASS\n'
