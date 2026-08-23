#!/bin/sh
# Damage controls for the added-source std quarantine.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/admission.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

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

printf '\ncontrols: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
