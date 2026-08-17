#!/bin/sh
# Prove that launch role selects an exact world at ingress and that the build
# cache cannot transfer that authority to byte-identical ordinary source.

set -eu

root=${WORLD_LAUNCH_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
mode=${IDOL_BUILD_MODE:-unknown}
case "$mode" in
    ReleaseFast|fast) mode=ReleaseFast ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-world-launch.XXXXXX")
cache_before=$work/cache.before

snapshot_cache() {
    output=$1
    for cache in /tmp/idol-cache-*; do
        [ -f "$cache" ] && printf '%s\n' "$cache"
    done | sort >"$output"
}

snapshot_cache "$cache_before"

cleanup() {
    cache_after=$work/cache.after
    cache_created=$work/cache.created
    snapshot_cache "$cache_after"
    comm -13 "$cache_before" "$cache_after" >"$cache_created"
    while IFS= read -r cache; do
        case "$cache" in
            /tmp/idol-cache-*) [ ! -f "$cache" ] || rm -f "$cache" ;;
        esac
    done <"$cache_created"
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'world-launch gate: FAIL %s\n' "$1" >&2
    exit 1
}

hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

check() {
    cwd=$1
    path=$2
    log=$3
    if (CDPATH='' cd -- "$cwd" && "$compiler" check "$path") >"$log" 2>&1; then
        return 0
    else
        return $?
    fi
}

admitted() {
    label=$1
    cwd=$2
    path=$3
    log="$work/$label.check"
    check "$cwd" "$path" "$log" || fail "$label was not admitted"
}

refused() {
    label=$1
    cwd=$2
    path=$3
    log="$work/$label.check"
    if check "$cwd" "$path" "$log"; then rc=0; else rc=$?; fi
    [ "$rc" -eq 1 ] || fail "$label refusal returned $rc"
    grep -Fq "'assert' is neither a descriptor nor a callable" "$log" \
        || fail "$label did not refuse the testing-world application"
}

compile() {
    compile_source=$1
    compile_output=$2
    compile_log=$3
    if "$compiler" compile --backend=direct "$compile_source" -o "$compile_output" \
        --build-report=compact >"$compile_log" 2>&1; then
        return 0
    else
        return $?
    fi
}

answer() {
    artifact=$1
    if "$artifact" >/dev/null 2>&1; then rc=0; else rc=$?; fi
    [ "$rc" -eq 37 ] || fail "artifact answered $rc instead of 37"
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
[ "$mode" = ReleaseFast ] || fail "requires a source-built ReleaseFast compiler, got $mode"

mkdir -p "$work/test" "$work/ordinary" "$work/testing" "$work/mytest"
testing_source=$work/test/role.id
ordinary=$work/ordinary/role.id
marker=$work
printf '%s\n' \
    'main: i64 = ()' \
    "    test:assert(1 == 1, \"$marker\")" \
    '    37' >"$testing_source"
cp "$testing_source" "$ordinary"
cp "$testing_source" "$work/testing/role.id"
cp "$testing_source" "$work/mytest/role.id"
cmp -s "$testing_source" "$ordinary" || fail 'testing and ordinary source bytes differ'
cmp -s "$testing_source" "$work/testing/role.id" || fail 'damage source bytes differ'

ln -s role.id "$work/test/alias.id"
ln -s role.id "$work/ordinary/alias.id"
ln -s ordinary/role.id "$work/role_test.id"
ln -s ordinary/role.id "$work/test_role.id"

source_hash=$(hash "$idol")
cp "$idol" "$work/idol-a"
touch "$work/idol-a"
[ "$(hash "$work/idol-a")" = "$source_hash" ] || fail 'compiler namespace A changed bytes'
compiler=$work/idol-a

# Every spelling still carries the same testing launch role.
admitted testing_absolute / "$testing_source"
admitted testing_relative "$work" test/role.id
admitted testing_dot "$work" ./test/role.id
admitted testing_normalized "$work" test/../test/role.id
admitted testing_symlink "$work" test/alias.id
admitted testing_suffix "$work" role_test.id
admitted testing_prefix "$work" test_role.id

# Similar spellings that are not the test role remain ordinary.
refused ordinary_absolute / "$ordinary"
refused ordinary_relative "$work" ordinary/role.id
refused ordinary_dot "$work" ./ordinary/role.id
refused ordinary_normalized "$work" ordinary/../ordinary/role.id
refused ordinary_symlink "$work" ordinary/alias.id
refused ordinary_testing_word "$work" testing/role.id
refused ordinary_mytest_word "$work" mytest/role.id

# Namespace A: a cold testing compile populates the cache. The same-role repeat
# must hit it, while the byte-identical ordinary compile and check still refuse.
compile "$testing_source" "$work/testing-a.out" "$work/testing-a.log" \
    || fail 'cold testing compile failed'
grep -Fq '(cached)' "$work/testing-a.log" \
    && fail 'private cache namespace A was not cold'
answer "$work/testing-a.out"

compile "$testing_source" "$work/testing-a-cached.out" "$work/testing-a-cached.log" \
    || fail 'same-role cache compile failed'
grep -Fq '(cached)' "$work/testing-a-cached.log" \
    || fail 'same-role cache did not engage'
cmp -s "$work/testing-a.out" "$work/testing-a-cached.out" \
    || fail 'same-role cached artifact changed bytes'

refused after_testing_check / "$ordinary"
if compile "$ordinary" "$work/ordinary-after-testing.out" "$work/ordinary-after-testing.log"; then
    ordinary_rc=0
else
    ordinary_rc=$?
fi
[ "$ordinary_rc" -eq 1 ] || fail "ordinary compile after testing returned $ordinary_rc"
[ ! -e "$work/ordinary-after-testing.out" ] \
    || fail 'testing cache supplied an ordinary artifact'
grep -Fq "'assert' is neither a descriptor nor a callable" "$work/ordinary-after-testing.log" \
    || fail 'ordinary compile did not reach semantic refusal after testing cache population'

# Namespace B reverses the order. Its compiler is byte-identical but has a new
# cache-key mtime; the unique source marker makes the namespace private across
# gate invocations as well.
sleep 1
cp "$idol" "$work/idol-b"
touch "$work/idol-b"
[ "$(hash "$work/idol-b")" = "$source_hash" ] || fail 'compiler namespace B changed bytes'
compiler=$work/idol-b

refused ordinary_first_check / "$ordinary"
if compile "$ordinary" "$work/ordinary-first.out" "$work/ordinary-first.log"; then
    ordinary_rc=0
else
    ordinary_rc=$?
fi
[ "$ordinary_rc" -eq 1 ] || fail "cold ordinary compile returned $ordinary_rc"
[ ! -e "$work/ordinary-first.out" ] || fail 'cold ordinary compile produced an artifact'

compile "$testing_source" "$work/testing-after-ordinary.out" "$work/testing-after-ordinary.log" \
    || fail 'testing compile after ordinary refusal failed'
grep -Fq '(cached)' "$work/testing-after-ordinary.log" \
    && fail 'private cache namespace B was not cold'
answer "$work/testing-after-ordinary.out"

# Deliberate damage: replace the exact `test` path component with `testing`.
# The same admitted-check must turn red, proving the role detector is live.
if check "$work" testing/role.id "$work/damaged-path.log"; then
    damage_rc=0
else
    damage_rc=$?
fi
[ "$damage_rc" -eq 1 ] || fail "damaged launch classification returned $damage_rc"
grep -Fq "'assert' is neither a descriptor nor a callable" "$work/damaged-path.log" \
    || fail 'damaged launch classification did not remove testing-world reach'

printf 'SUBJECT revision=%s dirty=%s compiler_sha256=%s build_mode=%s backend=direct\n' \
    "$(git -C "$root" rev-parse HEAD)" \
    "$(if git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet; then printf clean; else printf dirty; fi)" \
    "$source_hash" "$mode"
printf 'world-launch gate: PASS\n'
