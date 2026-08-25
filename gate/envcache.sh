#!/bin/sh
# ===========================================================================
# THE ARTIFACT CACHE MUST ANSWER FOR EVERY CODE-AFFECTING ENVIRONMENT VARIABLE.
#
# THE FAILURE THIS GATE EXISTS FOR. An A/B severing control whose two arms
# differ only in an environment variable was handed the FIRST arm's cached
# artifact for both arms. The two binaries were byte-identical, so the
# measurement compared a binary against itself and recorded 1.00x -- and
# recorded it as a RESULT, not as an error. Nothing in that run looked wrong:
# both arms compiled, both ran, both answered. Every historical
# environment-controlled measurement taken without isolated cache roots or a
# proof of distinct artifacts is invalid for the same reason.
#
# THE PROPERTY, stated so it can fail:
#
#   For every DUO_*/IDOL_* variable V and value X such that compiling subject S
#   with V=X under a FRESH cache yields different bytes than compiling S with V
#   unset, compiling S with V=X under a cache ALREADY HOLDING the V-unset entry
#   must ALSO yield different bytes than the V-unset artifact.
#
# Equivalently: a warm cache may never answer a code-affecting arm with the
# other arm's artifact. It may rebuild (declining the cache), or it may hit a
# different entry (the variable is in the key). It may not hit the SAME entry.
#
# ===================== WHY BYTES AND NOT ANSWERS =====================
# Two arms of a severing control usually compute the SAME ANSWER by design --
# that is what makes it a control. So "both arms answer 42" proves nothing at
# all about whether they are two binaries. Only the bytes distinguish "the
# transform was severed" from "the transform was never re-run". Compared with
# `cmp`, at the same output BASENAME in different directories, because two arms
# written to different names differ in the Mach-O UUID alone and would appear
# distinct for a reason that has nothing to do with the variable.
#
# ===================== THE VACUOUS PASS =====================
# A gate that examined zero code-affecting variables is a FAILURE, not a pass,
# and it is the specific way this gate is most likely to rot: the subject stops
# reaching the transform a variable controls, every variable measures inert,
# the negative control never executes, and the gate reports PASS having
# asserted nothing. Section 4 therefore requires the measured code-affecting
# set to be NON-EMPTY, and section 5 requires the comparison to be able to
# return "identical" -- a comparison that always answers DIFFERS would pass
# section 3 no matter how broken the cache was.
# ===========================================================================

set -eu

root=${ENVCACHE_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || { printf 'envcache gate: FAIL no compiler at %s\n' "$idol" >&2; exit 1; }

# THIS IS THE LOUDEST CASE OF THE SHARED HOST LIMIT IN THIS HOME. Every probe is
# a direct-backend compile, so on a host without that realization all 53
# registered variables come back "refused all 0 probe(s)", §4 declares the gate
# vacuous, §5's three controls fail, and the summary reports 46 VIOLATIONS of a
# cache law -- forty-six findings that are one host fact, in the gate best
# positioned to be believed, because it does name its own non-vacuity. One
# producer, asked before 53 variables are accused.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the environment-cache probe matrix (all 53 variables and both controls need direct-backend artifacts)'
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-envcache.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
mkdir -p "$work/home"

SEEN=0
FAILED=0

ok()  { SEEN=$((SEEN + 1)); printf '    ok   %s\n' "$1"; }
bad() { SEEN=$((SEEN + 1)); FAILED=$((FAILED + 1)); printf '    FAIL %s\n' "$1"; }

# EVERY COMPILE IN THIS GATE RUNS THROUGH HERE. `env -i` is not tidiness: the
# caller's own DUO_*/IDOL_* exports would otherwise be part of every arm,
# including the arm whose whole definition is "this variable is unset".
# TMPDIR is the cache root -- see `buildCacheDir`, the cache lives at
# `scratch.root()` -- so naming it per-arm is how a fresh cache is spelled.
run() {
    _cache=$1; _out=$2; _src=$3; shift 3
    mkdir -p "$(dirname -- "$_out")" "$_cache"
    env -i PATH="$PATH" HOME="$work/home" TMPDIR="$_cache" "$@" \
        "$idol" compile --backend=direct "$_src" -o "$_out" \
        >"$_out.log" 2>&1 || true
}

# ---------------------------------------------------------------------------
# THE SUBJECTS. One is not enough and the count is not the point: a variable is
# only observable on a source that REACHES the decision it controls, and no
# single small program reaches them all.
#
# MEASURED, and this is why there are two. On a loop with a LITERAL bound
# (`while i < 97`) every variable in the registry measures inert, IDOL_UNROLL
# included -- the unroll plan declines a compile-time bound outright, and the
# whole loop folds. A gate built on that subject reports 0 code-affecting out
# of 42 and passes having proved nothing. The bound must be a RUNTIME value.
#
# Likewise `/` is FLOAT division in this language and `//` is the integer one,
# so a division subject spelled `a / b` reaches none of the integer-division
# controls and measures them all inert. Both mistakes were made here first.
# ---------------------------------------------------------------------------

# S1 -- integer division by a runtime divisor. Reaches the divisor-guard,
# floored-correction, truncating-divrem and non-negative-divisor decisions.
cat > "$work/s_div.id" <<'EOF'
kern: i64 = (a: i64, b: i64)
  a // b

main: i64 = ()
  kern(97, 5) - 19
EOF

# S2 -- a reduce whose trip count is a runtime value. Reaches the unroll plan
# and the module-binding promotion.
cat > "$work/s_loop.id" <<'EOF'
kern: i64 = (bound: i64)
  n: i64 = 0
  i: i64 = 0
  while i < bound
    n = n + i * 7
    i = i + 1
  n

main: i64 = ()
  kern(97) - 32592
EOF

SUBJECTS='s_div s_loop'

# The values probed per variable. `0` and the empty string are not padding:
# they are the exact values a truthiness-based decline classified as absent
# while the reader -- `getenv(...) != null` -- classified them as present.
VALUES='1 0 EMPTY'

value_of() { [ "$1" = EMPTY ] && printf '' || printf '%s' "$1"; }

# A GENERIC VALUE SET CANNOT PROBE A PATH-SHAPED INPUT, and a gate that probes
# the wrong values reports inert and moves on. `SDKROOT=1` is not an SDK: the
# toolchain ignores or rejects it, the bytes do not move, and the gate would
# have declared code-affecting-by-measurement the one thing it must never
# declare -- that this input does not matter. So a name whose values are paths
# gets real ones, discovered on this machine, and if none can be discovered the
# gate says the name went UNPROBED rather than calling it inert.
ALT_SDK=''
for _c in /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
          /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk; do
    [ -d "$_c" ] && { ALT_SDK=$_c; break; }
done
if [ -z "$ALT_SDK" ]; then
    for _c in /Library/Developer/CommandLineTools/SDKs/*.sdk; do
        [ -d "$_c" ] || continue
        [ "$_c" = "$(xcrun --show-sdk-path 2>/dev/null)" ] && continue
        ALT_SDK=$_c; break
    done
fi

values_for() {
    case $1 in
        SDKROOT) [ -n "$ALT_SDK" ] && printf '%s' "$ALT_SDK" || printf '' ;;
        # A FACTOR IS NOT A BOOLEAN. `IDOL_UNROLL` selects an unroll factor:
        # `off`/`0`/`1` sever, 2..16 choose. MEASURED on this tree, on the
        # runtime-bound reduce subject: the severing spellings now produce bytes
        # IDENTICAL to the default, because the default plan no longer fires on
        # that loop -- while `=2` and `=8` still differ. Probed with {1,0,''}
        # alone this variable reports inert and leaves §3 with nothing to hold
        # the key to, which is how a modelled name quietly stops being tested.
        IDOL_UNROLL) printf 'off 2 8' ;;
        *)       printf '%s' "$VALUES" ;;
    esac
}

printf 'envcache gate -- compiler %s\n' "$idol"
printf '  subjects: %s\n' "$SUBJECTS"
if [ -n "$ALT_SDK" ]; then
    printf '  SDKROOT probe value: %s\n' "$ALT_SDK"
else
    printf '  SDKROOT probe value: NONE FOUND -- SDKROOT will report UNPROBED, not inert\n'
fi

# ---------------------------------------------------------------------------
# §1 THE REGISTRY IS THE COMPILER'S, AND IT IS EXHAUSTIVE.
#
# The registry is read from the binary under test (`idol env-census`), never
# retyped here. A hand list in a gate is a SECOND PRODUCER: it agrees with the
# compiler on the day it is written and silently stops agreeing afterwards,
# and the disagreement is invisible precisely when it matters.
#
# Exhaustiveness is then checked the other way -- against the env-read call
# sites in `src/` -- so a variable the compiler reads but has never classified
# is reported by name. Such a variable is already SAFE (the table's default is
# `.affects`, so it declines the cache), but it is safe by accident, and the
# accident is what this section converts into a decision.
# ---------------------------------------------------------------------------
printf '\n  §1 registry -- the compiler'"'"'s own classification, and its completeness\n'

"$idol" env-census > "$work/census.tsv" 2>"$work/census.err" || {
    printf '    FAIL env-census refused: %s\n' "$(head -1 "$work/census.err")"
    printf '\nenvcache gate: FAIL (0 probe(s)) the compiler publishes no registry\n'
    exit 1
}

# AN EMPTY CENSUS IS A FAILURE, ANNOUNCED. It happened: `env-census` printed
# through the diagnostic writer, which is stderr, so this redirect captured
# nothing, `set -e` killed the gate at the next pipeline, and the run ended
# after the section header with no message and exit 0 from the subshell. A
# silent gate that examined nothing is worse than a failing one.
TAB=$(printf '\t')
if [ ! -s "$work/census.tsv" ]; then
    printf '    FAIL env-census wrote nothing to stdout (%d byte(s) on stderr)\n' \
        "$(wc -c < "$work/census.err" | tr -d ' ')"
    printf '\nenvcache gate: FAIL (1 probe(s)) the compiler published an empty registry\n'
    exit 1
fi

DEFAULT_CLASS=$(awk -F"$TAB" '$1=="(unclassified)"{print $2}' "$work/census.tsv")
grep -v '^(unclassified)' "$work/census.tsv" > "$work/rows.tsv" || true
ROWS=$(grep -c . "$work/rows.tsv" || true)

SEEN=$((SEEN + 1))
if [ "$ROWS" -gt 0 ]; then
    ok "registry read from the binary under test: $ROWS classified row(s)"
else
    bad "registry is empty -- nothing to enumerate"
fi
if [ -z "$DEFAULT_CLASS" ]; then
    bad "registry publishes no default class -- the fail-closed rule is unstated and cannot be checked"
    DEFAULT_CLASS='(absent)'
fi

# THE FAIL-CLOSED DEFAULT IS THE WHOLE REPAIR and it is asserted, not assumed.
# Enumerating the ten known code-affecting names into the hash would leave the
# eleventh unmodelled; the default is what covers the eleventh.
if [ "$DEFAULT_CLASS" = affects ]; then
    ok "unclassified names default to 'affects' -- the eleventh variable declines the cache"
else
    bad "unclassified names default to '$DEFAULT_CLASS' -- a name nobody classified would be CACHED"
fi

# GROUND TRUTH, AND THE PATTERN IS NOT PREFIX-BOUND. A `(DUO|IDOL)_` scan is
# STRUCTURALLY BLIND to the inputs that carry no prefix, and one of them was
# live: `SDKROOT` selects the platform SDK, changes the emitted Mach-O by 53
# bytes at LC_BUILD_VERSION, and was served out of a warm cache with `(cached)`
# printed. No amount of care inside a prefixed table reaches it.
#
# So the scan matches ANY upper-case name inside an env read, and §1 requires
# every one to be classified. For unprefixed names this gate IS the closure:
# `surveyBehaviourEnv` cannot fail closed on them at runtime -- a rule that
# declined on any unclassified name would decline on PATH -- so an unprefixed
# code-affecting input has to be modelled in the key, and the only thing that
# can notice a new one is this enumeration.
grep -rhoE '(std\.c\.getenv|posix\.getenv|environ_map\.get|map\.get|env\.get|getEnvVarOwned|getenv)\([[:space:]]*"[A-Z][A-Z0-9_]*"' \
    "$root/src" 2>/dev/null | sed 's/.*"\(.*\)"/\1/' | sort -u > "$work/read.raw"
# Names that appear in an env-read shape inside GENERATED C or inside a comment
# quoting generated C, not in the compiler's own reads. Each is pinned with the
# file that emits it so the exclusion is auditable rather than a denylist.
cat > "$work/notenv.txt" <<'NOTENV'
DUO
IDOLPROBE
K
NOTENV
sort -u "$work/notenv.txt" -o "$work/notenv.txt"
comm -23 "$work/read.raw" "$work/notenv.txt" > "$work/read.txt"
READ_N=$(grep -c . "$work/read.txt" || true)
cut -f1 "$work/rows.tsv" | sort -u > "$work/classified.txt"

MISSING=$(comm -23 "$work/read.txt" "$work/classified.txt")
SEEN=$((SEEN + 1))
if [ -n "$MISSING" ]; then
    bad "read from the environment but absent from the registry: $(printf '%s' "$MISSING" | tr '\n' ' ') -- an unprefixed one cannot fail closed at runtime, so an unclassified name here is an OPEN hole, not a conservative one"
else
    ok "all $READ_N variable(s) read in src/ are classified -- including $(grep -vcE '^(DUO|IDOL)_' "$work/read.txt" || true) that carry no DUO_/IDOL_ prefix"
fi

printf '    registry: %d classified, %d read in src/, default=%s\n' \
    "$ROWS" "$READ_N" "$DEFAULT_CLASS"
for C in inert modelled affects; do
    printf '      %-9s %d\n' "$C" "$(awk -F"$TAB" -v c=$C '$2==c' "$work/rows.tsv" | grep -c . || true)"
done

# ---------------------------------------------------------------------------
# §2 WHAT EACH VARIABLE ACTUALLY DOES TO THE BYTES.
#
# Classification by MEASUREMENT, under a fresh cache per arm, so the answer is
# about the compiler and not about what any cache happened to be holding. A
# variable is code-affecting iff some probed value changes the artifact of some
# subject. This section decides nothing about the cache; it only establishes
# the population §3 then holds the cache to.
#
# The one hard failure here is the dangerous direction: a name the registry
# calls `.inert` -- a claim that no byte moves, which buys it the cache -- that
# measurably moves bytes.
# ---------------------------------------------------------------------------
printf '\n  §2 measured effect -- fresh cache, EVERY value of every variable\n'

: > "$work/affecting.txt"
N_AFFECTING=0
N_INERT=0
N_REFUSED=0
N_UNMEASURED=0
N_ACCEPTED=0
N_PAIRS=0
: > "$work/unmeasured.txt"

for S in $SUBJECTS; do
    run "$work/base.$S" "$work/base.$S.d/p.out" "$work/$S.id"
    [ -f "$work/base.$S.d/p.out" ] || {
        printf '    FAIL baseline compile of %s failed: %s\n' "$S" \
            "$(tail -2 "$work/base.$S.d/p.out.log" | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    }
done

while IFS="$TAB" read -r V CLASS; do
    [ -n "$V" ] || continue
    # EVERY VALUE, NO EARLY EXIT, AND THIS IS THE WHOLE DIFFERENCE BETWEEN A
    # GATE THAT CATCHES THE DEFECT AND ONE THAT DOES NOT.
    #
    # This loop used to stop at the first value that moved the bytes and hand
    # §3 that one pair. MEASURED against a compiler carrying the defect
    # deliberately reintroduced: the gate reported
    #
    #     ok IDOL_UNSAFE_TRUNC_DIVREM=1 ... warm cache produced arm B's own artifact
    #     envcache gate: PASS (18 probe(s))
    #
    # on a binary whose warm cache demonstrably served the unset-env artifact
    # -- because the decline it was missing was a TRUTHINESS decline, so `=1`
    # was the one value it still handled correctly, and `=1` is the value the
    # first-hit rule always picks. A gate that probes only the value that
    # works is a gate that passes on the broken build.
    HIT=''; PROBED=0; REFUSED_HERE=0
    for S in $SUBJECTS; do
        [ -f "$work/base.$S.d/p.out" ] || continue
        for TOK in $(values_for "$V"); do
            case $V in SDKROOT|IDOL_UNROLL) VAL=$TOK ;; *) VAL=$(value_of "$TOK") ;; esac
            D="$work/fresh"; rm -rf "$D" "$work/fc"
            run "$work/fc" "$D/p.out" "$work/$S.id" "$V=$VAL"
            if [ ! -f "$D/p.out" ]; then
                N_REFUSED=$((N_REFUSED + 1))
                REFUSED_HERE=$((REFUSED_HERE + 1))
                continue
            fi
            PROBED=$((PROBED + 1))
            if ! cmp -s "$D/p.out" "$work/base.$S.d/p.out"; then
                HIT=yes
                N_PAIRS=$((N_PAIRS + 1))
                printf '%s\t%s\t%s\t%s\n' "$V" "$CLASS" "$S" "$TOK" >> "$work/affecting.txt"
                printf '    %-28s %-9s CODE-AFFECTING (%s %s)\n' "$V" "$CLASS" "$S" "$TOK"
            fi
        done
    done
    if [ -n "$HIT" ]; then
        N_AFFECTING=$((N_AFFECTING + 1))
        SEEN=$((SEEN + 1))
        if [ "$CLASS" = inert ]; then
            bad "$V is registered 'inert' -- a claim that no byte moves, which buys it the cache -- but it moves bytes"
        fi
    elif [ "$PROBED" -eq 0 ]; then
        # NOT INERT -- UNMEASURED. `DUO_BENCH_BACKEND` accepts only the literal
        # `direct`, so every value this gate probes makes the compiler refuse
        # and no comparison ever happens. Counting that as "inert" would report
        # a byte-identity result that was never observed, which is the exact
        # species of claim this gate exists to stop making.
        N_UNMEASURED=$((N_UNMEASURED + 1))
        printf '%s\n' "$V" >> "$work/unmeasured.txt"
        printf '    %-28s %-9s UNMEASURED (refused all %d probe(s))\n' "$V" "$CLASS" "$REFUSED_HERE"
        SEEN=$((SEEN + 1))
        if [ "$CLASS" = affects ]; then
            ok "$V could not be measured, and is registered 'affects' -- it declines the cache without needing a measurement"
        else
            bad "$V refused every probed value, so its '$CLASS' registration rests on no comparison this gate made"
        fi
    else
        N_INERT=$((N_INERT + 1))
    fi
    N_ACCEPTED=$((N_ACCEPTED + PROBED))
done < "$work/rows.tsv"

printf '    measured: %d code-affecting variable(s) over %d (subject,value) pair(s), %d inert over %d accepted probe(s), %d unmeasured (refused every value), %d refusal(s) total\n' \
    "$N_AFFECTING" "$N_PAIRS" "$N_INERT" "$N_ACCEPTED" "$N_UNMEASURED" "$N_REFUSED"

# ---------------------------------------------------------------------------
# §3 THE PROPERTY. A warm cache never answers a code-affecting arm with the
# artifact built without that variable.
#
# This is the assertion the whole gate exists for, and it is the one that was
# FALSE. Arm A populates a cache root with the variable unset. Arm B then
# compiles the same subject, into the same output basename, against THAT SAME
# ROOT, with the variable set. §2 already proved the two differ when neither
# can see the other's cache. If they are byte-identical here, the cache served
# A's artifact to B, and any measurement of A against B is a measurement of one
# binary against itself.
# ---------------------------------------------------------------------------
printf '\n  §3 negative control -- warm cache must not serve the unset-env artifact\n'

while IFS="$TAB" read -r V CLASS S TOK; do
    [ -n "$V" ] || continue
    case $V in SDKROOT|IDOL_UNROLL) VAL=$TOK ;; *) VAL=$(value_of "$TOK") ;; esac

    # A cache root that holds exactly one thing: the V-unset artifact.
    WARM="$work/warm.root"; rm -rf "$WARM"
    rm -rf "$work/wa" "$work/wb" "$work/wf" "$work/freshb"
    if [ ! -f "$work/$S.id" ]; then
        bad "$V: §3 was handed subject '$S', which is not a file -- HARNESS fault, not a cache verdict"
        continue
    fi
    run "$WARM" "$work/wa/p.out" "$work/$S.id"
    [ -f "$work/wa/p.out" ] || { bad "$V: warm-root baseline compile failed: $(tail -1 "$work/wa/p.out.log" 2>/dev/null)"; continue; }

    # Independently, B's own correct artifact -- what the warm arm SHOULD equal.
    run "$work/freshb" "$work/wf/p.out" "$work/$S.id" "$V=$VAL"
    [ -f "$work/wf/p.out" ] || { bad "$V=$TOK: fresh-cache arm B compile failed"; continue; }

    # B against the warm root.
    run "$WARM" "$work/wb/p.out" "$work/$S.id" "$V=$VAL"
    if [ ! -f "$work/wb/p.out" ]; then
        bad "$V=$TOK changed the artifact under a fresh cache but the warm-cache compile refused"
    elif cmp -s "$work/wb/p.out" "$work/wa/p.out"; then
        SERVED=rebuilt; grep -q '(cached)' "$work/wb/p.out.log" && SERVED='reported (cached)'
        bad "$V=$TOK is code-affecting on $S yet the warm cache produced the UNSET-ENV artifact byte-for-byte [$SERVED] -- an A/B on this variable measures 1.00x against itself"
    elif ! cmp -s "$work/wb/p.out" "$work/wf/p.out"; then
        bad "$V=$TOK warm-cache artifact matches neither the unset-env artifact nor its own fresh-cache artifact -- the cache is nondeterministic under this variable"
    else
        ok "$V=$TOK ($CLASS) on $S -- warm cache produced arm B's own artifact, distinct from arm A's"
    fi
done < "$work/affecting.txt"

# ---------------------------------------------------------------------------
# §4 NON-VACUITY OF §3. The negative control must have had something to run on.
#
# If every variable measures inert, §3's loop body never executes and the gate
# passes having asserted nothing about the cache -- which is exactly what a
# subject that stopped reaching its transform would produce. This is not a
# hypothetical: the first two subjects written for this gate measured 0
# code-affecting out of 42, one because its loop bound was a literal and one
# because it spelled integer division `/`.
# ---------------------------------------------------------------------------
printf '\n  §4 non-vacuity -- §3 must have had a real population\n'
SEEN=$((SEEN + 1))
if [ "$N_AFFECTING" -gt 0 ]; then
    ok "§3 ran against $N_PAIRS (subject,value) pair(s) across $N_AFFECTING variable(s), not an empty set"
else
    bad "ZERO variables measured code-affecting -- §3 asserted nothing; the subjects no longer reach any environment-controlled decision and this gate is vacuous"
fi

# ---------------------------------------------------------------------------
# §5 POSITIVE CONTROL -- the comparison can still answer "identical".
#
# §3 passes when bytes DIFFER. An instrument that answers DIFFERS
# unconditionally -- a nondeterministic compile, an embedded timestamp, a path
# baked into the artifact -- would pass §3 with the cache completely broken.
# So: arms that genuinely SHOULD match must be shown to match, on the same
# instrument, in the same run.
#
#   5a. Same source, same (empty) environment, two different cache roots, same
#       output basename. Nothing differs, so nothing may differ. This is also
#       the determinism precondition every other section rests on.
#   5b. A warm cache HIT, which must reproduce the artifact exactly.
#   5c. A variable the registry calls `.inert` must leave the bytes alone AND
#       keep the cache -- the other half of the fail-closed bargain. Declining
#       on every name would pass §3 trivially by never reusing anything; this
#       is what makes "decline" a real cost and not a free win.
# ---------------------------------------------------------------------------
printf '\n  §5 positive control -- arms that should match, do\n'

rm -rf "$work/pc1" "$work/pc2" "$work/pa" "$work/pb"
run "$work/pc1" "$work/pa/p.out" "$work/s_div.id"
run "$work/pc2" "$work/pb/p.out" "$work/s_div.id"
if [ ! -f "$work/pa/p.out" ] || [ ! -f "$work/pb/p.out" ]; then
    bad "positive control 5a: a compile with no variable set failed"
elif cmp -s "$work/pa/p.out" "$work/pb/p.out"; then
    ok "5a two identical arms, two fresh cache roots -- identical bytes (the instrument can answer 'same')"
else
    bad "5a two identical arms produced DIFFERENT bytes -- the compile is nondeterministic and every DIFFERS in §3 is uninterpretable"
fi

rm -rf "$work/pc3"
run "$work/pc3" "$work/pc/p.out" "$work/s_div.id"
run "$work/pc3" "$work/pd/p.out" "$work/s_div.id"
if grep -q '(cached)' "$work/pd/p.out.log" && cmp -s "$work/pc/p.out" "$work/pd/p.out"; then
    ok "5b a warm cache HIT reproduces the artifact exactly -- the cache is live in this run, so §3's misses are real misses"
else
    bad "5b the second identical compile did not report a reproducing cache hit -- the cache is inert here and §3 proves nothing about it"
fi

INERT_PROBE=$(awk -F"$TAB" '$2=="inert"{print $1}' "$work/rows.tsv" | grep -x 'DUO_TRACE' || true)
: "${INERT_PROBE:=DUO_TRACE}"
rm -rf "$work/pc4" "$work/pe" "$work/pf"
run "$work/pc4" "$work/pe/p.out" "$work/s_div.id"
run "$work/pc4" "$work/pf/p.out" "$work/s_div.id" "$INERT_PROBE=1"
if [ ! -f "$work/pf/p.out" ]; then
    bad "5c $INERT_PROBE=1 made the compile fail"
elif ! cmp -s "$work/pe/p.out" "$work/pf/p.out"; then
    bad "5c $INERT_PROBE is registered inert but changed the artifact"
elif grep -q '(cached)' "$work/pf/p.out.log"; then
    ok "5c $INERT_PROBE=1 (inert) kept the cache and the bytes -- decline is selective, not blanket"
else
    bad "5c $INERT_PROBE=1 is registered inert yet lost the cache -- the decline has widened to names that do not need it"
fi

# ---------------------------------------------------------------------------
printf '\n'
printf 'SUBJECT revision=%s dirty=%s compiler=%s\n' \
    "$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)" \
    "$(if git -C "$root" diff --quiet 2>/dev/null && git -C "$root" diff --cached --quiet 2>/dev/null; then printf clean; else printf dirty; fi)" \
    "$(cd "$(dirname -- "$idol")" && pwd)/$(basename -- "$idol")"

if [ "$SEEN" -eq 0 ]; then
    printf 'envcache gate: FAIL (0 probe(s)) examined nothing\n'
    exit 1
fi
if [ "$FAILED" -eq 0 ]; then
    printf 'envcache gate: PASS (%d probe(s)) %d registry rows, %d code-affecting variable(s) over %d (subject,value) pair(s), warm cache distinct on every pair\n' \
        "$SEEN" "$ROWS" "$N_AFFECTING" "$N_PAIRS"
    exit 0
fi
printf 'envcache gate: FAIL (%d probe(s)) %d violation(s) -- the artifact cache does not answer for every code-affecting environment variable\n' \
    "$SEEN" "$FAILED"
exit 1
