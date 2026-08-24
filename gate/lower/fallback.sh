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
# Before this gate's repair, a pure-native module
# (`!moduleNeedsLuaRuntime()`) lowered a qualified call whose callee body was
# not at file scope to
#
#     duo_fatal("unlowered native call")
#
# and the command exited 0 with empty stderr. The production emitter now
# refuses that unknown realization before it can be accepted as a transfer.
# This gate keeps the old marker as a zero ceiling and pins every affected
# subject in the REFUSED class until a real cross-home realization replaces it.
#
# The refusal machinery already existed one arm over:
# lib/compiler/emit_c.id refuses with "codegen refused a reference to a module
# it cannot find". UNKNOWN module refuses; KNOWN module, non-local body aborts
# silently. This gate now pins the symmetric fail-closed result so the old
# behavior cannot return under another qualified spelling.
#
# CONSEQUENCE THIS GATE EXISTS TO KEEP VISIBLE (GAP-134 / GAP-145): the one
# grammar-fact owner is unreachable from Idol. lib/compiler/token_view.id — the
# immutable token view GAP-134 names as the parser-slice prerequisite — now
# refuses rather than claiming to emit those consumers. An Idol parser
# recognition decision therefore still needs a real cross-home realization;
# inlining its own grammar facts remains the fourth grammar authority
# `law.grammar.one` forbids.
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

# Measure one subject into exactly one of THREE classes.
#
#   <n>        the route succeeded and emitted n silent aborts
#   REFUSED    the route FAILED CLOSED -- the lawful answer, its own class,
#              never folded into a count of zero, because a subject that stops
#              refusing and starts aborting must be visible
#   UNTRUSTED  anything else
#
# The third class exists because "nonzero exit" is not "codegen refused". A
# crash, a signal, a missing file, a compiler that is not this compiler -- all
# exit nonzero, and mapping them to REFUSED would let an already-REFUSED pin
# keep matching while nothing was measured. Measured at dec7d509: a lawful
# refusal is exit 1 with `codegen refused` on stderr; `dump-c` on a path that
# does not exist is also exit 1 but says `FileNotFound`. Only the first is
# lawful, and the diagnostic is carried out so a reader can see which happened.
measure() {
    # `$?` AFTER AN `if` COMPOUND IS THE `if`'s STATUS, NOT THE COMMAND'S: a
    # bodyless-else `if` that does not take its branch exits 0. Capture the
    # status on the line that produces it, or every refusal reads as UNTRUSTED.
    "$IDOL" dump-c "$1" --lib >"$work/out.c" 2>"$work/err"
    status=$?
    if [ "$status" = 0 ]; then
        grep -c "$abort" "$work/out.c"
        return 0
    fi
    if [ "$status" = 1 ] && grep -q 'codegen refused' "$work/err"; then
        if [ -s "$work/out.c" ]; then
            printf 'UNTRUSTED\n'
            return 0
        fi
        printf 'REFUSED\n'
        return 0
    fi
    printf 'UNTRUSTED\n'
    return 0
}

# ============================== BOTH CONTROLS ==============================
# A reader that reports zero on everything agrees with a clean tree and with a
# broken tree alike. `scripts/grammarconvergence.id` exited 0 on a fully
# damaged owner for exactly that reason, so this file proves it can see the
# defect and proves it does not invent one, before it reports anything.
#
# POSITIVE: a cross-module call must not be answered the same way as a
# local-only one. `compiler.reader.read` is a two-line relation in
# lib/compiler/reader.id; the call resolves, and today the route still emits
# the abort.
#
# THE CONTROL MUST NOT REQUIRE THE DEFECT TO SURVIVE. An earlier version
# refused REFUSED here, which would have made this gate impossible to turn
# green on the very day cross-module lowering is repaired: the planted call
# would fail closed, the control would exit 3, and lowering the baseline could
# not admit the fix. What the control actually needs is that the reader
# DISCRIMINATES -- a planted cross-module call must not answer 0, the answer a
# local-only file gives. REFUSED is the repaired world and is lawful, and it is
# announced, because at that point every nonzero pin below must fall.
cat >"$work/positive.id" <<'PROBE'
grab: i64 = (d: { value: i64 })
  compiler.reader.read(d)
PROBE
positive=$(measure "$work/positive.id")
case $positive in
    0)
        printf 'lower fallback control: FAIL — a planted cross-module call measured 0, the same answer a local-only file gives, so this reader discriminates nothing\n' >&2
        exit 3
        ;;
    UNTRUSTED)
        printf 'lower fallback control: FAIL — a planted cross-module call did not produce a lawful refusal with empty stdout; the compiler under test is not measurable\n' >&2
        sed -n '1,5p' "$work/err" >&2
        exit 3
        ;;
    REFUSED)
        if ! grep -q 'codegen refused an application whose callee is not realized' "$work/err"; then
            printf 'lower fallback control: FAIL — the planted cross-module call refused for another reason\n' >&2
            sed -n '1,5p' "$work/err" >&2
            exit 3
        fi
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
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi
if [ ! -s "$work/out.c" ]; then
    printf 'lower fallback control: FAIL — a successful local-only transfer emitted an empty artifact\n' >&2
    exit 3
fi
if ! command -v "${CC:-cc}" >/dev/null 2>&1; then
    printf 'lower fallback control: NOT MEASURED — C syntax checker is unavailable: %s\n' "${CC:-cc}" >&2
    exit 3
fi
if ! "${CC:-cc}" -std=c11 -fsyntax-only "$work/out.c" >"$work/cc.out" 2>"$work/cc.err"; then
    printf 'lower fallback control: FAIL — the local-only transfer artifact does not compile\n' >&2
    sed -n '1,5p' "$work/cc.err" >&2
    exit 3
fi
if [ "$positive" = REFUSED ]; then
    printf 'lower fallback: the transfer route now FAILS CLOSED on a cross-module call — every nonzero pin below must fall\n'
fi
# NAME THE MEASURING COMPILER (`law.evidence.subject.one`). These pins are a
# property of the compiler that produced them, and the failure they cause when
# that compiler is the wrong one is indistinguishable from a real regression
# unless the run says which one it used. Measured both ways at dec7d509: debug
# and ReleaseFast agree on every row, so build mode is NOT the sensitive axis --
# REVISION is. The tracked, stale `out/bin/idol` refuses lib/compiler/parser.id
# where this revision measures it, and this gate calls that a CLASS CHANGE
# rather than agreeing with it.
printf 'lower fallback control: PASS — planted cross-module call counted %s; local-only file counted 0 (compiler %s)\n' \
    "$positive" "$IDOL"

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
        UNTRUSTED)
            printf 'lower fallback: NOT MEASURED — %s produced no lawful outcome\n' "$subject" >&2
            sed -n '1,5p' "$work/err" >&2
            exit 3
            ;;
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
