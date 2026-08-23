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

printf '\ncontrols: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
