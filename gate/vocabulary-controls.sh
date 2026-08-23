#!/bin/sh
# gate/vocabulary-controls.sh — proves gate/vocabulary.sh can reject, and
# proves it does not reject lawful work.
#
# Both directions, because a gate that only ever passes and a gate that only
# ever fails are the same useless artifact from the merge queue's point of
# view. gate/path.id could reject nothing for a long time and every commit
# "passed" it.

set -eu
here=$(cd "$(dirname "$0")" && pwd)
gate="$here/vocabulary.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocab-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
expect_fail() { l=$1; shift; if "$@" >"$tmp/o" 2>&1; then fail=$((fail+1)); printf 'POSITIVE CONTROL FAILED (accepted a violation): %s\n' "$l"; sed 's/^/      | /' "$tmp/o"; else pass=$((pass+1)); printf '  ok  reject: %s\n' "$l"; fi; }
expect_pass() { l=$1; shift; if "$@" >"$tmp/o" 2>&1; then pass=$((pass+1)); printf '  ok  admit:  %s\n' "$l"; else fail=$((fail+1)); printf 'NEGATIVE CONTROL FAILED (rejected lawful input): %s\n' "$l"; sed 's/^/      | /' "$tmp/o"; fi; }

echo "=== gate/vocabulary.sh negative controls ==="
echo
echo "-- against the real tree --"
expect_pass "today's tree is consistent with its own admitted list" "$gate" --census-only

echo
echo "-- deny-by-default on new public words --"

# The brief's own examples.
cat >"$tmp/mashed.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,2 @@
+rolebeginexprnew: i64 = (a: i64)
+  a
EOF
expect_fail "mashed compound rolebeginexprnew was never admitted" "$gate" --diff "$tmp/mashed.diff"

cat >"$tmp/rename.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,3 +1,3 @@
-call_extern: i64 = (n: i64)
+callextern: i64 = (n: i64)
   n
EOF
expect_fail "snake_case renamed to a mash (callextern) is denied by the LIST, not by morphology" "$gate" --diff "$tmp/rename.diff"

cat >"$tmp/desc.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1 @@
+wholelynewdescriptor: { a: i64, b: str }
EOF
expect_fail "new public descriptor" "$gate" --diff "$tmp/desc.diff"

cat >"$tmp/case.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1 @@
+neverseencaseset: { alpha, beta }
EOF
expect_fail "new public case set" "$gate" --diff "$tmp/case.diff"

cat >"$tmp/bind.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1 @@
+neverseenbinding = 41
EOF
expect_fail "new module-scope binding" "$gate" --diff "$tmp/bind.diff"

# A well-formed snake_case word is denied too. The gate has NO shape opinion.
cat >"$tmp/goodshape.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,2 @@
+role_begin_expression: i64 = (a: i64)
+  a
EOF
expect_fail "a nicely-spelled new word is denied identically -- no morphology heuristic here" "$gate" --diff "$tmp/goodshape.diff"

echo
echo "-- lawful work must not be blocked --"

cat >"$tmp/reuse.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,2 @@
+compare: i64 = (a: any, b: any)
+  0
EOF
expect_pass "re-declaring an ALREADY ADMITTED word (compare)" "$gate" --diff "$tmp/reuse.diff"

cat >"$tmp/private.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,2 @@
+_neverseenprivatehelper: i64 = (a: i64)
+  a
EOF
expect_pass "a PRIVATE (underscore-prefixed) new identity is not public vocabulary" "$gate" --diff "$tmp/private.diff"

cat >"$tmp/nested.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -3,0 +4,3 @@
+  neverseenlocalvariable = 7
+  another_local_thing = neverseenlocalvariable + 1
+  another_local_thing
EOF
expect_pass "INDENTED bindings are not module scope -- layout is the signal" "$gate" --diff "$tmp/nested.diff"

cat >"$tmp/stmt.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -1,0 +1,4 @@
+print(rows)
+if x > 1
+  print("hi")
+error("no")
EOF
expect_pass "column-1 statements and keywords are not declarations" "$gate" --diff "$tmp/stmt.diff"

cat >"$tmp/body.diff" <<'EOF'
--- a/src/x.id
+++ b/src/x.id
@@ -10,0 +11,3 @@
+  total = total + 1
+  path("out.txt"):write(total)
+  total
EOF
expect_pass "an ordinary body-only edit introduces no vocabulary" "$gate" --diff "$tmp/body.diff"

echo
echo "-- the list itself must be load-bearing --"

mk_root() {
    d=$1
    mkdir -p "$d/gate" "$d/src"
    cp "$gate" "$d/gate/vocabulary.sh"
    cp "$here/vocab-extract.awk" "$d/gate/vocab-extract.awk"
    cp "$here/vocabulary.admitted" "$d/gate/vocabulary.admitted"
    i=0
    while [ "$i" -lt 950 ]; do printf 'main()\n  print("ok")\n' >"$d/src/f$i.id"; i=$((i+1)); done
}

mk_root "$tmp/trunc"
LC_ALL=C awk 'NR <= 100' "$here/vocabulary.admitted" >"$tmp/trunc/gate/vocabulary.admitted"
expect_fail "truncated admitted list -> must fail, not become a rubber stamp" \
    "$tmp/trunc/gate/vocabulary.sh" --census-only

mk_root "$tmp/nolist"
rm -f "$tmp/nolist/gate/vocabulary.admitted"
expect_fail "missing admitted list -> must fail" \
    "$tmp/nolist/gate/vocabulary.sh" --census-only

mk_root "$tmp/noextract"
rm -f "$tmp/noextract/gate/vocab-extract.awk"
expect_fail "missing extractor -> must fail, never 'nothing found, clean'" \
    "$tmp/noextract/gate/vocabulary.sh" --census-only

mk_root "$tmp/unadmitted"
printf 'brandnewunadmittedword: i64 = (a: i64)\n  a\n' >"$tmp/unadmitted/src/new.id"
expect_fail "an unadmitted word already sitting in the TREE fails the census, with no diff at all" \
    "$tmp/unadmitted/gate/vocabulary.sh" --census-only

echo
echo "-- GAP-201 / GAP-220 --"

mkdir -p "$tmp/empty/gate"
cp "$gate" "$tmp/empty/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$tmp/empty/gate/vocab-extract.awk"
cp "$here/vocabulary.admitted" "$tmp/empty/gate/vocabulary.admitted"
expect_fail "zero .id subjects -> must fail (GAP-201)" \
    "$tmp/empty/gate/vocabulary.sh" --census-only

mkdir -p "$tmp/mirror/gate" "$tmp/mirror/src"
cp "$gate" "$tmp/mirror/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$tmp/mirror/gate/vocab-extract.awk"
cp "$here/vocabulary.admitted" "$tmp/mirror/gate/vocabulary.admitted"
printf 'compare: i64 = (a: any, b: any)\n  0\n' >"$tmp/mirror/src/one.id"
expect_fail "archive-mirror shape: 1 subject, under the floor -> must fail (GAP-220)" \
    "$tmp/mirror/gate/vocabulary.sh" --census-only

mk_root "$tmp/nodecl"
: >"$tmp/nodecl/gate/vocabulary.admitted"
i=0; while [ "$i" -lt 950 ]; do printf '# comment only\n' >"$tmp/nodecl/src/f$i.id"; i=$((i+1)); done
expect_fail "1000 subjects but ZERO declarations extracted -> inert gate, must fail (GAP-201)" \
    "$tmp/nodecl/gate/vocabulary.sh" --census-only

mk_root "$tmp/nogit"
expect_fail "no .git and no --diff: delta rule unevaluable -> must fail, not silently skip" \
    "$tmp/nogit/gate/vocabulary.sh"

echo
echo "=== controls: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
exit 0
