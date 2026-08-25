#!/bin/sh
# gate/realize/census.sh — how much of the corpus the C realizer can realize.
#
# WHY THIS EXISTS. The direct backend emits machine code for aarch64-darwin and
# refuses every other host by name (DNB004), so on any other machine the C
# backend is the ONLY route from source to a running program. Nothing measured
# whether it is one. Measured once by hand it was 13 of 253 subjects in
# `examples/`, and that number had never been recorded anywhere that recomputes
# it — which is the condition `AGENTS.md` names when it says a number lives in
# the runner that checks it.
#
# WHAT THIS GATE MEASURES AND WHAT IT REFUSES TO DECIDE. It reports, per
# subject, whether the C realizer produced a translation unit and — when it did
# not — the exact refusal NOTE and the relation FACE the refusal bound. It
# groups by note, and within the largest note it prints the face histogram.
#
# IT DOES NOT GROUP FACES INTO FAMILIES. Reading `tt` as "a non-callable subject
# applied" and `__emit` as "a compiler intrinsic" is a judgement about
# SPELLINGS, and a gate that ships a spelling roster is the exact producer this
# tree spent `gaps/GAP-226.md` documenting the cost of. The histogram is the
# measurement; the grouping is a human reading and lives in `gaps/GAP-233.md`,
# where it can be argued with.
#
# A LARGE CENSUS IS NOT A FAILURE. The realizer's coverage is a fact about the
# frontier, not a violated law, so this gate reports and exits 0. It exits
# non-zero only when it cannot measure — no compiler, no subjects, or a
# classifier that failed its own controls (`GAP-201`: a gate examining zero
# subjects must fail rather than pass vacuously).

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in
    /*) ;;
    *) idol=$repo/${idol#./} ;;
esac
[ -x "$idol" ] || {
    printf 'realize census: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2
    exit 2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-realize-census.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# One subject through the C realizer. Prints `OK`, `CHECK`, or `<note>\t<face>`.
#
# THE CHECK ARM IS SEPARATE ON PURPOSE. A subject `idol check` refuses is not a
# subject the realizer failed to realize — it is not a valid program, and
# counting it here would charge the realizer for the corpus's own negative
# probes. The first draft of this gate folded them into a `<no note>` bucket of
# 48, which read as "48 refusals with no diagnostic" when most of them never
# reached a diagnostic at all.
classify() {
    _s=$1
    if ! "$idol" check "$_s" >/dev/null 2>&1; then
        printf 'CHECK\t\n'
        return 0
    fi
    if "$idol" compile "$_s" --backend=c --emit=c -o "$work/out.c" \
        >"$work/log" 2>&1
    then
        printf 'OK\t\n'
        return 0
    fi
    _note=$(sed -n 's/.*refused at: //p' "$work/log" | head -1)
    _face=$(sed -n 's/.*in relation: //p' "$work/log" | head -1)
    [ -n "$_note" ] || _note='<no note>'
    printf '%s\t%s\n' "$_note" "$_face"
}

# IS THIS NOTE AN IDENTITY, OR A NAME?
#
# A refusal note is supposed to name a CAUSE, so that a reader can group it, a
# gate can pin it, and a ratchet can count it. Some of them name a SUBJECT
# instead. Measured in `src/dnir_lower.zig`, `bailWith` is called with a bare
# `fname` (9692), a bare field key `nf.key` (9726, 9736), and `@tagName(stmt.*)`
# (5788) — and at 2766 the note is built as `"{path}: {reason}"`, identity LAST,
# so even the notes that carry a cause put the provenance where a prefix match
# would look for the cause.
#
# The test is a fact about the note's SHAPE, not a judgement about any subject's
# spelling: a kebab-case word is the form every deliberate identity in this file
# uses (`missing-application-id`, `result-pack-arity`, `binop-not-in-c99-slice`).
# Anything carrying a space or a colon carries a name.
#
# ITS LIMIT, STATED RATHER THAN HIDDEN. A shape test cannot see a name that
# happens to look like an identity. `mcp` (from `bailWith(…, n.ident)`) and
# `directive` (from `bailWith(…, @tagName(stmt.*))`) are a binding's name and an
# AST tag, and both pass this test as cleanly as `result-not-i64` does. So the
# count below is a LOWER BOUND on name-bearing notes, never an upper one, and
# the two false negatives are named here so a reader does not have to rediscover
# them. Closing that gap needs the producer to declare which of the two it is
# emitting, which is `gaps/GAP-233.md`'s subject and not a thing a grep can
# decide.
#
# `<no note>` is this gate's OWN sentinel for a refusal that recorded nothing,
# so it is a third class and is excluded rather than counted as either.
note_is_identity() {
    case $1 in
        '<no note>') return 0 ;;
        *[!a-z0-9-]*) return 1 ;;
        '') return 1 ;;
        *) return 0 ;;
    esac
}

# ============================ §1 CONTROLS ===================================
# A census that classifies everything the same way reports a clean shape and
# measures nothing. Both directions are exercised on constructed subjects whose
# class is known before the classifier runs.
printf 'realize census: §1 control\n'
ctl=0

printf 'main: i64 = ()\n  0\n' >"$work/realizes.id"
_r=$(classify "$work/realizes.id")
case $_r in
    OK*) ;;
    *) printf '  control FAIL: a trivial main did not realize (%s)\n' "$_r" >&2
       # NOT a law failure — a host that cannot realize even this cannot run
       # the census at all, and saying so is the honest exit.
       printf 'realize census: CANNOT MEASURE — the C realizer refused a trivial subject\n' >&2
       exit 2 ;;
esac

# A subject the realizer is known to refuse, so the refusal arm is exercised
# rather than assumed. `tt(2)` on an aggregate is the shape `law.md` §5 rules
# and `gate/application.sh` already probes.
printf 'tt: [4]i64 = {1, 2, 3, 4}\ntt(2)\n' >"$work/refuses.id"
_f=$(classify "$work/refuses.id")
case $_f in
    OK*) printf '  control FAIL: the refusal arm never fired\n' >&2; ctl=1 ;;
    *) ;;
esac

# The face must survive into the classifier, or the histogram below is empty
# for a reason that has nothing to do with the corpus.
_face_seen=$(printf '%s' "$_f" | cut -f2)
[ -n "$_face_seen" ] || {
    printf '  control FAIL: the refusal bound no relation face\n' >&2
    ctl=1
}

[ "$ctl" -eq 0 ] || {
    printf 'realize census: BROKEN — the classifier failed its own controls\n' >&2
    exit 2
}
printf '  PASS — a subject that realizes, a subject that refuses, and a bound face\n'

# ============================== §2 CENSUS ===================================
printf 'realize census: §2 examples/\n'

: >"$work/rows"
subjects=0
realized=0
checkbad=0
for s in examples/*.id; do
    [ -f "$s" ] || continue
    subjects=$((subjects + 1))
    row=$(classify "$s")
    case $row in
        OK*) realized=$((realized + 1)) ;;
        # NOT a refusal, and NOT a row. A subject `idol check` rejects never
        # reaches the realizer, so folding it into the note histogram would
        # charge the realizer for the corpus's own negative probes and mint a
        # phantom note named CHECK.
        CHECK*) checkbad=$((checkbad + 1)) ;;
        *) printf '%s\n' "$row" >>"$work/rows" ;;
    esac
done

[ "$subjects" -gt 0 ] || {
    printf 'realize census: CANNOT MEASURE — no subjects in examples/\n' >&2
    exit 2
}

refused=$((subjects - realized - checkbad))
printf '  subjects            %s\n' "$subjects"
printf '  refused by check    %s   (not valid programs; the realizer never saw them)\n' "$checkbad"
printf '  realized            %s\n' "$realized"
printf '  refused by realizer %s\n' "$refused"

# =========================== §3 BY REFUSAL NOTE =============================
printf 'realize census: §3 refusals by note\n'
if [ "$refused" -eq 0 ]; then
    printf '  none\n'
else
    cut -f1 "$work/rows" | sort | uniq -c | sort -rn | while read -r count note; do
        if [ "$note" = '<no note>' ]; then
            printf '  %5s  %s   <- the refusal recorded no cause at all\n' "$count" "$note"
        elif note_is_identity "$note"; then
            printf '  %5s  %s\n' "$count" "$note"
        else
            printf '  %5s  %s   <- carries a NAME, not an identity\n' "$count" "$note"
        fi
    done
    named=$(cut -f1 "$work/rows" | sort -u | while read -r note; do
        note_is_identity "$note" || printf 'x\n'
    done | grep -c . || :)
    [ -n "$named" ] || named=0
    printf '  distinct notes %s, of which at least %s carry a name rather than a cause\n' \
        "$(cut -f1 "$work/rows" | sort -u | grep -c .)" "$named"
fi

# ======================= §4 FACES UNDER THE TOP NOTE ========================
# The face is a DIAGNOSTIC PROJECTION of the occurrence's relation, not an
# identity — two occurrences of one spelling share a face and differ in the id.
# It is printed because it is what separates causes that share a note, and
# NOT grouped, for the reason in this file's header.
printf 'realize census: §4 relation faces under the most common note\n'
if [ "$refused" -eq 0 ]; then
    printf '  none\n'
else
    top=$(cut -f1 "$work/rows" | sort | uniq -c | sort -rn | head -1 \
          | sed 's/^ *[0-9][0-9]* //')
    printf '  note: %s\n' "$top"
    bound=0
    unbound=0
    while IFS='	' read -r note face; do
        [ "$note" = "$top" ] || continue
        if [ -n "$face" ]; then bound=$((bound + 1)); else unbound=$((unbound + 1)); fi
    done <"$work/rows"
    printf '  with a bound face    %s\n' "$bound"
    printf '  with NO bound face   %s\n' "$unbound"
    printf '  distinct faces       %s\n' \
        "$(awk -F'\t' -v n="$top" '$1==n && $2!=""{print $2}' "$work/rows" | sort -u | grep -c .)"
    awk -F'\t' -v n="$top" '$1==n && $2!=""{print $2}' "$work/rows" \
        | sort | uniq -c | sort -rn | head -12 | while read -r count face; do
        printf '    %5s  %s\n' "$count" "$face"
    done
fi

printf 'realize census: OK — %s subject(s), %s refused by check, %s realized, %s refused by the realizer\n' \
    "$subjects" "$checkbad" "$realized" "$refused"
exit 0
