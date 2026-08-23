#!/bin/sh
# gate/admission-controls.sh — proves gate/admission.sh can actually reject.
#
# `gate/path.id` shipped for a long time unable to reject ANYTHING, and every
# commit "passed" it. A gate with no positive control is a decoration. This
# file drives the real gate/admission.sh -- the shipped constants, not a copy
# with the numbers relaxed -- in BOTH directions:
#
#   POSITIVE controls: a violating input MUST make the gate exit nonzero.
#   NEGATIVE controls: a lawful input MUST make the gate exit zero.
#
# A positive control that passes is itself a failure and is reported as one.
# Exit status is read directly from `if ! cmd`, never `$?` after a pipe.
#
# The synthetic trees below carry >= MIN_SUBJECTS .id files on purpose, so the
# budget arithmetic is exercised against the SHIPPED numbers rather than
# against a debug override. gate/admission.sh has no test hatch; there is no
# environment variable that relaxes it, because such a variable is the first
# thing a future evasion would reach for.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
gate="$here/admission.sh"
manifest="$here/std-fixtures.manifest"

[ -x "$gate" ] || { echo "control harness: $gate is not executable." >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0
fail=0

# expect_fail <label> <cmd...>
expect_fail() {
    label=$1; shift
    if "$@" >"$tmp/out.txt" 2>&1; then
        fail=$((fail + 1))
        printf 'POSITIVE CONTROL FAILED (gate accepted a violation): %s\n' "$label"
        sed 's/^/      | /' "$tmp/out.txt"
    else
        pass=$((pass + 1))
        printf '  ok  reject: %s\n' "$label"
    fi
}

# expect_pass <label> <cmd...>
expect_pass() {
    label=$1; shift
    if "$@" >"$tmp/out.txt" 2>&1; then
        pass=$((pass + 1))
        printf '  ok  admit:  %s\n' "$label"
    else
        fail=$((fail + 1))
        printf 'NEGATIVE CONTROL FAILED (gate rejected a lawful input): %s\n' "$label"
        sed 's/^/      | /' "$tmp/out.txt"
    fi
}

# make_tree <dir> <n_extra_files> <spellings_in_carrier>
# Builds a synthetic root that satisfies MIN_SUBJECTS and carries an exact
# number of canonical std. spellings in one non-fixture file.
make_tree() {
    d=$1; n=$2; k=$3
    mkdir -p "$d/gate" "$d/src"
    cp "$gate" "$d/gate/admission.sh"
    i=0
    while [ "$i" -lt "$n" ]; do
        printf 'main()\n  print("lawful %s")\n' "$i" >"$d/src/f$i.id"
        i=$((i + 1))
    done
    : >"$d/src/carrier.id"
    j=0
    while [ "$j" -lt "$k" ]; do
        printf 'x%s = std.io.open(p)\n' "$j" >>"$d/src/carrier.id"
        j=$((j + 1))
    done
    # A fixture, so the manifest is non-empty and exercised.
    printf 'flag(path, no, code, "std.script.", "host-TEMP", "frozen")\n' >"$d/gate/fixture.id"
    printf 'gate/fixture.id\t1\t# synthetic detector literal\n' >"$d/gate/std-fixtures.manifest"
}

echo "=== gate/admission.sh negative controls ==="
echo

# ---------------------------------------------------------------- REAL TREE --
echo "-- against the real tree --"
expect_pass "today's tree passes its own pinned census" \
    "$gate" --census-only

# --------------------------------------------------- ADDED-LINE RULE (diffs) --
echo
echo "-- added-line rule, driven by candidate diffs over the real tree --"

cat >"$tmp/lawful.diff" <<'EOF'
--- a/examples/lawful.id
+++ b/examples/lawful.id
@@ -1,0 +1,3 @@
+main()
+  data = path("in.txt"):read()
+  stdout:write(data)
EOF
expect_pass "lawful diff: world projections, no std spelling" \
    "$gate" --diff "$tmp/lawful.diff"

cat >"$tmp/violation.diff" <<'EOF'
--- a/examples/bad.id
+++ b/examples/bad.id
@@ -1,0 +1,2 @@
+main()
+  f = std.io.open("in.txt")
EOF
expect_fail "one added line reaching for std.io" \
    "$gate" --diff "$tmp/violation.diff"

cat >"$tmp/script.diff" <<'EOF'
--- a/scripts/bad.id
+++ b/scripts/bad.id
@@ -3,0 +4 @@
+  out = std.script.capture("echo hi")
EOF
expect_fail "one added line reaching for std.script" \
    "$gate" --diff "$tmp/script.diff"

# THE RULE THE BRIEF NAMES EXPLICITLY: net-negative is still a rejection.
{
    printf -- '--- a/scripts/migrating.id\n+++ b/scripts/migrating.id\n@@ -1,10 +1,10 @@\n'
    i=0
    while [ "$i" -lt 10 ]; do
        printf -- '-  x%s = std.io.open(p)\n' "$i"
        i=$((i + 1))
    done
    printf -- '+  x = path(p):read()\n'
    printf -- '+  y = std.io.open(q)\n'
} >"$tmp/net_negative.diff"
expect_fail "migration removing 10 std spellings and adding 1 (net -9) STILL fails" \
    "$gate" --diff "$tmp/net_negative.diff"

# Removal-only must be admitted, or the ratchet can never turn.
{
    printf -- '--- a/scripts/migrating.id\n+++ b/scripts/migrating.id\n@@ -1,10 +1,10 @@\n'
    i=0
    while [ "$i" -lt 10 ]; do
        printf -- '-  x%s = std.io.open(p)\n' "$i"
        i=$((i + 1))
    done
    printf -- '+  x = path(p):read()\n'
} >"$tmp/removal.diff"
expect_pass "removal-only migration (10 out, 0 in)" \
    "$gate" --diff "$tmp/removal.diff"

# `+++ ` is a diff header, not an added line. A gate that miscounts it fires
# on every diff and gets disabled within a week.
cat >"$tmp/header.diff" <<'EOF'
--- a/lib/std.id
+++ b/lib/std.id
@@ -1 +1,2 @@
 0
+1
EOF
expect_pass "diff header lines are not added lines" \
    "$gate" --diff "$tmp/header.diff"

# ------------------------------------------------------- SYNTHETIC CENSUS TREES --
echo
echo "-- census arithmetic, against the SHIPPED budget (473) --"

make_tree "$tmp/at_budget" 950 473
expect_pass "synthetic tree at exactly the budget (473)" \
    "$tmp/at_budget/gate/admission.sh" --census-only

make_tree "$tmp/over_budget" 950 474
expect_fail "synthetic tree one spelling OVER the budget (474)" \
    "$tmp/over_budget/gate/admission.sh" --census-only

# ------------------------------------------------------------- ZERO SUBJECTS --
echo
echo "-- GAP-201 / GAP-220: examining nothing must FAIL, not report clean --"

mkdir -p "$tmp/empty/gate"
cp "$gate" "$tmp/empty/gate/admission.sh"
cp "$manifest" "$tmp/empty/gate/std-fixtures.manifest"
expect_fail "zero .id subjects (empty tree, no .git) -> must fail (GAP-201)" \
    "$tmp/empty/gate/admission.sh" --census-only

# The exact GAP-220 shape: an archive mirror. `git ls-files` returns zero
# because there is no .git; the find fallback must catch it, and if the tree
# is genuinely short the floor must catch THAT.
mkdir -p "$tmp/mirror/gate" "$tmp/mirror/src"
cp "$gate" "$tmp/mirror/gate/admission.sh"
cp "$manifest" "$tmp/mirror/gate/std-fixtures.manifest"
printf 'main()\n  print("hi")\n' >"$tmp/mirror/src/one.id"
expect_fail "archive-mirror shape: 1 subject, under the floor -> must fail (GAP-220)" \
    "$tmp/mirror/gate/admission.sh" --census-only

# A no-.git tree may not silently skip the added-line rule.
make_tree "$tmp/nogit" 950 473
expect_fail "no .git and no --diff: added-line rule cannot be evaluated -> must fail" \
    "$tmp/nogit/gate/admission.sh"

# --------------------------------------------------------------- MANIFEST LAW --
echo
echo "-- manifest integrity --"

make_tree "$tmp/drift" 950 473
printf 'flag("std.io", "std.os")\n' >>"$tmp/drift/gate/fixture.id"
expect_fail "fixture drifted from its pinned exact count" \
    "$tmp/drift/gate/admission.sh" --census-only

make_tree "$tmp/stale" 950 473
printf 'gate/gone.id\t3\t# no such file\n' >>"$tmp/stale/gate/std-fixtures.manifest"
expect_fail "stale exemption for a file that carries no std spelling" \
    "$tmp/stale/gate/admission.sh" --census-only

make_tree "$tmp/nomanifest" 950 473
rm -f "$tmp/nomanifest/gate/std-fixtures.manifest"
expect_fail "missing manifest -> must fail, not fall back to exempting nothing" \
    "$tmp/nomanifest/gate/admission.sh" --census-only

make_tree "$tmp/emptymanifest" 950 473
printf '# only comments\n' >"$tmp/emptymanifest/gate/std-fixtures.manifest"
expect_fail "manifest classifying zero files -> must fail (empty escape hatch)" \
    "$tmp/emptymanifest/gate/admission.sh" --census-only

make_tree "$tmp/badmanifest" 950 473
printf 'gate/fixture.id\n' >"$tmp/badmanifest/gate/std-fixtures.manifest"
expect_fail "malformed manifest entry (no count) -> must fail" \
    "$tmp/badmanifest/gate/admission.sh" --census-only

# ---------------------------------------------------------- REGEX PRECISION --
echo
echo "-- spelling precision: neither over- nor under-counting --"

cat >"$tmp/nearmiss.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,4 @@
+  stdout:write("hi")
+  standard = 1
+  x = stdXio
+  my_std = 2
EOF
expect_pass "stdout / standard / stdXio / my_std are not std. spellings" \
    "$gate" --diff "$tmp/nearmiss.diff"

cat >"$tmp/dotted.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1 @@
+  x = wrapper.std.io.open(p)
EOF
expect_fail "dotted-path hiding (wrapper.std.io) is not a loophole" \
    "$gate" --diff "$tmp/dotted.diff"

echo
echo "=== controls: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
exit 0
