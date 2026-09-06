#!/bin/sh
# Exact two-compiler behavioural differential over a declared legacy-equivalent
# subject set. Each arm is observed ONCE. Status, stdout, stderr, timeout and
# signal therefore belong to one execution instead of being assembled from two
# different executions.
#
#   gate/differential.sh <base-idol> <candidate-idol> [file-list]
#   gate/differential.sh --null-control <idol> [file-list]
#   gate/differential.sh --selftest
#   gate/differential.sh                 # mandatory controls; comparison UNMEASURED
#
# A changed row is red. A timeout or broken outcome channel is infrastructure,
# never a semantic refusal. The oracle is intentionally bounded: callers must
# supply only programs expected to retain legacy behaviour (law.oracle.bounded).
#
# WHY EACH MECHANISM BELOW EXISTS. Every one was written after a hand-rolled
# differential in this tree produced a CONFIDENT WRONG ANSWER. Preserved as
# provenance so none is removed as redundant ceremony:
#
#   normalising `([0-9]+ ms` — compiler progress lines carry per-run timings.
#     Comparing raw stderr reported 279 of 943 files changed when nothing had.
#
#   normalising mirror paths — `detectCompilerLibRoot(..., args[0])`
#     (src/main.zig) resolves the compiler's lib/ from the BINARY's location,
#     not the cwd, so two arms from different mirrors compare two different
#     lib/ trees and diagnostics carry the mirror path. 126 false rows. Note
#     the pattern must cross a SPACE: an earlier `[^ ]*` could not match
#     "/Volumes/d 1/" and silently normalised nothing.
#
#   a working directory per arm — both arms otherwise write ./<name>.out into
#     one directory and the second hits the first's cached artifact. 28 false
#     rows INCLUDING apparent exit-code regressions (0 -> 1) on programs whose
#     stdout was byte-identical.
#
#   infrastructure classification — a killed run emits NO diagnostic, so a
#     naive census scores it as a CLEAN COMPILE. The error is silent and
#     OPTIMISTIC: under load this moved a measured refusal count from 445 to
#     345 with no signal at all.
#
#   the same-binary guard — a patched build that never finished linking
#     reports zero differences and reads as success. Related: copying a mirror
#     WITH its .zig-cache makes `zig build` emit a byte-identical binary from
#     changed sources (observed: 8584af5eb14f1ace on both arms). Hash both.
#
#   the zero-subject guard — run where the list resolves empty, an earlier
#     version printed "compared 0 ... CHANGED 0" and exited 0. GAP-201: a gate
#     examining zero subjects must fail.
#
#   Reading `$?` after a pipe reports the PIPE's status. This hid a genuinely
#     failing gate here; bash PIPESTATUS[0] and zsh pipestatus[1] differ in
#     BOTH name and index, so a snippet copied between shells is silently wrong.
#
#   normalising EACH ARM'''S OWN TREE ROOT. The mirror-path rule above only ever
#     matched `/Volumes/.../tmp-<name>/`, which is the shape `mktemp -d` happens
#     to produce here. Two SIBLING MIRRORS — `.../idol` and `.../idol-native`,
#     or any two clones — are not that shape, so every diagnostic that quotes
#     the compiler'''s own lib/ root came out different and every such row was
#     scored CHANGED. It reported ~163 rows on any two-mirror run. That was
#     proven false only by a null control, and by hand: the identical 163-row
#     set appeared between a baseline and a severed build whose MACHINE CODE
#     WAS IDENTICAL. A per-arm substitution cannot be written as one global
#     `sed` because the two roots are different strings, so `norm` now takes
#     the arm it is normalising.
#
#   --null-control. The reasoning above had to be done by hand, once, by
#     someone who already suspected the harness. It is a mode now: the SAME
#     compiler is placed under two different mirror roots and compared with
#     itself. Every row it reports is harness noise by construction, because
#     the machine code on both arms is the same bytes. Zero rows is the only
#     lawful result, and a caller who sees rows from a real comparison can run
#     this to find out whether to believe them.
#
#   searching for the sibling gate home. The shared outcome limiter was named
#     as `$ROOT/../idol-native/gate/run_limited.pl`, which is correct in a
#     clone and is `<main>/.worktrees/idol-native/...` in a git worktree —
#     a directory no host has. Every worktree run therefore refused at load,
#     before a single control, and `gate/all.sh` scored that refusal as "its
#     subject is in a tree that is not here" rather than as a law that went
#     unmeasured. The sibling is now SEARCHED FOR over an ordered candidate
#     list, a refusal prints every candidate it tried, and `selftest` carries
#     the worktree layout as a control.
#
#   normalising THE SUBJECT SOURCE ROOT, which belongs to NEITHER arm. The
#     per-arm rule above substitutes each arm's OWN tree root. But both arms
#     are handed the SAME subject, out of one source tree, so the source root
#     is a string both arms print and it was substituted on whichever arm
#     happened to be rooted there and left alone on the other. That is the
#     ordinary arrangement — a tree that builds its own compiler and supplies
#     its own subjects — and under it EVERY diagnostic that quotes a subject
#     path came out different and every such row was scored CHANGED.
#
#     `--null-control` cannot see this class. It copies BOTH arms under
#     `$WORK/null.a` and `$WORK/null.b` while the source stays `$ROOT`, so
#     neither arm is ever rooted at the source root and the collision it
#     exists to detect cannot arise in it. The one instrument a reader has for
#     deciding whether to believe a row is structurally blind here, which is
#     why this is carried as a selftest control instead.
#
#     The source root therefore normalises to the SAME token as an arm root:
#     the two play one role in a diagnostic — the tree a path was resolved out
#     of — and when an arm IS the source tree they are one string, so no
#     substitution could separate them and a SECOND token would only move the
#     divergence onto the other arm. It has to be one token, and the same one
#     on both arms, or the tokenisation depends on which arm is being
#     normalised, which is the defect itself. Ordering is by path length,
#     longest first, because one root can nest inside another — a mirror under
#     the tree it mirrors — and substituting the shorter first leaves the
#     longer unmatched on the arm that owns it.
#
#     WHAT ONE TOKEN COSTS, stated rather than controlled, because a control
#     for it would have to assert the erasure is correct: a difference that
#     consists ONLY of which tree a path was resolved out of — base opening
#     `<base>/lib/x.id` where candidate opens `<source>/lib/x.id` — now reads
#     identical. That is narrower than what it replaces (a false row on every
#     subject-quoting diagnostic in the ordinary arrangement) and it is
#     unobservable anyway on the arm where the two trees are one string, but
#     it is a real erasure and not a free repair.
#
#   a scratch root per arm. `src/scratch.zig` honours TMPDIR for the build
#     cache, intermediate objects, emitted C and logs, so giving each arm its
#     own makes each arm actually compile rather than serving the other arm'''s
#     artifact out of a shared `/tmp/idol-cache-*`.
#
#   SUBSTITUTING EACH ROOT IN BOTH SPELLINGS. Every root above was learned by
#     `cd <path> && pwd`, which is the spelling the harness was CALLED by:
#     `cd` keeps the symlinks it was handed. The arms do not report that
#     spelling. `detectCompilerLibRoot` (src/main.zig) calls
#     `realPathFileAbsoluteAlloc` on argv[0], `realPathOwned` canonicalises
#     every source spelling it resolves, and `getcwd` — what a compiled
#     program'''s `os.cwd` reduces to — answers with symlinks resolved. So an
#     arm reached through a symlinked path quotes a root string the harness
#     never substitutes, and the row is red for the harness'''s reason again.
#
#     This is not an exotic layout. It is macOS: `$TMPDIR` is
#     `/var/folders/...` and `/var` is a symlink to `private/var`, so the
#     harness'''s own `mktemp -d` scratch — the per-arm working directories and
#     the per-arm scratch roots both live in it — is symlink-spelled on the
#     platform whose paths appear throughout this provenance. It also reaches
#     any checkout under a symlinked home, mount or `/tmp`.
#
#     Both spellings therefore take the SAME token, for the reason the source
#     root takes an arm root'''s token: they are one directory, so they name one
#     role, and a second token would only move the divergence onto the arm that
#     spells it the other way. Length ordering already covers them — a physical
#     spelling can nest inside a logical one and the reverse.
#
#     `$WORK` is additionally resolved to its physical spelling at creation
#     rather than left to the substitution, because the harness owns it: the
#     roots it hands the arms are then the roots the arms report, and the
#     selftest fixtures built inside it are spelled the way `git` answers
#     about them. Under a symlinked TMPDIR the worktree control FAILED — git
#     resolves `--git-common-dir` physically while the fixture compared the
#     logical spelling — so the whole oracle refused at its mandatory
#     controls, which is the loud direction but still an oracle that does not
#     run.
#
#   ...AND RESOLVING THE ARM BINARY ITSELF, NOT ONLY THE PATH TO IT. The rule
#     above learns a root by `cd <path> && pwd -P`, and `cd` resolves
#     DIRECTORIES: it walks to the leaf and stops there. The arm does not stop
#     there. `detectCompilerLibRoot` calls `realPathFileAbsoluteAlloc` on
#     argv[0] — the FILE — before it takes its three dirnames, so an arm whose
#     BINARY is a symlink derives its lib root from the tree the symlink points
#     INTO while the harness substitutes the tree the symlink LIVES IN. This is
#     not a second SPELLING of the arm's root, which is why the rule above
#     cannot reach it: it is a DIFFERENT DIRECTORY, and no respelling of the
#     wrong directory becomes the right one.
#
#     This is how a reference compiler is ordinarily kept. An `idol` on PATH is
#     a symlink into the tree that built it, so
#     `differential.sh "$(command -v idol)" zig-out/bin/idol` — the installed
#     compiler against a fresh build — is the first comparison anyone runs, and
#     it is the shape that fails.
#
#     `--null-control` is blind twice over. It `cp`s each arm, and `cp` FOLLOWS
#     the symlink and lands a real file under a root the mode built itself; and
#     it refuses a binary whose `<tree>/lib/std.id` is absent, which is exactly
#     what a symlink placed beside no stdlib looks like. The reader's
#     instrument is structurally blind for the third time, so the controls live
#     in `selftest`.
#
#     Measured on this tree at d4ea54f2, one subject, two fakes that resolve
#     argv[0] the way an arm does:
#
#       real vs away  -> 0   changed 0, identical 1
#       link vs away  -> 1   changed 1  — the SAME two binaries, one of them
#                            reached through a symlink to itself
#
#     BOTH roots are kept, under ONE token, for the reason every root above
#     keeps both of its spellings: argv[0] is handed to the arm AS SPELLED, so
#     the spelled root is a string the arm can print, while the resolved root
#     is the one it actually resolves its lib/ out of. One arm, one role.
#
#   SUBSTITUTING ROOT TEXT, NOT A ROOT-SHAPED PATTERN. Every root above is
#     correct and every one of them was then handed to `sed` as the LEFT SIDE
#     OF A REGEX with only `#` and `\` escaped. A directory name may hold any
#     of `. [ ] { } ( ) * + ? ^ $ |`, and each one made the rule mean something
#     other than the root it was built from. Three directions, the first two
#     reproduced against this harness on this host by putting one character in
#     `$TMPDIR` and running the controls that already existed:
#
#       `+`  quantifier. The rule does not match its own root, so nothing is
#            normalised and the class every root above exists to kill comes
#            back whole. `TMPDIR=/tmp/d+1 gate/differential.sh --selftest`
#            failed at the sibling-mirror control.
#       `(`  unbalanced group. `sed` REFUSES THE EXPRESSION, writes nothing,
#            and its status is not read — so both arms get an empty normalised
#            stderr and every stderr difference on the run compares identical.
#            `TMPDIR='/tmp/p(1' gate/differential.sh --selftest` failed at the
#            control for a real row surviving normalisation, which is the only
#            reason that erasure was visible at all.
#       `.`  any character. The rule matches MORE than its root: built from
#            `.../a.c` it erases `.../aXc` out of a diagnostic. No control
#            could catch this one, because it needs a near-miss string no
#            fixture emits — it is a property of the rule, shown by the rule.
#            Silent, and in the optimistic direction.
#
#     This is not exotic either. macOS spells `$TMPDIR` as
#     `/var/folders/<2>/<base64ish>/T/`, and that middle component is base64:
#     `+` is in its alphabet. The harness's own `mktemp -d` scratch — which is
#     where the per-arm working directories and scratch roots come from — is
#     one draw away from it on the platform this whole provenance comes from.
#
#     The escape set is now every ERE metacharacter, and `normout` reads the
#     rules in ERE like `norm` already did. One escaped rule cannot serve two
#     dialects — `\+` is a literal plus in ERE and a quantifier in GNU BRE —
#     so the two channels were normalising the same root differently.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMO="${DIFFERENTIAL_TIMEOUT:-90}"

# physical <directory> — the same directory with every symlink resolved, or
# NOTHING when it does not exist.
#
# `cd <path> && pwd` answers the spelling it was HANDED; `pwd -P` answers the
# spelling the kernel gives a child that asks. Every root this harness learns
# is of the first kind and every root an arm reports is of the second, so the
# two have to be reconciled somewhere. Answering nothing for an absent path is
# deliberate: a rule for a directory that is not there could only match by
# accident, and `rootrules` drops it.
physical() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# physicalfile <path> — the same path with every symlink resolved INCLUDING a
# symlinked leaf, or NOTHING when it does not resolve.
#
# `physical` above answers by `cd`, so it resolves the directories on the way
# and then stops at the leaf; it can never resolve the FILE. The arms do not
# stop there — `detectCompilerLibRoot` (src/main.zig) calls
# `realPathFileAbsoluteAlloc` on argv[0] before it derives anything — so a root
# taken from the spelled binary and a root taken from the arm's own view of it
# are two different directories whenever the binary is a symlink.
#
# `perl` is already a hard dependency of this harness: the shared outcome
# limiter IS a perl script, and no observation happens without it.
# `Cwd::realpath` is the same resolution the arm performs, and unlike
# `readlink -f` it exists on every host this file has run on.
physicalfile() {
  perl -MCwd -e 'my $p = Cwd::realpath($ARGV[0]); print $p if defined $p' "$1" 2>/dev/null
}

# maincheckout <tree-root>
#
# The root that a SIBLING checkout is a sibling of. In an ordinary clone that
# is the tree itself, so this answers nothing and costs one `git rev-parse`.
# In a git WORKTREE it is a different directory: the worktree lives at
# <main>/.worktrees/<name>, so <tree>/.. is `.worktrees` and a sibling named
# from there has never existed on any host. `--git-common-dir` names the one
# .git that every worktree shares, and its parent is the main checkout.
#
# Answers nothing, not an error, when the tree is not a git checkout at all —
# a plain mirror copy is exactly that, and `subjectlist` below already exists
# because this harness is expected to run in one.
maincheckout() {
  _mc_root=$1
  command -v git >/dev/null 2>&1 || return 0
  _mc_common=$(cd "$_mc_root" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -n "$_mc_common" ] || return 0
  # The SAME git answers this RELATIVE from a main checkout (".git") and
  # ABSOLUTE from a worktree. Resolve against the tree rather than the cwd.
  case "$_mc_common" in
    /*) : ;;
    *) _mc_common="$_mc_root/$_mc_common" ;;
  esac
  (cd "$_mc_common/.." 2>/dev/null && pwd)
}

# nativecandidates <tree-root> — every sibling gate home worth trying, in
# order, one per line. `cd ..` normalises each, so the main-checkout case
# yields the same string twice and `awk` collapses it: the list a refusal
# prints is the list that was actually tried.
nativecandidates() {
  _ncs_root=$1
  for _ncs_base in "$_ncs_root" "$(maincheckout "$_ncs_root")"; do
    [ -n "$_ncs_base" ] || continue
    _ncs_up=$(cd "$_ncs_base/.." 2>/dev/null && pwd) || continue
    printf '%s/idol-native\n' "$_ncs_up"
  done | awk '!seen[$0]++'
}

# nativelimiter <tree-root> — the first candidate that actually holds the
# shared outcome limiter, or nothing. Existence is the selector, not the
# ordering: a candidate that is merely a directory decides nothing.
nativelimiter() {
  nativecandidates "$1" | while IFS= read -r _nl_cand; do
    if [ -f "$_nl_cand/gate/run_limited.pl" ]; then
      printf '%s/gate/run_limited.pl' "$_nl_cand"
      break
    fi
  done
}

# WHY THE SIBLING IS SEARCHED FOR RATHER THAN SPELLED. This read
# `${IDOL_NATIVE:-$ROOT/../idol-native}` and refused at load with that one
# path in the message. From a git worktree that path is
# <main>/.worktrees/idol-native — a directory no host has ever had — so the
# oracle refused before running a single control in EVERY worktree, while the
# sibling sat one level further up. The refusal was then read as a fact about
# the checkout: `gate/all.sh` classifies a gate whose log names an absent
# `$native` as "its subject is in a tree that is not here", so the oracle
# scored as absent-by-checkout instead of as unmeasured, and a census line
# that should have said the differential never ran said nothing at all. The
# controls in `selftest` pass on this host; they had simply never been reached
# from the worktrees that do the work.
if [ -n "${DIFFERENTIAL_LIMITER:-}" ]; then
  LIMITER=$DIFFERENTIAL_LIMITER
elif [ -n "${IDOL_NATIVE:-}" ]; then
  # EXPLICIT WINS AND STAYS LOUD. A supplied root that does not hold the
  # limiter is a caller error, not permission to search elsewhere
  # (law.fallback.zero) — searching would observe a tree the caller did not
  # name and report the result under the name they did.
  LIMITER="$IDOL_NATIVE/gate/run_limited.pl"
else
  LIMITER=$(nativelimiter "$ROOT")
fi

[ -n "$LIMITER" ] && [ -f "$LIMITER" ] || {
  echo "differential: shared outcome limiter absent — no control ran, nothing was compared" >&2
  if [ -n "${DIFFERENTIAL_LIMITER:-}" ]; then
    printf 'differential:   DIFFERENTIAL_LIMITER=%s names no file\n' "$DIFFERENTIAL_LIMITER" >&2
  elif [ -n "${IDOL_NATIVE:-}" ]; then
    printf 'differential:   IDOL_NATIVE=%s holds no gate/run_limited.pl\n' "$IDOL_NATIVE" >&2
  else
    nativecandidates "$ROOT" | while IFS= read -r _cand; do
      printf 'differential:   tried %s/gate/run_limited.pl\n' "$_cand" >&2
    done
    echo "differential:   set IDOL_NATIVE=<sibling checkout> to name it directly" >&2
  fi
  exit 2
}

# rootrules <token>=<path> ...
#
# One `s#<path>#<token>#g` per pair, LONGEST PATH FIRST, on stdout. Ordering is
# the whole point: these roots are not guaranteed disjoint. A mirror can sit
# under the tree it mirrors, and the subject source root can BE an arm root, so
# substituting a shorter root first would eat the head of a longer one and
# leave the tail behind on the arm that owns it while the other arm normalised
# the same string whole. Length ordering makes the most specific root win
# without either caller having to know which of them nests.
#
# `sed` has no fixed-string mode, so a path is not text here: it is the LEFT
# SIDE OF A REGEX, and every regex metacharacter a directory name is allowed to
# contain has to be escaped or the rule stops naming the root it was built
# from. Escaping only the `#` delimiter and `\` — which is what this did — left
# `. [ ] { } ( ) * + ? ^ $ |` live. An empty path contributes no rule; it would
# otherwise match at every position.
#
# THE ESCAPING IS ERE, AND SO IS EVERY CONSUMER. `\+` is a literal plus in ERE
# and a QUANTIFIER in GNU BRE, so one escaped rule cannot serve both dialects
# and the dialect stops being a detail of whichever `sed` invocation happens to
# read the rule. `norm` was already `sed -E`; `normout` was not, and the same
# root therefore normalised on one channel and not the other.
#
# A root holding a newline is still not representable — the rule transport
# below is line-oriented — and no directory this harness has met has one.
#
# EACH ROOT CONTRIBUTES BOTH OF ITS SPELLINGS, under one token. A root is
# learned here by `cd <path> && pwd`, which keeps whatever symlinks the caller
# spelled, while the arms report roots that have been through `realpath` or
# `getcwd` and carry none. The two strings are one directory playing one role,
# so a second token would only move the divergence onto the arm that spells it
# the other way. They join the same length ordering, because either can nest
# inside the other.
rootrules() {
  for _rr_pair in "$@"; do
    _rr_tok=${_rr_pair%%=*}
    _rr_path=${_rr_pair#*=}
    [ -n "$_rr_path" ] || continue
    for _rr_one in "$_rr_path" "$(physical "$_rr_path")"; do
      [ -n "$_rr_one" ] || continue
      printf '%s\t%s\t%s\n' "${#_rr_one}" "$_rr_tok" "$_rr_one"
    done
  done | sort -k1,1nr | awk '!seen[$0]++' \
  | while IFS="$(printf '\t')" read -r _rr_len _rr_tok _rr_path; do
    printf 's#%s#%s#g\n' \
      "$(printf '%s' "$_rr_path" | sed 's,[][\.*+?(){}|^$#],\\&,g')" "$_rr_tok"
  done
}

# norm <arm-tree-root> <arm-resolved-tree-root> <arm-working-directory>
#      <arm-scratch-root> <source-root>
#
# The root strings are substituted FIRST and by exact text, because they are
# the ones that legitimately differ between two arms of the same comparison.
# Everything after them is a pattern rule that applies to both arms
# identically.
#
# The SOURCE ROOT is not arm-owned — it is the one tree both arms read subjects
# out of — and it takes the SAME token as the arm root because a path quoted in
# a diagnostic names one role either way: the tree it was resolved out of. It
# was absent here, so the arm that happened to be rooted at the source tree
# normalised every quoted subject path and the other arm did not.
norm() {
  _norm_root=$1
  _norm_realroot=$2
  _norm_cwd=$3
  _norm_scratch=$4
  _norm_source=$5
  sed -E -e "$(rootrules "CWD=$_norm_cwd" "SCRATCH=$_norm_scratch" \
                         "TREE=$_norm_root" "TREE=$_norm_realroot" \
                         "TREE=$_norm_source")" \
         -e 's/\([0-9]+ ms/(MS/' \
         -e 's#/Volumes/.*/tmp-[A-Za-z0-9_-]+/#TREE/#g' \
         -e 's#duo_[A-Za-z0-9_]+_[0-9a-f]{6,}_[0-9]+#DUOTMP#g' \
         -e 's#^.*\(cached\)$#COMPILED#' \
         -e 's#^  ok compile.*#COMPILED#'
}

# STDOUT gets the root substitutions and NOTHING ELSE. The pattern rules in
# `norm` describe compiler diagnostics; a program's own output is the thing
# being compared and must not be reshaped. But the working directory and the
# scratch root name THIS ARM'S PRIVATE DIRECTORIES, which exist only for this
# run, so a program that prints one of them is printing the harness, not a
# difference.
#
#   `examples/shc/cwd.id` is the whole reason. Its body is `stdout:write(os.cwd)`
#   and each arm gets its own directory by design, so it was carried as a
#   PERMANENT false row that every reader had to know about and subtract by
#   hand. A row a reader must remember to ignore is a row that will one day be
#   ignored when it is real.
#
#   The tree roots are here for the same reason and the source root with them:
#   a program that prints where it was READ FROM prints one string on both arms
#   and a program that prints where its COMPILER lives prints two, and only the
#   second is a difference. Both are the harness either way.
#
# `-E`, the SAME DIALECT `norm` reads the same rules in. `rootrules` escapes a
# root for ERE, where `\+` is a literal plus; GNU BRE reads `\+` as a
# quantifier, so this ran the same rule as a different regex and a root holding
# a metacharacter normalised on stderr and survived on stdout — one channel
# repaired, one channel red, from one rule.
normout() {
  _no_root=$1
  _no_realroot=$2
  _no_cwd=$3
  _no_scratch=$4
  _no_source=$5
  sed -E -e "$(rootrules "CWD=$_no_cwd" "SCRATCH=$_no_scratch" \
                      "TREE=$_no_root" "TREE=$_no_realroot" \
                      "TREE=$_no_source")"
}

# The tree an arm's compiler resolves its lib/ from. `detectCompilerLibRoot`
# (src/main.zig) walks bin/ -> zig-out/ -> repo, so that is what a diagnostic
# from this arm will quote. A binary somewhere else owns only its directory.
#
# This answers for the binary AS SPELLED. That is the argv[0] the arm is handed
# and therefore a string it can print, but it is NOT the tree the arm resolves
# its lib/ from when the binary is a symlink — see `armrootreal`.
armroot() {
  _ar_bin=$1
  _ar_dir=$(cd "$(dirname "$_ar_bin")" && pwd)
  case "$_ar_dir" in
    */zig-out/bin) (cd "$_ar_dir/../.." && pwd) ;;
    *) printf '%s' "$_ar_dir" ;;
  esac
}

# armrootreal <arm-binary> — the same root derived the way the ARM derives it:
# from the binary with its symlinks resolved, leaf included.
#
# When the binary is not a symlink this equals `armroot` (or its physical
# spelling, which `rootrules` derives anyway) and the duplicate rule is
# collapsed there. When it IS a symlink the two are different directories and
# only this one appears in the arm's diagnostics.
#
# Answers NOTHING when the path does not resolve, so a rule is contributed only
# for a root that exists — the same discipline `physical` keeps.
armrootreal() {
  _arr_exe=$(physicalfile "$1")
  [ -n "$_arr_exe" ] || return 0
  armroot "$_arr_exe"
}

hash256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

# Print one tab-separated record:
#   event  status  stdout-path  normalized-stderr-path
# The caller owns all four paths. The child is never invoked a second time to
# recover another observation.
observe() {
  _obs_tag=$1
  _obs_cwd=$2
  _obs_bin=$3
  _obs_subject=$4
  _obs_record=$5
  _obs_root=$6
  _obs_realroot=$7
  _obs_scratch=$8
  _obs_source=$9
  _obs_event="$WORK/$_obs_tag.event"
  _obs_stdout_raw="$WORK/$_obs_tag.stdout.raw"
  _obs_stdout="$WORK/$_obs_tag.stdout"
  _obs_stderr_raw="$WORK/$_obs_tag.stderr.raw"
  _obs_stderr="$WORK/$_obs_tag.stderr"
  rm -f "$_obs_event" "$_obs_stdout_raw" "$_obs_stdout" "$_obs_stderr_raw" "$_obs_stderr"
  (
    cd "$_obs_cwd" || exit 125
    TMPDIR="$_obs_scratch"
    export TMPDIR
    perl "$LIMITER" "$TMO" "$_obs_event" \
      "$_obs_bin" run "$_obs_subject" </dev/null >"$_obs_stdout_raw" 2>"$_obs_stderr_raw"
  )
  _obs_status=$?
  if [ ! -s "$_obs_event" ]; then
    printf 'missing\t%s\t%s\t%s\n' "$_obs_status" "$_obs_stdout_raw" "$_obs_stderr" >"$_obs_record"
    return
  fi
  _obs_kind=$(sed -n '1p' "$_obs_event")
  normout "$_obs_root" "$_obs_realroot" "$_obs_cwd" "$_obs_scratch" "$_obs_source" \
    <"$_obs_stdout_raw" >"$_obs_stdout"
  norm "$_obs_root" "$_obs_realroot" "$_obs_cwd" "$_obs_scratch" "$_obs_source" \
    <"$_obs_stderr_raw" >"$_obs_stderr"
  printf '%s\t%s\t%s\t%s\n' "$_obs_kind" "$_obs_status" "$_obs_stdout" "$_obs_stderr" >"$_obs_record"
}

compare_subjects() {
  _cmp_base=$1
  _cmp_cand=$2
  _cmp_list=$3
  _cmp_source=$4

  for _cmp_bin in "$_cmp_base" "$_cmp_cand"; do
    [ -x "$_cmp_bin" ] || {
      echo "differential: not executable: $_cmp_bin" >&2
      return 2
    }
  done

  _cmp_base_hash=$(hash256 "$_cmp_base") || return 2
  _cmp_cand_hash=$(hash256 "$_cmp_cand") || return 2
  if [ "${NULL_CONTROL:-0}" = 1 ]; then
    # The guard is INVERTED here, not waived. A null control whose arms are
    # not the same bytes proves nothing at all, and it is exactly the mistake
    # this mode exists to catch elsewhere.
    [ "$_cmp_base_hash" = "$_cmp_cand_hash" ] || {
      echo "differential: null control arms differ ($_cmp_base_hash vs $_cmp_cand_hash)" >&2
      return 2
    }
  else
    [ "$_cmp_base_hash" != "$_cmp_cand_hash" ] || {
      echo "differential: both arms are the same binary ($_cmp_base_hash)" >&2
      return 2
    }
  fi
  printf 'differential: base sha256 %s\n' "$_cmp_base_hash"
  printf 'differential: candidate sha256 %s\n' "$_cmp_cand_hash"

  _cmp_a="$WORK/base.cwd"
  _cmp_b="$WORK/candidate.cwd"
  mkdir -p "$_cmp_a" "$_cmp_b" || return 2
  # Each arm's own tree root, and each arm's own scratch root. The first is
  # what its diagnostics quote; the second is where its build cache,
  # intermediate objects and emitted C live. Neither may leak into the other
  # arm's observation.
  _cmp_aroot=$(armroot "$_cmp_base")
  _cmp_broot=$(armroot "$_cmp_cand")
  # ...and the root each arm will actually quote, which is derived from the
  # binary with its symlinks resolved rather than from the path it was spelled
  # by. Reported separately when the two differ, because a reader deciding
  # whether to believe a row needs to see that an arm is a symlink into some
  # other tree — the harness cannot tell them apart from the caller's spelling.
  _cmp_areal=$(armrootreal "$_cmp_base")
  _cmp_breal=$(armrootreal "$_cmp_cand")
  _cmp_atmp="$WORK/base.scratch"
  _cmp_btmp="$WORK/candidate.scratch"
  mkdir -p "$_cmp_atmp" "$_cmp_btmp" || return 2
  printf 'differential: base tree %s\n' "$_cmp_aroot"
  [ "$_cmp_areal" = "$_cmp_aroot" ] || \
    printf 'differential: base tree resolves to %s\n' "$_cmp_areal"
  printf 'differential: candidate tree %s\n' "$_cmp_broot"
  [ "$_cmp_breal" = "$_cmp_broot" ] || \
    printf 'differential: candidate tree resolves to %s\n' "$_cmp_breal"

  _cmp_changed=0
  _cmp_identical=0
  _cmp_infra=0
  _cmp_seen=0
  while IFS= read -r _cmp_rel || [ -n "$_cmp_rel" ]; do
    [ -n "$_cmp_rel" ] || continue
    _cmp_subject="$_cmp_source/$_cmp_rel"
    if [ ! -f "$_cmp_subject" ]; then
      printf '%s infrastructure: subject absent\n' "$_cmp_rel" >&2
      _cmp_infra=$((_cmp_infra + 1))
      continue
    fi
    _cmp_seen=$((_cmp_seen + 1))

    _cmp_ar="$WORK/base.$_cmp_seen.record"
    _cmp_br="$WORK/candidate.$_cmp_seen.record"
    observe "base.$_cmp_seen" "$_cmp_a" "$_cmp_base" "$_cmp_subject" "$_cmp_ar" \
      "$_cmp_aroot" "$_cmp_areal" "$_cmp_atmp" "$_cmp_source"
    observe "candidate.$_cmp_seen" "$_cmp_b" "$_cmp_cand" "$_cmp_subject" "$_cmp_br" \
      "$_cmp_broot" "$_cmp_breal" "$_cmp_btmp" "$_cmp_source"
    IFS="$(printf '\t')" read -r _cmp_ak _cmp_arc _cmp_ao _cmp_ae <"$_cmp_ar"
    IFS="$(printf '\t')" read -r _cmp_bk _cmp_brc _cmp_bo _cmp_be <"$_cmp_br"

    case "$_cmp_ak" in
      ok|signal:*) : ;;
      *)
        printf '%s infrastructure base-event:%s status:%s\n' \
          "$_cmp_rel" "$_cmp_ak" "$_cmp_arc" >&2
        _cmp_infra=$((_cmp_infra + 1))
        continue
        ;;
    esac
    case "$_cmp_bk" in
      ok|signal:*) : ;;
      *)
        printf '%s infrastructure candidate-event:%s status:%s\n' \
          "$_cmp_rel" "$_cmp_bk" "$_cmp_brc" >&2
        _cmp_infra=$((_cmp_infra + 1))
        continue
        ;;
    esac

    if [ "$_cmp_ak" = "$_cmp_bk" ] && \
       [ "$_cmp_arc" = "$_cmp_brc" ] && \
       cmp -s "$_cmp_ao" "$_cmp_bo" && \
       cmp -s "$_cmp_ae" "$_cmp_be"; then
      _cmp_identical=$((_cmp_identical + 1))
    else
      _cmp_changed=$((_cmp_changed + 1))
      printf '%s CHANGED event:%s->%s status:%s->%s\n' \
        "$_cmp_rel" "$_cmp_ak" "$_cmp_bk" "$_cmp_arc" "$_cmp_brc"
    fi
  done <"$_cmp_list"

  _cmp_measured=$((_cmp_changed + _cmp_identical))
  printf 'differential: compared %s — changed %s, identical %s, infrastructure %s (subjects %s)\n' \
    "$_cmp_measured" "$_cmp_changed" "$_cmp_identical" "$_cmp_infra" "$_cmp_seen"
  [ "$_cmp_seen" -gt 0 ] || {
    echo "differential: zero subjects examined — vacuous" >&2
    return 2
  }
  [ "$_cmp_infra" -eq 0 ] || return 2
  [ "$_cmp_changed" -eq 0 ] || return 1
  [ "$_cmp_measured" -eq "$_cmp_seen" ] || return 2

  [ "$(hash256 "$_cmp_base")" = "$_cmp_base_hash" ] || {
    echo "differential: base compiler moved during measurement" >&2
    return 2
  }
  [ "$(hash256 "$_cmp_cand")" = "$_cmp_cand_hash" ] || {
    echo "differential: candidate compiler moved during measurement" >&2
    return 2
  }
  return 0
}

selftest() {
  _self="$WORK/selftest"

  # THE HARNESS'S OWN SCRATCH, FIRST, because every fixture below is built
  # inside it and every arm below is handed directories derived from it. If
  # `$WORK` is spelled through a symlink then the working directory and scratch
  # root given to each arm are strings no arm reports back, `git` answers about
  # the fixtures in the other spelling, and the controls that follow measure
  # the wrong thing — the worktree control fails outright and the cwd control
  # passes only because `/bin/sh`'s `pwd` is as logical as the harness is.
  [ -n "$WORK" ] && [ "$WORK" = "$(physical "$WORK")" ] || {
    echo "differential: selftest FAIL — the harness scratch root is not its physical spelling" >&2
    return 1
  }

  # ---------------------------------------------------------------------
  # THE SIBLING RESOLVER'S OWN CONTROLS. Everything below this block is a
  # control over the COMPARISON; these are controls over whether the harness
  # can be reached at all, and for as long as this file existed it could not
  # be reached from a git worktree. A resolver with no control answers
  # whatever the first host it ran on happened to be laid out as, and the
  # failure is silent in the optimistic direction: the oracle declines, and
  # the declining reads as a checkout fact rather than as an unmeasured law.

  # A DECOY, above every fixture below and belonging to none of them. Two of
  # the controls here answer "nothing found", and "nothing found" is a claim
  # about a search, not about an empty disk — with no decoy present they hold
  # for a resolver that walks the whole way to `/`, which is the one shape
  # that would silently compare against some unrelated checkout.
  mkdir -p "$WORK/idol-native/gate" || return 2
  : >"$WORK/idol-native/gate/run_limited.pl"

  # A PLAIN SIBLING. A clone, or a mirror copy with no git at all, which is
  # the layout the rest of this harness is written to survive.
  _self_res="$WORK/resolve"
  mkdir -p "$_self_res/idol-native/gate" "$_self_res/idol" || return 2
  : >"$_self_res/idol-native/gate/run_limited.pl"
  [ "$(nativelimiter "$_self_res/idol")" \
    = "$_self_res/idol-native/gate/run_limited.pl" ] || {
    echo "differential: selftest FAIL — plain sibling checkout not resolved" >&2
    return 1
  }

  # NO SIBLING ANYWHERE must answer nothing, so the caller prints the
  # candidates it tried instead of one path it invented. Its own directory:
  # a tree placed beside the fixture above would resolve THAT sibling and the
  # control would pass for the wrong reason.
  mkdir -p "$WORK/lonely/idol" || return 2
  [ -z "$(nativelimiter "$WORK/lonely/idol")" ] || {
    echo "differential: selftest FAIL — resolver invented a sibling that is not there" >&2
    return 1
  }

  # THE DEFECT ITSELF. A worktree at <main>/.worktrees/<name>, whose own
  # `..` is `.worktrees`, and whose sibling is one level further up.
  if command -v git >/dev/null 2>&1; then
    _self_wt="$WORK/worktree"
    mkdir -p "$_self_wt/idol-native/gate" "$_self_wt/idol" || return 2
    : >"$_self_wt/idol-native/gate/run_limited.pl"
    (
      cd "$_self_wt/idol" &&
        git init -q . &&
        git -c user.email=selftest@differential -c user.name=selftest \
          commit -q --allow-empty -m control &&
        git worktree add -q -b differential-selftest .worktrees/w
    ) >/dev/null 2>&1 || {
      echo "differential: selftest FAIL — could not build the worktree control" >&2
      return 1
    }
    [ "$(nativelimiter "$_self_wt/idol/.worktrees/w")" \
      = "$_self_wt/idol-native/gate/run_limited.pl" ] || {
      echo "differential: selftest FAIL — sibling unresolved from a git worktree" >&2
      return 1
    }
    # ...AND THE SEARCH MUST NOT REACH PAST A TREE THAT HAS NO SIBLING. The
    # main checkout is a candidate because a worktree is not its own root, not
    # because any ancestor will do; a resolver that walked upward would find
    # some unrelated `idol-native` on a developer's disk and compare against it.
    rm -rf "$_self_wt/idol-native" || return 2
    [ -z "$(nativelimiter "$_self_wt/idol/.worktrees/w")" ] || {
      echo "differential: selftest FAIL — resolver reached past the main checkout" >&2
      return 1
    }
  else
    echo "differential: selftest NOTE — git absent, worktree resolution UNCONTROLLED" >&2
  fi

  mkdir -p "$_self/source" || return 2
  printf 'main: i64 = ()\n  0\n' >"$_self/source/control.id"
  printf 'control.id\n' >"$_self/list"

  # ---------------------------------------------------------------------
  # SIBLING MIRROR ROOTS. Two arms in two different trees, each quoting its
  # OWN root in a diagnostic exactly as a real compiler does — that is what
  # `detectCompilerLibRoot` makes every arm do. Before per-arm normalisation
  # this pair was scored CHANGED, and on the real corpus that shape produced
  # ~163 false rows. It must now be identical.
  mkdir -p "$_self/mirror/a/zig-out/bin" "$_self/mirror/b/zig-out/bin" || return 2
  # The diagnostic shape matters. `norm` already collapses a whole line that
  # begins "  ok compile", so a fake that emitted only that line would be
  # normalised to COMPILED and this control would pass without the per-arm
  # rule ever running. Emit the root inside a line no other rule touches.
  _self_mirror='#!/bin/sh
root=$(cd "$(dirname "$0")/../.." && pwd)
printf "answer\n"
printf "error: cannot open %s/lib/std.id\n" "$root" >&2
printf "note: scratch at %s\n" "${TMPDIR:-/tmp}" >&2
exit 0
'
  printf '%s' "$_self_mirror" >"$_self/mirror/a/zig-out/bin/idol"
  printf '%s' "$_self_mirror" >"$_self/mirror/b/zig-out/bin/idol"
  chmod +x "$_self/mirror/a/zig-out/bin/idol" "$_self/mirror/b/zig-out/bin/idol"
  NULL_CONTROL=1 compare_subjects \
    "$_self/mirror/a/zig-out/bin/idol" "$_self/mirror/b/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — sibling mirror roots scored as a difference" >&2
    return 1
  }

  # THE `examples/shc/cwd.id` SHAPE: a program whose entire output is its own
  # working directory. Each arm has its own by construction, so this is a
  # harness fact and must not be a row.
  #
  # BOTH SPELLINGS. `pwd` alone is what the shell was handed and would agree
  # with the harness even when the harness is wrong; `pwd -P` is `getcwd`, which
  # is what `os.cwd` in a compiled program actually reduces to. Only the second
  # can convict a working directory whose spelling reaches the arm through a
  # symlink, and it convicts nothing unless `$TMPDIR` has one — which is why the
  # scratch-root control above is unconditional.
  mkdir -p "$_self/cwd/a/zig-out/bin" "$_self/cwd/b/zig-out/bin" || return 2
  _self_cwd='#!/bin/sh
pwd
pwd -P
'
  printf '%s' "$_self_cwd" >"$_self/cwd/a/zig-out/bin/idol"
  printf '%s\n# b\n' "$_self_cwd" >"$_self/cwd/b/zig-out/bin/idol"
  chmod +x "$_self/cwd/a/zig-out/bin/idol" "$_self/cwd/b/zig-out/bin/idol"
  compare_subjects "$_self/cwd/a/zig-out/bin/idol" "$_self/cwd/b/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — per-arm working directory scored as a difference" >&2
    return 1
  }

  # ...AND THE NORMALISER MUST NOT EAT A REAL DIFFERENCE THAT HAPPENS TO
  # CONTAIN A PATH. Same two roots, different diagnostic text. If per-arm
  # substitution were written loosely enough to erase this, every genuine
  # diagnostic regression would go unreported — the optimistic direction, and
  # the one that costs the most.
  mkdir -p "$_self/mirror/c/zig-out/bin" || return 2
  printf '%s' "$_self_mirror" | sed 's#cannot open#REFUSED, cannot open#' \
    >"$_self/mirror/c/zig-out/bin/idol"
  chmod +x "$_self/mirror/c/zig-out/bin/idol"
  compare_subjects "$_self/mirror/a/zig-out/bin/idol" \
    "$_self/mirror/c/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — per-arm normalisation erased a real row" >&2
    return 1
  }

  # ---------------------------------------------------------------------
  # AN ARM ROOTED AT THE SUBJECT SOURCE ROOT. The ordinary arrangement — a
  # tree that builds its own compiler into `zig-out/` and supplies its own
  # subjects, compared against a compiler that lives somewhere else. Both arms
  # are handed the SAME subject path out of that one tree, so a diagnostic
  # quoting it prints ONE string on both arms; before the source root was
  # normalised, the in-tree arm substituted that string as its own root and
  # the other arm left it absolute, and every such row scored CHANGED.
  #
  # `--null-control` cannot reach this shape. It copies BOTH arms under
  # `$WORK/null.a` and `$WORK/null.b` while the source stays `$ROOT`, so
  # neither arm is ever rooted at the source root and the collision cannot
  # arise in it. The instrument a reader uses to decide whether to believe a
  # row is blind here, so the control has to live in `selftest`.
  #
  # The fake quotes the subject it was handed AND its own lib root, because
  # the two are the whole difficulty: on the in-tree arm they are the same
  # string playing two roles, and both must land on the same token as the
  # other arm's.
  _self_quote='#!/bin/sh
root=$(cd "$(dirname "$0")/../.." && pwd)
printf "answer\n"
printf "error: cannot open %s\n" "$2" >&2
printf "note: lib root %s/lib/std.id\n" "$root" >&2
exit 0
'
  mkdir -p "$_self/insitu/zig-out/bin" "$_self/away/zig-out/bin" || return 2
  printf 'main: i64 = ()\n  0\n' >"$_self/insitu/control.id"
  printf 'control.id\n' >"$_self/insitu.list"
  printf '%s' "$_self_quote" >"$_self/insitu/zig-out/bin/idol"
  printf '%s\n# away\n' "$_self_quote" >"$_self/away/zig-out/bin/idol"
  chmod +x "$_self/insitu/zig-out/bin/idol" "$_self/away/zig-out/bin/idol"
  compare_subjects "$_self/insitu/zig-out/bin/idol" \
    "$_self/away/zig-out/bin/idol" \
    "$_self/insitu.list" "$_self/insitu" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — the subject source root scored as a difference" >&2
    return 1
  }

  # ...AND A MIRROR NESTED INSIDE THE SOURCE TREE. `<nest>/mirror` is a longer
  # root than `<nest>`, and the roots are substituted longest first for exactly
  # this: in the other order the source rule eats the head of the mirror arm's
  # own lib path and leaves a `/mirror/` segment behind that the other arm's
  # lib path does not have, and the row is red for the harness's reason again.
  mkdir -p "$_self/nest/mirror/zig-out/bin" "$_self/faraway/zig-out/bin" || return 2
  printf 'main: i64 = ()\n  0\n' >"$_self/nest/control.id"
  printf 'control.id\n' >"$_self/nest.list"
  printf '%s' "$_self_quote" >"$_self/nest/mirror/zig-out/bin/idol"
  printf '%s\n# faraway\n' "$_self_quote" >"$_self/faraway/zig-out/bin/idol"
  chmod +x "$_self/nest/mirror/zig-out/bin/idol" "$_self/faraway/zig-out/bin/idol"
  compare_subjects "$_self/nest/mirror/zig-out/bin/idol" \
    "$_self/faraway/zig-out/bin/idol" \
    "$_self/nest.list" "$_self/nest" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — a mirror nested in the source tree scored as a difference" >&2
    return 1
  }

  # ---------------------------------------------------------------------
  # AN ARM REACHED THROUGH A SYMLINK. `armroot` learns a root by `cd && pwd`,
  # which keeps the spelling it was handed; `detectCompilerLibRoot` resolves
  # argv[0] with `realpath` before it derives the lib root, so the arm quotes
  # the spelling with the symlink GONE. The harness then substitutes a string
  # that never appears and leaves the one that does, so every diagnostic
  # quoting the compiler's own tree came out different on that arm alone —
  # the same false-row class as the two-mirror and source-root defects, and
  # measured as one CHANGED row on the fixture below before this control.
  #
  # `--null-control` cannot see it either: it copies both arms into `$WORK`
  # and reaches them by the path it just built, so no symlink is ever between
  # a caller and an arm in it.
  #
  # The fake resolves its own root physically, which is what the realpath in
  # `detectCompilerLibRoot` amounts to for a shell.
  _self_deref='#!/bin/sh
root=$(cd "$(dirname "$0")/../.." && pwd -P)
printf "answer\n"
printf "error: cannot open %s/lib/std.id\n" "$root" >&2
exit 0
'
  mkdir -p "$_self/sym/real/zig-out/bin" "$_self/sym/away/zig-out/bin" || return 2
  ln -s "$_self/sym/real" "$_self/sym/link" || return 2
  printf '%s' "$_self_deref" >"$_self/sym/real/zig-out/bin/idol"
  printf '%s\n# away\n' "$_self_deref" >"$_self/sym/away/zig-out/bin/idol"
  chmod +x "$_self/sym/real/zig-out/bin/idol" "$_self/sym/away/zig-out/bin/idol"
  compare_subjects "$_self/sym/link/zig-out/bin/idol" \
    "$_self/sym/away/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — an arm reached through a symlink scored as a difference" >&2
    return 1
  }

  # ...AND THE SECOND SPELLING MUST NOT EAT A REAL ROW EITHER. Two rules per
  # root instead of one is two more chances to erase a difference, and the
  # erasure would be silent and optimistic. Same symlinked arm, different
  # diagnostic text.
  mkdir -p "$_self/sym/other/zig-out/bin" || return 2
  printf '%s' "$_self_deref" | sed 's#cannot open#REFUSED, cannot open#' \
    >"$_self/sym/other/zig-out/bin/idol"
  chmod +x "$_self/sym/other/zig-out/bin/idol"
  compare_subjects "$_self/sym/link/zig-out/bin/idol" \
    "$_self/sym/other/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — the physical-spelling rule erased a real row" >&2
    return 1
  }

  # ---------------------------------------------------------------------
  # AN ARM WHOSE BINARY IS ITSELF A SYMLINK. The control above puts a symlink
  # on the PATH TO an arm, and `physical` resolves it because `cd` resolves
  # directories. `cd` walks to the leaf and stops: it can never resolve the
  # FILE. The arm does not stop there — `detectCompilerLibRoot` realpaths
  # argv[0] itself — so an arm whose binary is a symlink into another tree
  # quotes THAT tree, and the harness substitutes the tree the symlink lives
  # in. Not a second spelling of one directory this time: two directories, so
  # the rule that fixed the last class cannot reach this one.
  #
  # It is the ordinary way a reference compiler is kept. An installed `idol` on
  # PATH is a symlink into the tree that built it, and comparing it against a
  # fresh build is the first differential anyone runs.
  #
  # `--null-control` is blind twice: `cp` FOLLOWS the symlink and lands a real
  # file under a root the mode built itself, and the mode refuses a binary with
  # no `<tree>/lib/std.id` beside it, which is what a symlink alone looks like.
  #
  # The fake resolves argv[0] as a FILE, which is what the realpath in
  # `detectCompilerLibRoot` amounts to; `readlink` in a loop, not `readlink -f`,
  # because -f is absent on the platform this file's provenance comes from.
  _self_exelink='#!/bin/sh
exe=$0
while [ -L "$exe" ]; do exe=$(readlink "$exe"); done
root=$(cd "$(dirname "$exe")/../.." && pwd -P)
printf "answer\n"
printf "error: cannot open %s/lib/std.id\n" "$root" >&2
exit 0
'
  mkdir -p "$_self/exe/real/zig-out/bin" "$_self/exe/link/zig-out/bin" \
           "$_self/exe/away/zig-out/bin" || return 2
  printf '%s' "$_self_exelink" >"$_self/exe/real/zig-out/bin/idol"
  printf '%s\n# away\n' "$_self_exelink" >"$_self/exe/away/zig-out/bin/idol"
  chmod +x "$_self/exe/real/zig-out/bin/idol" "$_self/exe/away/zig-out/bin/idol"
  ln -s "$_self/exe/real/zig-out/bin/idol" "$_self/exe/link/zig-out/bin/idol" || return 2
  # THE PAIR WITHOUT THE SYMLINK FIRST. Otherwise "identical" below could be
  # bought by the fake being blind to its own root rather than by the harness
  # having resolved it, and the control would pass for a reason it does not
  # name. These are the same two binaries reached two ways.
  compare_subjects "$_self/exe/real/zig-out/bin/idol" \
    "$_self/exe/away/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — two plain sibling arms scored as a difference" >&2
    return 1
  }
  compare_subjects "$_self/exe/link/zig-out/bin/idol" \
    "$_self/exe/away/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — an arm whose binary is a symlink scored as a difference" >&2
    return 1
  }

  # ...AND THE RESOLVED ROOT MUST NOT EAT A REAL ROW EITHER. A third rule per
  # arm is a third chance to erase a difference, and the erasure would be
  # silent and optimistic. Same symlinked arm, different diagnostic text.
  mkdir -p "$_self/exe/other/zig-out/bin" || return 2
  printf '%s' "$_self_exelink" | sed 's#cannot open#REFUSED, cannot open#' \
    >"$_self/exe/other/zig-out/bin/idol"
  chmod +x "$_self/exe/other/zig-out/bin/idol"
  compare_subjects "$_self/exe/link/zig-out/bin/idol" \
    "$_self/exe/other/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — the resolved-binary rule erased a real row" >&2
    return 1
  }

  # ---------------------------------------------------------------------
  # ROOTS THAT ARE REGEX METACHARACTERS. Every root above is derived
  # correctly and then handed to `sed` as the LEFT SIDE OF A REGEX. A
  # directory name may hold any of `. [ ] { } ( ) * + ? ^ $ |`, and each one
  # makes the rule mean something other than the root it was built from —
  # `+` a quantifier that never matches its own root, `.` any character so the
  # rule erases MORE than the root, `(` unbalanced so `sed` refuses the whole
  # expression, writes nothing, and both arms compare an empty stderr equal.
  #
  # This is the harness's own scratch on macOS, where `$TMPDIR` is
  # `/var/folders/<2>/<base64ish>/T/` and `+` is in base64's alphabet. It is
  # also any checkout a developer parked under such a name.
  #
  # BOTH CHANNELS. The fake quotes its root on stdout AND stderr, because the
  # two are normalised by different functions reading the SAME rules, and an
  # ERE-escaped rule is a different regex in BRE — `\+` is a literal plus in
  # one and a quantifier in the other. A control on stderr alone passes for a
  # `normout` that is silently reading the rules in the other dialect.
  _self_meta='#!/bin/sh
root=$(cd "$(dirname "$0")/../.." && pwd)
printf "answer from %s/lib\n" "$root"
printf "error: cannot open %s/lib/std.id\n" "$root" >&2
exit 0
'
  _self_ma="$_self/meta/a+b.c(d[e\$f"
  _self_mb="$_self/meta/g*h?i|j{k}^l"
  mkdir -p "$_self_ma/zig-out/bin" "$_self_mb/zig-out/bin" || return 2
  printf '%s' "$_self_meta" >"$_self_ma/zig-out/bin/idol"
  printf '%s' "$_self_meta" >"$_self_mb/zig-out/bin/idol"
  chmod +x "$_self_ma/zig-out/bin/idol" "$_self_mb/zig-out/bin/idol"
  NULL_CONTROL=1 compare_subjects \
    "$_self_ma/zig-out/bin/idol" "$_self_mb/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — a metacharacter in an arm root scored as a difference" >&2
    return 1
  }

  # ...AND ESCAPING MUST NOT EAT A REAL ROW, ON EITHER CHANNEL. Escaping is one
  # more chance to erase a difference, and the `(` shape erases EVERY row on
  # the channel by making `sed` refuse the expression outright, write nothing,
  # and hand both arms an empty file to compare — silent, and in the optimistic
  # direction. Same metacharacter roots, different text.
  #
  # ONE FIXTURE PER CHANNEL, because a row erased on both arms of one channel
  # is invisible to a control whose difference lives on the other. The null row
  # above cannot see this class at all for the same reason: equal erasure reads
  # as equality. The stdout fixture is what convicts a `normout` reading the
  # rules in the wrong dialect, which the null row and the stderr fixture both
  # score green.
  _self_mc="$_self/meta/m+n.o(p[q\$r"
  _self_md="$_self/meta/s+t.u(v[w\$x"
  mkdir -p "$_self_mc/zig-out/bin" "$_self_md/zig-out/bin" || return 2
  printf '%s' "$_self_meta" | sed 's#cannot open#REFUSED, cannot open#' \
    >"$_self_mc/zig-out/bin/idol"
  printf '%s' "$_self_meta" | sed 's#answer from#ANSWER, from#' \
    >"$_self_md/zig-out/bin/idol"
  chmod +x "$_self_mc/zig-out/bin/idol" "$_self_md/zig-out/bin/idol"
  compare_subjects "$_self_ma/zig-out/bin/idol" \
    "$_self_mc/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — the metacharacter escaping erased a real stderr row" >&2
    return 1
  }
  compare_subjects "$_self_ma/zig-out/bin/idol" \
    "$_self_md/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — the metacharacter escaping erased a real stdout row" >&2
    return 1
  }

  # Different bytes, one identical observation. Each fake records its own
  # invocation count; a future second-run stderr probe makes this control red.
  _self_fake='#!/bin/sh
count=$0.count
n=0
[ ! -f "$count" ] || n=$(sed -n "1p" "$count")
n=$((n + 1))
printf "%s\n" "$n" > "$count"
printf "answer\n"
printf "  ok compile (123 ms — /Volumes/d 1/tmp-self/base.out)\n" >&2
exit 7
'
  printf '%s\n# base\n' "$_self_fake" >"$_self/base"
  printf '%s\n# candidate\n' "$_self_fake" >"$_self/candidate"
  chmod +x "$_self/base" "$_self/candidate"

  compare_subjects "$_self/base" "$_self/candidate" \
    "$_self/list" "$_self/source" >/dev/null || return 1
  [ "$(sed -n '1p' "$_self/base.count")" = 1 ] || return 1
  [ "$(sed -n '1p' "$_self/candidate.count")" = 1 ] || return 1

  # Comparator damage: one candidate emits another value, and the differential
  # must turn red rather than merely print CHANGED and return success.
  sed 's/printf "answer\\n"/printf "damaged\\n"/' \
    "$_self/candidate" >"$_self/candidate.damaged"
  chmod +x "$_self/candidate.damaged"
  compare_subjects "$_self/base" "$_self/candidate.damaged" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || return 1

  # Zero-subject damage remains infrastructure, never a green comparison.
  : >"$_self/empty.list"
  compare_subjects "$_self/base" "$_self/candidate" \
    "$_self/empty.list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 2 ] || return 1

  # A normal exit 154 and signal 26 are distinct even though shells commonly
  # project both to status 154. This is the exact typed-oracle collision in
  # native_only/result_pack_pointer.id. The out-of-band event makes it changed
  # semantic observation rather than comparing the status integers equal.
  printf '#!/bin/sh\nexit 154\n# ordinary\n' >"$_self/exit154"
  printf '#!/bin/sh\nkill -26 $$\n# signal\n' >"$_self/signal26"
  printf '#!/bin/sh\nprintf partial\nkill -26 $$\n# partial signal\n' >"$_self/partial26"
  chmod +x "$_self/exit154" "$_self/signal26" "$_self/partial26"
  compare_subjects "$_self/exit154" "$_self/signal26" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || return 1
  compare_subjects "$_self/exit154" "$_self/partial26" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || return 1

  # Ordinary exit 124 remains an answer; watchdog 124 is infrastructure and
  # its private process group is reaped.
  printf '#!/bin/sh\nexit 124\n# ordinary\n' >"$_self/exit124"
  printf '#!/bin/sh\nsleep 10\n# timeout\n' >"$_self/timeout"
  chmod +x "$_self/exit124" "$_self/timeout"
  _self_old_tmo=$TMO
  TMO=1
  compare_subjects "$_self/exit124" "$_self/timeout" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  TMO=$_self_old_tmo
  [ "$_self_rc" -eq 2 ] || return 1

  echo "differential: selftest PASS — physical scratch root, sibling resolution from a plain checkout, from a git worktree, absent-sibling and no-walk-past-main, sibling-mirror null row, per-arm cwd in both spellings, real row survives normalisation, in-tree arm at the subject source root, mirror nested in the source tree, arm reached through a symlink and a real row surviving that, an arm whose binary is a symlink and a real row surviving that, regex metacharacters in an arm root on both channels and a real row surviving that on each, one observation, comparator damage, zero-subject, exit154/signal26/partial-output and exit124/timeout controls"
  return 0
}

# NULL CONTROL. One compiler, placed under two mirror roots, compared with
# itself over the real subject list. Every row it reports is harness noise, by
# construction: the machine code on the two arms is the same bytes. The two
# roots are DIFFERENT SPELLINGS because that is the condition being controlled
# for — a null control run from one root would exercise nothing.
#
# The copy is a copy and not a symlink on purpose: `detectCompilerLibRoot`
# calls realpath on argv[0], so a symlinked arm resolves back to the original
# tree and the mirror roots collapse into one. `lib` IS a symlink, because it
# is only opened by path and copying a stdlib per arm buys nothing.
null_control() {
  _nc_bin=$1
  _nc_list=$2
  _nc_source=$3
  _nc_home=$(cd "$(dirname "$_nc_bin")" && pwd)
  case "$_nc_home" in
    */zig-out/bin) _nc_home=$(cd "$_nc_home/../.." && pwd) ;;
    *)
      echo "differential: null control needs a compiler at <tree>/zig-out/bin/, got $_nc_bin" >&2
      return 2
      ;;
  esac
  [ -f "$_nc_home/lib/std.id" ] || {
    echo "differential: null control cannot find $_nc_home/lib/std.id" >&2
    return 2
  }
  for _nc_arm in a b; do
    mkdir -p "$WORK/null.$_nc_arm/zig-out/bin" || return 2
    cp "$_nc_bin" "$WORK/null.$_nc_arm/zig-out/bin/idol" || return 2
    ln -s "$_nc_home/lib" "$WORK/null.$_nc_arm/lib" || return 2
  done
  printf 'differential: NULL CONTROL — one compiler under two mirror roots\n'
  NULL_CONTROL=1 compare_subjects \
    "$WORK/null.a/zig-out/bin/idol" "$WORK/null.b/zig-out/bin/idol" \
    "$_nc_list" "$_nc_source"
  _nc_rc=$?
  if [ "$_nc_rc" -eq 0 ]; then
    printf 'differential: NULL CONTROL PASS — the harness reports zero rows for identical machine code\n'
  else
    printf 'differential: NULL CONTROL FAIL (status %s) — every row above is harness noise, and a real comparison on this list cannot be believed until it is zero\n' "$_nc_rc" >&2
  fi
  return $_nc_rc
}

WORK=$(mktemp -d) || exit 2
# PHYSICALLY SPELLED, before anything is built inside it. `mktemp -d` answers
# with `$TMPDIR` as spelled, and on macOS that is `/var/folders/...` with `/var`
# a symlink — so the per-arm working directories and scratch roots handed to the
# arms would be strings the arms never report back, and the selftest fixtures
# would be spelled one way here and another way by `git`. Owning the spelling is
# cheaper than substituting it twice everywhere it is later derived from.
WORKREAL=$(cd "$WORK" && pwd -P) || { rm -rf "$WORK"; exit 2; }
WORK=$WORKREAL
trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = "--selftest" ]; then
  selftest || {
    echo "differential: selftest FAIL" >&2
    exit 1
  }
  exit 0
fi

selftest || {
  echo "differential: mandatory controls FAIL" >&2
  exit 1
}

subjectlist() {
  # The default subject list. `find`, not `git ls-files`: this runs against a
  # mirror root that may be a plain copy, and an enumerator that answers zero
  # in such a tree is the GAP-220 failure. Zero here is still a failure — the
  # zero-subject guard in compare_subjects owns that — but it is reached
  # honestly.
  _sl_out=$1
  (cd "$ROOT" && find examples lib scripts -name '*.id' -type f 2>/dev/null | sort) >"$_sl_out"
  [ -s "$_sl_out" ] || {
    echo "differential: default subject list resolved to zero files under $ROOT" >&2
    return 2
  }
  return 0
}

if [ "${1:-}" = "--null-control" ]; then
  shift
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo "usage: gate/differential.sh --null-control <idol> [file-list]" >&2
    exit 2
  }
  [ -x "$1" ] || {
    echo "differential: compiler path absent or not executable: $1" >&2
    exit 2
  }
  NCBIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  if [ "$#" -eq 2 ]; then
    NCLIST=$2
    [ -r "$NCLIST" ] || {
      echo "differential: unreadable subject list: $NCLIST" >&2
      exit 2
    }
  else
    NCLIST="$WORK/subjects"
    subjectlist "$NCLIST" || exit 2
  fi
  null_control "$NCBIN" "$NCLIST" "$ROOT"
  exit $?
fi

if [ "$#" -eq 0 ]; then
  echo "differential: compiler comparison UNMEASURED — supply base and candidate"
  exit 0
fi
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
  echo "usage: gate/differential.sh <base-idol> <candidate-idol> [file-list]" >&2
  exit 2
}

[ -x "$1" ] && [ -x "$2" ] || {
  echo "differential: compiler path absent or not executable" >&2
  exit 2
}
BASE=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
CAND=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
if [ "$#" -eq 3 ]; then
  LIST=$3
else
  LIST="$WORK/subjects"
  subjectlist "$LIST" || exit 2
fi
[ -r "$LIST" ] || {
  echo "differential: unreadable subject list: $LIST" >&2
  exit 2
}

compare_subjects "$BASE" "$CAND" "$LIST" "$ROOT"
exit $?
