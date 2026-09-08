#!/bin/sh
# Damage controls for the fail-closed declaration freeze.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/vocabulary.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocabulary-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0
fail=0
expect_fail() { label=$1; shift; if "$@" >"$tmp/out" 2>&1; then fail=$((fail+1)); printf 'FAIL accepted: %s\n' "$label"; sed 's/^/  /' "$tmp/out"; else pass=$((pass+1)); printf '  ok reject: %s\n' "$label"; fi; }
expect_pass() { label=$1; shift; if "$@" >"$tmp/out" 2>&1; then pass=$((pass+1)); printf '  ok admit:  %s\n' "$label"; else fail=$((fail+1)); printf 'FAIL rejected: %s\n' "$label"; sed 's/^/  /' "$tmp/out"; fi; }

make_diff() {
    name=$1
    line=$2
    {
        printf '%s\n' '--- a/examples/probe.id' '+++ b/examples/probe.id' '@@ -1,0 +1 @@'
        printf '+%s\n' "$line"
    } >"$tmp/$name.diff"
}

make_diff mashed 'rolebeginexprnew: i64 = (a: i64)'
expect_fail "mashed relation" "$gate" --diff "$tmp/mashed.diff"
make_diff nice 'project: i64 = (a: i64)'
expect_fail "well-spelled relation is equally unproven" "$gate" --diff "$tmp/nice.diff"
make_diff descriptor 'record: { a: i64, b: str }'
expect_fail "descriptor" "$gate" --diff "$tmp/descriptor.diff"
make_diff cases 'color: { red, green }'
expect_fail "case set" "$gate" --diff "$tmp/cases.diff"
make_diff binding 'config = 41'
expect_fail "ordinary module binding is not misdeclared public; it is unknown and frozen" "$gate" --diff "$tmp/binding.diff"
make_diff uppercase 'Color: { red, green }'
expect_fail "uppercase declaration" "$gate" --diff "$tmp/uppercase.diff"
make_diff main 'main: i64 = ()'
expect_fail "ceremonial source main" "$gate" --diff "$tmp/main.diff"

make_diff private '_probe: i64 = (a: i64)'
expect_pass "explicit private declaration" "$gate" --diff "$tmp/private.diff"

cat >"$tmp/nested.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -2,0 +3,3 @@
+  localvalue = 7
+  another_value = localvalue + 1
+  another_value
EOF
expect_pass "nested descriptive bindings" "$gate" --diff "$tmp/nested.diff"

cat >"$tmp/root.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -3,0 +4 @@
+project()
EOF
expect_pass "root application is not a declaration" "$gate" --diff "$tmp/root.diff"

cat >"$tmp/body.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -3,0 +4,2 @@
+  total = total + 1
+  total
EOF
expect_pass "body-only change" "$gate" --diff "$tmp/body.diff"

cat >"$tmp/existing.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -1 +1 @@
-answer: bool = @comp.str.contains(text, "needle")
+answer: bool = "needle" in text
EOF
expect_pass "existing binding value changes without declaring vocabulary" "$gate" --diff "$tmp/existing.diff"

cat >"$tmp/rename.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -1 +1 @@
-old_answer = 41
+new_answer = 42
EOF
expect_fail "renaming an existing binding still declares a new identity" "$gate" --diff "$tmp/rename.diff"

cat >"$tmp/kind-change.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -1 +1 @@
-project = 41
+project: i64 = (value: i64)
EOF
expect_fail "changing an existing name to a relation still declares a new identity kind" "$gate" --diff "$tmp/kind-change.diff"

cat >"$tmp/statement.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -3,0 +4,2 @@
+print(rows)
+if ready
EOF
expect_pass "column-one applications and control heads" "$gate" --diff "$tmp/statement.diff"

expect_fail "missing diff" "$gate" --diff "$tmp/missing.diff"

mirror="$tmp/mirror"
mkdir -p "$mirror/gate" "$mirror/examples"
cp "$gate" "$mirror/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$mirror/gate/vocab-extract.awk"
cp "$here/subject.sh" "$mirror/gate/subject.sh"
printf '0\n' >"$mirror/examples/one.id"
expect_fail "archive-shaped tree without Git is never evidence" "$mirror/gate/vocabulary.sh" --diff "$tmp/body.diff"

# IDENTITY CLASS. Every case below names a declaration that ALREADY EXISTS in
# this tree, so the answer comes from the production graph rather than from a
# fixture agreeing with itself. The pair that motivated them: `first_value` and
# `firstvalue` were both graph-proven for one file, which proves only that the
# parser accepted two spellings.
tree_diff() {
    name=$1
    path=$2
    line=$3
    {
        printf -- '--- a/%s\n' "$path"
        printf -- '+++ b/%s\n' "$path"
        printf -- '@@ -1,0 +1 @@\n'
        printf '+%s\n' "$line"
    } >"$tmp/$name.diff"
}

tree_diff word lib/compiler/parser.id 'eval: i64 = (src: str)'
expect_pass "a native word on an Idol callable" "$gate" --diff "$tmp/word.diff"
tree_diff bytes lib/compiler/parser.id 'is_digit: i64 = (c: i64)'
expect_fail "foreign exact bytes on an Idol callable, which binds nothing" "$gate" --diff "$tmp/bytes.diff"
tree_diff bound lib/sqlite.id 'sqlite3_open: int = (path: str, db: any)'
expect_pass "foreign exact bytes carried by a real foreign binding" "$gate" --diff "$tmp/bound.diff"
tree_diff aliased vendor/mathc.id 'sin_c: f64 = (x: f64)'
expect_fail "a foreign spelling that is not the symbol it binds" "$gate" --diff "$tmp/aliased.diff"

# The selftest carries the in-graph damage controls (no normalization; foreign
# bytes need a binding; a binding admits only its own bytes) and nothing else
# runs it, so `--controls` would otherwise never reach them.
expect_pass "gate selftest, including the identity damage controls" "$gate" --selftest

printf '\ncontrols: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
