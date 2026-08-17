#!/bin/sh
# Prove that executable cache reuse follows the resolved semantic home rather
# than the source path spelling or source bytes alone.

set -eu

root=${CACHE_HOME_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
mode=${IDOL_BUILD_MODE:-unknown}
case "$mode" in
    ReleaseFast|fast) mode=ReleaseFast ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-cache-home.XXXXXX")
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
    printf 'cache-home gate: FAIL %s\n' "$1" >&2
    exit 1
}

hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

compile() {
    cwd=$1
    source=$2
    output=$3
    log=$4
    if (CDPATH='' cd -- "$cwd" && "$compiler" compile --backend=direct "$source" \
        -o "$output" --build-report=compact) >"$log" 2>&1; then
        return 0
    else
        return $?
    fi
}

has_symbol() {
    artifact=$1
    symbol=$2
    nm -g "$artifact" 2>/dev/null | awk '{print $NF}' | grep -Fxq "$symbol"
}

matches_home() {
    artifact=$1
    expected=$2
    forbidden=$3
    has_symbol "$artifact" "$expected" && ! has_symbol "$artifact" "$forbidden"
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"

project=$work/project
mkdir -p "$project/src" "$project/left" "$project/right"
left=$project/left/role.id
right=$project/right/role.id
printf '%s\n' \
    'helper: i64 = ()' \
    '    42' \
    'main: i64 = ()' \
    '    helper()' >"$left"
cp "$left" "$right"
cmp -s "$left" "$right" || fail 'left and right source bytes differ'
ln -s "$project" "$work/link"

source_hash=$(hash "$idol")
cp "$idol" "$work/idol"
touch "$work/idol"
[ "$(hash "$work/idol")" = "$source_hash" ] || fail 'private compiler changed bytes'
compiler=$work/idol

left_symbol=_idol_left_role__helper
right_symbol=_idol_right_role__helper

compile "$project" left/role.id "$work/left.out" "$work/left.log" \
    || fail 'cold left compile failed'
grep -Fq '(cached)' "$work/left.log" && fail 'private cache was not cold'
matches_home "$work/left.out" "$left_symbol" "$right_symbol" \
    || fail 'left executable does not carry the exact left-home symbol'

compile "$project" right/role.id "$work/right.out" "$work/right.log" \
    || fail 'cold right compile failed'
grep -Fq '(cached)' "$work/right.log" && fail 'right home reused the left-home cache entry'
matches_home "$work/right.out" "$right_symbol" "$left_symbol" \
    || fail 'right executable does not carry the exact right-home symbol'

compile / "$left" "$work/absolute.out" "$work/absolute.log" \
    || fail 'absolute same-home compile failed'
grep -Fq '(cached)' "$work/absolute.log" || fail 'absolute spelling missed the same-home cache entry'

compile "$project" ./left/role.id "$work/dot.out" "$work/dot.log" \
    || fail 'dot same-home compile failed'
grep -Fq '(cached)' "$work/dot.log" || fail 'dot spelling missed the same-home cache entry'

compile "$project" left/../right/role.id "$work/parent.out" "$work/parent.log" \
    || fail 'parent-normalized same-home compile failed'
grep -Fq '(cached)' "$work/parent.log" || fail 'parent spelling missed the same-home cache entry'
cmp -s "$work/right.out" "$work/parent.out" \
    || fail 'parent-normalized executable changed bytes'
matches_home "$work/parent.out" "$right_symbol" "$left_symbol" \
    || fail 'parent spelling changed the exact right-home symbol'

compile / "$work/link/left/role.id" "$work/symlink.out" "$work/symlink.log" \
    || fail 'symlinked-root same-home compile failed'
grep -Fq '(cached)' "$work/symlink.log" || fail 'symlinked-root spelling missed the same-home cache entry'

for artifact in "$work/absolute.out" "$work/dot.out" "$work/symlink.out"; do
    cmp -s "$work/left.out" "$artifact" || fail "same-home cached executable changed bytes: $artifact"
    matches_home "$artifact" "$left_symbol" "$right_symbol" \
        || fail 'same-home spelling changed the exact native symbol'
done

# Deliberate damage: substitute the byte-identical-source artifact from the
# wrong home. The same symbol verifier must reject it.
cp "$work/left.out" "$work/damaged.out"
if matches_home "$work/damaged.out" "$right_symbol" "$left_symbol"; then
    fail 'wrong-home artifact substitution escaped the verifier'
fi

printf 'SUBJECT revision=%s dirty=%s compiler_sha256=%s build_mode=%s backend=direct\n' \
    "$(git -C "$root" rev-parse HEAD)" \
    "$(if git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet; then printf clean; else printf dirty; fi)" \
    "$source_hash" "$mode"
printf 'cache-home gate: PASS\n'
