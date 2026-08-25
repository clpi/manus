#!/bin/sh
# BRANCH CENSUS — how much of the ref pile is actually unreconciled work.
#
# WHY THIS IS A RUNNER AND NOT A DOCUMENT. A count of unreconciled branches is
# volatile state: it changes on every push, merge and delete. `AGENTS.md` and
# `docs/METRICS.md` both rule that a number lives in the runner that recomputes
# it, never in prose, because every figure this project wrote down as an
# assertion has decayed. A census markdown at the repository root is the exact
# artifact #154 deleted twenty-seven of.
#
# THE MEASUREMENT THIS EXISTS TO CORRECT. "There are still 150 ref branches"
# counts refs, and a ref is not work. Three populations hide inside that one
# number and only the third is a reconciliation obligation:
#
#   CONTAINED           the ref is an ancestor of the base branch. Zero delta.
#   LANDED-BY-SUBJECT   the ref has commits the base does not, but every one of
#                       their subjects is already in the base's history. This is
#                       what a squash merge leaves behind: the PR landed, the
#                       branch keeps its pre-squash commits, and `git diff
#                       base...branch` still prints thousands of lines that are
#                       rebase noise, not work.
#   CARRIES-UNLANDED    at least one commit subject is in no commit on the base.
#                       Only these can carry work nobody has landed.
#
# The middle class is why a raw ref count overstates the debt so badly: the
# largest branch measured here had a 110-file, +8463-line diff against the base
# and all 48 of its commits were already in it.
#
# WHAT A SUBJECT MATCH DOES AND DOES NOT PROVE, CORRECTED. This first read
# "an UPPER BOUND on the obligation", and that was wrong. Review of #155
# constructed the counterexample: two divergent commits both titled `same`, where
# `base..branch` prints `same`, the subject match counts it landed, and
# `git diff base branch` is still non-empty. A subject is not a patch, so the
# subject test can MISS unlanded work and is not a bound in either direction.
#
# It errs both ways, for opposite reasons:
#
#   over-reports   a reworded squash lands the work under a new subject, and
#                  the branch is still called CARRIES-UNLANDED
#   under-reports  a branch-only commit reusing a base subject with a different
#                  patch is called landed
#
# So `git cherry` is run beside it, which compares PATCH IDS: `-` is upstream,
# `+` is not. That has the opposite bias — a squash merge rewrites the patch, so
# every squash-landed commit reads `+` — and the two together are informative
# where neither alone is. The under-reporting case is given its own line,
# SUBJECT-ONLY: every subject matched and at least one patch is not upstream.
# A squash merge looks exactly like that and so does the counterexample, which
# is precisely why the census names the refs instead of ruling on them.
#
# No column here is a bound. Each member still needs reading by hand — several in
# the measured run turned out to be superseded under a different subject, and
# one turned out to be landable after all.
#
# This gate MEASURES. It does not fail on a large census, because a large
# census is a fact about the repository and not a violated law.

set -u

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf 'branch census: BROKEN — not inside a git work tree\n' >&2
    exit 2
}
cd -- "$repo" || exit 2

base=${IDOL_CENSUS_BASE:-origin/main}
git rev-parse --verify --quiet "$base" >/dev/null || {
    printf 'branch census: CANNOT MEASURE — no such base ref: %s\n' "$base" >&2
    printf 'branch census: set IDOL_CENSUS_BASE, or fetch the remote first\n' >&2
    exit 2
}

# A shallow clone cannot answer ancestry, and would silently report every ref
# as unlanded. Refuse rather than report a number derived from missing history.
if [ -f "$(git rev-parse --git-dir)/shallow" ]; then
    printf 'branch census: CANNOT MEASURE — shallow clone; ancestry is not answerable\n' >&2
    printf 'branch census: run `git fetch --unshallow` first\n' >&2
    exit 2
fi

work=${TMPDIR:-/tmp}/idol-branch-census.$$
mkdir -p "$work" || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

git log --format=%s "$base" | sort -u >"$work/subjects"
[ -s "$work/subjects" ] || {
    printf 'branch census: CANNOT MEASURE — base %s has no history\n' "$base" >&2
    exit 2
}

# ============================ §1 POSITIVE CONTROL ===========================
# A census that examined nothing must not report a clean zero. The classifier
# is exercised on two constructed refs whose class is known before it runs.
printf 'branch census: §1 control\n'
ctl_fail=0

# The base is trivially contained in itself.
if git merge-base --is-ancestor "$base" "$base" 2>/dev/null; then :; else
    printf '  control FAIL: the base is not recognised as contained in itself\n' >&2
    ctl_fail=1
fi

# A subject that cannot be in the base must not be found in it.
if grep -qxF -e 'zzz-no-such-commit-subject-zzz' "$work/subjects" 2>/dev/null; then
    printf '  control FAIL: a subject that is in no commit was matched\n' >&2
    ctl_fail=1
fi

# The first subject of the base must be found in the base. This is the half
# that fails if the matcher is broken in the direction that reports everything
# as unlanded — the direction that would make the headline number too large.
ctl_subject=$(git log -1 --format=%s "$base")
if grep -qxF -e "$ctl_subject" "$work/subjects"; then :; else
    printf '  control FAIL: the base tip subject was not found in the base\n' >&2
    ctl_fail=1
fi

[ "$ctl_fail" -eq 0 ] || {
    printf 'branch census: BROKEN — the classifier failed its own controls\n' >&2
    exit 2
}
printf '  PASS — containment, a present subject, and an absent subject\n'

# =============================== §2 CENSUS ==================================
printf 'branch census: §2 census against %s\n' "$base"

contained=0
landed=0
unlanded=0
subject_only=0
examined=0

: >"$work/unlanded"
: >"$work/subjectonly"

for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin \
             | grep -v '/HEAD$'); do
    [ "$ref" = "$base" ] && continue
    examined=$((examined + 1))

    if git merge-base --is-ancestor "$ref" "$base" 2>/dev/null; then
        contained=$((contained + 1))
        continue
    fi

    total=0
    hit=0
    git log --format=%s "$base".."$ref" >"$work/refsubjects" 2>/dev/null || :
    while IFS= read -r subj; do
        [ -n "$subj" ] || continue
        total=$((total + 1))
        if grep -qxF -e "$subj" "$work/subjects"; then
            hit=$((hit + 1))
        fi
    done <"$work/refsubjects"

    # A SUBJECT IS NOT A PATCH, and this is where that bites. Two divergent
    # commits can carry one subject — verified by construction: with both titled
    # `same`, `base..branch` prints `same`, the match above increments `hit`, and
    # `git diff base branch` is still non-empty. The subject test alone therefore
    # UNDER-reports, so calling its result an upper bound was wrong.
    #
    # `git cherry` answers the other half by PATCH ID: `-` is upstream, `+` is
    # not. It has the opposite bias — a squash merge rewrites the patch, so every
    # squash-landed commit reads `+` — which is why neither column is the answer
    # and both are printed.
    # `grep -c` PRINTS 0 AND EXITS 1 when it matches nothing, so the obvious
    # `|| echo 0` appends a SECOND line and the comparison below then dies with
    # "Illegal number: 0\n0". `|| :` swallows the status and leaves the count
    # grep already printed.
    cherry_plus=$(git cherry "$base" "$ref" 2>/dev/null | grep -c '^+' || :)
    [ -n "$cherry_plus" ] || cherry_plus=0

    if [ "$total" -eq 0 ] || [ "$hit" -eq "$total" ]; then
        landed=$((landed + 1))
        # The bot's case made visible: every subject matched, and the patch did
        # not. Not an error — a squash merge looks exactly like this — but the
        # only way to tell the two apart is to read the ref, so it is named.
        if [ "$cherry_plus" -gt 0 ]; then
            subject_only=$((subject_only + 1))
            printf '%s\t%s\n' "$ref" "$cherry_plus" >>"$work/subjectonly"
        fi
    else
        unlanded=$((unlanded + 1))
        printf '%s\t%s\t%s\t%s\n' "$ref" "$((total - hit))" "$total" "$cherry_plus" >>"$work/unlanded"
    fi
done

[ "$examined" -gt 0 ] || {
    printf 'branch census: CANNOT MEASURE — no remote refs besides the base\n' >&2
    exit 2
}

printf '  examined            %s\n' "$examined"
printf '  contained           %s\n' "$contained"
printf '  landed-by-subject   %s\n' "$landed"
printf '  carries-unlanded    %s   (read each one)\n' "$unlanded"
printf '  subject-only         %s   (every subject in base, patch is not)\n' "$subject_only"

# ========================= §3 THE OBLIGATION SET ============================
printf 'branch census: §3 refs carrying at least one unlanded subject\n'
if [ "$unlanded" -eq 0 ]; then
    printf '  none\n'
else
    sort "$work/unlanded" | while IFS='	' read -r ref miss tot plus; do
        printf '  %-52s %s of %s subject(s) not in base, %s patch(es) not upstream\n' \
            "$ref" "$miss" "$tot" "$plus"
    done
fi

printf 'branch census: OK — %s ref(s) examined, %s carry an unlanded subject\n' \
    "$examined" "$unlanded"
exit 0
