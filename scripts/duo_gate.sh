#!/usr/bin/env bash
# duo_gate.sh — global concurrency guard for Duo multi-agent builds.
#
# Problem (G-057): duo_lock.sh serializes *build steps* but does NOT cap total
# concurrent duo/clang/cc1 processes system-wide. A parallel agent's non-locked
# compiles/probes can exhaust the per-user maxproc limit, stalling ALL agents
# (EAGAIN on every posix_spawn — even `echo`), risking a forced reboot.
#
# Solution: a counting semaphore that caps total simultaneous heavy processes
# (duo, clang, cc1, zig, ld) system-wide, not just serialized build steps.
#
# Usage:
#   scripts/duo_gate.sh -- <cmd...>           # acquire a slot, run, release
#   scripts/duo_gate.sh --timeout 120 -- <cmd...>
#   scripts/duo_gate.sh status                 # show live heavy-proc count
#   scripts/duo_gate.sh config                 # show current config
#
# Environment overrides:
#   DUO_GATE_MAX   — max concurrent heavy procs (default: min(maxproc/4, 16))
#   DUO_GATE_DIR   — semaphore directory (default: /tmp/duo-gate)
#   DUO_GATE_WAIT  — max wait seconds (default: 1800)
#   DUO_GATE_PROC_PAT — regex of process names to count (default: duo|clang|cc1|zig|ld|ld64)

set -euo pipefail

GATE_DIR="${DUO_GATE_DIR:-/tmp/duo-gate}"
GATE_WAIT="${DUO_GATE_WAIT:-1800}"
PROC_PAT="${DUO_GATE_PROC_PAT:-duo|clang|cc1|zig|ld|ld64}"

# --- Compute default cap from system limits ---
compute_default_cap() {
    local maxproc
    maxproc=$(sysctl -n kern.maxprocperuid 2>/dev/null || echo 2666)
    # Cap at maxproc/4, clamped to [4, 16]
    local cap=$(( maxproc / 4 ))
    if (( cap < 4 )); then cap=4; fi
    if (( cap > 16 )); then cap=16; fi
    echo "$cap"
}

GATE_MAX="${DUO_GATE_MAX:-$(compute_default_cap)}"

# --- Count live heavy processes belonging to this user ---
count_heavy_procs() {
    # Count processes whose name matches PROC_PAT, owned by current user.
    # Uses ps + grep for portability (no Linux /proc dependency).
    local uid
    uid=$(id -u)
    ps -u "$uid" -o comm= 2>/dev/null \
        | grep -E "($PROC_PAT)" \
        | grep -v "grep" \
        | wc -l \
        | tr -d ' '
}

# --- Get system load average (1-min) ---
get_loadavg() {
    # macOS: sysctl -n vm.loadavg returns "{ 1.23 2.34 3.45 }"
    # Linux: /proc/loadavg has "1.23 2.34 3.45 ..."
    local load=""
    if [[ -r /proc/loadavg ]]; then
        load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)
    else
        # macOS path — strip braces
        load=$(sysctl -n vm.loadavg 2>/dev/null | sed 's/[{}]//g' | awk '{print $1}' || echo 0)
    fi
    echo "${load:-0}"
}

# --- Get maxproc limit ---
get_maxproc() {
    sysctl -n kern.maxprocperuid 2>/dev/null || echo 2666
}

# --- Check if system is under fork pressure ---
is_fork_safe() {
    local procs load maxproc
    procs=$(count_heavy_procs)
    load=$(get_loadavg)
    maxproc=$(get_maxproc)

    # Block if heavy proc count >= GATE_MAX
    if (( procs >= GATE_MAX )); then
        echo "BLOCKED: heavy procs ($procs) >= gate cap ($GATE_MAX)" >&2
        return 1
    fi

    # Block if load average > 8x CPU cores (system critically overloaded).
    # macOS load avg includes uninterruptible I/O wait + memory pressure,
    # which inflates the number significantly compared to Linux. We use 8x
    # as the threshold — this only triggers during genuine resource
    # exhaustion, not normal high-load development. The proc-count check
    # below is the primary EAGAIN guard.
    local cpus
    cpus=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    local load_limit=$(( cpus * 8 ))
    # Compare as integers (truncate float)
    local load_int=${load%.*}
    load_int=${load_int:-0}
    if (( load_int > load_limit )); then
        echo "BLOCKED: load avg ($load) > ${load_limit} (8x ${cpus} cores)" >&2
        return 1
    fi

    # Block if total user procs > 80% of maxproc
    local total_procs
    total_procs=$(ps -u "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')
    local proc_limit=$(( maxproc * 80 / 100 ))
    if (( total_procs > proc_limit )); then
        echo "BLOCKED: total user procs ($total_procs) > 80% of maxproc ($proc_limit)" >&2
        return 1
    fi

    return 0
}

# --- Acquire a gate slot (wait until safe to fork) ---
acquire() {
    local timeout="${1:-$GATE_WAIT}"
    local waited=0
    mkdir -p "$GATE_DIR" 2>/dev/null || true

    while true; do
        if is_fork_safe 2>/dev/null; then
            # Register ourselves
            local slot_file="$GATE_DIR/slot_$$"
            printf '%s %s %s\n' "$$" "$(date +%s)" "$1" >"$slot_file" 2>/dev/null || true
            return 0
        fi

        local reason
        reason=$(is_fork_safe 2>&1 1>/dev/null || true)

        if (( waited >= timeout )); then
            echo "duo_gate: timed out after ${timeout}s waiting for fork safety ($reason)" >&2
            # Clean up stale slots
            cleanup_stale_slots
            return 75
        fi

        # Exponential-ish backoff: 2s, 2s, 2s, ..., 5s after 30s
        local sleep_time=2
        if (( waited > 30 )); then sleep_time=5; fi
        if (( waited > 120 )); then sleep_time=10; fi
        sleep "$sleep_time"
        waited=$((waited + sleep_time))
    done
}

# --- Release our gate slot ---
release() {
    rm -f "$GATE_DIR/slot_$$" 2>/dev/null || true
}

# --- Clean up stale slot files (older than 30 min) ---
cleanup_stale_slots() {
    local now
    now=$(date +%s)
    if [[ -d "$GATE_DIR" ]]; then
        for f in "$GATE_DIR"/slot_*; do
            [[ -f "$f" ]] || continue
            local ts
            ts=$(cut -d' ' -f2 "$f" 2>/dev/null || echo 0)
            if (( now - ts > 1800 )); then
                rm -f "$f" 2>/dev/null || true
            fi
        done
    fi
}

# --- Status command ---
cmd_status() {
    local procs load maxproc total
    procs=$(count_heavy_procs) || procs=0
    load=$(get_loadavg) || load=0
    maxproc=$(get_maxproc) || maxproc=0
    total=$(ps -u "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ') || total=0

    echo "duo_gate status:"
    echo "  heavy procs (duo|clang|cc1|zig|ld): $procs"
    echo "  gate cap (GATE_MAX):               $GATE_MAX"
    echo "  system load (1-min):               $load"
    echo "  total user procs:                  $total / $maxproc"
    if is_fork_safe 2>/dev/null; then
        echo "  state:                             OK"
    else
        echo "  state:                             BLOCKED"
    fi || true

    # Show active slot files
    if [[ -d "$GATE_DIR" ]]; then
        local nslots
        nslots=$(ls -1 "$GATE_DIR"/slot_* 2>/dev/null | wc -l | tr -d ' ') || nslots=0
        echo "  active gate slots:                 $nslots"
    fi
}

# --- Config command ---
cmd_config() {
    echo "duo_gate config:"
    echo "  GATE_MAX:     $GATE_MAX"
    echo "  GATE_DIR:     $GATE_DIR"
    echo "  GATE_WAIT:    $GATE_WAIT"
    echo "  PROC_PAT:     $PROC_PAT"
    echo "  maxproc:      $(get_maxproc)"
    echo "  cpus:         $(sysctl -n hw.logicalcpu 2>/dev/null || echo '?')"
}

# --- Main ---
main() {
    local timeout="$GATE_WAIT"
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            status) cmd_status; exit 0 ;;
            config) cmd_config; exit 0 ;;
            --timeout) timeout="${2:?--timeout needs a value}"; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        echo "duo_gate: no command given (usage: duo_gate.sh [--timeout N] -- <cmd...>)" >&2
        exit 64
    fi

    # Periodic cleanup
    cleanup_stale_slots

    acquire "$timeout"
    trap release EXIT INT TERM
    export DUO_GATE_HELD=1
    "$@"
}

main "$@"