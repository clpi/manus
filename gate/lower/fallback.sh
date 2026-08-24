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
# Two defects, in the order they were closed.
#
# FIRST, THE SILENT FALLBACK. A pure-native module (`!moduleNeedsLuaRuntime()`)
# lowered a qualified call whose callee body was not at file scope to
#
#     duo_fatal("unlowered native call")
#
# and the command exited 0 with empty stderr. `1ec8850e` replaced that with a
# located compile refusal. This gate keeps the marker as a ZERO CEILING so the
# old behaviour cannot return under another qualified spelling.
#
# SECOND, AND THIS IS WHY REFUSED WAS NEVER THE DESTINATION: refusing honestly
# is still not being able to call. `emit_reached_partitions` realizes the
# source partitions the module's APPLICATIONS reach, into the same transfer
# unit, and `try_emit_reached_home_call` emits the direct call. The 319 sites
# that were aborts, then refusals, are now CALLS.
#
# SO THE ZERO CEILING IS NOW NEARLY EVERY ROW, AND A GATE WHOSE EVERY ROW READS
# ZERO IS THE DEFECT THIS REPOSITORY KEEPS SHIPPING. Two things stop that here.
#
#   1. THE ARTIFACT IS COMPILED, not just scanned. A count of zero says the
#      emitter wrote no abort; it says nothing about whether it wrote C. Every
#      subject carries a SECOND pin, CLEAN or DIRTY, from `cc -fsyntax-only`
#      over its emitted artifact. That column is where the remaining damage
#      lives and it is not zero: `lib/compiler/parser.id`, `monolith.id`,
#      `rewrite.id` and `lib/token/classify.id` still do not compile, for
#      reasons that have nothing to do with cross-home calls.
#   2. THE CROSS-HOME EVIDENCE IS EXECUTED. Two subjects are linked and RUN
#      against answers derived from the source, below. A compiler that stopped
#      realizing, or realized wrongly, fails those before any pin is read.
#
# WHAT THIS GATE EXISTED TO KEEP VISIBLE (GAP-134 / GAP-145), now measured the
# other way: `lib/compiler/token_view.id` — the immutable token view GAP-134
# names as the parser-slice prerequisite — calls `token.grammarrole.*`,
# compiles, links, and answers the grammar owner's own table. The parser slice
# no longer has to choose between a runtime abort and a fourth copy of the
# grammar facts, which is the choice `law.grammar.one` forbids.
#
# THE RATCHET. Every subject is pinned by exact measured class in
# gate/lower/fallback.baseline: an abort class and an artifact class. A RISE
# fails. A FALL fails, so that a repair must lower the pin and be seen. A CLASS
# CHANGE in either column fails. An UNPINNED subject fails. A pin naming a
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

CCBIN=${CC:-cc}
if ! command -v "$CCBIN" >/dev/null 2>&1; then
    printf 'lower fallback: NOT MEASURED — C compiler is unavailable: %s\n' "$CCBIN" >&2
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
# THE SECOND PINNED COLUMN, recorded by every `measure` into `$work/artclass`:
#
#   CLEAN   the emitted C passes `cc -std=c11 -fsyntax-only`
#   DIRTY   it does not
#   -       there is no artifact, because the route refused
#
# A FILE AND NOT A VARIABLE. Every caller reads `measure` through `$(...)`,
# which is a SUBSHELL: a variable this function assigns is gone the moment it
# returns, and the first version of this column silently read the initial `-`
# for every subject. `artifact_class` below is the reader's own local, loaded
# from the file the subshell wrote.
#
# COARSE ON PURPOSE. An error COUNT would pin this baseline to one C compiler's
# diagnostic set; "does it compile" is the same answer everywhere, and it is the
# question a transfer artifact actually has to pass.
artclass() { cat "$work/artclass" 2>/dev/null || printf -- '-'; }
measure() {
    printf -- '-' >"$work/artclass"
    # `$?` AFTER AN `if` COMPOUND IS THE `if`'s STATUS, NOT THE COMMAND'S: a
    # bodyless-else `if` that does not take its branch exits 0. Capture the
    # status on the line that produces it, or every refusal reads as UNTRUSTED.
    "$IDOL" dump-c "$1" --lib >"$work/out.c" 2>"$work/err"
    status=$?
    if [ "$status" = 0 ]; then
        if "$CCBIN" -std=c11 -fsyntax-only "$work/out.c" >/dev/null 2>"$work/cc.err"; then
            printf 'CLEAN' >"$work/artclass"
        else
            printf 'DIRTY' >"$work/artclass"
        fi
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

# ============================== FIVE CONTROLS ==============================
# A reader that reports zero on everything agrees with a clean tree and with a
# broken tree alike. `scripts/grammarconvergence.id` exited 0 on a fully
# damaged owner for exactly that reason, so this file proves it can see the
# defect and proves it does not invent one, before it reports anything.
#
# C1 REALIZED, AND THE ARTIFACT IS RUN. `compiler.reader.read` is a two-line
# relation in lib/compiler/reader.id. A planted call to it must (a) count zero
# aborts, (b) DEFINE the callee in the emitted artifact — otherwise "zero" only
# means the reader is blind — (c) compile, and (d) LINK AND ANSWER.
#
# THE EXECUTION IS THE POINT. This control used to demand a nonzero count, then
# a refusal; both were assertions that the defect survived, and both would have
# had to be edited on the day it did not. What the control actually needs is
# that a cross-partition application PRODUCES THE CALLEE'S ANSWER, which no
# amount of emitter blindness can fake.
cat >"$work/positive.id" <<'PROBE'
grab: i64 = (d: { value: i64 })
  compiler.reader.read(d)
PROBE
positive=$(measure "$work/positive.id")
positive_art=$(artclass)
cp "$work/out.c" "$work/positive.c" 2>/dev/null
case $positive in
    0) ;;
    UNTRUSTED)
        printf 'lower fallback control: FAIL — a planted cross-module call produced no lawful outcome; the compiler under test is not measurable\n' >&2
        sed -n '1,5p' "$work/err" >&2
        exit 3
        ;;
    *)
        printf 'lower fallback control: FAIL — a planted cross-module call answered %s; the realization it needs is gone\n' "$positive" >&2
        sed -n '1,5p' "$work/err" >&2
        exit 3
        ;;
esac
if ! grep -q 'compiler_reader__read' "$work/positive.c"; then
    printf 'lower fallback control: FAIL — the planted call counted 0 but its callee is not defined in the artifact; the reader is blind, not the emitter correct\n' >&2
    exit 3
fi
if [ "$positive_art" != CLEAN ]; then
    printf 'lower fallback control: FAIL — the planted cross-module artifact does not compile\n' >&2
    sed -n '1,5p' "$work/cc.err" >&2
    exit 3
fi
cat >"$work/positive_main.c" <<'DRIVER'
#include <stdio.h>
#include <stdint.h>
typedef struct { int64_t value; } probe_document;
int64_t grab(probe_document *d);
int main(void) { probe_document d; d.value = 21; printf("%lld\n", (long long)grab(&d)); return 0; }
DRIVER
if ! "$CCBIN" -std=c11 -o "$work/positive.bin" "$work/positive.c" "$work/positive_main.c" >"$work/link.err" 2>&1; then
    printf 'lower fallback control: FAIL — the planted cross-module artifact does not link\n' >&2
    sed -n '1,5p' "$work/link.err" >&2
    exit 3
fi
positive_run=$("$work/positive.bin" 2>/dev/null)
if [ "$positive_run" != 21 ]; then
    printf 'lower fallback control: FAIL — the planted cross-module call ran and answered %s, not 21\n' "$positive_run" >&2
    exit 3
fi

# C2 NEGATIVE: a file whose every call is file-scope local must measure ZERO. A
# reader that counted the string anywhere in the emitted C would pass the
# positive control and still be wrong about every subject below.
cat >"$work/negative.id" <<'PROBE'
twice: i64 = (n: i64)
  n * 2

quad: i64 = (n: i64)
  twice(twice(n))
PROBE
negative=$(measure "$work/negative.id")
negative_art=$(artclass)
if [ "$negative" != 0 ]; then
    printf 'lower fallback control: FAIL — a file with only local calls measured %s, not 0\n' "$negative" >&2
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi
if [ ! -s "$work/out.c" ]; then
    printf 'lower fallback control: FAIL — a successful local-only transfer emitted an empty artifact\n' >&2
    exit 3
fi
if [ "$negative_art" != CLEAN ]; then
    printf 'lower fallback control: FAIL — the local-only transfer artifact does not compile\n' >&2
    sed -n '1,5p' "$work/cc.err" >&2
    exit 3
fi

# C3 THE ROUTE STILL FAILS CLOSED, and this is what keeps the zero ceiling from
# being a ceiling over nothing. Realization answers for an application whose
# callee this compilation RESOLVED. An application into a home that resolves to
# no file has no callee to realize, must not be answered with a marker, and
# must not be answered with a call: it refuses, with empty stdout.
#
# It also proves the refusal is not keyed on the DOT. If a dotted callee alone
# triggered it, C1 above could not have run.
cat >"$work/unrealizable.id" <<'PROBE'
grab: i64 = (n: i64)
  nosuchhome.nosuchrelation(n)
PROBE
unrealizable=$(measure "$work/unrealizable.id")
if [ "$unrealizable" != REFUSED ]; then
    printf 'lower fallback control: FAIL — an application with no resolvable callee answered %s, not REFUSED\n' "$unrealizable" >&2
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi
if ! grep -q 'codegen refused an application whose callee is not realized' "$work/err"; then
    printf 'lower fallback control: FAIL — the unrealizable application refused for another reason\n' >&2
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi

# C4 CLOSURE IS TRANSITIVE OR IT IS NOT CLOSURE. `root` applies `mid`, `mid`
# applies `deep`, and only `root` is the file being compiled. Realizing what the
# ENTRY applies and stopping there leaves `mid`'s body naming a symbol nothing
# defined.
#
# MEASURED before the transitive walk existed, and it is why this control is
# here rather than in a comment: `emit_embedded_module` caught the nested
# refusal, the driver warned, and `dump-c --lib` EXITED 0 having written
# `return lua_mul(__attribute__((visibility("default"))) …` — a function
# truncated mid-expression under a success exit. The count was zero. Only
# building the artifact catches that, so this control builds and runs it.
mkdir -p "$work/tri" || exit 3
cat >"$work/tri/deep.id" <<'PROBE'
plus: i64 = (n: i64)
  n + 1
PROBE
cat >"$work/tri/mid.id" <<'PROBE'
twice: i64 = (n: i64)
  deep.plus(n) * 2
PROBE
cat >"$work/tri/root.id" <<'PROBE'
quad: i64 = (n: i64)
  mid.twice(n)
PROBE
transitive=$(measure "$work/tri/root.id")
transitive_art=$(artclass)
if [ "$transitive" != 0 ] || [ "$transitive_art" != CLEAN ]; then
    printf 'lower fallback control: FAIL — a three-partition chain answered %s/%s, not 0/CLEAN\n' "$transitive" "$transitive_art" >&2
    sed -n '1,5p' "$work/err" >&2
    sed -n '1,5p' "$work/cc.err" >&2
    exit 3
fi
cp "$work/out.c" "$work/tri/root.c"
cat >"$work/tri/main.c" <<'DRIVER'
#include <stdio.h>
#include <stdint.h>
int64_t quad(int64_t n);
int main(void) { printf("%lld\n", (long long)quad(20)); return 0; }
DRIVER
if ! "$CCBIN" -std=c11 -o "$work/tri/bin" "$work/tri/root.c" "$work/tri/main.c" >"$work/tri/link.err" 2>&1; then
    printf 'lower fallback control: FAIL — the three-partition artifact does not link\n' >&2
    sed -n '1,5p' "$work/tri/link.err" >&2
    exit 3
fi
transitive_run=$("$work/tri/bin" 2>/dev/null)
if [ "$transitive_run" != 42 ]; then
    printf 'lower fallback control: FAIL — the three-partition chain ran and answered %s, not 42\n' "$transitive_run" >&2
    exit 3
fi

# C5 A REACHED PARTITION THAT CANNOT BE REALIZED IS A REFUSAL, NOT A WARNING.
# Same shape as C4 with `mid` applying a home that resolves to nothing. The
# route must fail closed WITH EMPTY STDOUT: a partial artifact under a nonzero
# exit is `measure`'s UNTRUSTED class and would be reported as unmeasurable
# rather than as this control passing.
mkdir -p "$work/bad" || exit 3
cat >"$work/bad/mid.id" <<'PROBE'
twice: i64 = (n: i64)
  nosuchhome.nosuchrelation(n) * 2
PROBE
cat >"$work/bad/root.id" <<'PROBE'
quad: i64 = (n: i64)
  mid.twice(n)
PROBE
nested=$(measure "$work/bad/root.id")
if [ "$nested" != REFUSED ]; then
    printf 'lower fallback control: FAIL — a chain through an unrealizable partition answered %s, not REFUSED\n' "$nested" >&2
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi
if ! grep -q 'cannot realize the source partition this program reaches' "$work/err"; then
    printf 'lower fallback control: FAIL — the unrealizable partition was not named in the refusal\n' >&2
    sed -n '1,5p' "$work/err" >&2
    exit 3
fi

# NAME THE MEASURING COMPILER (`law.evidence.subject.one`). These pins are a
# property of the compiler that produced them, and the failure they cause when
# that compiler is the wrong one is indistinguishable from a real regression
# unless the run says which one it used. Measured both ways: debug and
# ReleaseFast agree on every row, so build mode is NOT the sensitive axis --
# REVISION is. The tracked, stale `out/bin/idol` disagrees with a fresh build
# on these rows, and this gate calls that a CLASS CHANGE rather than agreeing.
printf 'lower fallback control: PASS — planted cross-module call answered 21; three-partition chain answered 42; local-only file 0/CLEAN; unresolvable application and unrealizable partition both REFUSED (compiler %s, cc %s)\n' \
    "$IDOL" "$CCBIN"

# ==================== EXECUTED CROSS-HOME EVIDENCE =========================
# The controls prove the MACHINERY works on a planted pair. These two prove it
# works on the subjects the gap is about, and they are RUN, not read.
#
# Each demonstration links the subject's own transfer artifact against a driver
# whose expected answers are derived from the source, and compares exactly. A
# realization that emitted a call to the wrong relation, or to the right one
# with the arguments shuffled, passes every count and fails here.
#
# THEY ARE `exit 3`, NOT `exit 1`. A demonstration that cannot be built is a
# gate that did not measure, and must not be read as a moved ratchet.
demo() {
    demo_name=$1
    demo_subject=$2
    demo_expect=$3
    "$IDOL" dump-c "$demo_subject" --lib >"$work/demo.c" 2>"$work/demo.err"
    if [ $? != 0 ]; then
        printf 'lower fallback demo: FAIL — %s did not emit a transfer artifact\n' "$demo_subject" >&2
        sed -n '1,5p' "$work/demo.err" >&2
        exit 3
    fi
    if ! "$CCBIN" -std=c11 -o "$work/demo.bin" "$work/demo.c" "$work/demo_main.c" >"$work/demo.cc" 2>&1; then
        printf 'lower fallback demo: FAIL — %s artifact does not build with its driver\n' "$demo_subject" >&2
        sed -n '1,8p' "$work/demo.cc" >&2
        exit 3
    fi
    demo_got=$("$work/demo.bin" 2>/dev/null)
    if [ "$demo_got" != "$demo_expect" ]; then
        printf 'lower fallback demo: FAIL — %s answered "%s", expected "%s"\n' "$demo_name" "$demo_got" "$demo_expect" >&2
        exit 3
    fi
    printf 'lower fallback demo: %s — %s\n' "$demo_name" "$demo_got"
}

# ONE IDOL COMPILER MODULE CALLING THE SELF-HOSTED IDOL LEXER.
# `lib/compiler/bind.id` writes `lexer.new(src, file, family)` and
# `lexer.next(lx)`; the callee is `lib/compiler/lexer.id`, 1221 lines of Idol
# that this tree's only executed authority already came from. `unresolved`
# counts names a file references and never binds: none in the first source,
# `zzz` in the second.
cat >"$work/demo_main.c" <<'DRIVER'
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
int64_t unresolved(const char *src, const char *file, int64_t family, bool report);
int main(void) {
    printf("%lld %lld\n",
        (long long)unresolved("f: i64 = (n: i64)\n  n + 1\n", "clean.id", 0, false),
        (long long)unresolved("g: i64 = (n: i64)\n  n + zzz\n", "bad.id", 0, false));
    return 0;
}
DRIVER
demo 'bind.id calls the self-hosted lexer' lib/compiler/bind.id '0 1'

# THE GAP-134 PARSER-SLICE PREREQUISITE CALLING THE ONE GRAMMAR-FACT OWNER.
# `lib/compiler/token_view.id` calls `token.grammarrole.rolebeginexpr` and
# `token.grammarrole.roleprecedence`; the callee is `lib/token/grammarrole.id`,
# GENERATED from `lib/compiler/token.id`, which is the single owner
# `law.grammar.one` names. The expected answers are that file's own tables:
# `beginexpr` is 1 at kind 0, 0 at kind 3, 1 at kind 55; `precedence` is 4 at
# kind 4 and 19 at kind 66. An index past `count` projects `token.kindeof`.
#
# THIS IS THE ROW THE GAP IS ABOUT. Before realization it was three runtime
# aborts under exit 0, then three refusals. It is now three calls that answer.
cat >"$work/demo_main.c" <<'DRIVER'
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
typedef struct {
    int64_t *kinds; int64_t *lines; int64_t *cols; const char **texts; int64_t count;
} probe_pack;
bool canbeginexpr(probe_pack *pack, int64_t index);
int64_t roleprecedence(probe_pack *pack, int64_t index);
int64_t len(probe_pack *pack);
int main(void) {
    int64_t kinds[8] = { 0, 0, 3, 55, 4, 66, 3, 0 };
    int64_t zero[8] = { 0 };
    const char *text[8] = { 0 };
    probe_pack p; p.kinds = kinds; p.lines = zero; p.cols = zero; p.texts = text; p.count = 6;
    printf("%lld %d%d%d %lld %lld %d\n",
        (long long)len(&p),
        (int)canbeginexpr(&p, 1), (int)canbeginexpr(&p, 2), (int)canbeginexpr(&p, 3),
        (long long)roleprecedence(&p, 4), (long long)roleprecedence(&p, 5),
        (int)canbeginexpr(&p, 99));
    return 0;
}
DRIVER
demo 'token_view.id calls token.grammarrole.*' lib/compiler/token_view.id '6 101 4 19 0'

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
clean=0
dirty=0

for subject in $subjects; do
    printf '%s\n' "$subject" >>"$seen"
    pin=$(printf '%s\n' "$pinned" | awk -v s="$subject" '$3 == s { print $1 }')
    pin_art=$(printf '%s\n' "$pinned" | awk -v s="$subject" '$3 == s { print $2 }')
    got=$(measure "$subject")
    got_art=$(artclass)
    case $got in
        UNTRUSTED)
            printf 'lower fallback: NOT MEASURED — %s produced no lawful outcome\n' "$subject" >&2
            sed -n '1,5p' "$work/err" >&2
            exit 3
            ;;
        REFUSED) refused=$((refused + 1)) ;;
        *) total=$((total + got)); [ "$got" -gt 0 ] && counted=$((counted + 1)) ;;
    esac
    case $got_art in
        CLEAN) clean=$((clean + 1)) ;;
        DIRTY) dirty=$((dirty + 1)) ;;
    esac
    if [ -z "$pin" ]; then
        printf 'lower fallback: UNPINNED %s measured %s %s — every transfer subject must carry a pin\n' "$subject" "$got" "$got_art" >&2
        status=1
        continue
    fi
    if [ "$pin_art" != "$got_art" ]; then
        # THE SECOND COLUMN MOVES IN BOTH DIRECTIONS AND BOTH FAIL. DIRTY ->
        # CLEAN is a repair and must be recorded in the baseline rather than
        # absorbed; CLEAN -> DIRTY is an artifact that stopped compiling while
        # its abort count stayed at zero, which is exactly the blindness the
        # count alone had.
        printf 'lower fallback: ARTIFACT %s pinned %s, measured %s\n' "$subject" "$pin_art" "$got_art" >&2
        [ "$got_art" = DIRTY ] && sed -n '1,3p' "$work/cc.err" >&2
        status=1
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
printf '%s\n' "$pinned" | while read -r pin pin_art subject; do
    grep -qxF "$subject" "$seen" && continue
    printf 'lower fallback: STALE pin %s %s %s — the baseline names a subject that no longer enumerates\n' "$pin" "$pin_art" "$subject" >&2
    printf 'stale\n' >>"$work/stale"
done
[ -f "$work/stale" ] && status=1

printf 'lower fallback: %s subject(s); %s emit silent aborts (%s total); %s fail closed and refuse; %s artifact(s) compile, %s do not\n' \
    "$(printf '%s\n' $subjects | wc -l | tr -d ' ')" "$counted" "$total" "$refused" "$clean" "$dirty"

if [ "$status" -ne 0 ]; then
    printf 'lower fallback: FAIL — the transfer ratchet moved\n' >&2
    exit 1
fi
printf 'lower fallback: OK — every transfer subject matches both of its pins\n'
exit 0
