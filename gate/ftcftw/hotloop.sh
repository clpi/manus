#!/bin/sh
# gate/ftcftw/hotloop.sh — one executed FTCFTW row: the Idol wasm engine vs
# wasmtime on the GAP-130 kernel loop (`benchmarks/wasm_rt/hot_big.wasm`).
#
# WHY THIS EXISTS. GAP-130 records an 18 percent generated-code loss in the
# engine's JIT on this exact module, measured on macOS/aarch64, and records the
# value-flow cause: two loop-carried alias flushes plus a branch-feed move that
# liveness does not require, `MUL; ADD` where the value graph exposes one MADD,
# and a two-word materialization of -9 where the signed value selects `SUB #9`.
# That number decays the moment it lives only in prose, so this runner
# recomputes the row wherever it is run and names which realization it actually
# exercised. `docs/bootstrap.md` keeps FTCFTW INVALID as an aggregate claim at
# S0; this is one workload, one axis, and it binds to the exact exercised path.
#
# WHAT A REFUSAL MEANS, precisely, because on most hosts this refuses. The
# engine (`tools/wasm/src/engine.id`) has exactly two realizations today and
# both are narrower than this fixture's oracle:
#
#   direct-native   macOS/aarch64 only (`src/native_backend.zig` refuses DNB004
#                   elsewhere), and the engine's own JIT is an ARM64 emitter
#                   behind `jit_is_arm64`
#   C99 slice       refuses `engine.id` at `req` (GraphFactsInvalid,
#                   missing-application-id)
#
# So on an x86_64 host there is NO engine arm at all — not even the
# interpreter — and the only honest output is CANNOT MEASURE with the exact
# refusal, plus proof the oracle side works so the zero has its positive
# control. Printing a one-armed table here is how a bogus row gets published.
#
# ANSWER EQUIVALENCE IS CHECKED BEFORE TIME, and the comparator is proved able
# to fail before it is trusted to pass. Timing is interleaved min-of-N wall
# clock; the engine's own printed `seconds=` is never read (os.clock, and it
# accumulates CPU across threads on macOS).

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in /*) ;; *) idol=$repo/${idol#./} ;; esac
mod=$repo/benchmarks/wasm_rt/hot_big.wasm
entry=_start
N=${N:-7}
FLOOR_MS=${FLOOR_MS:-40}

[ -f "$mod" ] || { printf 'ftcftw/hotloop: CANNOT MEASURE — fixture missing at %s\n' "$mod" >&2; exit 2; }
command -v wasmtime >/dev/null 2>&1 || { printf 'ftcftw/hotloop: CANNOT MEASURE — wasmtime is the oracle and it is missing\n' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-ftcftw-hotloop.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ================= §0 THE COMPARATOR CAN FAIL, THE ORACLE ANSWERS ============
# A differencer that cannot disagree proves nothing when it agrees. The control
# is a deliberate one-digit corruption of whatever the oracle answers.
printf 'ftcftw/hotloop: §0 oracle and comparator controls\n'
oracle_answer=$(wasmtime --invoke "$entry" "$mod" 2>/dev/null | grep -E '^[0-9]+$' | head -n 1)
case "$oracle_answer" in
    '' ) printf 'ftcftw/hotloop: CANNOT MEASURE — wasmtime produced no numeric answer for %s\n' "$entry" >&2; exit 2 ;;
esac
corrupt="${oracle_answer}0"
if [ "$oracle_answer" = "$corrupt" ]; then
    printf 'ftcftw/hotloop: BROKEN — the comparator control cannot construct a disagreement\n' >&2
    exit 2
fi
printf '  oracle wasmtime %s answer=%s   comparator control: %s != %s ok\n' \
    "$(wasmtime --version 2>/dev/null | head -n 1 | cut -d ' ' -f 2)" "$oracle_answer" "$oracle_answer" "$corrupt"

# ====================== §1 DOES AN ENGINE ARM EXIST HERE =====================
# ENGINE_BIN reuses a prebuilt engine (it must still answer correctly below);
# otherwise the engine is built PRIVATELY, never from a shared mutable output —
# GAP-130's own reproduction note records the shared compiler hash changing
# mid-measurement.
printf 'ftcftw/hotloop: §1 engine realization on this host\n'
engine=${ENGINE_BIN:-}
if [ -n "$engine" ]; then
    [ -x "$engine" ] || { printf 'ftcftw/hotloop: CANNOT MEASURE — ENGINE_BIN=%s is not executable\n' "$engine" >&2; exit 2; }
    printf '  using ENGINE_BIN=%s (sha256 %s)\n' "$engine" "$(sha256sum "$engine" 2>/dev/null | cut -d ' ' -f 1)"
else
    [ -x "$idol" ] || { printf 'ftcftw/hotloop: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2; exit 2; }
    if "$idol" compile tools/wasm/src/engine.id --backend=direct --emit exe -o "$work/engine" >"$work/engine.log" 2>&1; then
        engine=$work/engine
        printf '  built private engine (sha256 %s)\n' "$(sha256sum "$engine" | cut -d ' ' -f 1)"
    else
        printf '  the direct backend refused the engine on this host:\n'
        grep -E '^error:' "$work/engine.log" | head -n 2 | sed 's/^/    /'
        printf 'ftcftw/hotloop: CANNOT MEASURE — the engine has no realization on this host.\n'
        printf '  The GAP-130 row (18%% JIT generated-code loss) binds to the ARM64 JIT path\n'
        printf '  and is NOT recomputable here; the oracle control above is the positive\n'
        printf '  control for this zero. Run this gate on macOS/aarch64 to recompute the row.\n'
        exit 2
    fi
fi

# =================== §2 WHICH ENGINE PATH, AND THE SAME ANSWER ===============
# `DUO_WASM_ENGINE=jit` refuses (exit 4) rather than answering under the
# interpreter's name; a refusal here drops to the interpreter arm EXPLICITLY
# and the row is labeled with the path that actually ran. The two paths are
# different claims and must never share a number.
printf 'ftcftw/hotloop: §2 engine path and equivalence\n'
mode=jit
DUO_WASM_MODULE=$mod DUO_WASM_INVOKE=$entry DUO_WASM_ENGINE=jit "$engine" >"$work/eng.out" 2>"$work/eng.err"
st=$?
if [ "$st" -ne 0 ]; then
    mode=interp
    printf '  jit path refused (exit %s): %s\n' "$st" "$(head -n 1 "$work/eng.err" 2>/dev/null)"
    DUO_WASM_MODULE=$mod DUO_WASM_INVOKE=$entry DUO_WASM_ENGINE=interp "$engine" >"$work/eng.out" 2>"$work/eng.err" || {
        printf 'ftcftw/hotloop: CANNOT MEASURE — the interpreter arm also failed:\n' >&2
        head -n 3 "$work/eng.err" | sed 's/^/    /' >&2
        exit 2
    }
fi
engine_answer=$(grep -E '^[0-9]+$' "$work/eng.out" | head -n 1)
printf '  exercised path: engine=%s   answer=%s\n' "$mode" "${engine_answer:-<none>}"
[ "$engine_answer" = "$oracle_answer" ] || {
    printf 'ftcftw/hotloop: BROKEN — the engine answered %s, wasmtime answered %s; nothing is timed\n' "${engine_answer:-<none>}" "$oracle_answer" >&2
    exit 3
}

# ============================== §3 TIME =====================================
printf 'ftcftw/hotloop: §3 min of %s, alternating\n' "$N"
be=999999999; bo=999999999
i=0
while [ "$i" -lt "$N" ]; do
    s=$(date +%s%N); DUO_WASM_MODULE=$mod DUO_WASM_INVOKE=$entry DUO_WASM_ENGINE=$mode "$engine" >/dev/null 2>&1; e=$(date +%s%N)
    t=$(( (e - s) / 1000000 )); [ "$t" -lt "$be" ] && be=$t
    s=$(date +%s%N); wasmtime --invoke "$entry" "$mod" >/dev/null 2>&1; e=$(date +%s%N)
    t=$(( (e - s) / 1000000 )); [ "$t" -lt "$bo" ] && bo=$t
    i=$((i + 1))
done
printf '  engine (%s) %6s ms\n' "$mode" "$be"
printf '  wasmtime %9s ms\n' "$bo"
if [ "$be" -lt "$FLOOR_MS" ] && [ "$bo" -lt "$FLOOR_MS" ]; then
    printf 'ftcftw/hotloop: CANNOT MEASURE — both arms under the %s ms startup floor; the number would be process startup\n' "$FLOOR_MS" >&2
    exit 2
fi

# ============================ §4 THE OUTCOME ================================
# §99 admits exactly three outcomes. Equality with wasmtime is a tie against
# ONE oracle, not a lower-bound witness: OPTIMAL is claimed by nobody here.
# The lower bound on record is GAP-130's inspected ~9-instruction kernel loop.
printf 'ftcftw/hotloop: §4 outcome (engine=%s vs wasmtime, %s)\n' "$mode" "$(uname -m)"
if [ "$be" -lt "$bo" ]; then
    printf '  WIN — engine %s ms vs wasmtime %s ms on the exercised %s path\n' "$be" "$bo" "$mode"
elif [ "$be" -eq "$bo" ]; then
    printf '  TIE — equals the strongest measured oracle (%s ms); OPTIMAL is not claimed,\n' "$be"
    printf '        the lower-bound witness remains the ~9-instruction kernel loop\n'
else
    pct=$(( (be - bo) * 100 / bo ))
    printf '  LOSS — engine %s ms vs wasmtime %s ms (+%s%%); the §99 debt row:\n' "$be" "$bo" "$pct"
    printf '    application    %s %s kernel loop, engine=%s\n' "benchmarks/wasm_rt/hot_big.wasm" "$entry" "$mode"
    printf '    extra cost     %s ms per run on this host\n' "$((be - bo))"
    if [ "$mode" = jit ]; then
        printf '    semantic cause loop-carried alias flushes + branch-feed move liveness does\n'
        printf '                   not require; MUL+ADD where the value graph is one MADD;\n'
        printf '                   two-word -9 materialization where the signed value is SUB #9\n'
        printf '    unresolved     the production relation/descriptor identity for wire ops —\n'
        printf '                   the 2026-08-10 signed-immediate prototype was rejected until\n'
        printf '                   the application owner mints it (GAP-130)\n'
    else
        printf '    semantic cause the exercised path is the interpreter: the JIT is an ARM64\n'
        printf '                   emitter and this host admits no compiled engine realization\n'
        printf '    unresolved     a non-ARM64 realization of the engine (direct backend DNB004\n'
        printf '                   off macOS/aarch64; C99 slice refuses engine.id at req)\n'
    fi
    printf '    lower bound    the inspected ~9-instruction kernel loop (GAP-130)\n'
    printf '    workstream     graph/DNIR value identities and realization facts feeding the\n'
    printf '                   shared allocator — not a wider alias cache or a hot_big recognizer\n'
fi
printf 'ftcftw/hotloop: OK — one workload, one axis, answers equal before timing, path named\n'
exit 0
