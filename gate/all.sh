#!/bin/sh
# Runs every shell gate that EXISTS, and measures the citation debt gap[212]
# records. AGENTS.md has told every reader `sh gate/all.sh runs the lot` since
# before this file was written; `git log --all -- gate/all.sh` was empty until
# it was written. This is that file, and it claims only what it measures.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64

# THE COMPILER GATES ARE NOT SANDBOXED FROM THEIR OWN TREE. Anything below that
# names `zig-out/bin/idol` reads the artifact that is there; it does not build
# one. `gate/defaults.sh` and `gate/world-launch.sh` derive the optimize mode
# from that artifact (tools/node/dev/build-mode) and refuse a non-ReleaseFast
# one by name, which is why they can be run from here at all: they used to read
# `IDOL_BUILD_MODE`, which this file has never set and never could have set
# honestly.
pass=0
fail=0
failed=
hostbound=0
hostbound_names=
crosstree=0
crosstree_names=

# The sibling gate home. Read BEFORE the gate loop, not just for the citation
# census below, because a gate whose subject lives in that tree fails here for
# the same reason a citation into it cannot be resolved: the tree is absent. The
# citation census already separated that from a debt; the gate tally did not, and
# counted it among the laws.
native=${IDOL_NATIVE:-$repo/../idol-native}

# ===================== DIRECT-NATIVE POSITIVE CONTROL =======================
# On a host with no direct-native realization every gate whose subject is a
# native executable fails for ONE shared reason, and a bare "24 failed" reads as
# twenty-four violated laws. So establish the host fact ONCE and attribute the
# failures against it. A zero needs a positive control; so does a red.
#
# The fact has one producer, `gate/realization/direct.sh`, which asks the
# compiler rather than uname — see its header for why six gates describing this
# in six ways is the defect it replaces.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/idol-gate-all.XXXXXX") || exit 64
trap 'rm -rf "$scratch"' EXIT
. "$repo/gate/realization/direct.sh"
direct_native_probe zig-out/bin/idol

for gate in gate/*.sh gate/*/*.sh; do
  case $gate in
    gate/all.sh) continue ;;
  esac
  [ -r "$gate" ] || continue
  # A SOURCED LIBRARY IS NOT A GATE, and it says so itself. The role is read
  # from the file — one `# gate-role: library` line — rather than kept as a name
  # list here and a second one in `gate/vacuity.sh`, which would reintroduce the
  # two-producers-of-one-fact defect that the helper below exists to remove.
  # `vacuity` holds the marker honest by requiring a declared library to be
  # sourced by a real gate.
  case $(sed -n '1,40p' "$gate" | sed -n 's/^# *gate-role: *\([a-z]*\) *$/\1/p' | head -1) in
    library) continue ;;
  esac
  if sh "$gate" >"$scratch/gate.log" 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $gate"
    # Attributed, not guessed. This used to match five prose spellings
    # ('only on Darwin', 'requires Darwin', 'NOT MEASURED (uname', …) because the
    # gates each described the limit their own way; that list was a projection of
    # the duplication, and it would have needed a sixth entry for every gate
    # added. The gates now route through the producer and emit ONE sentence, so
    # this matches the identity and that sentence. `requires Darwin` stays for
    # gate/taint.sh, whose subject is dyld interposition — a DIFFERENT host fact
    # that the direct-realization producer does not speak for.
    if grep -q 'DNB004\|NOT MEASURED —\|requires Darwin' "$scratch/gate.log"; then
      hostbound=$((hostbound + 1))
      hostbound_names="$hostbound_names $gate"
    elif [ ! -d "$native/gate" ] && grep -qF "$native" "$scratch/gate.log"; then
      # ITS SUBJECT IS IN A TREE THAT IS NOT HERE. `gate/differential.sh` needs
      # ../idol-native/gate/run_limited.pl and says so by path; with no sibling
      # checkout that is neither a law nor a host limit, and it is the same class
      # the citation census below reports as UNRESOLVABLE HERE. Conditioned on the
      # tree being absent, so a real failure that happens to name the path when
      # the tree IS present still counts as law.
      crosstree=$((crosstree + 1))
      crosstree_names="$crosstree_names $gate"
    fi
  fi
done

# ===================== NATIVE (.id) GATES =====================
# Gates migrated from shell to Idol live as gate/*.id and are RUN here, by
# this file, through the compiler they measure. The list is EXPLICIT: the
# gate/*.id home is heterogeneous -- libraries (gate/bootstrap.id),
# semantic-scan drivers fed on stdin (gate/admission.id), retired probes
# (gate/preflight.id) -- and an enumerator would sweep up files that are not
# gates. One entry is added per migration, in the migration's own commit.
#
# The driver itself executes through the direct backend (gatecap needs the
# direct-native realization), so on a host the compiler refuses with DNB004
# the gate is NOT MEASURED rather than failed: the same attribution class
# the .sh gates get from the producer's sentence, via IDOL_DIRECT_NATIVE,
# which this file already probed above.
IDOL_GATES='gate/table_apply.id gate/canonicality.id gate/readpath.id gate/gap-111-map-ambiguity.id gate/gap-111-subject-first.id gate/gap-118-env-absence.id gate/perfmonotone.id gate/grammar-projection.id gate/delimiter-projection-law.id gate/gap-114-boxed-len.id gate/gap-121-module-init.id gate/selfhost.id gate/architecture-roadmap.id gate/public-safety.id gate/module-zero-precheck.id gate/elfexec.id gate/architecture-negative.id gate/architecture-companion.id gate/gap-141-runtime-temp.id'

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
for idgate in $IDOL_GATES; do
  [ -r "$idgate" ] || continue
  if [ "${IDOL_DIRECT_NATIVE:-unbuilt}" = no ]; then
    hostbound=$((hostbound + 1))
    hostbound_names="$hostbound_names $idgate"
    printf '%s: NOT MEASURED — the .id driver executes through the direct backend. This host has no direct-native realization: the compiler refused a trivial program with DNB004.\n' "$idgate"
    continue
  fi
  if [ ! -x "$idol" ]; then
    fail=$((fail + 1))
    failed="$failed $idgate"
    printf '%s: no compiler at %s\n' "$idgate" "$idol" >&2
    continue
  fi
  if "$idol" run --backend=direct "$idgate" >"$scratch/gate.log" 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $idgate"
    # Same attribution as the .sh loop: a host refusal or an absent sibling
    # tree is not a law violation.
    if grep -q 'DNB004\|NOT MEASURED —\|requires Darwin' "$scratch/gate.log"; then
      hostbound=$((hostbound + 1))
      hostbound_names="$hostbound_names $idgate"
    elif [ ! -d "$native/gate" ] && grep -qF "$native" "$scratch/gate.log"; then
      crosstree=$((crosstree + 1))
      crosstree_names="$crosstree_names $idgate"
    fi
  fi
done

# ============================ CITATION RESOLUTION ============================
# gap[212]: a citation to a gate that does not exist is indistinguishable, to a
# reader, from a citation to a passing one. This RESOLVES each cited path and
# counts the classes, rather than asserting a number, so the figure cannot rot
# the way the one in AGENTS.md line 60 did.
#
# TWO CORRECTIONS TO THE FIRST VERSION OF THIS CENSUS, both of which inflated
# it, and together they account for the whole of the reported "81 of 133
# citations name 27 gates with no commit in any history":
#
#   1. IT LOOKED IN ONE REPOSITORY. The compiler in src/*.zig is cited against
#      the gate home in the SIBLING tree — AGENTS.md's own instruction is
#      `cd ../idol-native`, docs/METRICS.md already spells
#      `../idol-native/gate/selfhost.sh`, and src/dnir_hardware.zig says
#      "gate/simd.sh §1 in idol-native". Twenty-six of the twenty-seven
#      "ghosts" are committed, runnable files in ../idol-native/gate/.
#      `gate/narrow.sh` — the one cited by a live refusal in dnir_lower.zig —
#      is 652 lines, passes, and prints the cited number on every run.
#
#   2. IT COUNTED UNTRACKED FILES. `src/*.zig.orig` are patch backups in a
#      working tree. Eleven citations lived only there.
#
# So the debt is real but it is a DIFFERENT debt: an UNDER-QUALIFIED citation,
# repaired by writing the path a reader can follow, not by writing a gate.
#   3. IT CHARGED AN UNRESOLVABLE CITATION TO THE UNRESOLVED RATCHET. When the
#      sibling tree is absent the two `sibling` branches below cannot fire, so
#      every cross-tree citation fell through to `unresolved` and tripped a
#      ceiling of 0 with the message "CITATION DEBT ROSE" — which reads as
#      "someone added citations to gates that do not exist" when nothing had
#      changed but the tree being alone. Measured here: 76 unresolved with no
#      sibling, 0 unresolved the moment any sibling gate home exists. That is
#      this file committing its own headline error one level up — an
#      UNRESOLVABLE citation is indistinguishable, to a reader, from an
#      UNRESOLVED one. They are now separate classes, and the sibling ceilings
#      are NOT EVALUATED when the census that feeds them examined nothing,
#      because 0 <= 71 is a vacuous pass (GAP-201, the same rule this file
#      already applies to its own subject list).
# `native` is set above the gate loop, which needs the same fact.
if [ -d "$native" ]; then
  cross=resolvable
else
  cross=absent
fi

cited=0
here=0
qualified=0
here_retired=0
sibling=0
sibling_retired=0
unresolved=0
unresolvable=0
unresolved_names=
unresolvable_names=
sibling_names=
retired_names=

# THIS FILE IS EXCLUDED FROM ITS OWN CENSUS. The paragraphs above name a dozen
# gates in order to explain the measurement, and a census that counts its own
# explanation is measuring itself — `tools/node/dev/gapc0` records the same
# convention for scanner fixtures. Nothing here is an authority citation; every
# gate this runner actually depends on it RUNS, in the loop above.
# `2>/dev/null` on the enumerator, and a "NOT MEASURED" line that then falls
# through to the ratchet below with unresolved=0, which passes a ceiling of 0.
# That is a vacuous PASS wearing a warning's clothes: in a tree with no `.git`
# this census examined nothing and the file still exited 0. GAP-201 rules that
# a gate examining zero subjects must FAIL, so it does.
if ! sh "$repo/gate/subject.sh" -- src gate docs AGENTS.md CLAUDE.md >/dev/null; then
  printf 'gate/all.sh: citation census has NO SUBJECTS — refusing to report a debt figure\n' >&2
  exit 2
fi
sources=$(git ls-files -- src gate docs AGENTS.md CLAUDE.md | grep -v '^gate/all\.sh$')
if [ -z "$sources" ]; then
  printf 'gate/all.sh: citation census resolved to zero sources after self-exclusion — NOT MEASURED\n' >&2
  exit 2
else
  # A citation may be spelled QUALIFIED (`../idol-native/gate/x.sh`, which
  # docs/METRICS.md already uses) or bare. The qualified spelling is the repair
  # for the under-qualified debt below, so it must be counted as its own class
  # or repairing a citation would leave the number unmoved.
  for cite in $(printf '%s\n' $sources | xargs grep -hoE '(\.\./idol-native/)?gate/[a-z0-9_-]+\.sh' 2>/dev/null | sort -u); do
    n=$(printf '%s\n' $sources | xargs grep -hoF "$cite" 2>/dev/null | wc -l | tr -d ' ')
    case $cite in
      ../idol-native/*)
        # A qualified citation resolves in the sibling or nowhere; the bare
        # occurrences it contains are already counted here, so subtract them
        # from the bare tally below by matching the bare form's count.
        path=${cite#../idol-native/}
        cited=$((cited + n))
        if [ -f "$native/$path" ]; then
          qualified=$((qualified + n))
        elif [ "$cross" = absent ]; then
          unresolvable=$((unresolvable + n))
          unresolvable_names="$unresolvable_names $cite"
        else
          unresolved=$((unresolved + n))
          unresolved_names="$unresolved_names $cite"
        fi
        continue
        ;;
    esac
    path=$cite
    # `grep -oF gate/x.sh` also matches inside `../idol-native/gate/x.sh`, so a
    # qualified citation would be double-counted as bare. Remove those.
    q=$(printf '%s\n' $sources | xargs grep -hoF "../idol-native/$path" 2>/dev/null | wc -l | tr -d ' ')
    n=$((n - q))
    [ "$n" -gt 0 ] || continue
    cited=$((cited + n))
    if [ -f "$path" ]; then
      here=$((here + n))
    elif [ -n "$(git log --all --oneline -- "$path" 2>/dev/null | head -1)" ]; then
      here_retired=$((here_retired + n))
      retired_names="$retired_names $path(here)"
    elif [ -f "$native/$path" ]; then
      sibling=$((sibling + n))
      sibling_names="$sibling_names $path"
    elif [ -d "$native" ] && [ -n "$(git -C "$native" log --all --oneline -- "$path" 2>/dev/null | head -1)" ]; then
      sibling_retired=$((sibling_retired + n))
      retired_names="$retired_names $path(sibling)"
    elif [ "$cross" = absent ]; then
      unresolvable=$((unresolvable + n))
      unresolvable_names="$unresolvable_names $path"
    else
      unresolved=$((unresolved + n))
      unresolved_names="$unresolved_names $path"
    fi
  done
fi

printf 'gate/all.sh: ran %s gate(s): %s passed, %s failed\n' \
  "$((pass + fail))" "$pass" "$fail"
[ -n "$failed" ] && printf 'gate/all.sh: FAILED:%s\n' "$failed"
case ${IDOL_DIRECT_NATIVE:-unbuilt} in
  no)
    printf 'gate/all.sh: this host has NO direct-native realization (the compiler refused the positive control by name), so %s of the %s failures are a HOST LIMIT, not a law:%s\n' \
      "$hostbound" "$fail" "$hostbound_names"
    [ "$crosstree" -gt 0 ] && printf 'gate/all.sh: %s further failure(s) name a subject in the absent sibling tree — the same UNRESOLVABLE HERE class the citation census reports, and neither a law nor a host limit:%s\n' \
      "$crosstree" "$crosstree_names"
    printf 'gate/all.sh: the remaining %s failure(s) are the law signal this host can carry\n' \
      "$((fail - hostbound - crosstree))" ;;
  broken)
    printf 'gate/all.sh: direct-native positive control failed for a reason that is NOT a host refusal, so failure attribution is unreliable; the compiler said:\n' >&2
    printf '%s\n' "${IDOL_DIRECT_NATIVE_WHY:-}" | sed 's/^/gate\/all.sh:   /' >&2 ;;
  unbuilt)
    printf 'gate/all.sh: no compiler at zig-out/bin/idol — every compiling gate below failed UNBUILT, which is not a finding\n' >&2 ;;
esac

if [ "$cross" = absent ]; then
  printf 'gate/all.sh: sibling gate home absent at %s — cross-tree citations CANNOT BE RESOLVED from here; set IDOL_NATIVE\n' "$native"
fi
printf 'gate/all.sh: gate citations: %s total — %s resolve here, %s spelled ../idol-native/ and resolve there, %s BARE but only in %s, %s name a RETIRED gate, %s UNRESOLVED, %s UNRESOLVABLE HERE (gap[212])\n' \
  "$cited" "$here" "$qualified" "$sibling" "$native" "$((here_retired + sibling_retired))" "$unresolved" "$unresolvable"
[ -n "$retired_names" ] && printf 'gate/all.sh: RETIRED authority:%s\n' "$retired_names"
[ -n "$unresolved_names" ] && printf 'gate/all.sh: UNRESOLVED:%s\n' "$unresolved_names"
[ -n "$unresolvable_names" ] && printf 'gate/all.sh: UNRESOLVABLE HERE (no sibling tree; these are NOT a debt this checkout can measure):%s\n' "$unresolvable_names"

# ================================ THE RATCHET ================================
# A gate shipped red is skipped on day one, which is the reasoning build.zig
# already records for audit100 and capability-scan. So these are CEILINGS that
# fall, not a demand for zero — except UNRESOLVED, which is zero TODAY and is
# therefore gated at zero honestly rather than aspirationally.
#
# Measured at 64928599 with both corrections applied, this file excluded, and
# the two dnir_lower.zig citations for the live `mod-global-written:` refusal
# qualified:
#     120 citations, 43 here, 6 qualified, 70 bare-but-sibling, 1 retired,
#     0 unresolved
# The 70 fall by rewriting `gate/x.sh` as `../idol-native/gate/x.sh` in the
# citing comment. That is a path edit, not a gate to write: every one of the 26
# gates behind them is a committed, runnable file in the sibling tree.
# Lower these as citations are qualified. Raising one is the edit that must be
# argued for.
UNRESOLVED_CEILING=0
SIBLING_CEILING=71
RETIRED_CEILING=1

debt_fail=0
if [ "$unresolved" -gt "$UNRESOLVED_CEILING" ]; then
  printf 'gate/all.sh: CITATION DEBT ROSE — %s unresolved citations, ceiling %s\n' \
    "$unresolved" "$UNRESOLVED_CEILING" >&2
  debt_fail=1
fi
# SIBLING is decided ONLY by consulting the sibling tree, so with no sibling it
# reads 0 against a ceiling of 71 and passes without examining a subject. Say so
# instead of banking it.
if [ "$cross" = absent ]; then
  printf 'gate/all.sh: UNDER-QUALIFIED ceiling NOT EVALUATED — that census examined zero subjects (%s citations unresolvable here)\n' \
    "$unresolvable"
elif [ "$sibling" -gt "$SIBLING_CEILING" ]; then
  printf 'gate/all.sh: UNDER-QUALIFIED CITATIONS ROSE — %s, ceiling %s\n' \
    "$sibling" "$SIBLING_CEILING" >&2
  debt_fail=1
fi
# RETIRED has a local half that IS measurable alone, and a missing sibling can
# only make the total too LOW. A ceiling read against a lower bound cannot fail
# falsely, so it is still evaluated — but a PASS on it is not a clean bill.
retired=$((here_retired + sibling_retired))
if [ "$retired" -gt "$RETIRED_CEILING" ]; then
  printf 'gate/all.sh: CITATIONS TO RETIRED GATES ROSE — %s, ceiling %s\n' \
    "$retired" "$RETIRED_CEILING" >&2
  debt_fail=1
elif [ "$cross" = absent ]; then
  printf 'gate/all.sh: retired citations %s of ceiling %s — LOWER BOUND, the sibling half was not consulted\n' \
    "$retired" "$RETIRED_CEILING"
fi

[ "$fail" -eq 0 ] && [ "$debt_fail" -eq 0 ] || exit 1
exit 0
