#!/usr/bin/env bash
# duo_lock.sh — serialize heavy Duo/Zig operations across concurrent agent sessions.
# Logic: bash mutex (fast). Duo helpers in std.script.build_lock_* for in-process use.
# Optional: DUO_LOCK_DUO=1 delegates to scripts/duo_lock.duo (requires `duo run -- args`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO_BIN:-$ROOT/zig-out/bin/duo}"
LOCK_SCRIPT="$ROOT/scripts/duo_lock.duo"

if [[ "${DUO_LOCK_DUO:-0}" == "1" ]] && [[ -x "$DUO" ]]; then
  exec "$DUO" run "$LOCK_SCRIPT" -- "$@"
fi

LOCK_DIR="${DUO_BUILD_LOCK:-/tmp/duo-build.lock}"

acquire() {
    local timeout="${1:-1800}"
    local max_age="${DUO_LOCK_MAX_AGE:-1800}"   # force-release locks older than this (catches HUNG-but-alive holders)
    local waited=0
    while true; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            printf '%s %s\n' "$$" "$(date +%s)" >"$LOCK_DIR/owner"
            return 0
        fi
        local owner_pid="" owner_ts=""
        if [[ -f "$LOCK_DIR/owner" ]]; then
            owner_pid=$(cut -d' ' -f1 "$LOCK_DIR/owner" 2>/dev/null || true)
            owner_ts=$(cut -d' ' -f2 "$LOCK_DIR/owner" 2>/dev/null || true)
        fi
        local now; now=$(date +%s)
        # Force-release if the owner is DEAD, or if the lock is older than max_age
        # (the holder is presumed hung/crashed — a live-but-stuck process would
        # otherwise block every other agent forever, which caused the multi-hour
        # duo_lock stalls observed across sessions).
        local stale=0
        if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then stale=1; fi
        if [[ -n "$owner_ts" ]] && (( now - owner_ts > max_age )); then stale=1; fi
        if (( stale )); then
            rm -rf "$LOCK_DIR"
            continue
        fi
        if (( waited >= timeout )); then
            local age=$((now - ${owner_ts:-now}))
            echo "duo_lock: timed out after ${timeout}s waiting for $LOCK_DIR (held by pid ${owner_pid:-?}, age ${age}s)" >&2
            return 75
        fi
        sleep 2
        waited=$((waited + 2))
    done
}

release() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

cmd_status() {
    if [[ -d "$LOCK_DIR" ]] && [[ -f "$LOCK_DIR/owner" ]]; then
        echo "LOCKED by $(cat "$LOCK_DIR/owner" 2>/dev/null)"
    else
        echo "FREE"
    fi
}

# --- G-057: Fork-safety pre-check (delegates to duo_gate.sh if available) ---
check_fork_safety() {
    local gate_script="$ROOT/scripts/duo_gate.sh"
    if [[ -x "$gate_script" ]] && [[ -z "${DUO_GATE_HELD:-}" ]]; then
        if ! "$gate_script" status >/dev/null 2>&1; then
            # Gate says system is under fork pressure — wait for it to clear
            local gate_wait="${DUO_GATE_WAIT:-120}"
            echo "duo_lock: waiting up to ${gate_wait}s for fork safety (G-057)..." >&2
            "$gate_script" --timeout "$gate_wait" -- true 2>/dev/null || true
        fi
    fi
}

main() {
    local timeout=1800
    case "${1:-}" in
        status) cmd_status; exit 0 ;;
        --timeout) timeout="${2:?--timeout needs a value}"; shift 2 ;;
    esac
    if [[ "${1:-}" == "--" ]]; then shift; fi
    if [[ $# -eq 0 ]]; then
        echo "duo_lock: no command given (usage: duo_lock.sh [--timeout N] -- <cmd...>)" >&2
        exit 64
    fi
    # G-057: pre-check fork safety before acquiring the build lock
    check_fork_safety
    acquire "$timeout"
    trap release EXIT INT TERM
    export DUO_LOCK_HELD=1
    export DUO_BUILD_LOCK="$LOCK_DIR"
    # G-057: also register a gate slot while the build runs
    local gate_dir="${DUO_GATE_DIR:-/tmp/duo-gate}"
    if [[ -d "$gate_dir" ]] || mkdir -p "$gate_dir" 2>/dev/null; then
        printf '%s %s\n' "$$" "$(date +%s)" >"$gate_dir/slot_$$" 2>/dev/null || true
        trap 'rm -f "'"$gate_dir"'/slot_$$" 2>/dev/null; release' EXIT INT TERM
    fi
    "$@"
}

main "$@"
