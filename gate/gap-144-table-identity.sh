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
# NC5  A realization knob cannot move a canonical relation identity. Target,
#      ABI and allocator are varied on the exercised generated-C path, and
#      every relation the graph publishes must come back out of each variant
#      under the same name.
#
# NC4 (fail closed on removed table demand) and NC6 (provenance survives
# folding into machine byte ranges) are NOT pinned here and remain owed by the
# gap.
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
# NC5 IS THREE AXES AND EACH ONE MUST BE PROVED LIVE FIRST. An invariance
# asserted across a knob that reached nothing is the vacuity this repository
# keeps rediscovering, so no axis is believed until its own liveness evidence
# is in hand:
#
#   target     `--target native` against `--target wasm32-wasi` must EMIT
#              DIFFERENT C before "the relation identities did not move" is
#              worth asserting
#   abi        the same emitted C linked position-dependent against
#              position-independent must produce DIFFERENT binaries, and then
#              carry identical relation symbols and identical values
#   allocator  the realization must reach an allocator at all, and glibc's
#              MALLOC_PERTURB_ must be observably live on this host, before
#              "the values did not move under another allocator" means
#              anything
#
# THE GRAPH IS THE AUTHORITY AND THE REALIZATION IS THE SUBJECT. `idol graph`
# publishes this program's relation identities; the identity read then asks, of
# each variant, which emitted or linked definitions carry that relation. A
# realization prefix is admitted, because the entry relation reaches the C as
# `duo_entry_main`; a renamed relation is not, and a relation the graph
# publishes that no name in a variant realizes fails the gate rather than
# quietly comparing two empty sets.
#
# An axis this host cannot vary exits 2 (unexercisable), never 0 — a control
# that could not run is not a control that passed.
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

# graph_rels <graph.json> — the canonical relation identities the graph
# publishes for this program, sorted. The graph is the AUTHORITY NC5 measures
# realizations against, and no realization gets a vote on it.
graph_rels() {
    grep -oaE '"kind":"func","name":"[A-Za-z0-9_]+"' "$1" |
        sed 's/.*"name":"//; s/"$//' | sort -u
}

# emitted_names <file.c> — the function definitions an emitted C artifact
# carries. linked_names <binary> — the ones a linked artifact defines.
# Identifiers reserved to the C implementation (leading underscore) are dropped
# from both: `__wrap_main` arrives from the host runtime on the
# position-dependent link and realizes no Idol relation.
emitted_names() {
    grep -oaE '^([A-Za-z_][A-Za-z0-9_]*[ *]+)+[A-Za-z_][A-Za-z0-9_]*\(' "$1" |
        grep -oaE '[A-Za-z_][A-Za-z0-9_]*\($' | tr -d '(' |
        grep -vE '^_' | sort -u
}

linked_names() {
    nm "$1" | awk '$2 == "t" || $2 == "T" { print $3 }' | grep -vE '^_' | sort -u
}

# carries <namefile> <relation> — the names in <namefile> that realize
# <relation>: the ones carrying it as a whole word component. A realization
# prefix is admitted, because the entry relation reaches the C as
# `duo_entry_main`; a RENAMED relation is not, which is what makes this the
# observable NC5 is about.
carries() {
    grep -aE "(^|_)$2(_|\$)" "$1"
}

# run_probe <out> <cmd...> — observed values: stdout plus exit status. The
# command is passed whole rather than as a bare binary so an environment can be
# varied with `env` without leaking assignments into this shell.
run_probe() {
    _o=$1
    shift
    "$@" >"$_o" 2>"$_o.err"
    printf 'exit=%s\n' "$?" >>"$_o"
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

    # C4 — the RELATION IDENTITY read convicts a renamed RELATION, and is not
    # passing by returning an empty set. NC1 renames table BINDINGS and requires
    # agreement; this is the opposite direction, and it is what proves the read
    # NC5 depends on can see a relation identity at all.
    mkdir -p "$_c/rel1" "$_c/rel2" || exit 2
    cat >"$_c/rel1/probe.id" <<'PLANT'
tally: i64 = (bag)
    bag:len()

main: i64 = ()
    bag = {}
    bag(1) = 5
    print(tally(bag))
    0
PLANT
    sed 's/\btally\b/stash/g' "$_c/rel1/probe.id" >"$_c/rel2/probe.id"
    ( CDPATH='' cd -- "$_c/rel1" && "$idol" dump-c probe.id ) >"$_c/rel1.c" 2>"$_c/rel1.err"
    ( CDPATH='' cd -- "$_c/rel2" && "$idol" dump-c probe.id ) >"$_c/rel2.c" 2>"$_c/rel2.err"
    emitted_names "$_c/rel1.c" >"$_c/rel1.names"
    emitted_names "$_c/rel2.c" >"$_c/rel2.names"
    if ! carries "$_c/rel1.names" tally | grep -q .; then
        cat "$_c/rel1.err" >&2
        printf 'gap-144 control: FAIL — the relation identity read found no realization of a declared relation\n' >&2
        _rc=1
    elif carries "$_c/rel2.names" tally | grep -q .; then
        printf 'gap-144 control: FAIL — the relation identity read still reports a relation that was renamed away\n' >&2
        _rc=1
    elif ! carries "$_c/rel2.names" stash | grep -q .; then
        printf 'gap-144 control: FAIL — the relation identity read does not follow a relation to its new name\n' >&2
        _rc=1
    fi

    # C5 — the ALLOCATOR axis needs an allocator that can actually be varied
    # here. glibc's MALLOC_PERTURB_ writes a known byte over freed and freshly
    # allocated memory; if both runs of this control agree, the knob reached
    # nothing on this host and NC5's allocator axis is UNEXERCISABLE. That
    # exits 2, because a control that could not run is not a control that
    # passed.
    cat >"$_c/perturb.c" <<'PLANT'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    unsigned char *p = malloc(4096);
    if (p == NULL) return 1;
    memset(p, 0xab, 4096);
    free(p);
    unsigned char *q = malloc(4096);
    if (q == NULL) return 1;
    printf("%02x\n", q[2048]);
    free(q);
    return 0;
}
PLANT
    if ! "$cc" "$_c/perturb.c" -o "$_c/perturb.bin" 2>"$_c/perturb.cc.err"; then
        cat "$_c/perturb.cc.err" >&2
        printf 'gap-144 control: FAIL — the allocator liveness control did not compile\n' >&2
        _rc=1
    else
        "$_c/perturb.bin" >"$_c/perturb.plain" 2>/dev/null
        env MALLOC_PERTURB_=165 "$_c/perturb.bin" >"$_c/perturb.set" 2>/dev/null
        if cmp -s "$_c/perturb.plain" "$_c/perturb.set"; then
            printf 'gap-144-table-identity gate: this host does not observe MALLOC_PERTURB_, so NC5 cannot vary the allocator here\n' >&2
            exit 2
        fi
    fi

    # C6 — VACUITY, the NC5 half. Zero varied knobs must not be a pass.
    if axes_pass 0; then
        printf 'gap-144 control: FAIL — zero varied realization knobs was accepted as a pass\n' >&2
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
    printf 'gap-144 control: PASS — value, realization, graph and relation identity comparators each convict; the allocator is perturbable here; zero pairs and zero knobs refused\n'
    return 0
}

# axes_pass <n> — NC5 names three knobs, so a run that varied fewer than three
# asserted less than the control it claims to pin.
axes_pass() {
    [ "$1" -ge 3 ]
}

# pairs_pass <n> — a run is a pass only with at least one pair compared.
pairs_pass() {
    [ "$1" -ge 1 ]
}

[ -x "$idol" ] || { printf 'gap-144-table-identity gate: compiler is not executable: %s\n' "$idol" >&2; exit 2; }
command -v "$cc" >/dev/null 2>&1 || { printf 'gap-144-table-identity gate: C compiler is unavailable: %s\n' "$cc" >&2; exit 2; }
command -v nm >/dev/null 2>&1 || { printf 'gap-144-table-identity gate: nm is unavailable, so NC5 cannot read a linked relation symbol\n' >&2; exit 2; }

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
# §5 NC5 — A REALIZATION KNOB CANNOT MOVE A CANONICAL RELATION IDENTITY.
# Target, ABI and allocator are the three knobs the control names. The graph
# publishes the relation identities; each knob is varied, each is proved to
# have reached something before its invariance is believed, and the identities
# are then read back out of the artifact that knob actually produced.
AXES=0

knob=$work/knob
mkdir -p "$knob" || exit 2
# The probe applies its relations as `tally(bag)` rather than the subject face
# `bag:tally()`. That is not a preference: MEASURED on this tree, the two faces
# of one relation over a table value answer differently — a probe whose only
# difference is `print(tally(bag))` against `print(bag:tally())` printed 1 and
# 140733193388032. NC5 is about relation identity under realization knobs, so it
# is asserted over the face that answers, and it claims nothing about the other.
cat >"$knob/probe.id" <<'PROBE'
tally: i64 = (bag)
    bag(bag:len() + 1) = 9
    bag:len()

sift: i64 = (bag, ndx)
    bag[ndx]

main: i64 = ()
    bag = {}
    for cur = 1, 6
        bag(bag:len() + 1) = cur * 10
    print(tally(bag))
    print(sift(bag, 6))
    print(bag:len())
    0
PROBE

# emit <target> <out> — the emitted C for one target.
emit() {
    ( CDPATH='' cd -- "$knob" && "$idol" dump-c --target "$1" probe.id ) >"$2" 2>"$2.err"
}

# knob_rels <label> <namefile> — the realization of every canonical relation,
# one block per relation, so a comparison names which relation moved. An empty
# block is a measurement of nothing and is refused here rather than compared.
knob_rels() {
    _out=$knob/$1.rels
    : >"$_out"
    while read -r _r; do
        printf '%s:' "$_r" >>"$_out"
        carries "$2" "$_r" | tr '\n' ' ' >>"$_out"
        printf '\n' >>"$_out"
        carries "$2" "$_r" | grep -q . || {
            fail "knob/$1: relation '$_r' is published by the graph and realized by no name in $2"
            return 1
        }
    done <"$knob/graph.rels"
    return 0
}

nc5() {
    ( CDPATH='' cd -- "$knob" && "$idol" graph probe.id ) >"$knob/graph.json" 2>"$knob/graph.err" || {
        cat "$knob/graph.err" >&2
        fail 'knob: the graph refused the probe, so there is no authority to measure against'
        return 1
    }
    graph_rels "$knob/graph.json" >"$knob/graph.rels"

    # VACUITY. The authority must publish the relations this probe DECLARES.
    for _r in tally sift main; do
        grep -qx "$_r" "$knob/graph.rels" || {
            fail "knob: the graph publishes no relation identity for '$_r', so nothing below is being measured"
            return 1
        }
    done

    emit native "$knob/native.c" || {
        cat "$knob/native.c.err" >&2
        fail 'knob: the native target emitted no C'
        return 1
    }
    emit wasm32-wasi "$knob/wasm.c" || {
        cat "$knob/wasm.c.err" >&2
        fail 'knob: the wasm32-wasi target emitted no C'
        return 1
    }

    # AXIS 1 TARGET. Live first: two targets that emit the same bytes have
    # varied nothing, and their agreement would then be an artifact of the knob
    # being ignored rather than of relation identity holding still.
    if cmp -s "$knob/native.c" "$knob/wasm.c"; then
        fail 'knob/target: both targets emitted identical C, so this axis asserted nothing'
    else
        emitted_names "$knob/native.c" >"$knob/native.names"
        emitted_names "$knob/wasm.c" >"$knob/wasm.names"
        knob_rels native "$knob/native.names" || return 1
        knob_rels wasm "$knob/wasm.names" || return 1
        AXES=$((AXES + 1))
        cmp -s "$knob/native.rels" "$knob/wasm.rels" || {
            diff "$knob/native.rels" "$knob/wasm.rels" >&2
            fail 'knob/target: changing the target moved a canonical relation identity'
        }
    fi

    # AXIS 2 ABI. One emitted C, two link-time ABIs.
    "$cc" -fno-pie -no-pie "$knob/native.c" -o "$knob/fixed.bin" -lm 2>"$knob/fixed.cc.err" || {
        cat "$knob/fixed.cc.err" >&2
        fail "knob/abi: $cc refused the position-dependent link"
        return 1
    }
    "$cc" -fPIE -pie "$knob/native.c" -o "$knob/moved.bin" -lm 2>"$knob/moved.cc.err" || {
        cat "$knob/moved.cc.err" >&2
        fail "knob/abi: $cc refused the position-independent link"
        return 1
    }
    if cmp -s "$knob/fixed.bin" "$knob/moved.bin"; then
        fail 'knob/abi: both ABIs produced identical binaries, so this axis asserted nothing'
    else
        linked_names "$knob/fixed.bin" >"$knob/fixed.names"
        linked_names "$knob/moved.bin" >"$knob/moved.names"
        knob_rels fixed "$knob/fixed.names" || return 1
        knob_rels moved "$knob/moved.names" || return 1
        AXES=$((AXES + 1))
        cmp -s "$knob/fixed.rels" "$knob/moved.rels" || {
            diff "$knob/fixed.rels" "$knob/moved.rels" >&2
            fail 'knob/abi: changing the ABI moved a canonical relation identity'
        }
        run_probe "$knob/fixed.out" "$knob/fixed.bin"
        run_probe "$knob/moved.out" "$knob/moved.bin"
        cmp -s "$knob/fixed.out" "$knob/moved.out" || {
            diff "$knob/fixed.out" "$knob/moved.out" >&2
            fail 'knob/abi: changing the ABI changed the observed values'
        }
    fi

    # AXIS 3 ALLOCATOR. An allocator the realization never reaches cannot be
    # varied, so that is established before it is perturbed. `--selftest` has
    # already proved this host observes MALLOC_PERTURB_ at all.
    if grep -qaE '\b(malloc|calloc|realloc)\b' "$knob/native.c"; then
        AXES=$((AXES + 1))
        # Perturbed bytes, one arena, and every allocation mmapped: freed and
        # fresh memory carries a known byte instead of whatever was there, and
        # the placement strategy changes with it. Both are the allocator
        # behaving differently under unchanged relation identities.
        run_probe "$knob/perturbed.out" env \
            MALLOC_PERTURB_=165 MALLOC_ARENA_MAX=1 MALLOC_MMAP_THRESHOLD_=0 \
            "$knob/fixed.bin"
        cmp -s "$knob/fixed.out" "$knob/perturbed.out" || {
            diff "$knob/fixed.out" "$knob/perturbed.out" >&2
            fail 'knob/allocator: changing the allocator changed the observed values'
        }
    else
        fail 'knob/allocator: this realization reaches no allocator, so the allocator axis asserted nothing'
    fi
    return 0
}

nc5

axes_pass "$AXES" || fail 'not every named realization knob was varied — NC5 asserted less than the control it pins'

# ---------------------------------------------------------------------------
pairs_pass "$PAIRS" || fail "no rename pair was compared — this run measured nothing"

[ "$RC" -eq 0 ] || exit 1
printf 'gap-144-table-identity gate: PASS — %s rename pairs invariant in graph, realization and value; alias identity held; five table cases distinct; %s realization knobs varied without moving a relation identity\n' "$PAIRS" "$AXES"
