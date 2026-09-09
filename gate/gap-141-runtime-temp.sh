#!/bin/sh
# Execute the generated-C temporary-artifact bridge. Source-shape tests did not
# prove this slice: the gate compiles the exact emitted helper, proves its files
# share one mode-0700 run directory, and proves a shared-/tmp damage is caught.
# GAP-141 remains open until the separately red dynamic-load capability executes.

set -eu

repo=${GAP141_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$repo/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$repo/zig-out/bin/idol"}
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap141.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail() {
    printf 'gap-141 runtime temp gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
command -v "$cc" >/dev/null 2>&1 || fail "C compiler is unavailable: $cc"

# Compatibility input is deliberate: this is an execution control for the
# generated-C foreign bridge, not canonical Idol source or semantic authority.
cat >"$work/load.lua" <<'EOF'
local f, err = load("return 42")
assert(f, err or "load failed")
print(f())
EOF

TMPDIR="$work/compiler-scratch"
export TMPDIR
mkdir -p "$TMPDIR"
"$idol" dump-c "$work/load.lua" >"$work/generated.c" \
    || fail 'compiler did not emit the compatibility runtime'

begin=$(grep -c 'IDOL_TEMP_SECTION_BEGIN' "$work/generated.c" || true)
end=$(grep -c 'IDOL_TEMP_SECTION_END' "$work/generated.c" || true)
[ "$begin" -eq 1 ] && [ "$end" -eq 1 ] \
    || fail "emitted helper boundary is not unique (begin=$begin end=$end)"
sed -n '/IDOL_TEMP_SECTION_BEGIN/,/IDOL_TEMP_SECTION_END/p' \
    "$work/generated.c" >"$work/helper.c"

write_probe() {
    helper=$1
    output=$2
    {
        cat <<'EOF'
#define _GNU_SOURCE 1
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
EOF
        cat "$helper"
        cat <<'EOF'
static int ends_with(const char* value, const char* suffix) {
    size_t n = strlen(value), m = strlen(suffix);
    return n >= m && strcmp(value + n - m, suffix) == 0;
}

int main(void) {
    char first[512], second[512], parent[512];
    struct stat info;
    if (duo_make_temp_path(first, sizeof first, ".one") != 0) return 1;
    if (duo_make_temp_path(second, sizeof second, ".two") != 0) return 2;
    if (!ends_with(first, ".one") || !ends_with(second, ".two")) return 3;
    if (access(first, F_OK) != 0 || access(second, F_OK) != 0) return 4;
    char* first_slash = strrchr(first, '/');
    char* second_slash = strrchr(second, '/');
    if (!first_slash || !second_slash) return 5;
    size_t parent_len = (size_t)(first_slash - first);
    if (parent_len == 0 || parent_len >= sizeof parent) return 6;
    memcpy(parent, first, parent_len);
    parent[parent_len] = '\0';
    if ((size_t)(second_slash - second) != parent_len ||
        memcmp(first, second, parent_len) != 0) return 7;
    if (stat(parent, &info) != 0 || !S_ISDIR(info.st_mode)) return 8;
    if ((info.st_mode & 0777) != 0700) {
        (void)unlink(first);
        (void)unlink(second);
        idol_cleanup_private_run_dir();
        return 9;
    }
    if (unlink(first) != 0 || unlink(second) != 0) return 10;
    idol_cleanup_private_run_dir();
    if (access(parent, F_OK) == 0) return 11;
    return 0;
}
EOF
    } >"$output"
}

write_probe "$work/helper.c" "$work/probe.c"
"$cc" -std=c11 -Wall -Wextra -Werror "$work/probe.c" -o "$work/probe" \
    || fail 'exact emitted helper did not compile'
"$work/probe" || fail 'exact emitted helper did not reserve a private run directory'

# Positive damage control: changing only the artifact parent back to shared
# /tmp must make the same executable observation fail.
sed 's@int written = snprintf(out, out_sz, "%s/artifact-XXXXXX%s", idol_private_run_dir, suffix);@int written = snprintf(out, out_sz, "/tmp/idol-artifact-XXXXXX%s", suffix);@' \
    "$work/helper.c" >"$work/helper-damaged.c"
cmp -s "$work/helper.c" "$work/helper-damaged.c" \
    && fail 'damage control did not alter the helper'
write_probe "$work/helper-damaged.c" "$work/probe-damaged.c"
"$cc" -std=c11 -Wall -Wextra -Werror "$work/probe-damaged.c" \
    -o "$work/probe-damaged" || fail 'damaged helper did not compile'
if "$work/probe-damaged"; then
    fail 'shared-/tmp damage passed the private-directory observation'
fi

# Compile the complete emitted translation unit so the executed extracted helper
# cannot pass while its integration point is syntactically dead.
dlflags=-ldl
[ "$(uname -s)" = Darwin ] && dlflags=
if ! "$cc" -std=gnu11 -O2 "$work/generated.c" -lm $dlflags \
    -o "$work/load" >"$work/generated-cc.log" 2>&1; then
    sed -n '1,120p' "$work/generated-cc.log" >&2
    fail 'emitted dynamic-load translation unit did not compile'
fi

# WASI has no lawful dynamic-artifact bridge. Selecting its physical arm must
# refuse before creating a path.
sed 's@int main(void) {@int private_probe_main(void) {@' "$work/probe.c" \
    >"$work/probe-wasi-prefix.c"
cat >>"$work/probe-wasi-prefix.c" <<'EOF'
int main(void) {
    char path[32];
    return duo_make_temp_path(path, sizeof path, ".x") == -1 ? 0 : 1;
}
EOF
"$cc" -std=c11 -Wall -Wextra -Werror -Wno-unused-function -D__wasm__ \
    "$work/probe-wasi-prefix.c" -o "$work/probe-wasi" \
    || fail 'WASI refusal arm did not compile'
"$work/probe-wasi" || fail 'WASI temporary-artifact bridge did not fail closed'

printf 'gap-141 runtime temp gate: PASS private-temp slice (private run, damage, integration compile, WASI refusal); dynamic-load acceptance remains OPEN\n'
