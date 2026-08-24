#!/bin/sh
# gate/lower/fallback.sh — law.fallback.zero at the SHC TRANSFER ROUTE.
#
# `idol dump-c <file> --lib` is not one recipe among several. It is THE recipe
# that produced the tree's only executed Idol authority: tools/node/dev/lexer/
# artifact runs exactly this command on lib/compiler/lexer.id, and the C it
# emits is src/lexer_tokenize.c, which the host links and calls. Every future
# transfer named in docs/bootstrap.md — parser recognition, binding, scope —
# has to cross the same seam.
#
# WHAT THIS GATE MEASURES, and why it is not a style check.
#
# In a pure-native module (`!moduleNeedsLuaRuntime()`), src/codegen.zig:17698
# lowers a qualified call whose callee body is not at file scope to
#
#     duo_fatal("unlowered native call")
#
# and the command EXITS 0 with EMPTY STDERR. So the route reports success while
# replacing the body of the transferred decision with a runtime abort. That is
# a silent fallback (`law.fallback.zero`) at the one seam a self-host transfer
# must survive, and nothing in this tree measured it.
#
# The refusal machinery already exists and is already correct one arm over:
# lib/compiler/emit_c.id refuses with "codegen refused a reference to a module
# it cannot find". UNKNOWN module refuses; KNOWN module, non-local body aborts
# silently. This gate pins that asymmetry so it cannot spread, and so the day
# it is repaired the pins fall and say so.
#
# CONSEQUENCE THIS GATE EXISTS TO KEEP VISIBLE (GAP-134 / GAP-145): the one
# grammar-fact owner is unreachable from Idol. lib/compiler/token_view.id — the
# immutable token view GAP-134 names as the parser-slice prerequisite — emits
# three of these aborts, one for each of its `token.grammarrole.*` consumers.
# An Idol parser recognition decision therefore either aborts at runtime or
# inlines its own copy of the grammar facts, and the second is the fourth
# grammar authority `law.grammar.one` forbids.
#
# THE RATCHET. Every subject is pinned by exact measured class in
# gate/lower/fallback.baseline. A RISE fails. A FALL fails, so that a repair
# must lower the pin and be seen. An UNPINNED subject fails. A pin naming a
# subject that no longer enumerates fails. It is a ratchet, not a budget.
set -u

cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)" || exit 3

IDOL=${IDOL:-./zig-out/bin/idol}
baseline=gate/lower/fallback.baseline
abort='unlowered native call'

if [ ! -x "$IDOL" ]; then
    printf 'lower fallback: NOT MEASURED — compiler is not executable: %s\n' "$IDOL" >&2
    exit 3
fi
if [ ! -r "$baseline" ]; then
    printf 'lower fallback: NOT MEASURED — baseline is unreadable: %s\n' "$baseline" >&2
    exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.lower.fallback.XXXXXX") || exit 3
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Measure one subject. Prints REFUSED when the route fails closed, otherwise
# the exact number of silent aborts it emitted. Refusal is the LAWFUL answer
# here and is recorded as its own class, never folded into a count of zero:
# a subject that stops refusing and starts aborting must be visible.
measure() {
    if "$IDOL" dump-c "$1" --lib >"$work/out.c" 2>/dev/null; then
        grep -c "$abort" "$work/out.c"
    else
        printf 'REFUSED\n'
    fi
}

# ============================== BOTH CONTROLS ==============================
# A reader that reports zero on everything agrees with a clean tree and with a
# broken tree alike. `scripts/grammarconvergence.id` exited 0 on a fully
# damaged owner for exactly that reason, so this file proves it can see the
# defect and proves it does not invent one, before it reports anything.
#
# POSITIVE: a cross-module call must be COUNTED. `compiler.reader.read` is a
# two-line relation in lib/compiler/reader.id; the call resolves, and the route
# still emits the abort.
cat >"$work/positive.id" <<'PROBE'
grab: i64 = (d: { value: i64 })
  compiler.reader.read(d)
PROBE
positive=$(measure "$work/positive.id")
case $positive in
    REFUSED|0)
        printf 'lower fallback control: FAIL — a planted cross-module call measured %s, so this reader cannot see the defect it exists to count\n' "$positive" >&2
        exit 3
        ;;
esac

# NEGATIVE: a file whose every call is file-scope local must measure ZERO. A
# reader that counted the string anywhere in the emitted C would pass the
# positive control and still be wrong about every subject below.
cat >"$work/negative.id" <<'PROBE'
twice: i64 = (n: i64)
  n * 2

quad: i64 = (n: i64)
  twice(twice(n))
PROBE
negative=$(measure "$work/negative.id")
if [ "$negative" != 0 ]; then
    printf 'lower fallback control: FAIL — a file with only local calls measured %s, not 0\n' "$negative" >&2
    exit 3
fi
printf 'lower fallback control: PASS — planted cross-module call counted %s; local-only file counted 0\n' "$positive"

# ============================== THE SUBJECTS ===============================
# gate/subject.sh owns the GAP-201 ruling that zero subjects is a FAILURE and
# the GAP-220 ruling that "not a git work tree" is distinguishable from "no
# such file". Both matter here: this gate is cheap enough to run in a mirror.
subjects=$(sh gate/subject.sh -- lib/compiler lib/token) || exit 3

pinned=$(grep -v '^#' "$baseline" | grep -v '^[[:space:]]*$')
if [ -z "$pinned" ]; then
    printf 'lower fallback: NOT MEASURED — the baseline pins no subject\n' >&2
    exit 3
fi

status=0
seen=$work/seen
: >"$seen"
total=0
counted=0
refused=0

for subject in $subjects; do
    printf '%s\n' "$subject" >>"$seen"
    pin=$(printf '%s\n' "$pinned" | awk -v s="$subject" '$2 == s { print $1 }')
    got=$(measure "$subject")
    case $got in
        REFUSED) refused=$((refused + 1)) ;;
        *) total=$((total + got)); [ "$got" -gt 0 ] && counted=$((counted + 1)) ;;
    esac
    if [ -z "$pin" ]; then
        printf 'lower fallback: UNPINNED %s measured %s — every transfer subject must carry a pin\n' "$subject" "$got" >&2
        status=1
        continue
    fi
    [ "$pin" = "$got" ] && continue
    if [ "$pin" = REFUSED ] || [ "$got" = REFUSED ]; then
        printf 'lower fallback: CLASS CHANGED %s pinned %s, measured %s\n' "$subject" "$pin" "$got" >&2
        status=1
    elif [ "$got" -gt "$pin" ]; then
        printf 'lower fallback: ROSE %s pinned %s, measured %s\n' "$subject" "$pin" "$got" >&2
        status=1
    else
        printf 'lower fallback: FELL %s pinned %s, measured %s — lower the pin so the repair is recorded\n' "$subject" "$pin" "$got" >&2
        status=1
    fi
done

# A pin describing a subject that no longer enumerates is the other edge. Left
# unchecked the baseline becomes a museum and the gate quietly guards less than
# it claims — the failure mode gate/treesitter/agreement.sh calls STALE.
printf '%s\n' "$pinned" | while read -r pin subject; do
    grep -qxF "$subject" "$seen" && continue
    printf 'lower fallback: STALE pin %s %s — the baseline names a subject that no longer enumerates\n' "$pin" "$subject" >&2
    printf 'stale\n' >>"$work/stale"
done
[ -f "$work/stale" ] && status=1

printf 'lower fallback: %s subject(s); %s emit silent aborts (%s total); %s fail closed and refuse\n' \
    "$(printf '%s\n' $subjects | wc -l | tr -d ' ')" "$counted" "$total" "$refused"

if [ "$status" -ne 0 ]; then
    printf 'lower fallback: FAIL — the silent-abort ratchet moved\n' >&2
    exit 1
fi
printf 'lower fallback: OK — every transfer subject matches its pin\n'
exit 0
