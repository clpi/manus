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
    shift 4
    if (CDPATH='' cd -- "$cwd" && "$compiler" compile --backend=direct "$source" \
        -o "$output" --build-report=compact "$@") >"$log" 2>&1; then
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
mkdir -p "$project/src" "$project/left" "$project/right" \
    "$project/other/left" "$project/other/right"
left=$project/left/role.id
right=$project/right/role.id
printf '%s\n' \
    'helper: i64 = ()' \
    '    42' \
    'main: i64 = ()' \
    '    helper()' >"$left"
cp "$left" "$right"
cp "$left" "$project/other/right/role.id"
cmp -s "$left" "$right" || fail 'left and right source bytes differ'
ln -s "$project" "$work/link"
ln -s other/left "$project/turn"

source_hash=$(hash "$idol")
cp "$idol" "$work/idol"
touch "$work/idol"
[ "$(hash "$work/idol")" = "$source_hash" ] || fail 'private compiler changed bytes'
compiler=$work/idol

left_symbol=_idol_left_role__helper
right_symbol=_idol_right_role__helper
other_symbol=_idol_other_right_role__helper

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

compile "$project" other/right/role.id "$work/other.out" "$work/other.log" \
    || fail 'cold symlink-parent target compile failed'
grep -Fq '(cached)' "$work/other.log" && fail 'symlink-parent target reused another home cache entry'
matches_home "$work/other.out" "$other_symbol" "$right_symbol" \
    || fail 'symlink-parent target does not carry its exact home symbol'

compile "$project" turn/../right/role.id "$work/symlink-parent.out" "$work/symlink-parent.log" \
    || fail 'symlink-parent same-file compile failed'
grep -Fq '(cached)' "$work/symlink-parent.log" \
    || fail 'symlink-parent spelling missed the actual-file cache entry'
cmp -s "$work/other.out" "$work/symlink-parent.out" \
    || fail 'symlink-parent spelling aliased the lexical home'
matches_home "$work/symlink-parent.out" "$other_symbol" "$right_symbol" \
    || fail 'symlink-parent spelling changed the actual-file home symbol'

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

# Physical compile inputs that are not yet represented in buildCacheKey must
# disable reuse. Otherwise a warm ordinary artifact can bypass the requested
# entry point, missing library, or missing C toolchain entirely.
entry_source=$project/entry.id
printf '%s\n' \
    'main: i64 = ()' \
    '    11' \
    '' \
    'alternate: i64 = ()' \
    '    22' >"$entry_source"

compile "$project" entry.id "$work/entry-default.out" "$work/entry-default.log" \
    || fail 'cold default-entry compile failed'
grep -Fq '(cached)' "$work/entry-default.log" && fail 'default-entry cache was not cold'
if "$work/entry-default.out"; then
    default_exit=0
else
    default_exit=$?
fi
[ "$default_exit" -eq 11 ] || fail "default entry returned $default_exit instead of 11"

compile "$project" entry.id "$work/entry-cached.out" "$work/entry-cached.log" \
    || fail 'warm ordinary compile failed'
grep -Fq '(cached)' "$work/entry-cached.log" || fail 'ordinary compile no longer reuses cache'

compile "$project" entry.id "$work/entry-alternate.out" "$work/entry-alternate.log" \
    --entry alternate || fail 'alternate-entry compile failed'
grep -Fq '(cached)' "$work/entry-alternate.log" \
    && fail 'alternate entry reused the default-entry artifact'
if "$work/entry-alternate.out"; then
    alternate_exit=0
else
    alternate_exit=$?
fi
[ "$alternate_exit" -eq 22 ] || fail "alternate entry returned $alternate_exit instead of 22"

missing_library=idol_cache_input_missing_83f1
if compile "$project" entry.id "$work/link-missing.out" "$work/link-missing.log" \
    --link "$missing_library"; then
    fail 'missing library succeeded through a warm ordinary cache entry'
fi
grep -Fq '(cached)' "$work/link-missing.log" \
    && fail 'missing library invocation reported a cache hit'

missing_cc=idol_cc_missing_83f1
if compile "$project" entry.id "$work/cc-missing.out" "$work/cc-missing.log" \
    --cc "$missing_cc"; then
    fail 'missing C toolchain succeeded through a warm ordinary cache entry'
fi
grep -Fq '(cached)' "$work/cc-missing.log" \
    && fail 'missing C toolchain invocation reported a cache hit'

if compile "$project" entry.id "$work/shared-memory.out" "$work/shared-memory.log" \
    --shared-memory; then
    fail 'shared-memory mode succeeded through a warm ordinary cache entry'
fi
grep -Fq '(cached)' "$work/shared-memory.log" \
    && fail 'shared-memory invocation reported a cache hit'

printf 'SUBJECT revision=%s dirty=%s compiler_sha256=%s build_mode=%s backend=direct\n' \
    "$(git -C "$root" rev-parse HEAD)" \
    "$(if git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet; then printf clean; else printf dirty; fi)" \
    "$source_hash" "$mode"
printf 'cache-home gate: PASS\n'
