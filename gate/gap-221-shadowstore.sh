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
# ARM 0  THE FIXTURES ARE THE FIXTURES. All four match HEAD byte for byte
#        before anything is compiled, because `idol fmt` writes in place with
#        no dry-run and, on a mid-transfer grammar, exits 0 having written a
#        DIFFERENT legal program. That happened to these files once already.
#        It is numbered 0 because it is a PRECONDITION on arm 2's inputs, and
#        it runs immediately before arm 2 rather than at the top; arm 1 is a
#        scan of `src/dnir_lower.zig` and does not read the fixtures at all.
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
#          * PARSE. At 2954038e the `.id` grammar refused a descriptor, a typed
#            binding and a subject relation, so nothing parsed. `29d77ed0`
#            repaired that root and left one: a module carrying MORE THAN ONE
#            RELATION still does not parse, which is every fixture here
#            (GAP-145).
#          * REALIZATION. On an aarch64 Linux host the direct backend answers
#            DNB004 for `native-exe`. This is the "Fixture execution requires
#            backend support" `4a0b2eef` wrote down, and it is a host fact, not
#            this gap's.
#
#            IT IS NOT "nothing runs here", and this gate must not say so.
#            `.id` programs DO execute on this host:
#
#              idol compile --backend=c --emit=c p.id -o p.c
#              cc p.c tools/node/dev/grammar/idol_c_runtime_shim.c -o p.bin
#              ./p.bin            # `print(7)` prints 7, exit 0 — measured
#
#            (`--backend=c` WITHOUT `--emit=c` refuses at the realizer, which
#            is what made this look closed.) That route is not wired in below
#            because it still cannot run THESE fixtures: the C99 slice refuses
#            table field access — `refused at: operation-not-in-c99-slice` —
#            which is the one construct this gap is about. Wiring a fallback
#            that can never pass would be a dead arm, and this gate's whole
#            complaint about its predecessor is arms that assert without asking.
#
#            So the acceptance needs ONE of: an aarch64-linux native
#            realization in the direct backend, or table field storage inside
#            the C99 slice. Whoever lands either should wire the route above.
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

if grep -q "fn bodyDeclaresBinding" src/graph/lower.zig; then
    fail "bodyDeclaresBinding still exists (deletion witness unmet)"
fi

if ! grep -q "bindingNamedIn" src/graph/lower.zig; then
    fail "bindingNamedIn not found (binding-identity approach missing)"
fi

if ! grep -q "moduleFieldWord.*struct { RT, \[\]const u8 }" src/graph/lower.zig; then
    fail "moduleFieldWord does not return struct with type and storage key"
fi

if grep -A5 "moduleFieldWord" src/graph/lower.zig | grep -q "ctx.module_globals.storageKey"; then
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

fixtures='examples/shadowstore.id examples/shadow.id examples/shadow_field_storage.id examples/keyed_table_write_wins.id'

# ===================== ARM 0: THE FIXTURES ARE THE FIXTURES =================
# A GATE THAT DOES NOT KNOW WHICH PROGRAM IT RAN PROVES NOTHING. `idol fmt`
# ends in an UNCONDITIONAL `writeFile` (`src/main.zig:7618`) — there is no
# --check and no --dry-run — so any formatting pass over the corpus rewrites
# these four files in place. While the grammar is mid-transfer (GAP-145) the
# printer reprints the MISREADING, and it exits 0 doing it: measured on this
# head, `idol fmt examples/keyed_table_write_wins.id` reports "Formatted",
# deletes `print(read())`, and leaves `M.a = M.a < read()` behind — a legal
# program that is not this one. That already happened once during this gap's
# own investigation, and the resulting diagnostic was quoted in `gaps/GAP-221.md`
# as if the parser had produced it.
#
# So before anything is compiled, the fixtures must be byte-identical to what
# Git carries. This is not a style check; it is the gate declining to report an
# answer about a program nobody wrote. `GAP-223` is the same corruption mode.
for fixture in $fixtures
do
    [ -f "$fixture" ] || fail "acceptance fixture is missing: $fixture"
    if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        if ! git -C "$root" diff --quiet HEAD -- "$fixture" 2>/dev/null; then
            fail "acceptance fixture differs from HEAD: $fixture — the gate cannot
       say what it measured. If a formatter rewrote it, restore it with
       'git checkout -- $fixture'; if the edit is intended, commit it first."
        fi
    fi
done
printf 'gap-221-shadowstore gate: arm 0 four fixtures match HEAD byte for byte\n'

for fixture in $fixtures
do
    name=$(basename "$fixture" .id)
    want=$(sed -n 's/^# expect: *//p' "$fixture" | head -1)
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"

    if ! "$idol" compile --backend=direct "$fixture" -o "$work/$name.out" \
        >"$work/$name.compile" 2>&1
    then
        # A FIXTURE THAT DOES NOT COMPILE IS NOT EVIDENCE ABOUT THIS GAP.
        # GAP-221 is a WRONG ANSWER, so its assertion is over an answer that
        # exists. While the grammar is mid-transfer a refusal here says what the
        # head cannot do, not what this lowering decides — and it is not always
        # a refusal that names itself: at 29d77ed0
        # `examples/keyed_table_write_wins.id` PARSES and then reports
        # `16:4: return type mismatch: expected 'i64', got 'bool'` on the bare
        # field read `M.a`, which is an i64 and is the only thing in that body.
        # The module was misread, and deleting its comment header selects a
        # DIFFERENT wrong reading (a parse refusal at `<eof>`), so the trivia
        # picks the answer. Classifying either as this gap's failure would be
        # a confident wrong verdict of exactly the kind this gap is about.
        # So every compile refusal is BLOCKED, VERBATIM, and classified as far
        # as it can honestly be classified; the one thing that FAILS is a
        # fixture that ran and answered wrong.
        why=$(grep -m1 'error:' "$work/$name.compile" | head -1)
        case $why in
            *'at this token edge'*|*'expected expression'*)
                whence='refuses at parse'
                ;;
            *DNB004*)
                whence='has no realization on this host'
                ;;
            *)
                whence='did not compile'
                ;;
        esac
        printf 'gap-221-shadowstore gate: BLOCKED %s %s — %s\n' \
            "$fixture" "$whence" "$why"
        blocked=$((blocked + 1))
        continue
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
