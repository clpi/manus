#!/bin/sh
# gate/admission-all.sh — local mechanical admission primitives over a real diff.
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
#   gate/admission.sh   no newly added raw std source spelling
#   gate/vocabulary.sh  fail-closed module-declaration freeze; no word registry
#   gate/layering.sh    dependency direction, projections, relation ownership
#
# Each has controls in both directions. This script is not server enforcement:
# a candidate-owned hook or workflow can weaken itself. A protected-base
# workflow or admission service must execute these exact base-owned bytes over
# the candidate diff, and a repository ruleset must require that workflow.
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
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --controls) run_gates=no; run_controls=yes ;;
        --all) run_controls=yes ;;
        --base) shift; [ $# -gt 0 ] || { echo "$prog: --base needs a revision" >&2; exit 1; }; base_rev=$1 ;;
        *) echo "$prog: unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

rc=0

if [ "$run_gates" = yes ]; then
    if ! (cd "$here/.." && sh "$here/subject.sh" --tree) >/dev/null; then
        echo "$prog: BLOCKED — admission requires a real Git work tree." >&2
        exit 1
    fi
    for g in admission vocabulary layering; do
        printf '\n--- gate/%s.sh ---\n' "$g" >&2
        # Exit status is read directly from the command, never from $? after a
        # pipe. A pipeline's $? is the LAST stage's status, and a gate whose
        # failure is swallowed by a `| tee` is a gate that cannot fail.
        if [ -n "$base_rev" ]; then
            sh "$here/$g.sh" --base "$base_rev" || rc=1
        else
            sh "$here/$g.sh" || rc=1
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
