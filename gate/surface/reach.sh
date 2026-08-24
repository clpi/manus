#!/bin/sh
# FALSE SURFACE AREA — the five-level reachability census.
#
# THE PROBLEM THIS MEASURES. The tree's apparent capability is read off SOURCE:
# a file exists under `lib/`, an example is named after a feature, a registry
# holds a directive name — and a census says the capability "exists". That
# reading is wrong here, and `lib/jit.id` says so in its own header: ten foreign
# origin/ABI realizations, no owning graph fact, and NO backend reachable from
# `idol compile` realizes it. Only `idol dump-c` — which is not a compile
# backend — reaches the emitter that honours its payloads.
#
# So capability is scored on five INDEPENDENTLY MEASURED levels, not one:
#
#   L1 SOURCE EXISTS            tracked subjects exist for the subsystem
#   L2 GRAPH OWNER EXISTS       `idol graph` publishes facts and blocks nothing
#   L3 COMPILER REACHABLE       `idol compile` exits 0 under some backend
#   L4 REALIZATION REACHABLE    that compile left a non-empty artifact
#   L5 EXECUTED CONTROL EXISTS  `idol run` reaches program execution
#
# ANYTHING SATISFYING ONLY L1 IS NOT IMPLEMENTED CAPABILITY. It is false
# surface area, and the SOURCE-ONLY inventory in §4 is what the subtractive
# phase deletes from.
#
# `idol check` IS NOT EVIDENCE AND THIS GATE PROVES IT RATHER THAN ASSERTING IT.
# §0 plants `nosuchmodule.nosuchrelation(1)` — a call into a home that does not
# exist anywhere in the tree — and requires `check` to ACCEPT it. A front end
# that accepts a call to nothing cannot be a witness that anything is reachable,
# so every L2..L5 cell below is measured with `graph`, `compile`, and `run`.
#
# WHY IT CANNOT PASS VACUOUSLY. Five instruments in this tree have passed while
# measuring nothing.
#
#   §0 CONTROLS  a trivial program must COMPILE AND RUN (positive), a planted
#                foreign call must be REFUSED BY NAME (negative), and `check`
#                must accept the call to nothing. If the compiler were simply
#                broken all three would move together and the gate exits 2.
#   §1 SUBJECTS  every subsystem must enumerate at least one tracked subject.
#                Zero subjects is a FAIL, never a pass.
#   §5 LEDGER    the level each subsystem reaches is recomputed here on every
#                run and compared to the pinned row. A copied total goes stale
#                while the gate keeps passing; a recomputed one cannot.
#
# COMMANDS BEHIND EVERY CELL, so a reader can reproduce one row by hand:
#
#   L2   idol graph <subject>                       -> fact_coverage
#   L3   idol compile --backend=direct <subject>
#        idol compile --backend=c --emit=c <subject>
#        idol compile --backend=wasm --target=wasm32-wasi <subject>
#   L4   test -s <artifact>
#   L5   idol run --backend=direct <subject>
#   OFF  idol dump-c <subject>                      -> NOT a compile backend
#
# The OFF column is the jit lesson generalized: an emitter reachable only from
# `dump-c` realizes nothing a user of `idol compile` can obtain.
set -u

root=${SURFACEREACHROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$root" || exit 2
idol=${IDOL_BIN:-$root/zig-out/bin/idol}
case $idol in /*) ;; *) idol=$root/${idol#./} ;; esac

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-surface-reach.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

broke() { printf 'surface/reach: INSTRUMENT BROKEN — %s\n' "$1" >&2; exit 2; }
fail=0
note() { printf 'surface/reach: FAIL %s\n' "$1" >&2; fail=1; }

[ -x "$idol" ] || broke "compiler absent or not executable: $idol"
command -v git >/dev/null 2>&1 || broke "git absent; subject enumeration is git-tracked"

# ============================== §0 CONTROLS =================================
# Three controls that must DISAGREE with each other. A compiler that refused
# everything, or accepted everything, cannot satisfy all three at once.

# C1 POSITIVE — the instrument can observe a success.
printf 'main: i64 = ()\n    7\n' >"$work/pos.id"
"$idol" compile --backend=direct "$work/pos.id" -o "$work/pos.out" >"$work/pos.log" 2>&1 </dev/null \
    || broke "C1 positive control did not compile; see $work/pos.log"
[ -s "$work/pos.out" ] || broke "C1 positive control compiled but wrote no artifact"
"$idol" run --backend=direct "$work/pos.id" >"$work/pos.run" 2>&1 </dev/null
[ $? -eq 7 ] || broke "C1 positive control did not execute to 7"

# C2 NEGATIVE — the instrument can observe a refusal, BY NAME. Exit status
# alone is not enough: a broken parser also exits non-zero.
printf 'main: i64 = ()\n    jit.arch()\n' >"$work/neg.id"
if "$idol" compile --backend=direct "$work/neg.id" -o "$work/neg.out" >"$work/neg.log" 2>&1 </dev/null; then
    broke "C2 negative control COMPILED — a call into lib/jit.id now realizes; retire this control"
fi
grep -q 'DNB001' "$work/neg.log" || broke "C2 negative control refused without DNB001; see $work/neg.log"
grep -q 'runtime-global:jit' "$work/neg.log" || broke "C2 refusal lost its named cause 'runtime-global:jit'"

# C3 CHECK IS NOT EVIDENCE — a call into a home that exists NOWHERE must still
# be accepted by `check`. When this control starts failing, `check` has become
# a resolution authority and this gate's premise must be rewritten.
printf 'main: i64 = ()\n    nosuchmodule.nosuchrelation(1)\n' >"$work/void.id"
"$idol" check "$work/void.id" >"$work/void.log" 2>&1 </dev/null \
    || broke "C3: 'check' now refuses a call into a nonexistent home — premise changed"

printf '%s\n' '== §0 controls =============================================================='
printf '  C1 positive   idol compile+run <trivial>            compiled, executed to 7\n'
printf '  C2 negative   idol compile --backend=direct <jit>   DNB001 runtime-global:jit\n'
printf '  C3 check      idol check <call into nothing>        ACCEPTED — check is not evidence\n'

# ====================== §1 THE UNIVERSAL LIBRARY BLOCKER ====================
# Before any per-subsystem row: measure whether a consumer can reach a library
# module AT ALL. Two sibling files, one calling the other, nothing exotic.
#
# This is the fact that holds every `lib/` subsystem below at or under L2
# regardless of how well-owned its graph is — and `lib/compiler/monolith.id` already records
# it in its own header ("Cross-module references don't work, so everything is
# inlined"). Measured, not quoted.
mkdir -p "$work/sib" "$work/run" || broke "cannot create probe dirs"
printf 'twice: i64 = (n: i64)\n    n + n\n' >"$work/sib/helper.id"
printf 'main: i64 = ()\n    helper.twice(21)\n' >"$work/sib/user.id"

"$idol" compile --backend=direct "$work/sib/user.id" -o "$work/sib/u.out" >"$work/sib/d.log" 2>&1 </dev/null
sib_direct=$?
"$idol" compile --backend=c --emit=c "$work/sib/user.id" -o "$work/sib/u.c" >"$work/sib/c.log" 2>&1 </dev/null
sib_c=$?
"$idol" dump-c "$work/sib/user.id" >"$work/sib/dump.c" 2>"$work/sib/dump.log" </dev/null
sib_dump=$?

sib_verdict=UNREACHABLE
[ "$sib_direct" -eq 0 ] && sib_verdict=REACHABLE
printf '%s\n' '== §1 cross-module consumer =================================================='
printf '  direct   exit=%s  %s\n' "$sib_direct" "$(grep -m1 -e 'Undefined symbols' -e 'error:' "$work/sib/d.log" | sed 's/^ *//' | cut -c1-72)"
printf '  c        exit=%s  %s\n' "$sib_c" "$(grep -m1 'refused at:' "$work/sib/c.log" | sed 's/^ *//' | cut -c1-72)"
printf '  dump-c   exit=%s  %s\n' "$sib_dump" "$(grep -c 'unlowered native call' "$work/sib/dump.c" | sed 's/^/duo_fatal("unlowered native call") x/')"
printf '  verdict  library modules are %s from a consumer\n' "$sib_verdict"

if [ "$sib_direct" -eq 0 ]; then
    note "§1 cross-module linking now WORKS — every library row below is stale; re-derive the ledger"
else
    grep -q 'Undefined symbols' "$work/sib/d.log" \
        || note "§1 direct refused the consumer WITHOUT a link error; the named cause changed"
    grep -q 'call-target-not-in-module' "$work/sib/c.log" \
        || note "§1 the C99 realizer lost its named cause 'call-target-not-in-module'"
    grep -q 'unlowered native call' "$work/sib/dump.c" \
        || note "§1 dump-c no longer emits duo_fatal for the unlinked callee"
fi

# ========================= §2 SUBSYSTEM ENUMERATION =========================
# Subjects are TRACKED files only — an untracked scratch file is not surface
# area. A subsystem that enumerates zero subjects fails the gate; that is the
# rule that stops this becoming the sixth instrument to pass measuring nothing.
subjects() {
    case $1 in
    jit)      git ls-files '*.id' | grep -E '^lib/jit\.id$|^tools/wasm/src/wasm/jit|^tools/wasm/src/probe_jit\.id$|^examples/jit_' ;;
    gpu)      git ls-files '*.id' | grep -E 'gpu|metal' ;;
    simd)     git ls-files '*.id' | grep -E 'simd' ;;
    foreign)  git ls-files '*.id' | grep -E '^lib/foreign\.id$|^lib/ffi_gen\.id$|^lib/c\.id$|foreign_showcase|ffi_gen_showcase|^scripts/census/foreign' ;;
    reflect)  git ls-files '*.id' | grep -E 'reflect' ;;
    meta)     git ls-files '*.id' | grep -E '^lib/meta|^examples/meta_|^examples/comptime_|^examples/macros_|^examples/exponential_metaprogramming' ;;
    wasm)     git ls-files '*.id' | grep -E '^lib/wasm/|^tools/wasm/src/|^examples/wasm' ;;
    compiler) git ls-files '*.id' | grep -E '^lib/compiler/' ;;
    mcp)      git ls-files '*.id' | grep -E '^lib/mcp\.id$|^tools/mcp/native\.id$|mcp' ;;
    esac
}
systems='jit gpu simd foreign reflect meta wasm compiler mcp'

# ------------------------------- measurement --------------------------------
# One subject, all five levels plus the off-path emitter. Every cell is an
# invocation; nothing here is inferred from another cell.
measure() { # $1 subject -> sets m_graph m_compile m_artifact m_run m_dump m_check
    s=$1
    m_graph=0; m_compile=0; m_artifact=0; m_run=0; m_dump=0; m_check=0

    "$idol" check "$s" >"$work/m.log" 2>&1 </dev/null && m_check=1

    if "$idol" graph "$s" >"$work/m.json" 2>/dev/null </dev/null; then
        cov=$(sed -n 's/.*"fact_coverage":{\([^}]*\)}.*/\1/p' "$work/m.json")
        pub=$(printf '%s' "$cov" | sed -n 's/.*"published":\([0-9]*\).*/\1/p')
        blk=$(printf '%s' "$cov" | sed -n 's/.*"blocking":\([0-9]*\).*/\1/p')
        [ -n "${pub:-}" ] && [ -n "${blk:-}" ] && [ "$pub" -gt 0 ] && [ "$blk" -eq 0 ] && m_graph=1
    fi

    rm -f "$work/m.out" "$work/m.c" "$work/m.wasm"
    if "$idol" compile --backend=direct "$s" -o "$work/m.out" >"$work/md.log" 2>&1 </dev/null; then
        m_compile=1; [ -s "$work/m.out" ] && m_artifact=1
    elif "$idol" compile --backend=c --emit=c "$s" -o "$work/m.c" >"$work/mc.log" 2>&1 </dev/null; then
        m_compile=1; [ -s "$work/m.c" ] && m_artifact=1
    elif "$idol" compile --backend=wasm --target=wasm32-wasi "$s" -o "$work/m.wasm" >"$work/mw.log" 2>&1 </dev/null; then
        m_compile=1; [ -s "$work/m.wasm" ] && m_artifact=1
    fi

    # L5 wants EXECUTION, not exit status: a program is free to exit 42. The
    # observation is the absence of a compiler diagnostic on the run path.
    # `-o` keeps the linked binary in scratch: `idol run` otherwise drops it
    # beside the working directory, and a census may not litter the tree it is
    # censusing. The cwd stays at the project root because home resolution
    # searches down from there, and moving it would change what is measured.
    if [ "$m_compile" -eq 1 ]; then
        "$idol" run --backend=direct -o "$work/run/x.out" "$s" \
            >"$work/mr.log" 2>&1 </dev/null
        grep -q '^error:\|: error:' "$work/mr.log" || m_run=1
    fi

    "$idol" dump-c "$s" >"$work/m.dumpc" 2>/dev/null </dev/null && [ -s "$work/m.dumpc" ] && m_dump=1
}

printf '%s\n' '== §2 five-level census ======================================================'
printf '%-9s %6s %6s %6s %6s %6s %6s %6s   %s\n' \
    SYSTEM SUBJ CHECK L2gph L3cmp L4art L5run OFFdmp LEVEL

ledger=$work/ledger
: >"$ledger"
total_subjects=0

for sys in $systems; do
    subjects "$sys" >"$work/subj.$sys"
    # `grep -c` exits 1 on a zero count, so the count and any `||` fallback
    # would BOTH land in `n` and every later `[ "$n" -eq 0 ]` would abort with
    # "integer expression expected" — the zero-subject FAIL would be replaced
    # by a shell error, which is the one outcome this gate may not have.
    n=$(grep -c . "$work/subj.$sys" 2>/dev/null)
    case ${n:-} in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -eq 0 ]; then
        note "§2 subsystem '$sys' enumerated ZERO subjects — an instrument that measures nothing"
        printf '%-9s %6s %6s %6s %6s %6s %6s %6s   %s\n' "$sys" 0 - - - - - - NOSUBJECT
        printf '%s\tNOSUBJECT\n' "$sys" >>"$ledger"
        continue
    fi
    total_subjects=$((total_subjects + n))

    ck=0; g=0; c=0; a=0; r=0; d=0
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        measure "$s"
        ck=$((ck + m_check)); g=$((g + m_graph)); c=$((c + m_compile))
        a=$((a + m_artifact)); r=$((r + m_run)); d=$((d + m_dump))
    done <"$work/subj.$sys"

    # The level a subsystem REACHES is the deepest level any subject reaches.
    # A subsystem is credited with capability it can actually demonstrate once,
    # never with capability inferred from a sibling file that merely exists.
    lvl=L1
    [ "$g" -gt 0 ] && lvl=L2
    [ "$c" -gt 0 ] && lvl=L3
    [ "$a" -gt 0 ] && lvl=L4
    [ "$r" -gt 0 ] && lvl=L5

    printf '%-9s %6s %6s %6s %6s %6s %6s %6s   %s\n' "$sys" "$n" "$ck" "$g" "$c" "$a" "$r" "$d" "$lvl"
    printf '%s\t%s\n' "$sys" "$lvl" >>"$ledger"
done

[ "$total_subjects" -gt 0 ] || broke "§2 enumerated ZERO subjects in total — nothing was measured"

# ====================== §2b THE GPU DIRECTIVE IS INERT ======================
# `gpu` scores L1 above on tracked subjects, but a level table alone cannot
# say WHY, and the reason matters to a subtractive phase: `@device(...)` is
# not refused, it is IGNORED. The probe plants the same kernel under four
# device targets — including one that does not exist — and requires all four
# to compile and answer IDENTICALLY on the direct backend.
#
# Identical answers are the FINDING, not the pass condition being fudged: a
# directive that selects a realization cannot be invariant under `.metal` vs
# `.nosuchdevice`. If any row ever diverges, or the invalid device is refused,
# the directive has become live and the gpu row must be re-derived.
printf '%s\n' '== §2b @device inertness ====================================================='
dev_answers=
for target in .metal .cuda .webgpu .nosuchdevice; do
    d=$work/dev$(printf '%s' "$target" | tr -d '.')
    mkdir -p "$d"
    printf '@device(%s)\nkern: i64 = (n: i64)\n    n * 2\n\nmain: i64 = ()\n    kern(21)\n' \
        "$target" >"$d/k.id"
    ( cd "$d" && "$idol" run --backend=direct k.id >run.log 2>&1 </dev/null )
    a=$?
    printf '  @device(%-14s run exit=%s\n' "$target)" "$a"
    dev_answers="$dev_answers $a"
done
uniq_answers=$(printf '%s\n' $dev_answers | sort -u | grep -c .)
if [ "$uniq_answers" -eq 1 ] && [ "${dev_answers# }" = "42 42 42 42" ]; then
    printf '  verdict  every device target answers 42 — @device selects no realization\n'
else
    note "§2b @device answers diverged ($dev_answers) — the directive is no longer inert"
fi

# ================== §2c GENERATED FILES vs THEIR GENERATOR ==================
# A generated file whose generator no longer reproduces it is surface area with
# no owner: the committed text is authoritative for readers and the generator
# is authoritative for nobody. Measured by running the generators in a SCRATCH
# cwd — they write relative to the working directory, so the tracked tree is
# never touched — and comparing byte-for-byte.
printf '%s\n' '== §2c generator ownership ==================================================='
gen=$work/gen
mkdir -p "$gen/lib/wasm" "$gen/lib/token" "$gen/src" || broke "cannot stage generator scratch"
printf 'main: i64 = ()\n    0\n' >"$gen/seed.id"
( cd "$gen" && "$idol" wasm-tables emit seed.id >gen.log 2>&1 </dev/null ) \
    || note "§2c 'idol wasm-tables emit' failed"
( cd "$gen" && "$idol" token-tables emit seed.id >>gen.log 2>&1 </dev/null ) \
    || note "§2c 'idol token-tables emit' failed"
gen_drift=
gen_seen=0
for f in lib/wasm/opcode_lookup.id lib/wasm/ward_mvp_opcodes.id lib/token/classify.id; do
    [ -f "$gen/$f" ] || { note "§2c generator produced no $f"; continue; }
    gen_seen=$((gen_seen + 1))
    if cmp -s "$gen/$f" "$root/$f"; then
        printf '  reproduces  %s\n' "$f"
    else
        n=$(diff "$root/$f" "$gen/$f" | grep -c '^[<>]')
        printf '  DRIFT %-5s %s\n' "$n" "$f"
        gen_drift="$gen_drift $f"
    fi
done
[ "$gen_seen" -gt 0 ] || broke "§2c compared ZERO generated files"
if grep -q '^--' "$gen/lib/wasm/ward_mvp_opcodes.id" 2>/dev/null; then
    printf '  cause    the generator emits retired dash comments into .id\n'
fi

# ===================== §2d DOCUMENTED BUT UNREACHABLE CLI ===================
# `idol help` is a capability claim. Each command it names is invoked here
# against a trivial subject; a command the dispatcher never reaches answers
# `unknown command`, which is exactly what a reader of `help` cannot see.
printf '%s\n' '== §2d CLI surface ==========================================================='
cli=$work/cli
mkdir -p "$cli" || broke "cannot stage cli scratch"
printf 'main: i64 = ()\n    0\n' >"$cli/t.id"
"$idol" help 2>&1 </dev/null | sed -n '/^commands:/,/^$/p' | sed 's/^  //' \
    | awk 'NF{print $1}' | grep -vE '^(commands:|--.*|-h|list|all|stage|import-c)$' | sort -u >"$work/cmds"
ncmd=$(grep -c . "$work/cmds")
[ "$ncmd" -gt 0 ] || broke "§2d extracted ZERO commands from 'idol help'"
dead=
while IFS= read -r c; do
    [ -n "$c" ] || continue
    ( cd "$cli" && "$idol" "$c" t.id >cmd.log 2>&1 </dev/null )
    grep -q "unknown command" "$cli/cmd.log" && dead="$dead $c"
done <"$work/cmds"
printf '  commands documented by `idol help`: %s\n' "$ncmd"
if [ -n "$dead" ]; then
    printf '  DEAD — documented, never dispatched:%s\n' "$dead"
else
    printf '  every documented command is dispatched\n'
fi

# ===================== §3 REGISTRY DORMANCY (meta names) ====================
# A registry entry with no subject anywhere in the tracked corpus is surface
# area with no specimen at all — below L1. `src/meta_module.zig` publishes the
# directive spellings; the corpus is asked which of them anyone writes.
reg=src/meta_module.zig
if [ -r "$reg" ]; then
    grep -oE '\.public = "[^"]+"' "$reg" | sed 's/.*"\(.*\)"/\1/' | sort -u >"$work/regnames"
    regtotal=$(grep -c . "$work/regnames")
    [ "$regtotal" -gt 0 ] || broke "§3 extracted ZERO registry names from $reg"
    git ls-files '*.id' >"$work/corpus"
    # One pass over the corpus per name is too slow; collect every written
    # spelling once, then intersect.
    while IFS= read -r f; do cat "$f"; done <"$work/corpus" \
        | grep -oE '@[A-Za-z][A-Za-z0-9_.]*' | sed 's/^@//' | sort -u >"$work/written"
    dormant=0; live=0
    while IFS= read -r nm; do
        if grep -qxF "$nm" "$work/written"; then live=$((live + 1)); else dormant=$((dormant + 1)); fi
    done <"$work/regnames"
    printf '%s\n' '== §3 registry dormancy ======================================================'
    printf '  src/meta_module.zig publishes %s directive spellings\n' "$regtotal"
    printf '  written somewhere in the tracked .id corpus: %s\n' "$live"
    printf '  DORMANT — no specimen anywhere:              %s\n' "$dormant"
    [ "$dormant" -gt 0 ] || note "§3 dormancy scan found zero dormant names; the scanner is probably broken"
else
    note "§3 registry authority $reg is absent"
fi

# ========================== §4 SOURCE-ONLY INVENTORY ========================
printf '%s\n' '== §4 SOURCE-ONLY inventory (false surface area) ============================='
srconly=$(awk -F'\t' '$2=="L1"||$2=="L2"{printf "%s ", $1}' "$ledger")
noexec=$(awk -F'\t' '$2=="L3"||$2=="L4"{printf "%s ", $1}' "$ledger")
if [ -n "$srconly" ]; then
    printf '  SOURCE-ONLY (no reachable compiler realization): %s\n' "$srconly"
else
    printf '  SOURCE-ONLY: none — every subsystem reached L3 or deeper\n'
fi
if [ -n "$noexec" ]; then
    printf '  REALIZED BUT NEVER EXECUTED (artifact, no run):  %s\n' "$noexec"
fi
printf '  registry entries with no specimen at all:       %s dormant directive spellings\n' "${dormant:-?}"

# ============================== §5 THE LEDGER ===============================
# The pinned rows. These are the ONLY numbers written down, they live inside
# the runner that recomputes them, and a drift in either direction fails.
# A subsystem MOVING UP is also a failure here: it means the census is stale
# and the SOURCE-ONLY inventory the subtractive phase reads is wrong.
cat >"$work/pinned" <<'PIN'
jit	L1
gpu	L1
simd	L2
foreign	L4
reflect	L1
meta	L2
wasm	L5
compiler	L5
mcp	L1
PIN

printf '%s\n' '== §5 ledger ================================================================='
# Pinned alongside the level rows, for the same reason: these are the two
# surfaces a reader trusts most (the help text and a "generated" header) and
# they are both currently wrong.
[ "${dead# }" = "catalog dev" ] \
    || note "§5 the dead documented-command set moved: expected 'catalog dev', measured '${dead# }'"
[ "${gen_drift# }" = "lib/wasm/opcode_lookup.id lib/wasm/ward_mvp_opcodes.id lib/token/classify.id" ] \
    || note "§5 the generator-drift set moved: measured '${gen_drift# }'"
if cmp -s "$work/pinned" "$ledger"; then
    printf '  measured census matches the pinned ledger (%s subjects)\n' "$total_subjects"
else
    printf '  pinned vs measured:\n'
    diff -u "$work/pinned" "$ledger" | sed 's/^/    /' >&2
    note "§5 the census MOVED — update the pinned ledger in this file and say what changed"
fi

[ "$fail" -eq 0 ] || exit 1
printf 'surface/reach: pass — %s subjects across %s subsystems, census matches ledger\n' \
    "$total_subjects" "$(printf '%s\n' $systems | grep -c .)"
