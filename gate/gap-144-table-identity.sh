#!/bin/sh
# gate/gap-144-table-identity.sh — GAP-144's negative controls, executed.
#
# WHAT THIS PINS, and why it is not the construction half. `gaps/GAP-144.md`
# has two halves. The REJECTION half is crossed: `d806f566` selected growable
# table realization from source binding names, `5f08600a` rejected it, and no
# line of it is in the tree. The CONSTRUCTION half — a graph-authoritative
# growable realization meeting the eight required-boundary items — is unstarted
# and stays OPEN. This gate is neither. It closes the gap's own third finding:
#
#     "None of the eight required-boundary items or the six negative controls
#      in this file is pinned by any gate, test or build step."
#
# Three of the six negative controls are TRUE OF THE CURRENT TREE and were
# measured, not assumed. Nothing held them there. A rejection recorded only as
# an absent symbol is a specimen fix: the next name-selected lowering will not
# be spelled `collectIndexedNames`, and `git grep` for a retired identifier
# cannot see it. What convicts the CLASS is the observation the class violates,
# so each control below is asserted as an observation and holds against any
# spelling (`law.repair.class`).
#
# NC1  Renaming a source binding, preserving its semantic value identity,
#      cannot change table representation or behavior.
# NC2  Aliasing the same table cannot mint another table identity or lose
#      mutation.
# NC3  Present integer zero must remain distinguishable from absence.
#      Asserted with the rest of required-boundary item 2's case set: absent,
#      present zero, invalid index, empty, and length are five distinct
#      observations, not one integer zero wearing five hats. Answering an
#      unwritten element as 0 was defect 1 of the rejected branch.
#
# NC4 (fail closed on removed table demand), NC5 (ABI/allocator/target cannot
# move relation identity) and NC6 (provenance survives folding into machine
# byte ranges) are NOT pinned here and remain owed by the gap.
#
# NC1 IS ASSERTED AT THREE LEVELS, because a rename that changes nothing
# observable can still have changed the physical choice — that is exactly what
# the rejected branch did when a textually-named empty table became heap-backed
# on a later index. Values alone would have passed it.
#
#   graph        `idol graph` export, byte-identical
#   realization  emitted C, byte-identical
#   value        stdout and exit status, byte-identical
#
# The two spellings in a pair use SAME-LENGTH identifiers, so line and column
# provenance is identical too and the only admitted normalization is the
# identifier substitution itself plus `source_hash`, which is a hash of the
# source text and provenance by construction. A normalization broad enough to
# hide a representation change would be the defect, so it is kept this narrow
# on purpose.
#
# EXECUTION PATH, and what this evidence does NOT cover. `idol run` on this
# host refuses with `wasm32-wasi: no native realization (UnsupportedProgram)`,
# so the direct-native path executes nothing here and the generated-C
# realization is the exact exercised path — the same bridge
# gate/gap-114-boxed-len.sh and gate/gap-141-runtime-temp.sh run through.
# Generated-C evidence is not direct-native evidence and is not Wasm evidence.
# Required-boundary item 8 wants a direct-native/C differential and allocation,
# copy and latency counts against a C floor; none of that is claimed here.
#
# `--selftest` runs the planted-violation controls and exits. The full run
# executes them first: a gate that measures nothing passes, and that is the
# recurring defect in this repository.
#
# THE BUILD LOCK. This gate writes nothing into the repository — it reads
# `zig-out/bin/idol` and works in its own mktemp directory — but it takes the
# shared build lock anyway, because a concurrent `zig build` in THIS worktree
# would replace the compiler underneath a run and the two halves of a pair
# would then come from two compilers. The lock is heavily contended by
# 20-minute builds, so a run can exit 75 (`idol-lock: timed out`) having
# asserted nothing; that is a lock outcome, not a gate outcome, and it must not
# be read as a pass or a failure. `IDOL_LOCK_HELD=1` is the documented bypass
# for a caller that already holds the lock or has otherwise pinned `zig-out`.
set -u

root=${GAP144_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
cc=${CC:-cc}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap144.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

RC=0

fail() {
    printf 'gap-144-table-identity gate: FAIL %s\n' "$1" >&2
    RC=1
}

# ---------------------------------------------------------------------------
# NORMALIZE. The ONLY admitted difference between the two spellings of a pair.
# `$1` file, `$2` space-separated `a:b` identifier pairs. Each side of a pair
# collapses to the same opaque token, so a surviving difference is a difference
# the compiler made for a reason other than the name.
normalize() {
    _f=$1
    _spec=$2
    _n=0
    _script='s/"source_hash":[0-9-]+/"source_hash":NORMALIZED/g;'
    for _p in $_spec; do
        _n=$((_n + 1))
        _script="$_script s/\\b${_p%%:*}\\b/IDOLGATENAME$_n/g; s/\\b${_p##*:}\\b/IDOLGATENAME$_n/g;"
    done
    sed -E "$_script" "$_f"
}

# build <dir> <label> — emit C, compile it, and run it. Writes <dir>/out and
# <dir>/graph.json. Returns non-zero and reports on any stage that refuses.
build() {
    _d=$1
    _l=$2
    ( CDPATH='' cd -- "$_d" && "$idol" graph probe.id ) >"$_d/graph.json" 2>"$_d/graph.err" || {
        cat "$_d/graph.err" >&2
        fail "$_l: graph export refused"
        return 1
    }
    ( CDPATH='' cd -- "$_d" && "$idol" dump-c probe.id ) >"$_d/probe.c" 2>"$_d/emit.err" || {
        cat "$_d/emit.err" >&2
        fail "$_l: emitted no C"
        return 1
    }
    "$cc" "$_d/probe.c" -o "$_d/probe.bin" -lm 2>"$_d/cc.err" || {
        cat "$_d/cc.err" >&2
        fail "$_l: emitted C that $cc refused"
        return 1
    }
    "$_d/probe.bin" >"$_d/out" 2>"$_d/run.err"
    printf 'exit=%s\n' "$?" >>"$_d/out"
    return 0
}

# ---------------------------------------------------------------------------
# §1 CONTROLS. Each proves one comparator can convict. Without these the whole
# gate could pass by comparing nothing, or by normalizing every difference away.
selftest() {
    _c=$work/control
    mkdir -p "$_c/a" "$_c/b" "$_c/c" || exit 2
    _rc=0

    # C1 — the VALUE comparator convicts differing output.
    printf '1\nexit=0\n' >"$_c/a/out"
    printf '2\nexit=0\n' >"$_c/b/out"
    if cmp -s "$_c/a/out" "$_c/b/out"; then
        printf 'gap-144 control: FAIL — value comparator called 1 and 2 equal\n' >&2
        _rc=1
    fi

    # C2 — the REALIZATION comparator convicts a body difference under
    # IDENTICAL identifiers, so the normalizer cannot be passing by erasing
    # everything. Same names, one changed bound.
    cat >"$_c/a/probe.id" <<'PLANT'
main: i64 = ()
    pot = {}
    for cur = 1, 4
        pot(pot:len() + 1) = cur * 10
    print(pot:len())
    0
PLANT
    sed 's/1, 4/1, 5/' "$_c/a/probe.id" >"$_c/c/probe.id"
    if build "$_c/a" 'control-a' && build "$_c/c" 'control-c'; then
        normalize "$_c/a/probe.c" 'pot:pot cur:cur' >"$_c/a/probe.c.norm"
        normalize "$_c/c/probe.c" 'pot:pot cur:cur' >"$_c/c/probe.c.norm"
        if cmp -s "$_c/a/probe.c.norm" "$_c/c/probe.c.norm"; then
            printf 'gap-144 control: FAIL — realization comparator called two different bodies equal\n' >&2
            _rc=1
        fi
        normalize "$_c/a/graph.json" 'pot:pot cur:cur' >"$_c/a/graph.norm"
        normalize "$_c/c/graph.json" 'pot:pot cur:cur' >"$_c/c/graph.norm"
        if cmp -s "$_c/a/graph.norm" "$_c/c/graph.norm"; then
            printf 'gap-144 control: FAIL — graph comparator called two different bodies equal\n' >&2
            _rc=1
        fi
    else
        printf 'gap-144 control: FAIL — control probes did not build\n' >&2
        _rc=1
    fi

    # C3 — VACUITY. Zero pairs must not be reportable as a pass. The count the
    # PASS line prints is derived from the pairs actually run, so a zero here
    # is a gate that measured nothing.
    if pairs_pass 0; then
        printf 'gap-144 control: FAIL — zero pairs was accepted as a pass\n' >&2
        _rc=1
    fi

    [ "$_rc" -eq 0 ] || return 1
    printf 'gap-144 control: PASS — value, realization and graph comparators each convict, zero pairs refused\n'
    return 0
}

# pairs_pass <n> — a run is a pass only with at least one pair compared.
pairs_pass() {
    [ "$1" -ge 1 ]
}

[ -x "$idol" ] || { printf 'gap-144-table-identity gate: compiler is not executable: %s\n' "$idol" >&2; exit 2; }
command -v "$cc" >/dev/null 2>&1 || { printf 'gap-144-table-identity gate: C compiler is unavailable: %s\n' "$cc" >&2; exit 2; }

case ${1:-} in
    --selftest) selftest || exit 1; exit 0 ;;
    '') ;;
    *) printf 'usage: %s [--selftest]\n' "$0" >&2; exit 2 ;;
esac

selftest || exit 1

# ---------------------------------------------------------------------------
# §2 NC1 — RENAME INVARIANCE. Each pair is one Idol program in two spellings
# that differ ONLY in binding identifiers of equal length.
PAIRS=0

# rename_pair <name> <spec> — reads probe source on stdin, writes the renamed
# sibling with sed from <spec>, and requires graph, C and values to agree.
rename_pair() {
    _name=$1
    _spec=$2
    _a=$work/$_name.a
    _b=$work/$_name.b
    mkdir -p "$_a" "$_b" || exit 2
    cat >"$_a/probe.id"

    _sed=''
    for _p in $_spec; do
        _sed="$_sed s/\\b${_p%%:*}\\b/${_p##*:}/g;"
    done
    sed -E "$_sed" "$_a/probe.id" >"$_b/probe.id"

    # A rename that renamed nothing would make every assertion below vacuous.
    if cmp -s "$_a/probe.id" "$_b/probe.id"; then
        fail "$_name: the two spellings are identical, so nothing was renamed"
        return 1
    fi

    build "$_a" "$_name.a" || return 1
    build "$_b" "$_name.b" || return 1
    PAIRS=$((PAIRS + 1))

    cmp -s "$_a/out" "$_b/out" || {
        diff "$_a/out" "$_b/out" >&2
        fail "$_name: renaming a binding changed the observed values"
    }

    normalize "$_a/graph.json" "$_spec" >"$_a/graph.norm"
    normalize "$_b/graph.json" "$_spec" >"$_b/graph.norm"
    cmp -s "$_a/graph.norm" "$_b/graph.norm" || {
        diff "$_a/graph.norm" "$_b/graph.norm" | head -20 >&2
        fail "$_name: renaming a binding changed the semantic graph"
    }

    normalize "$_a/probe.c" "$_spec" >"$_a/probe.c.norm"
    normalize "$_b/probe.c" "$_spec" >"$_b/probe.c.norm"
    cmp -s "$_a/probe.c.norm" "$_b/probe.c.norm" || {
        diff "$_a/probe.c.norm" "$_b/probe.c.norm" | head -20 >&2
        fail "$_name: renaming a binding changed the emitted realization"
    }
    return 0
}

# The rejected branch's exact trigger: an EMPTY table whose textual name is
# later indexed, grown through a length read. Under `d806f566` this shape is
# what promoted the binding to heap-backed storage by name.
rename_pair grow 'pot:jar cur:ndx' <<'PROBE'
main: i64 = ()
    pot = {}
    for cur = 1, 4
        pot(pot:len() + 1) = cur * 10
    print(pot:len())
    print(pot[1])
    print(pot[4])
    0
PROBE

# The same table crossing a call boundary and rebound inside the callee, where
# the rejected branch's whole-body name walk lost the identity entirely. Only
# the TABLE binding is renamed: a relation's own name reaches the emitted
# linkage symbol (`idol_probe__add`) by design, and moving that is NC5's
# subject, not NC1's.
rename_pair cross 'bag:sac' <<'PROBE'
add: i64 = (bag)
    bag(bag:len() + 1) = 9
    bag:len()

main: i64 = ()
    bag = {}
    bag(1) = 3
    print(add(bag))
    print(bag:len())
    print(bag[2])
    0
PROBE

# ---------------------------------------------------------------------------
# §3 NC2 — ALIASING. Two names for one table are one table: the mutation made
# through the second name is visible through the first, and the first name's
# earlier write is visible through the second.
alias_dir=$work/alias
mkdir -p "$alias_dir" || exit 2
cat >"$alias_dir/probe.id" <<'PROBE'
main: i64 = ()
    pot = {}
    pot(1) = 3
    jar = pot
    jar(2) = 7
    print(pot:len())
    print(pot[2])
    print(jar[1])
    0
PROBE
if build "$alias_dir" alias; then
    printf '2\n7\n3\nexit=0\n' | cmp -s - "$alias_dir/out" || {
        cat "$alias_dir/out" >&2
        fail "alias: expected len 2, pot[2]=7, jar[1]=3 — a second identity was minted or a mutation was lost"
    }
fi

# ---------------------------------------------------------------------------
# §4 NC3 and required-boundary item 2 — FIVE DISTINCT CASES. Defect 1 of the
# rejected branch collapsed every one of these onto integer zero. The probe
# prints one line per case, in this order, and the expected block below is
# read against it position by position:
#
#     0         empty table length
#     absent    element 1 of an empty table
#     1         length after ONE write, of the value zero
#     present   that written zero — present, not absent
#     absent    an unwritten index inside no written range
#     absent    index 0
#     absent    a negative index
#
# The labels live here rather than in the probe because `print(a, b)` writes a
# tab between its operands and DNB001 leaves `..` unavailable, so a labelled
# line would assert the separator instead of the case.
cases_dir=$work/cases
mkdir -p "$cases_dir" || exit 2
cat >"$cases_dir/probe.id" <<'PROBE'
report: i64 = (value)
    if value == nil
        print("absent")
    else
        print("present")
    0

main: i64 = ()
    pot = {}
    print(pot:len())
    report(pot[1])
    pot(1) = 0
    print(pot:len())
    report(pot[1])
    report(pot[9])
    report(pot[0])
    report(pot[0 - 1])
    0
PROBE
if build "$cases_dir" cases; then
    cat >"$work/cases.want" <<'WANT'
0
absent
1
present
absent
absent
absent
exit=0
WANT
    cmp -s "$work/cases.want" "$cases_dir/out" || {
        diff "$work/cases.want" "$cases_dir/out" >&2
        fail "cases: absent, present zero, invalid index, empty and length are no longer five distinct observations"
    }
fi

# ---------------------------------------------------------------------------
pairs_pass "$PAIRS" || fail "no rename pair was compared — this run measured nothing"

[ "$RC" -eq 0 ] || exit 1
printf 'gap-144-table-identity gate: PASS — %s rename pairs invariant in graph, realization and value; alias identity held; five table cases distinct\n' "$PAIRS"
