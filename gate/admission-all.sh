#!/bin/sh
# gate/admission-all.sh — the mechanical admission gate, run over a real diff.
#
# READ THIS IF YOU ARE WIRING SOMETHING.
#
# `.githooks/pre-commit` invokes `idol check gate/idiom.id` and friends. That
# TYPECHECKS THE GATE SOURCE. It does not scan the staged diff. The hook's own
# header says so: "Do not treat check-pass as a scan." So every "gates passed"
# in this repository's commit flow has meant one thing -- the gate file
# compiles. It has never meant the patch was examined.
#
# The three gates below are POSIX shell. They read the staged diff and the
# working tree with awk and git. They do not need `zig-out/bin/idol` to exist,
# they do not call `idol check`, and they do not depend on `idol run`, which
# the hook header records as SIGKILLing on a non-empty diff. Nothing here is
# implementation-blocked. The hook can execute them today, and does.
#
#   gate/admission.sh   std ratchet: pinned census + a stricter added-line rule
#   gate/vocabulary.sh  deny-by-default admission of new public vocabulary
#   gate/layering.sh    dependency direction, projections, relation ownership
#
# Each of the three has a control harness proving it can reject a violating
# input AND admit a lawful one. Run them with --controls. They are not in the
# per-commit path because they clone the repository ~25 times; they belong in
# CI and before any change to a gate.
#
# USAGE:
#   gate/admission-all.sh                 all three, staged diff
#   gate/admission-all.sh --base <rev>    all three, <rev>..worktree
#   gate/admission-all.sh --controls      the control harnesses
#   gate/admission-all.sh --all           gates then controls

set -eu
here=$(cd "$(dirname "$0")" && pwd)
prog=$(basename "$0")

run_gates=yes
run_controls=no
fwd=""
while [ $# -gt 0 ]; do
    case "$1" in
        --controls) run_gates=no; run_controls=yes ;;
        --all) run_controls=yes ;;
        --base) shift; [ $# -gt 0 ] || { echo "$prog: --base needs a revision" >&2; exit 1; }; fwd="--base $1" ;;
        *) echo "$prog: unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

rc=0

if [ "$run_gates" = yes ]; then
    for g in admission vocabulary layering; do
        printf '\n--- gate/%s.sh ---\n' "$g" >&2
        # Exit status is read directly from the command, never from $? after a
        # pipe. A pipeline's $? is the LAST stage's status, and a gate whose
        # failure is swallowed by a `| tee` is a gate that cannot fail.
        if ! sh "$here/$g.sh" $fwd; then
            rc=1
        fi
    done
fi

if [ "$run_controls" = yes ]; then
    for c in admission vocabulary layering; do
        printf '\n--- gate/%s-controls.sh ---\n' "$c" >&2
        if ! sh "$here/$c-controls.sh"; then
            rc=1
        fi
    done
fi

printf '\n' >&2
if [ "$rc" -eq 0 ]; then
    echo "$prog: ADMITTED." >&2
else
    echo "$prog: BLOCKED. See the named gate above." >&2
fi
exit "$rc"
