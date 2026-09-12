#!/bin/sh
# Damage controls for the fail-closed declaration freeze.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/vocabulary.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocabulary-controls.XXXXXX")
trap 'rm -rf "$tmp" "$here/../addprobe.id"' EXIT INT TERM

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


# CONCATENATION UNITS. A relation whose body bare-calls a name from another
# file cannot be witnessed per-file; without a declared unit it stays refused.
cat >"$tmp/xref.diff" <<'EOF'
--- a/lib/compiler/parser.id
+++ b/lib/compiler/parser.id
@@ -1,0 +2 @@
+xrefprobe: i64 = (src: str)
+  eval(src)
EOF
expect_fail "cross-file bare call without a declared unit stays refused" "$gate" --diff "$tmp/xref.diff"

# Unit behavior is exercised in throwaway Git trees so the real repo's
# manifest is never mutated by a control run. IDOL points at the real
# compiler; root resolves to the throwaway tree.
REALIDOL="$here/../zig-out/bin/idol"
mkunitrepo() {
    dest=$1
    mkdir -p "$dest/gate"
    cp "$gate" "$dest/gate/vocabulary.sh"
    cp "$here/vocab-extract.awk" "$dest/gate/vocab-extract.awk"
    cp "$here/subject.sh" "$dest/gate/subject.sh"
    git -C "$dest" init -q
    git -C "$dest" add -A
    git -C "$dest" -c user.email=t@t -c user.name=t commit -qm init
}

# Positive: the unit's concatenated sources witness a cross-file relation
# that per-file analysis cannot see.
urepok="$tmp/unitrepo-ok"
mkdir -p "$urepok/gate"
printf 'u: a.id b.id\n' > "$urepok/gate/concat-units"
printf 'one: i64 = ()\n  1\n' > "$urepok/a.id"
printf 'two: i64 = ()\n  one()\n' > "$urepok/b.id"
cp "$gate" "$urepok/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$urepok/gate/vocab-extract.awk"
cp "$here/subject.sh" "$urepok/gate/subject.sh"
mkunitrepo "$urepok"
cat >"$tmp/unit.diff" <<'EOF'
--- a/b.id
+++ b/b.id
@@ -1,0 +2 @@
+two: i64 = ()
EOF
expect_pass "concatenation unit witnesses a cross-file relation" env "IDOL=$REALIDOL" "$urepok/gate/vocabulary.sh" --diff "$tmp/unit.diff"

# Negative: a unit member escaping the repository fails the gate loudly.
urepobad="$tmp/unitrepo-bad"
mkdir -p "$urepobad/gate"
printf 'evil: ../escape.id\n' > "$urepobad/gate/concat-units"
printf 'x = 1\n' > "$urepobad/probe.id"
cp "$gate" "$urepobad/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$urepobad/gate/vocab-extract.awk"
cp "$here/subject.sh" "$urepobad/gate/subject.sh"
mkunitrepo "$urepobad"
cat >"$tmp/unitbad.diff" <<'EOF'
--- a/probe.id
+++ b/probe.id
@@ -1,0 +2 @@
+badrel: i64 = ()
EOF
expect_fail "unit member escaping the repository" env "IDOL=$REALIDOL" "$urepobad/gate/vocabulary.sh" --diff "$tmp/unitbad.diff"

# Negative: a non-word unit name is refused.
ureponame="$tmp/unitrepo-name"
mkdir -p "$ureponame/gate"
printf 'bad_name: a.id\n' > "$ureponame/gate/concat-units"
printf 'x = 1\n' > "$ureponame/probe.id"
cp "$gate" "$ureponame/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$ureponame/gate/vocab-extract.awk"
cp "$here/subject.sh" "$ureponame/gate/subject.sh"
mkunitrepo "$ureponame"
expect_fail "non-word unit name" env "IDOL=$REALIDOL" "$ureponame/gate/vocabulary.sh" --diff "$tmp/unitbad.diff"


# TEST-DATA SCOPE. Bindings under test/ are data, not library surface: they
# are admitted without graph proof, but LAW-16 naming and zero prose still hold.
cat >"$tmp/testdata.diff" <<'EOF'
--- a/test/byte.id
+++ b/test/byte.id
@@ -1,0 +4 @@
+a = "L1"
+b = "LLLA2A31"
+e = "LLLLLLLLLLLLLLLLLLLLLA2A3A4A5A6A7A8A9A!10!A!11!A!12!A!13!A!14!A!15!A!16!A!17!A!18!A!19!A!20!A!21!1"
EOF
expect_pass "test-data bindings are admitted without graph proof" "$gate" --diff "$tmp/testdata.diff"

cat >"$tmp/testunder.diff" <<'EOF'
--- a/test/byte.id
+++ b/test/byte.id
@@ -1,0 +2 @@
+a_thing = 1
EOF
expect_fail "underscore binding in test data" "$gate" --diff "$tmp/testunder.diff"

cat >"$tmp/testcamel.diff" <<'EOF'
--- a/test/byte.id
+++ b/test/byte.id
@@ -1,0 +2 @@
+myVar = 1
EOF
expect_fail "camelCase binding in test data" "$gate" --diff "$tmp/testcamel.diff"

cat >"$tmp/testprose.diff" <<'EOF'
--- a/test/byte.id
+++ b/test/byte.id
@@ -1,0 +3 @@
+# a note about the data below
+a = 1
EOF
expect_fail "prose comment in test data" "$gate" --diff "$tmp/testprose.diff"

cat >"$tmp/nontest.diff" <<'EOF'
--- a/examples/probe.id
+++ b/examples/probe.id
@@ -1,0 +2 @@
+a = 1
EOF
expect_fail "the same binding outside test data stays refused" "$gate" --diff "$tmp/nontest.diff"

# A `.testdata` sidecar marker extends the scope to data files outside test/.
urepotd="$tmp/unitrepo-td"
mkdir -p "$urepotd/gate"
printf 'x = 1\n' > "$urepotd/data.id"
: > "$urepotd/data.id.testdata"
cp "$gate" "$urepotd/gate/vocabulary.sh"
cp "$here/vocab-extract.awk" "$urepotd/gate/vocab-extract.awk"
cp "$here/subject.sh" "$urepotd/gate/subject.sh"
mkunitrepo "$urepotd"
cat >"$tmp/td.diff" <<'EOF'
--- a/data.id
+++ b/data.id
@@ -1,0 +2 @@
+a = 1
EOF
expect_pass "testdata sidecar marker admits bindings" env "IDOL=$REALIDOL" "$urepotd/gate/vocabulary.sh" --diff "$tmp/td.diff"

cat >"$tmp/tdunder.diff" <<'EOF'
--- a/data.id
+++ b/data.id
@@ -1,0 +2 @@
+a_thing = 1
EOF
expect_fail "underscore binding refused under a sidecar marker" env "IDOL=$REALIDOL" "$urepotd/gate/vocabulary.sh" --diff "$tmp/tdunder.diff"

# ADDITIVE-MODULE PATH. A relation in a file this diff adds earns provisional
# admission on structural checks; naming, prose, and canonical-collision
# violations stay refused. The worktree file is created fresh per case and
# removed by the EXIT trap.
addprobe="$here/../addprobe.id"
addcase() {
    printf '%s\n' "$1" "$2" > "$addprobe"
    {
        printf '%s\n' '--- /dev/null' '+++ b/addprobe.id' '@@ -0,0 +1,2 @@'
        printf '+%s\n' "$1" "$2"
    } > "$tmp/addprobe.diff"
}

addcase 'double: i64 = (x: i64)' '  x + x'
expect_pass "additive module: clean new word admitted provisionally" "$gate" --diff "$tmp/addprobe.diff"

addcase 'myeval: i64 = (src: str)' '  eval(src)'
expect_pass "additive module: cross-file bare call admitted provisionally (structural)" "$gate" --diff "$tmp/addprobe.diff"

addcase 'bad_name: i64 = (x: i64)' '  x'
expect_fail "additive module: underscore name refused" "$gate" --diff "$tmp/addprobe.diff"

addcase 'badName: i64 = (x: i64)' '  x'
expect_fail "additive module: camelCase name refused" "$gate" --diff "$tmp/addprobe.diff"

addcase 'prosy: i64 = (x: i64)' '# a comment'
expect_fail "additive module: prose refused" "$gate" --diff "$tmp/addprobe.diff"

addcase 'fetch: i64 = (x: i64)' '  x'
expect_fail "additive module: synonym of canonical vocabulary refused" "$gate" --diff "$tmp/addprobe.diff"

addcase 'len: i64 = (x: i64)' '  x'
expect_fail "additive module: already-canonical word refused" "$gate" --diff "$tmp/addprobe.diff"

# Phantom file: the diff adds a new file that is absent from the worktree.
rm -f "$addprobe"
{
    printf '%s\n' '--- /dev/null' '+++ b/addprobe.id' '@@ -0,0 +1,2 @@'
    printf '%s\n' '+ghost2: i64 = (x: i64)' '  x'
} > "$tmp/addprobe.diff"
expect_fail "additive module: phantom new file refused" "$gate" --diff "$tmp/addprobe.diff"

# The selftest carries the in-graph damage controls (no normalization; foreign
# bytes need a binding; a binding admits only its own bytes) and nothing else
# runs it, so `--controls` would otherwise never reach them.
expect_pass "gate selftest, including the identity damage controls" "$gate" --selftest

printf '\ncontrols: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
