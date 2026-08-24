#!/bin/sh
# gate/layering-controls.sh — proves gate/layering.sh can reject.
#
# The substrate is a real `git clone --shared --no-checkout` of this repo,
# then a checkout. NOT `git archive` (an archive mirror has no .git, and this
# harness needs to test the git path), and NOT `cp -R` (copying a tree that
# carries a .zig-cache makes a later `zig build` emit a byte-identical binary
# from changed sources -- a lie this project has already paid for). A clone
# takes tracked files only, so no cache travels with it.
#
# Both directions. A positive control that passes is reported as a failure.
#
# ═══ THE SUBSTRATE IS ASSERTED, NOT ASSUMED ════════════════════════════════
#
# `gate/vacuity.sh` recorded this file UNPROVEN — it never observed the gate
# decide anything, under either plant. Under `set -e` the first `mkclone` died
# inside `git clone` (128: not a repository) or, with a repository present but
# empty, inside the `checkout HEAD` that follows it (128 again: no such ref).
# 128 is the shell's signal range, so both plants graded as a CRASH, and a
# crash is not a measurement. A gate that DIES is not a gate that NOTICED.
#
# Every prerequisite a clone needs is therefore named and refused with 2,
# before any clone is attempted: the gate under test, the rule files copied
# into each clone, a real work tree with a resolvable HEAD, and a non-empty
# population of the units the controls damage.
#
# Exit 0 = every control decided the right way. 1 = a control failed. 2 = the
# substrate could not support the controls, so none of them ran.

set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
gate="$here/layering.sh"
self="$here/$(basename -- "$0")"

refuse() {
    printf 'layering-controls: FAIL — %s\n' "$*" >&2
    exit 2
}

[ -x "$gate" ] || refuse "no executable gate under test at $gate"
for f in subject.sh layers.manifest layering.rules layering.baseline \
         generated.manifest relation-ownership.baseline; do
    [ -r "$here/$f" ] || refuse "gate/$f absent — every clone would carry an incomplete rule set"
done
[ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null || echo no)" = true ] ||
    refuse "$root is not a git work tree — cloning it cannot produce a substrate"
git -C "$root" rev-parse --verify --quiet HEAD >/dev/null ||
    refuse "$root has no HEAD commit — a clone of it checks out nothing to damage"
units=$(git -C "$root" ls-files -- 'src/*.zig' | grep -c . || true)
[ "${units:-0}" -gt 0 ] ||
    refuse "zero tracked src/*.zig in $root — the controls would damage nothing (GAP-201)"

# Each clone is a full checkout of the repo, so the scratch root goes next to
# the repo rather than on ${TMPDIR}, which is typically the boot volume and
# will fill. Every clone is deleted the moment its control has run.
scratch="${IDOL_GATE_SCRATCH:-$(dirname "$root")/.idol-gate-scratch}"
mkdir -p "$scratch"
tmp=$(mktemp -d "$scratch/layering-controls.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
expect_fail() { l=$1; shift; if "$@" >"$tmp/o" 2>&1; then fail=$((fail+1)); printf 'POSITIVE CONTROL FAILED (accepted a violation): %s\n' "$l"; sed 's/^/      | /' "$tmp/o"; else pass=$((pass+1)); printf '  ok  reject: %s\n' "$l"; fi; }
expect_pass() { l=$1; shift; if "$@" >"$tmp/o" 2>&1; then pass=$((pass+1)); printf '  ok  admit:  %s\n' "$l"; else fail=$((fail+1)); printf 'NEGATIVE CONTROL FAILED (rejected lawful input): %s\n' "$l"; sed 's/^/      | /' "$tmp/o"; fi; }

# A clone gives a clean TRACKED source tree. The gate files under test are
# copied in from the working tree afterwards, so the harness exercises the
# gate you are about to commit -- not whatever version HEAD happens to hold.
mkclone() {
    d=$(mktemp -d "$tmp/cXXXXXX")
    rmdir "$d"
    git clone --quiet --shared --no-checkout "$root" "$d"
    git -C "$d" checkout --quiet HEAD -- .
    mkdir -p "$d/gate"
    for g in layering.sh subject.sh layers.manifest layering.rules layering.baseline \
             generated.manifest relation-ownership.baseline; do
        cp "$here/$g" "$d/gate/$g"
    done
    chmod +x "$d/gate/layering.sh"
    printf '%s' "$d"
}

echo "=== gate/layering.sh negative controls ==="
echo

echo "-- baseline: an untouched clone must pass all three rules --"
C=$(mkclone)
expect_pass "untouched clone of HEAD (L1 + L3 + L2a)" "$C/gate/layering.sh" --static-only

echo
echo "-- L1: dependency direction --"

C=$(mkclone)
printf '\nconst sema = @import("sema.zig");\n' >>"$C/src/c_backend.zig"
expect_fail "c_backend.zig (BACKEND) newly imports sema.zig -- backend recovering meaning" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '\nconst ast = @import("ast.zig");\n' >>"$C/src/wasm_semantic.zig"
expect_fail "wasm_semantic.zig (BACKEND) newly imports ast.zig" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '\nconst p = @import("parser.zig");\n' >>"$C/src/backend_identity.zig"
expect_fail "backend_identity.zig (IR) newly imports parser.zig" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

# The evasion this rule most needs to survive: hide the reach mid-file, far
# from the header block, where a reviewer skimming imports will not see it.
C=$(mkclone)
LC_ALL=C awk 'NR == 40 { print "fn hidden() void { const s = @import(\"sema.zig\").Sema; _ = s; }" } { print }' \
    "$C/src/c_backend.zig" >"$C/src/c_backend.new"
mv "$C/src/c_backend.new" "$C/src/c_backend.zig"
expect_fail "sema reach buried mid-file, far from the import header a reviewer skims" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
LC_ALL=C sed -i.bak '/^const ast = @import("ast.zig");$/d' "$C/src/jit.zig"; rm -f "$C/src/jit.zig.bak"
expect_fail "a baselined edge was REMOVED -- must fail until the baseline is re-pinned" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf 'const std = @import("std");\nconst dnir = @import("native_ir.zig");\n' >>"$C/src/wasm_semantic.zig"
expect_pass "lawful new edge: BACKEND -> IR (wasm_semantic.zig imports native_ir.zig)" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

echo
echo "-- L1: the manifest must be load-bearing --"

C=$(mkclone)
printf 'const std = @import("std");\nconst sema = @import("sema.zig");\n' >"$C/src/sneaky_helper.zig"
git -C "$C" add src/sneaky_helper.zig
expect_fail "a NEW staged src/*.zig with no layer -- the cheapest way to route a forbidden edge" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf 'BACKEND  parser.zig\n' >>"$C/gate/layers.manifest"
expect_fail "a file classified twice (ambiguity is an escape hatch)" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf 'SEMA     nonexistent_module.zig\n' >>"$C/gate/layers.manifest"
expect_fail "manifest classifies a file that does not exist" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '# nothing forbidden\n' >"$C/gate/layering.rules"
expect_fail "empty rule set -> must fail, not become a permissive firewall" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '# nothing pinned\n' >"$C/gate/layering.baseline"
expect_fail "empty baseline -> must fail" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
rm -f "$C/gate/layers.manifest"
expect_fail "missing layer manifest -> must fail" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

# GAP-201 in its exact shape: extraction collapses, every violation vanishes,
# and the run reads as a clean sweep.
C=$(mkclone)
for f in "$C"/src/*.zig; do printf 'const std = @import("std");\n' >"$f"; done
expect_fail "edge extraction collapses to near-zero -> must fail, not read as a cleanup (GAP-201)" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
rm -rf "$C/.git"
rm -f "$C"/src/*.zig
expect_fail "zero compiler units -> must fail (GAP-201)" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
rm -rf "$C/.git"
expect_fail "no .git and no --diff: L2b unevaluable -> must fail, not silently skip" \
    "$C/gate/layering.sh"
rm -rf "$C"

echo
echo "-- L3: the parser must not own semantic relation identity --"

C=$(mkclone)
printf '\npub const relation_id_table = [_]u32{ 1, 2, 3 };\n' >>"$C/src/ast.zig"
expect_fail "ast.zig (AST) newly owns a relation_id table" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '\nfn mint_relation_symbol() void {}\n' >>"$C/src/parser.zig"
expect_fail "parser.zig gains another relation_symbol -- ownership grew past the pin" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
LC_ALL=C sed -i.bak 's/relation_edges/edgemap/g' "$C/src/parser.zig"; rm -f "$C/src/parser.zig.bak"
expect_fail "ownership paid down -> must fail until gate/relation-ownership.baseline is re-pinned" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '\nfn shape_only_helper() void {}\n' >>"$C/src/parser.zig"
expect_pass "an ordinary parser change that touches no relation identity" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

echo
echo "-- L2a: projections keep their do-not-edit marker --"

C=$(mkclone)
LC_ALL=C sed -i.bak 's|// GENERATED from lib/compiler/token.id — do not edit by hand.|// hand-maintained now|' "$C/src/grammar_role_table.zig"; rm -f "$C/src/grammar_role_table.zig.bak"
expect_fail "generated file stripped of its do-not-edit marker" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf 'src/never_generated.c\tsrc/token_classify_gen.zig\tdo not edit\n' >>"$C/gate/generated.manifest"
expect_fail "manifest names a projection that does not exist" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

C=$(mkclone)
printf '# nothing generated\n' >"$C/gate/generated.manifest"
expect_fail "empty projection manifest -> must fail, not ship an inert rule" \
    "$C/gate/layering.sh" --static-only
rm -rf "$C"

echo
echo "-- L2b: a projection may not be authored outside its generator --"

cat >"$tmp/orphan.diff" <<'EOF'
--- a/src/grammar_role_table.zig
+++ b/src/grammar_role_table.zig
@@ -20,0 +21 @@
+    .{ .name = "handpatched", .role = 7 },
EOF
expect_fail "src/grammar_role_table.zig edited without lib/compiler/token.id" \
    "$gate" --diff "$tmp/orphan.diff"

cat >"$tmp/paired.diff" <<'EOF'
--- a/lib/compiler/token.id
+++ b/lib/compiler/token.id
@@ -10,0 +11 @@
+  rolebeginexpr = 7
--- a/src/grammar_role_table.zig
+++ b/src/grammar_role_table.zig
@@ -20,0 +21 @@
+    .{ .name = "rolebeginexpr", .role = 7 },
EOF
expect_pass "projection and its generator changed together" \
    "$gate" --diff "$tmp/paired.diff"

cat >"$tmp/unrelated.diff" <<'EOF'
--- a/src/sema.zig
+++ b/src/sema.zig
@@ -100,0 +101 @@
+    // a comment
EOF
expect_pass "a diff touching no projection at all" \
    "$gate" --diff "$tmp/unrelated.diff"

cat >"$tmp/twoorphans.diff" <<'EOF'
--- a/lib/wasm/opcode_lookup.id
+++ b/lib/wasm/opcode_lookup.id
@@ -5,0 +6 @@
+  handadded = 1
--- a/lib/token/classify.id
+++ b/lib/token/classify.id
@@ -5,0 +6 @@
+  handadded = 2
EOF
expect_fail "two projections edited by hand, neither generator touched" \
    "$gate" --diff "$tmp/twoorphans.diff"

# A CONTROL HARNESS THAT RAN NO CONTROLS IS NOT A PASS. `fail -eq 0` is
# satisfied exactly as well by zero controls as by all of them, so the number
# that actually ran is compared against the number this file declares. The
# expected count is NOT written down: it is recounted from the source on every
# run, so adding or deleting a control needs no bookkeeping, while a control
# that is commented out, short-circuited, or skipped past is fatal.
declared=$(grep -cE '^expect_(fail|pass) "' -- "$self" || true)
ran=$((pass + fail))
[ "${declared:-0}" -gt 0 ] ||
    refuse "could not recount the controls declared in $self"
[ "$ran" -eq "$declared" ] ||
    refuse "$ran of the $declared controls declared in this file actually ran"

echo
echo "=== controls: $pass passed, $fail failed, $declared declared and all run ==="
[ "$fail" -eq 0 ] || exit 1
exit 0
