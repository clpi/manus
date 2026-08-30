#!/bin/sh
# Damage controls for the added-source std quarantine AND the code-position
# census. A gate with no positive control is a decoration: gate/path.id shipped
# for a long time unable to reject anything and every commit "passed" it.
#
# Both directions, on the SHIPPED constants -- there is no test hatch and no
# environment variable that relaxes the gate, because such a variable is the
# first thing a future evasion reaches for.
#
#   POSITIVE control: a violating input MUST make the gate exit nonzero.
#   NEGATIVE control: a lawful input MUST make the gate exit zero.
#
# The census controls plant the identical bytes twice -- once where they reach
# a home and once where they cannot -- and demand OPPOSITE verdicts. A byte
# counter fails half of them; a gate that has quietly stopped charging anything
# fails the other half. Only a lexer passes both.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/admission.sh"
manifest="$here/std-fixtures.manifest"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

# The production gate owns the ratchet. Controls derive their planted boundary
# from that exact shipped constant so lowering the budget cannot silently turn
# every position-precision positive control into an unrelated over-budget red.
budget=$(sed -n 's/^STD_BUDGET=\([0-9][0-9]*\)$/\1/p' "$gate")
case $budget in
    ''|*[!0-9]*) printf 'admission controls: cannot read one numeric STD_BUDGET from %s\n' "$gate" >&2; exit 2 ;;
esac
overbudget=$((budget + 1))

pass=0
fail=0
expect_fail() { label=$1; shift; if "$@" >"$tmp/out" 2>&1; then fail=$((fail+1)); printf 'FAIL accepted: %s\n' "$label"; sed 's/^/  /' "$tmp/out"; else pass=$((pass+1)); printf '  ok reject: %s\n' "$label"; fi; }
expect_pass() { label=$1; shift; if "$@" >"$tmp/out" 2>&1; then pass=$((pass+1)); printf '  ok admit:  %s\n' "$label"; else fail=$((fail+1)); printf 'FAIL rejected: %s\n' "$label"; sed 's/^/  /' "$tmp/out"; fi; }

cat >"$tmp/lawful.diff" <<'EOF'
--- a/examples/lawful.id
+++ b/examples/lawful.id
@@ -1,0 +1,3 @@
+project: i64 = ()
+  data = path("in.txt"):read()
+project()
EOF
expect_pass "lawful source delta" "$gate" --diff "$tmp/lawful.diff"

cat >"$tmp/io.diff" <<'EOF'
--- a/examples/bad.id
+++ b/examples/bad.id
@@ -1,0 +1 @@
+  f = std.io.open("in.txt")
EOF
expect_fail "new std.io reach" "$gate" --diff "$tmp/io.diff"

cat >"$tmp/comment.diff" <<'EOF'
--- a/examples/bad.id
+++ b/examples/bad.id
@@ -1,0 +1 @@
+# do not teach std.script here
EOF
expect_fail "new raw std spelling in canonical source prose" "$gate" --diff "$tmp/comment.diff"

cat >"$tmp/string.diff" <<'EOF'
--- a/examples/bad.id
+++ b/examples/bad.id
@@ -1,0 +1 @@
+label = "std.script.capture"
EOF
expect_fail "new raw std spelling in source data" "$gate" --diff "$tmp/string.diff"

{
    printf '%s\n' '--- a/scripts/migrate.id' '+++ b/scripts/migrate.id' '@@ -1,2 +1,2 @@'
    printf '%s\n' '-  a = std.io.open(p)' '-  b = std.io.open(q)'
    printf '%s\n' '+  a = path(p):read()' '+  b = std.io.open(q)'
} >"$tmp/net.diff"
expect_fail "deletion cannot buy one reintroduced spelling" "$gate" --diff "$tmp/net.diff"

cat >"$tmp/remove.diff" <<'EOF'
--- a/scripts/migrate.id
+++ b/scripts/migrate.id
@@ -1 +1 @@
-  a = std.io.open(p)
+  a = path(p):read()
EOF
expect_pass "debt removal" "$gate" --diff "$tmp/remove.diff"

cat >"$tmp/near.diff" <<'EOF'
--- a/examples/near.id
+++ b/examples/near.id
@@ -1,0 +1,4 @@
+  stdout:write("hi")
+  standard = 1
+  x = stdXio
+  my_std = 2
EOF
expect_pass "near spellings are not the std root" "$gate" --diff "$tmp/near.diff"

cat >"$tmp/dotted.diff" <<'EOF'
--- a/examples/bad.id
+++ b/examples/bad.id
@@ -1,0 +1 @@
+  x = wrapper.std.io.open(p)
EOF
expect_fail "dotted hiding" "$gate" --diff "$tmp/dotted.diff"

cat >"$tmp/header.diff" <<'EOF'
--- a/lib/std.id
+++ b/lib/std.id
@@ -1 +1 @@
-0
+1
EOF
expect_pass "diff header is not source" "$gate" --diff "$tmp/header.diff"

expect_fail "missing diff file" "$gate" --diff "$tmp/missing.diff"
expect_fail "unknown option" "$gate" --unknown

mirror="$tmp/mirror"
mkdir -p "$mirror/gate" "$mirror/examples"
cp "$gate" "$mirror/gate/admission.sh"
cp "$here/subject.sh" "$mirror/gate/subject.sh"
printf '0\n' >"$mirror/examples/one.id"
expect_fail "archive-shaped tree without Git is never evidence" "$mirror/gate/admission.sh" --diff "$tmp/lawful.diff"

# ===========================================================================
# CENSUS CONTROLS. Everything above drives the QUARANTINE, which charges the
# raw spelling at any position on an added line. Everything below drives the
# CENSUS, which charges only reaches -- and the two rules disagreeing on that
# is deliberate, so both halves need proving.

# make_tree <dir> <n_extra_files> <reaches_in_carrier>
# A synthetic root over MIN_SUBJECTS carrying an exact number of code-position
# reaches in one unpinned file, plus decoys at every non-code position.
make_tree() {
    d=$1; n=$2; k=$3
    mkdir -p "$d/gate" "$d/src"
    cp "$gate" "$d/gate/admission.sh"
    cp "$here/subject.sh" "$d/gate/subject.sh"
    i=0
    while [ "$i" -lt "$n" ]; do
        printf 'project: i64 = ()\n  %s\n' "$i" >"$d/src/f$i.id"
        i=$((i + 1))
    done
    : >"$d/src/carrier.id"
    j=0
    while [ "$j" -lt "$k" ]; do
        printf 'x%s = std.io.open(p)\n' "$j" >>"$d/src/carrier.id"
        j=$((j + 1))
    done
    # DECOYS at four non-code positions. A position-blind counter reads this
    # tree as k+4 and every at-budget control below goes red.
    {
        printf '# prose: std.io.open is the spelling this tree is about\n'
        printf 'needle = "std.script.capture("\n'
        printf "byteneedle = 'std.os.exit'\n"
        printf 'escaped = "a quote \\" then std.fmt.boolean"\n'
    } >"$d/src/decoy.id"
    # A pinned carrier with a REAL reach: an exemption for a file that has none
    # is what this gate calls earned out and refuses.
    printf 'x = std.script.capture(cmd)\n' >"$d/gate/fixture.id"
    printf 'gate/fixture.id\t1\t# synthetic pinned carrier\n' >"$d/gate/std-fixtures.manifest"
    ( cd "$d" && git init -q . >/dev/null 2>&1 &&
      git config user.email ctl@admission.local && git config user.name ctl &&
      git add -A >/dev/null 2>&1 && git commit -qm ctl >/dev/null 2>&1 ) || return 1
}

printf '\n-- census, against the real tree --\n'
expect_pass "today's tree passes its own pinned census" "$gate" --census-only

printf '\n-- census arithmetic, against the SHIPPED budget --\n'
make_tree "$tmp/atbudget" 950 "$budget"
expect_pass "synthetic tree at exactly the budget ($budget)" \
    "$tmp/atbudget/gate/admission.sh" --census-only
make_tree "$tmp/overbudget" 950 "$overbudget"
expect_fail "synthetic tree one reach OVER the budget ($overbudget)" \
    "$tmp/overbudget/gate/admission.sh" --census-only

printf '\n-- manifest integrity --\n'
make_tree "$tmp/drift" 950 "$budget"
printf 'y = std.os.exit(1)\n' >>"$tmp/drift/gate/fixture.id"
expect_fail "pinned carrier drifted from its exact count" \
    "$tmp/drift/gate/admission.sh" --census-only

make_tree "$tmp/earnedout" 950 "$budget"
printf 'needle = "std.script.capture("\n' >"$tmp/earnedout/gate/fixture.id"
expect_fail "pinned carrier that no longer reaches -> EARNED OUT, must fail" \
    "$tmp/earnedout/gate/admission.sh" --census-only

make_tree "$tmp/zeropin" 950 "$budget"
printf 'gate/fixture.id\t0\t# a pin of zero\n' >"$tmp/zeropin/gate/std-fixtures.manifest"
expect_fail "a pin of 0 is a placeholder, not an exemption -> must fail" \
    "$tmp/zeropin/gate/admission.sh" --census-only

make_tree "$tmp/stale" 950 "$budget"
printf 'gate/gone.id\t3\t# no such subject\n' >>"$tmp/stale/gate/std-fixtures.manifest"
expect_fail "exemption for a path that does not exist -> must fail" \
    "$tmp/stale/gate/admission.sh" --census-only

make_tree "$tmp/nomanifest" 950 "$budget"
rm -f "$tmp/nomanifest/gate/std-fixtures.manifest"
expect_fail "missing manifest -> must fail, not exempt nothing and carry on" \
    "$tmp/nomanifest/gate/admission.sh" --census-only

make_tree "$tmp/emptymanifest" 950 "$budget"
printf '# only comments\n' >"$tmp/emptymanifest/gate/std-fixtures.manifest"
expect_fail "manifest classifying zero files -> must fail (empty escape hatch)" \
    "$tmp/emptymanifest/gate/admission.sh" --census-only

make_tree "$tmp/badmanifest" 950 "$budget"
printf 'gate/fixture.id\n' >"$tmp/badmanifest/gate/std-fixtures.manifest"
expect_fail "malformed manifest entry (no count) -> must fail" \
    "$tmp/badmanifest/gate/admission.sh" --census-only

printf '\n-- census position precision: a reach is charged, a mention is not --\n'
# One planted line at a time, in an otherwise lawful synthetic tree sized
# exactly at the budget. If the counter charges the plant the tree is one over
# and the gate must go red; if it correctly ignores it the tree stays green.
plant() {
    label=$1; body=$2; verdict=$3
    d="$tmp/plant$plantno"; plantno=$((plantno + 1))
    make_tree "$d" 950 "$budget"
    printf '%s\n' "$body" >"$d/src/planted.id"
    ( cd "$d" && git add -A >/dev/null 2>&1 && git commit -qm plant >/dev/null 2>&1 )
    "expect_$verdict" "$label" "$d/gate/admission.sh" --census-only
}
plantno=0
plant "PLANTED REACH at code position pushes the census over"  'x = std.io.open(p)'                       fail
plant "the same bytes after a # comment marker"                '# do not write std.io.open(p) here'       pass
plant "the same bytes inside a text literal"                   'needle = "std.io.open("'                  pass
plant "the same bytes inside a byte literal"                   "needle = 'std.io.open('"                  pass
plant "a reach BEFORE a comment on the same line"              'x = std.io.open(p)  # migrated from lua'  fail
plant "a reach AFTER a closed text literal"                    'x = f("std.") ; y = std.os.exit(1)'       fail
plant "a mention inside a literal that FOLLOWS code"           'x = f(p) ; needle = "std.os.exit"'        pass
plant "a reach after an escaped quote inside a string"         'a = "said \" then" ; b = std.io.read(f)'  fail
plant "a mention after an escaped quote inside a string"       'a = "said \" then std.io.read"'           pass
plant "a # inside a text literal does not open a comment"      'a = "#" ; b = std.io.read(f)'             fail
plant "an apostrophe in a COMMENT does not open a byte literal" "# don't write std.io.read"               pass
plant "stdout / standard / stdXio / my_std are not the root"   'x = stdXio ; y = standard ; z = my_std.q' pass
plant "dotted-path hiding is a reach"                          'x = wrapper.std.io.open(p)'               fail

printf '\ncontrols: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
