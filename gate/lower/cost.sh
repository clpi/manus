#!/bin/sh
# gate/lower/cost.sh — GAP-185's measured-cost face: enforcement cost,
# MEASURED on this host, never estimated.
#
# WHY THIS EXISTS. `lower.costOf` states cycle-scale ORDERS — `law` §14:
# unmeasured is stated, never dressed up. This runner measures the mechanisms
# this host can exercise without pretending hardware it lacks exists:
#
#   * `software_check` — the test+trap the graph-backed C99 arm emits around
#     an enforced access. Two loops identical but for the check are compiled by
#     the host C compiler and timed interleaved min-of-N.
#   * `process` — a byte ping-pong across a forked process through pipes; one
#     round trip is two authority-domain crossings.
#   * `network_isolation` — the same ping-pong over loopback TCP; one round
#     trip is two transport-domain crossings.
#
# The answer is one `idol.world.cost.v1` row per measured mechanism on stdout —
# one mechanism, one target triple, one unit, and the exact measured subject
# revision (`law.evidence.subject.one`). `lower.selectMeasured` is the consumer:
# measured facts decide ONLY a uniform comparison, so rows join a selection only
# when every candidate on the target was measured in the same unit.
#
# THE CONTROLS. The software measurement is meaningless if the host compiler
# folded the check away — then nothing is being measured. `probe selftest` runs
# the checked loop with the extent fact set BELOW the index range: a live check
# kills the process by signal, and this gate requires that death before it
# trusts a timing. The boundary measurements must complete a live child-process
# round trip and a live loopback TCP round trip before any row is printed.
#
# REFUSALS. No C compiler, a failed compile, a folded check, or an unavailable
# boundary crossing is CANNOT MEASURE (exit 2) with the reason named — never a
# fabricated row.
#
# K (software accesses per repetition, default 2^22), B (boundary round trips
# per repetition, default 4096), and N (repetitions, default 9) are
# environment-tunable. The software row reports checked and plain ns/access
# separately; the enforcement cost is the difference, reported even when noise
# makes it negative. Boundary rows report ns per one-way crossing.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

cc=${CC:-cc}
K=${K:-4194304}
B=${B:-4096}
N=${N:-9}

command -v "$cc" >/dev/null 2>&1 || {
    printf 'lower/cost: CANNOT MEASURE — no C compiler (%s)\n' "$cc" >&2
    exit 2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-lower-cost.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cat >"$work/probe.c" <<'EOF'
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#define EXTENT 64

static unsigned long table_data[EXTENT];
/* The extent is a runtime fact: a copy of a volatile read, so the compiler
   cannot prove the check away and cannot fold the comparison. */
static volatile size_t extent_fact = EXTENT;
static volatile unsigned long sink;

static uint64_t walk_state = 0x9e3779b97f4a7c15ULL;

static uint64_t walk_next(void) {
    walk_state ^= walk_state << 13;
    walk_state ^= walk_state >> 7;
    walk_state ^= walk_state << 17;
    return walk_state;
}

/* The mechanism under measurement: a compiler-emitted test+trap per
   enforced access — software_check itself. The index walk is uniform in
   [0, EXTENT), so the branch predicts; what remains is the compare, the
   branch slot and the extent read. */
static unsigned long accesses_checked(size_t len, unsigned long n) {
    unsigned long acc = 0;
    for (unsigned long i = 0; i < n; i++) {
        size_t idx = (size_t)(walk_next() & (EXTENT - 1));
        if (idx >= len) __builtin_trap();
        acc += table_data[idx];
    }
    return acc;
}

/* The same walk with no enforcement: the baseline the check is measured
   against. Identical in every other instruction. */
static unsigned long accesses_plain(size_t len, unsigned long n) {
    (void)len;
    unsigned long acc = 0;
    for (unsigned long i = 0; i < n; i++) {
        size_t idx = (size_t)(walk_next() & (EXTENT - 1));
        acc += table_data[idx];
    }
    return acc;
}

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *p = (const unsigned char *)buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += (size_t)n;
        len -= (size_t)n;
    }
    return 0;
}

static int read_all(int fd, void *buf, size_t len) {
    unsigned char *p = (unsigned char *)buf;
    while (len > 0) {
        ssize_t n = read(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += (size_t)n;
        len -= (size_t)n;
    }
    return 0;
}

static int wait_child(pid_t pid) {
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        return -1;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return -1;
    return 0;
}

static int ping_child(int in_fd, int out_fd, unsigned long n) {
    unsigned char byte = 0;
    for (unsigned long i = 0; i < n; i++) {
        if (read_all(in_fd, &byte, 1) != 0) return -1;
        byte ^= 0x5a;
        if (write_all(out_fd, &byte, 1) != 0) return -1;
    }
    return 0;
}

/* Process isolation crossing: pipe ping-pong across a forked child. One
   round trip crosses the authority-domain boundary twice. */
static double process_once(unsigned long n) {
    int p2c[2] = { -1, -1 };
    int c2p[2] = { -1, -1 };
    if (pipe(p2c) != 0) return -1.0;
    if (pipe(c2p) != 0) {
        close(p2c[0]);
        close(p2c[1]);
        return -1.0;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(p2c[0]);
        close(p2c[1]);
        close(c2p[0]);
        close(c2p[1]);
        return -1.0;
    }
    if (pid == 0) {
        close(p2c[1]);
        close(c2p[0]);
        int rc = ping_child(p2c[0], c2p[1], n);
        close(p2c[0]);
        close(c2p[1]);
        _exit(rc == 0 ? 0 : 111);
    }
    close(p2c[0]);
    close(c2p[1]);
    unsigned char byte = 0x31;
    double a = now_ns();
    double b = -1.0;
    for (unsigned long i = 0; i < n; i++) {
        if (write_all(p2c[1], &byte, 1) != 0) goto parent_fail;
        if (read_all(c2p[0], &byte, 1) != 0) goto parent_fail;
    }
    b = now_ns();
parent_fail:
    close(p2c[1]);
    close(c2p[0]);
    if (b < 0.0) kill(pid, SIGTERM);
    if (wait_child(pid) != 0) return -1.0;
    return b < 0.0 ? -1.0 : b - a;
}

static int set_nodelay(int fd) {
    int one = 1;
    return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
}

/* Network isolation crossing: loopback TCP ping-pong through a forked child.
   One round trip crosses the transport-domain boundary twice. */
static double network_once(unsigned long n) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return -1.0;
    int one = 1;
    (void)setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(listener);
        return -1.0;
    }
    if (listen(listener, 1) != 0) {
        close(listener);
        return -1.0;
    }
    socklen_t addr_len = sizeof(addr);
    if (getsockname(listener, (struct sockaddr *)&addr, &addr_len) != 0) {
        close(listener);
        return -1.0;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(listener);
        return -1.0;
    }
    if (pid == 0) {
        int conn = accept(listener, NULL, NULL);
        close(listener);
        if (conn < 0) _exit(111);
        (void)set_nodelay(conn);
        int rc = ping_child(conn, conn, n);
        close(conn);
        _exit(rc == 0 ? 0 : 111);
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        kill(pid, SIGTERM);
        close(listener);
        (void)wait_child(pid);
        return -1.0;
    }
    (void)set_nodelay(fd);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        kill(pid, SIGTERM);
        close(fd);
        close(listener);
        (void)wait_child(pid);
        return -1.0;
    }
    close(listener);
    unsigned char byte = 0x73;
    double a = now_ns();
    double b = -1.0;
    for (unsigned long i = 0; i < n; i++) {
        if (write_all(fd, &byte, 1) != 0) goto network_fail;
        if (read_all(fd, &byte, 1) != 0) goto network_fail;
    }
    b = now_ns();
network_fail:
    close(fd);
    if (b < 0.0) kill(pid, SIGTERM);
    if (wait_child(pid) != 0) return -1.0;
    return b < 0.0 ? -1.0 : b - a;
}

typedef double (*roundtrip_fn)(unsigned long);

static double measured_crossing(roundtrip_fn fn, unsigned long n, int reps) {
    double best = 1e30;
    for (int rep = 0; rep < reps; rep++) {
        double elapsed = fn(n);
        if (elapsed < 0.0) return -1.0;
        if (elapsed < best) best = elapsed;
    }
    return best / ((double)n * 2.0);
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "selftest") == 0) {
        /* Extent below the index range: a live check must kill the
           process. Completing the loop proves the check was folded. */
        extent_fact = EXTENT / 2;
        sink = accesses_checked(extent_fact, 1UL << 24);
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "process-selftest") == 0) {
        return process_once(1) >= 0.0 ? 0 : 2;
    }
    if (argc > 1 && strcmp(argv[1], "network-selftest") == 0) {
        return network_once(1) >= 0.0 ? 0 : 2;
    }

    unsigned long k = argc > 2 ? strtoul(argv[2], NULL, 10) : (1UL << 22);
    int reps = argc > 3 ? atoi(argv[3]) : 9;
    if (reps <= 0 || k == 0) return 2;

    if (argc > 1 && strcmp(argv[1], "process") == 0) {
        double crossing = measured_crossing(process_once, k, reps);
        if (crossing < 0.0) return 2;
        printf("%.4f\n", crossing);
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "network") == 0) {
        double crossing = measured_crossing(network_once, k, reps);
        if (crossing < 0.0) return 2;
        printf("%.4f\n", crossing);
        return 0;
    }

    size_t len = extent_fact;
    double best_checked = 1e30;
    double best_plain = 1e30;
    for (int rep = 0; rep < reps; rep++) {
        double a = now_ns();
        sink = accesses_checked(len, k);
        double b = now_ns();
        sink = accesses_plain(len, k);
        double c = now_ns();
        if (b - a < best_checked) best_checked = b - a;
        if (c - b < best_plain) best_plain = c - b;
    }
    printf("%.4f %.4f\n", best_checked / (double)k, best_plain / (double)k);
    return 0;
}
EOF

if ! "$cc" -O2 -std=c11 -D_POSIX_C_SOURCE=199309L -o "$work/probe" "$work/probe.c" 2>"$work/cc.err"; then
    printf 'lower/cost: CANNOT MEASURE — probe does not compile:\n' >&2
    cat "$work/cc.err" >&2
    exit 2
fi

# §0 The controls: every reported mechanism must be live, or nothing is being
# measured. Rows are printed only after all controls and measurements succeed.
"$work/probe" selftest >/dev/null 2>&1
st=$?
if [ "$st" -eq 0 ]; then
    printf 'lower/cost: CANNOT MEASURE — the selftest completed, so the host compiler folded the check away\n' >&2
    exit 2
fi
if [ "$st" -le 128 ]; then
    printf 'lower/cost: CANNOT MEASURE — selftest exit %d is not a trap\n' "$st" >&2
    exit 2
fi
printf 'lower/cost: control — the check is live (selftest killed by signal, status %d)\n' "$st" >&2

if ! "$work/probe" process-selftest >/dev/null 2>&1; then
    printf 'lower/cost: CANNOT MEASURE — process boundary selftest failed\n' >&2
    exit 2
fi
printf 'lower/cost: control — process boundary round trip is live\n' >&2

if ! "$work/probe" network-selftest >/dev/null 2>&1; then
    printf 'lower/cost: CANNOT MEASURE — network boundary selftest failed\n' >&2
    exit 2
fi
printf 'lower/cost: control — network boundary round trip is live\n' >&2

# §1 The measurements: min-of-N, no row until the complete set succeeds.
out=$("$work/probe" run "$K" "$N") || {
    printf 'lower/cost: CANNOT MEASURE — software_check probe run failed\n' >&2
    exit 2
}
checked_ns=${out%% *}
plain_ns=${out##* }
delta_ns=$(awk -v c="$checked_ns" -v p="$plain_ns" 'BEGIN { printf "%.4f", c - p }')

process_ns=$("$work/probe" process "$B" "$N") || {
    printf 'lower/cost: CANNOT MEASURE — process boundary probe run failed\n' >&2
    exit 2
}
network_ns=$("$work/probe" network "$B" "$N") || {
    printf 'lower/cost: CANNOT MEASURE — network boundary probe run failed\n' >&2
    exit 2
}

machine=$(uname -m 2>/dev/null || echo unknown)
case "$machine" in
    aarch64|arm64) arch=aarch64 ;;
    x86_64|amd64)  arch=x86_64 ;;
    *)             arch=unknown ;;
esac
system=$(uname -s 2>/dev/null || echo unknown)
case "$system" in
    Linux)  os=linux ;;
    Darwin) os=macos ;;
    *)      os=unknown ;;
esac
dump=$("$cc" -dumpmachine 2>/dev/null || echo unknown)
case "$dump" in
    *musl*) abi=musl ;;
    *)      abi=gnu ;;
esac
triple="$arch-$os-$abi"

revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)

printf '{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"%s","unit":"nanoseconds","cost":{"access":%s,"crossing":0},"subject_revision":"%s","checked_access_ns":%s,"plain_access_ns":%s,"accesses_per_rep":%s,"reps":%s}\n' \
    "$triple" "$delta_ns" "$revision" "$checked_ns" "$plain_ns" "$K" "$N"
printf '{"schema":"idol.world.cost.v1","mechanism":"process","triple":"%s","unit":"nanoseconds","cost":{"access":0,"crossing":%s},"subject_revision":"%s","roundtrips_per_rep":%s,"reps":%s}\n' \
    "$triple" "$process_ns" "$revision" "$B" "$N"
printf '{"schema":"idol.world.cost.v1","mechanism":"network_isolation","triple":"%s","unit":"nanoseconds","cost":{"access":0,"crossing":%s},"subject_revision":"%s","roundtrips_per_rep":%s,"reps":%s}\n' \
    "$triple" "$network_ns" "$revision" "$B" "$N"

printf 'lower/cost: software_check on %s at %s — checked %s ns/access, plain %s ns/access, enforcement %s ns/access (min-of-%s)\n' \
    "$triple" "$revision" "$checked_ns" "$plain_ns" "$delta_ns" "$N" >&2
printf 'lower/cost: process on %s at %s — crossing %s ns (two-way pipe ping-pong, min-of-%s, %s round trips/rep)\n' \
    "$triple" "$revision" "$process_ns" "$N" "$B" >&2
printf 'lower/cost: network_isolation on %s at %s — crossing %s ns (two-way loopback TCP ping-pong, min-of-%s, %s round trips/rep)\n' \
    "$triple" "$revision" "$network_ns" "$N" "$B" >&2
