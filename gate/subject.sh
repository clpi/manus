#!/bin/sh
# gate/subject.sh — THE subject enumerator. One place owns two rulings.
#
#   sh gate/subject.sh [pathspec...]        enumerate; ZERO is a FAILURE
#   sh gate/subject.sh --any [pathspec...]  enumerate; empty is a lawful answer
#   sh gate/subject.sh --tree               assert a real git work tree, print nothing
#   sh gate/subject.sh --selftest           both-direction controls for this file
#
# Exit 0 = subjects on stdout. Exit 3 = the enumeration is not trustworthy.
# Never exit 1: a gate's own findings own that status, and a reader must be
# able to tell "the gate ran and found something" from "the gate never ran".
#
# ---------------------------------------------------------------------------
# WHY THIS FILE EXISTS (GAP-220, and GAP-201's ruling it enforces)
#
# The standard isolation method in this project was
# `git archive HEAD | tar -x -C mirror`. That tree has no `.git`, so:
#
#     $ git ls-files | wc -l
#     0
#
# FORTY-FOUR files under gate/, scripts/, tools/ and .githooks/ enumerated
# their subjects with `git ls-files`. In such a mirror they examined NOTHING
# and reported clean. `scripts/public_safety_scan.id` is the proven case: it
# was vacuously green in a mirror and RED in a real checkout at the same
# commit, so the isolation method concealed a live failure. GAP-201's ruling
# is already written down — a gate that examines zero subjects must FAIL,
# never pass — and forty-three of the forty-four did not honour it.
#
# TWO distinct failures are guarded here and they are not the same failure:
#
#   NOT A GIT WORK TREE. `git ls-files` exits 128 with "not a git repository"
#     and prints nothing. Sites that discard stderr and read only stdout
#     cannot tell this from "the repository legitimately contains no such
#     file". This is the GAP-220 shape.
#
#   ZERO SUBJECTS in a real tree. The pathspec is stale, the files moved, or
#     a `--` was dropped. The tree is fine and the QUESTION is broken. This is
#     the shape that ate `examples/cbackend/prove.sh` for 324 commits: a
#     deleted subject whose absence was indistinguishable from the refusal the
#     control was asserting.
#
# ---------------------------------------------------------------------------
# A PIPE DESTROYS THIS FILE'S STATUS, AND THAT IS THE CALLER'S PROBLEM
#
#     sh gate/subject.sh '*.id' | xargs grep -c ... | awk ...
#
# reports awk's status. Exiting 3 here changes nothing about that pipeline's
# verdict; the count simply comes out zero and reads clean. So a caller that
# consumes this file THROUGH A PIPE must ALSO assert the enumeration
# separately, in a position where the status survives:
#
#     rc = cap("sh gate/subject.sh '*.id' >/dev/null 2>&1; echo $?")
#     if rc != "0"  -> fail the gate
#
# That is one line per gate, and the ruling it applies still lives here.
# Reading `$?` after a pipe is what hid a genuinely failing gate in this tree
# once already; bash `PIPESTATUS[0]` and zsh `pipestatus[1]` differ in both
# name and index, so a snippet copied between shells is silently wrong.
set -u

subject_say() {
  printf 'subject: %s\n' "$1" >&2
}

subject_tree() {
  # `--is-inside-work-tree` is the exact question. `rev-parse --git-dir`
  # succeeds inside a bare repository, where `git ls-files` has no index and
  # would answer zero for every pathspec.
  if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null || echo no)" != "true" ]; then
    subject_say "NOT A GIT WORK TREE at ${PWD} — every subject enumerator here examines"
    subject_say "  NOTHING and reports clean (GAP-220). Mirror with 'git clone', never"
    subject_say "  'git archive | tar -x'."
    return 3
  fi
  return 0
}

subject_list() {
  # No command substitution: `git ls-files -z` emits NUL separators, and $( )
  # would eat them. A temp file also lets `-s` answer "did this produce any
  # bytes at all" without interpreting the bytes.
  subject_allow_empty=$1
  shift
  subject_tree || return 3
  subject_out=$(mktemp -t idolsubject) || {
    subject_say "cannot create a scratch file under ${TMPDIR:-/tmp}"
    return 3
  }
  if git ls-files "$@" >"$subject_out" 2>"$subject_out.err"; then
    :
  else
    subject_say "git ls-files $* FAILED in ${PWD}:"
    sed 's/^/  /' <"$subject_out.err" >&2
    rm -f "$subject_out" "$subject_out.err"
    return 3
  fi
  if [ ! -s "$subject_out" ] && [ "$subject_allow_empty" -eq 0 ]; then
    subject_say "ZERO SUBJECTS for 'git ls-files $*' in ${PWD} — a gate that examines"
    subject_say "  zero subjects must FAIL, never pass (GAP-201). Either the pathspec is"
    subject_say "  stale or this is not the tree you think it is."
    rm -f "$subject_out" "$subject_out.err"
    return 3
  fi
  cat "$subject_out"
  rm -f "$subject_out" "$subject_out.err"
  return 0
}

# ---------------------------------------------------------------------------
# CONTROLS IN BOTH DIRECTIONS. A guard that cannot be shown to catch its own
# failure mode is not a guard. Each case below constructs the failure and
# proves this file is red, then constructs the lawful case and proves it is
# green — in a scratch tree, so the controls do not depend on the contents of
# whatever repository the gate happens to be measuring.
subject_selftest() {
  subject_work=$(mktemp -d -t idolsubjectctl) || return 1
  # `trap ... RETURN` is not POSIX; clean up on every exit path by hand.
  subject_rc=0

  # --- the lawful tree ------------------------------------------------------
  mkdir -p "$subject_work/live/lib" || subject_rc=1
  printf 'main: i64 = ()\n  0\n' >"$subject_work/live/lib/probe.id"
  printf 'x\n' >"$subject_work/live/other.txt"
  (
    cd "$subject_work/live" || exit 1
    git init -q . >/dev/null 2>&1 || exit 1
    git config user.email ctl@subject.local
    git config user.name ctl
    git add -A >/dev/null 2>&1 || exit 1
    git commit -qm ctl >/dev/null 2>&1 || exit 1
  ) || subject_rc=1

  subject_case() {
    # $1 expected status, $2 expected line count (-1 = do not check), rest = argv
    subject_want=$1
    subject_lines=$2
    shift 2
    subject_got=$(cd "$subject_work/$subject_where" && sh "$subject_self" "$@" 2>/dev/null)
    subject_status=$?
    if [ "$subject_status" != "$subject_want" ]; then
      subject_say "SELFTEST FAIL [$subject_where: $*] status $subject_status, want $subject_want"
      subject_rc=1
      return
    fi
    if [ "$subject_lines" != "-1" ]; then
      subject_n=$(printf '%s' "$subject_got" | grep -c . || true)
      if [ "$subject_n" != "$subject_lines" ]; then
        subject_say "SELFTEST FAIL [$subject_where: $*] $subject_n line(s), want $subject_lines"
        subject_rc=1
      fi
    fi
  }

  subject_where=live
  # LAWFUL: a pathspec with subjects is green and carries them.
  subject_case 0 1 'lib/*.id'
  subject_case 0 2
  # FAILURE: a pathspec with no subject in a perfectly healthy tree is RED.
  subject_case 3 -1 'src/*.zig'
  # LAWFUL under --any: a negative probe may legitimately answer nothing, but
  # the tree assertion still applies.
  subject_case 0 0 --any 'src/*.zig'
  # LAWFUL: the bare tree assertion.
  subject_case 0 0 --tree

  # --- the mirror that started all of this ----------------------------------
  # This is exactly `git archive HEAD | tar -x`: a faithful copy of every
  # tracked byte, and no `.git`. Every case that was green above must now be
  # RED, including the one that asks only whether this is a work tree.
  mkdir -p "$subject_work/mirror" || subject_rc=1
  (cd "$subject_work/live" && git archive HEAD) 2>/dev/null |
    tar -x -C "$subject_work/mirror" 2>/dev/null
  [ -f "$subject_work/mirror/lib/probe.id" ] || {
    subject_say "SELFTEST FAIL: mirror control did not materialise"
    subject_rc=1
  }
  [ ! -e "$subject_work/mirror/.git" ] || {
    subject_say "SELFTEST FAIL: mirror control carries a .git and proves nothing"
    subject_rc=1
  }
  subject_where=mirror
  subject_case 3 -1 'lib/*.id'
  subject_case 3 -1
  subject_case 3 -1 --any 'src/*.zig'
  subject_case 3 -1 --tree

  # --- the clone that replaces it -------------------------------------------
  # Same isolation from the working tree, and the enumerator works.
  git clone -q "$subject_work/live" "$subject_work/clone" >/dev/null 2>&1 || {
    subject_say "SELFTEST FAIL: clone control did not materialise"
    subject_rc=1
  }
  subject_where=clone
  subject_case 0 1 'lib/*.id'
  subject_case 0 2

  rm -rf "$subject_work"
  if [ "$subject_rc" -eq 0 ]; then
    echo "subject: selftest PASS — lawful/zero/mirror/clone controls, 12 cases"
  else
    subject_say "selftest FAIL"
  fi
  return "$subject_rc"
}

subject_self=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
case "${1:-}" in
  --selftest)
    subject_selftest
    exit $?
    ;;
  --tree)
    subject_tree
    exit $?
    ;;
  --any)
    shift
    subject_list 1 "$@"
    exit $?
    ;;
  *)
    subject_list 0 "$@"
    exit $?
    ;;
esac
