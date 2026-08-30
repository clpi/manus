#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
zig_version=0.17.0-dev.1567+f0354179a
wart_pin=ca2b0b9c0fb8c397987be2b4475fd1ccfe4d150b
wasmtime_pin=47.0.3
host_os=$(uname -s)
host_arch=$(uname -m)
wart_remote_ssh=${WART_ORACLE_REMOTE_SSH:-git@github.com:clpi/wart.git}
wart_remote_https=${WART_ORACLE_REMOTE_HTTPS:-https://github.com/clpi/wart.git}

hash256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        printf 'CAPABILITY BLOCKED sha256-tool-missing need shasum or sha256sum\n' >&2
        exit 2
    fi
}

wasmtime_version_matches() {
    case "$1" in
        "wasmtime ${wasmtime_pin}"|"wasmtime ${wasmtime_pin} "*) return 0 ;;
        *) return 1 ;;
    esac
}

case "${host_os}:${host_arch}" in
    Linux:x86_64) zig_name=zig-x86_64-linux-${zig_version} ;;
    Linux:aarch64) zig_name=zig-aarch64-linux-${zig_version} ;;
    Darwin:arm64) zig_name=zig-aarch64-macos-${zig_version} ;;
    Darwin:x86_64) zig_name=zig-x86_64-macos-${zig_version} ;;
    *)
        printf 'CAPABILITY BLOCKED zig-bootstrap-unsupported-host host=%s arch=%s pinned_version=%s\n' "$host_os" "$host_arch" "$zig_version" >&2
        exit 2
        ;;
esac

zig_url=https://zig-mirror.tsimnet.eu/zig/${zig_name}.tar.xz
zig_home=${TMPDIR:-/tmp}/idol-zig/${zig_name}
zig_bin=${zig_home}/zig

need_bootstrap=1
if command -v zig >/dev/null 2>&1; then
    have=$(zig version 2>/dev/null || true)
    if [ "$have" = "$zig_version" ]; then
        zig_bin=$(command -v zig)
        need_bootstrap=0
    fi
fi

if [ "$need_bootstrap" -ne 0 ]; then
    if [ ! -x "$zig_bin" ]; then
        archive=${zig_home}.tar.xz
        parent=$(dirname "$zig_home")
        mkdir -p "$parent"
        tmp=${archive}.part.$$
        rm -f "$tmp"
        if command -v curl >/dev/null 2>&1; then
            curl -L --fail -o "$tmp" "$zig_url"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "$tmp" "$zig_url"
        else
            printf 'CAPABILITY BLOCKED zig-fetch-tool-missing need curl or wget\n' >&2
            exit 2
        fi
        rm -rf "$zig_home"
        mkdir -p "$zig_home"
        tar -xf "$tmp" -C "$parent"
        rm -f "$tmp"
    fi
    PATH=$(dirname "$zig_bin"):$PATH
    export PATH
fi

ensure_wart_repo() {
    if [ -n "${WART_ORACLE_REPO:-}" ]; then
        wart_repo=$WART_ORACLE_REPO
    else
        wart_repo=${TMPDIR:-/tmp}/idol-wart/wart-oracle-${wart_pin}
    fi
    if [ -d "$wart_repo/.git" ]; then
        return 0
    fi
    parent=$(dirname "$wart_repo")
    rm -rf "$wart_repo"
    mkdir -p "$parent"
    if git clone --filter=blob:none --no-checkout "$wart_remote_ssh" "$wart_repo" >/dev/null 2>&1; then
        return 0
    fi
    if GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --no-checkout "$wart_remote_https" "$wart_repo" >/dev/null 2>&1; then
        return 0
    fi
    printf 'CAPABILITY BLOCKED wart-oracle-bootstrap clone_ssh=%s clone_https=%s\n' "$wart_remote_ssh" "$wart_remote_https" >&2
    exit 2
}

ensure_wart_checkout() {
    if ! git -C "$wart_repo" rev-parse --verify "$wart_pin^{commit}" >/dev/null 2>&1; then
        if ! git -C "$wart_repo" fetch --depth=1 origin "$wart_pin" >/dev/null 2>&1; then
            printf 'CAPABILITY BLOCKED wart-oracle-fetch revision=%s repo=%s\n' "$wart_pin" "$wart_repo" >&2
            exit 2
        fi
    fi
    git -C "$wart_repo" checkout --detach "$wart_pin" >/dev/null 2>&1
    wart_revision=$(git -C "$wart_repo" rev-parse HEAD 2>/dev/null || true)
    if [ "$wart_revision" != "$wart_pin" ]; then
        printf 'CAPABILITY BLOCKED wart-oracle-revision expected=%s actual=%s repo=%s\n' "$wart_pin" "${wart_revision:-missing}" "$wart_repo" >&2
        exit 2
    fi
    wart_dirty=$(git -C "$wart_repo" status --porcelain=v1 --untracked-files=all)
    if [ -n "$wart_dirty" ]; then
        printf 'CAPABILITY BLOCKED wart-oracle-dirty revision=%s repo=%s\n' "$wart_revision" "$wart_repo" >&2
        exit 2
    fi
}

ensure_wart_artifacts() {
    wart_bin=${WART_ORACLE_BIN:-$wart_repo/zig-out/bin/wart}
    case "$wart_bin" in "$wart_repo"/*) ;; *) printf 'CAPABILITY BLOCKED wart-oracle-unattributed binary=%s\n' "$wart_bin" >&2; exit 2 ;; esac
    if [ ! -x "$wart_bin" ]; then
        (cd "$wart_repo" && "$zig_bin" build -Drelease=true)
    fi
    if [ ! -x "$wart_bin" ]; then
        printf 'CAPABILITY BLOCKED wart-oracle-binary-missing path=%s revision=%s\n' "$wart_bin" "$wart_pin" >&2
        exit 2
    fi
    wart_provenance=${WART_ORACLE_PROVENANCE:-$wart_bin.provenance}
    wart_hash=$(hash256 "$wart_bin")
    printf 'revision=%s\nzig_version=%s\nbuild=%s\nhost=%s\nbinary_sha256=%s\n' \
        "$wart_pin" \
        "$zig_version" \
        'zig build -Drelease=true' \
        "$(uname -sm)" \
        "$wart_hash" > "$wart_provenance"
}

printf 'wasm-proof zig=%s\n' "$zig_bin"
printf 'wasm-proof zig_version=%s\n' "$("$zig_bin" version)"
printf 'wasm-proof host=%s arch=%s\n' "$host_os" "$host_arch"
printf 'wasm-proof repo=%s\n' "$repo"
cd "$repo"

build_host_tool() {
    src=$1
    out=$2
    label=$3
    case "${host_os}:${host_arch}" in
        Darwin:arm64|Darwin:aarch64)
            printf 'wasm-proof preflight=%s-direct-native\n' "$label"
            if ! "$compiler_bin" compile "$src" --backend=direct --emit exe -o "$out"; then
                printf 'CAPABILITY BLOCKED direct-native-%s source=%s host=%s arch=%s\n' "$label" "$src" "$host_os" "$host_arch" >&2
                exit 2
            fi
            ;;
        *)
            cc_bin=${CC:-cc}
            if ! command -v "$cc_bin" >/dev/null 2>&1; then
                printf 'CAPABILITY BLOCKED host-cc-missing source=%s cc=%s\n' "$src" "$cc_bin" >&2
                exit 2
            fi
            printf 'wasm-proof preflight=%s-c-host-bridge cc=%s\n' "$label" "$cc_bin"
            if ! "$compiler_bin" dump-c "$src" > "$out.c"; then
                printf 'CAPABILITY BLOCKED c-host-bridge-%s source=%s host=%s arch=%s stage=dump-c\n' "$label" "$src" "$host_os" "$host_arch" >&2
                exit 2
            fi
            if ! "$cc_bin" -std=c11 -O2 -o "$out" "$out.c" -lm; then
                printf 'CAPABILITY BLOCKED c-host-bridge-%s source=%s host=%s arch=%s stage=cc\n' "$label" "$src" "$host_os" "$host_arch" >&2
                exit 2
            fi
            ;;
    esac
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-wasm-proof.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

compiler_bin=./zig-out/bin/idol
if [ -x "$compiler_bin" ]; then
    printf 'wasm-proof preflight=compiler-reuse path=%s\n' "$compiler_bin"
else
    printf 'wasm-proof preflight=build-compiler\n'
    tools/node/dev/idol-lock -- "$zig_bin" build
fi

if [ ! -x "$compiler_bin" ]; then
    printf 'CAPABILITY BLOCKED compiler-binary-missing path=%s/zig-out/bin/idol\n' "$repo" >&2
    exit 2
fi

build_host_tool tools/wasm/src/engine.id "$work/wasm-engine" engine
build_host_tool tools/wasm/test/conform.id "$work/wasm-conform" harness

ensure_wart_repo
ensure_wart_checkout
ensure_wart_artifacts
printf 'wasm-proof wart_repo=%s\n' "$wart_repo"
printf 'wasm-proof wart_revision=%s\n' "$wart_pin"

if ! oracle=$(command -v wasmtime); then
    printf 'CAPABILITY BLOCKED wasmtime-oracle-missing expected_version=%s\n' "$wasmtime_pin" >&2
    exit 2
fi
oracle_version=$("$oracle" --version)
wasmtime_version_matches "wasmtime ${wasmtime_pin}" || {
    printf 'wasm-proof INTERNAL version control rejected exact pin=%s\n' "$wasmtime_pin" >&2
    exit 3
}
wasmtime_version_matches "wasmtime ${wasmtime_pin} (build metadata)" || {
    printf 'wasm-proof INTERNAL version control rejected admitted metadata suffix pin=%s\n' "$wasmtime_pin" >&2
    exit 3
}
if wasmtime_version_matches "wasmtime 0.0.0"; then
    printf 'wasm-proof INTERNAL version control admitted wrong version\n' >&2
    exit 3
fi
if ! wasmtime_version_matches "$oracle_version"; then
    printf 'CAPABILITY BLOCKED oracle-pin expected=%s actual=%s\n' "$wasmtime_pin" "$oracle_version" >&2
    exit 2
fi
printf 'wasm-proof oracle_version=%s version_controls=pass\n' "$oracle_version"

cd "$repo/tools/wasm"
exec env \
    DUO_WASM_BINDING="sh tools/wasm/proof.sh" \
    DUO_WASM_BIN="$work/wasm-engine" \
    WART_ORACLE_REPO="$wart_repo" \
    WART_ORACLE_BIN="$wart_bin" \
    WART_ORACLE_PROVENANCE="$wart_provenance" \
    WASMTIME="$oracle" \
    WASMTIME_VERSION="$wasmtime_pin" \
    "$work/wasm-conform"
