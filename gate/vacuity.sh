#!/bin/sh
# gate/vacuity.sh — a gate that cannot fail is not reporting a fact it measured.
#
# ═══ THE INVARIANT, stated before the mechanism ════════════════════════════
#
# Every instrument this repository has caught lying failed the SAME way:
#
#     ABSENCE OF A SUBJECT WAS INDISTINGUISHABLE FROM ABSENCE OF A VIOLATION.
#
# Five of them, measured, not supposed:
#
#   1. `2>/dev/null` on a scan turned "no such file" into a count of 0, so a
#      producer census reported four absent producers and — worse — one clean
#      PASS from a ceiling check on a file it never opened.
#   2. An `awk` abort swallowed by `/dev/null`, so a PLANTED violation passed.
#   3. A parity probe grepping `ROLEIDENTITYCOUNT` while the file writes
#      `roleidentitycount`; its four real checks never ran, and it was green.
#   4. A ledger row grepping `sema.zig` for its own accessor name — a check
#      with no reachable success state.
#   5. A refusal whose `fail=1` died inside a command substitution: the gate
#      printed `FAIL …` and exited 0.
#
# `GAP-201` already rules that a gate examining zero subjects must FAIL, and
# `gate/all.sh` says so in prose about its own census. Every one of the five
# above shipped anyway. The rule was STATED, per repository; it was never
# EXECUTED, per gate. That gap is what this file closes.
#
# ═══ THE METHOD: DAMAGE THE SUBJECT, NOT THE GATE ══════════════════════════
#
# A green run can never tell you an instrument works. The only thing that can
# is feeding it a known-bad input and watching it go red. So each gate is run
# against a scaffold in which the thing it measures IS NOT THERE, and is
# required to exit non-zero. Editing the gate would prove nothing about the
# gate; removing its subject proves exactly the property in question.
#
# A non-zero exit is the whole requirement, and a CLEAN REFUSAL COUNTS. A gate
# that says "no compiler at …" and exits 2 has noticed its subject is missing,
# which is the property being tested. Only a gate that examines nothing and
# calls it clean is convicted.
#
# TWO PLANTS, because they catch different lies:
#
#   EMPTY   the gate script and nothing else. Every path it names is absent.
#           Catches "I counted zero because I opened no file."
#   HOLLOW  an executable compiler that answers NOTHING, plus empty source and
#           corpus homes, plus an empty git repository. Every subject EXISTS
#           and is silent. Catches "I asked, got nothing back, and called that
#           agreement" — the class an existence check cannot see.
#
# The scaffold reproduces each gate's own path depth, because gates derive
# their root from `dirname $0` and the nested ones (`gate/world/face.sh`,
# `gate/wasm/global.sh`) walk up two levels rather than one.
#
# ═══ WHAT IS NOT CONVICTED ═════════════════════════════════════════════════
#
# Some gates legitimately cannot fail and SAY SO in their own headers —
# roadmaps, coverage reports, `UNMEASURED` differentials. The distinction that
# matters is not "does it fail" but:
#
#     CANNOT FAIL BY DESIGN AND SAYS SO   versus   CANNOT FAIL AND CLAIMS OTHERWISE
#
# So report-only gates are DECLARED in the list below rather than forced red.
# The list is the point: it makes the set visible, and `vacuity` fails if the
# list names a gate that no longer exists, so it cannot rot quietly. A gate on
# the list that turns out to be SOUND is reported too — that is a line to
# delete, and deleting it is a ratchet that falls.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { echo "vacuity: cannot enter root" >&2; exit 2; }

# ── report-only, by their own declaration ──────────────────────────────────
# Each of these states in its own header that it does not block. Adding a name
# here is a claim about that gate's header, and `vacuity` checks the file
# exists; it deliberately does NOT check the wording, because a prose match is
# the same fragile instrument this gate exists to distrust.
# Two, and each was CHECKED against its own header rather than assumed:
#   architecture-roadmap.sh  "Always exits 0. Lists behavioral gates awaiting
#                             harnesses; does not block."   (0/0 under plant)
#   coverage.sh              "reporting only (set COVERAGE_BUDGET to ratchet)"
#                            (64 empty / 0 hollow — needs the exemption)
#
# THE LIST STARTED AT FIVE AND THIS HARNESS SHRANK IT. `attribution.sh`,
# `differential.sh` and `envcache.sh` were exempted on the strength of a
# keyword grep over their headers; under a plant all three REFUSE, so none of
# them ever needed an exemption, and `attribution.sh` turned out not to
# self-declare anything at all — the grep had matched nothing for it, and
# `envcache.sh` matched a variable named `N_UNMEASURED`. An exemption granted
# by a loose pattern match is the same instrument this gate distrusts, so the
# three are gone and they are measured like everything else.
DECLARED='gate/architecture-roadmap.sh gate/coverage.sh'

# ── convicted, and not yet repaired ────────────────────────────────────────
# A NAMED list, not a count. `gate/all.sh` ratchets on bare numbers, which is
# enough for a citation census but not here: a bare ceiling of 1 is satisfied
# just as well by a DIFFERENT gate going vacuous while this one is fixed, and
# a substitution is precisely the drift worth catching. Vacuous-and-listed is
# reported; vacuous-and-unlisted is fatal. Lines here are meant to be deleted.
#
# IT IS EMPTY, AND THAT IS THE POINT. It shipped holding `gate/posix.sh` and
# `gate/researchgap.sh`, and "no NEW convictions" is a weaker property than
# "no convictions" — it lets a standing lie stand forever so long as nobody
# adds another. Both were repaired; the reasoning survives in each gate's own
# header, where a reader looking at the gate will meet it. Adding a name back
# is not forbidden, but it is now the edit that has to be argued for.
KNOWNVACUOUS=''

# ── crashed under HOLLOW before reaching a measurement ─────────────────────
# NOT a conviction and NOT a pass: the harness never observed these decide
# anything. Also empty now, and one of the two entries was this file's own
# fault — `gate/grammar-projection.sh` died at ENOTDIR on a stub the plant
# mis-shaped (see `build_hollow`), and `gate/layering-controls.sh` died at 128
# inside `git clone` under `set -e`, which grades as a signal. Neither had ever
# been observed deciding anything, and the first turned out to be hiding a
# VACUOUS verdict rather than a sound one, which is exactly why UNPROVEN may
# never be read as SOUND. Lines here are meant to be deleted.
KNOWNUNPROVEN=''

# `gate/all.sh` is a RUNNER, not a gate: it executes every file here, so under
# a plant it would recurse into this one. Excluded by role, and named so the
# exclusion is visible rather than implicit in a glob.
RUNNERS='gate/all.sh gate/vacuity.sh gate/admission-all.sh'

PER_GATE_TIMEOUT=${VACUITY_TIMEOUT:-90}

# ── the timeout facility, and honesty about not having one ─────────────────
# TIMEOUT is its own verdict, never green. A gate that hangs with no subject
# has not demonstrated it notices; it has demonstrated nothing.
if command -v timeout >/dev/null 2>&1; then
  runner='timeout'
elif command -v gtimeout >/dev/null 2>&1; then
  runner='gtimeout'
else
  runner=''
fi

# `$1/.say` receives the gate's own last line of output, which is what makes a
# conviction READABLE instead of oracular. A bare "VACUOUS" asks the reader to
# trust this harness; quoting what the gate said lets them judge it. The first
# conviction this file produced needed exactly that — the gate had a
# zero-subject guard and still passed, and only its own PASS line showed why.
# THE TRANSCRIPT LIVES OUTSIDE THE SCAFFOLD. It used to be written to
# `$dir/.say`, INSIDE the very tree the gate is about to examine — a plant that
# adds a file to the scaffold is not a clean plant, and any gate globbing the
# root would have been handed a subject this harness invented. Nothing may
# exist in a scaffold except what the plant deliberately put there.
# ONE SCRATCH PARENT, torn down on EXIT AND ON SIGNALS. Every scaffold and the
# transcript live under it, so there is no path — normal, refusing, or
# interrupted — that leaves a planted tree behind. Per-scaffold `rm -rf` calls
# remain, because every gate x 2 plants should not all sit on disk at once.
scratch=$(mktemp -d) || { echo "vacuity: cannot allocate scratch" >&2; exit 2; }
cleanup() { rm -rf -- "$scratch"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP
say_file="$scratch/say"


# THE RUNNER IS PROBED, NOT ASSUMED, and this is not defensive habit — it is a
# defect this file already committed. A review asked for `-k` (TERM then KILL)
# so a gate trapping TERM cannot hang the harness. Correct advice for GNU
# coreutils; the `timeout` first on PATH here is a PERL SCRIPT that rejects the
# switch and exits 25. Every plant then returned 25, every gate looked non-zero
# on both, and the whole report would have been a uniform silent SOUND — the
# instrument reporting one fact per gate that it had not measured, in the file written to
# forbid exactly that. The canary self-test below caught it.
#
# So each capability is DEMONSTRATED on a command with a known answer before it
# is used, and a runner that cannot pass its own probe is discarded rather than
# trusted.
killarg=''
if [ -n "$runner" ]; then
  if ! "$runner" 5 true >/dev/null 2>&1; then
    printf 'vacuity: NOTE `%s` failed a trivial probe (`%s 5 true`); ignoring it.\n' "$runner" "$runner" >&2
    runner=''
  elif "$runner" -k 1 5 true >/dev/null 2>&1; then
    killarg='-k 10'
  else
    printf 'vacuity: NOTE `%s` has no -k; a gate that traps TERM is bounded by TERM alone.\n' "$runner" >&2
  fi
fi
if [ -z "$runner" ]; then
  printf 'vacuity: NOTE no usable timeout(1) — a gate that hangs under a plant hangs this harness;\n' >&2
  printf 'vacuity:   TIMEOUT cannot be distinguished from "still running". Install coreutils.\n' >&2
fi

run_bounded() {
  # $1 dir, $2 relative gate path -> echoes exit code, or 124 for timeout
  if [ -n "$runner" ]; then
    ( cd "$1" && "$runner" $killarg "$PER_GATE_TIMEOUT" sh "$2" >"$say_file" 2>&1 </dev/null )
  else
    ( cd "$1" && sh "$2" >"$say_file" 2>&1 </dev/null )
  fi
  echo $?
}

said() {
  [ -s "$say_file" ] || { echo '(no output)'; return; }
  tr -d '\r' < "$say_file" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-96
}

# A non-zero exit is the requirement, but HOW a gate reached one is worth
# separating. 126/127 and 128+ are the shell failing to run something or a
# signal — the gate DIED, it did not NOTICE. That still cannot report a false
# clean, so it is not a conviction, but it is a weaker guarantee than a
# deliberate refusal and the table says which one happened.
grade() {
  case "$1" in
    0) echo green ;;
    124) echo timeout ;;
    126|127) echo crash ;;
    # NO SWALLOWED COMPARISON. This read `[ "$1" -ge 128 ] 2>/dev/null`, and a
    # `2>/dev/null` hiding a failed test that then falls through to a benign
    # default is the exact anti-pattern this whole file polices — in the
    # function that grades the policing. The exit status is matched as text
    # instead, so there is no error to hide.
    1[3-9][0-9]|1[2][89]|2[0-9][0-9]) echo crash ;;
    *[!0-9]*) echo "nonnumeric($1)" ;;
    *) echo refused ;;
  esac
}

# ── the plants ─────────────────────────────────────────────────────────────
build_empty() {
  # $1 scaffold, $2 relative gate path. Nothing but the script, at its own depth.
  mkdir -p "$1/$(dirname "$2")" || return 1
  cp "$2" "$1/$2" || return 1
  return 0
}

build_hollow() {
  # $1 scaffold, $2 relative gate path. Subjects EXIST and are silent.
  mkdir -p "$1/$(dirname "$2")" || return 1
  cp "$2" "$1/$2" || return 1
  mkdir -p "$1/zig-out/bin" "$1/src" "$1/lib" "$1/docs/spec" "$1/examples" \
           "$1/scripts" "$1/tools/node/dev" "$1/gaps" "$1/benchmarks" || return 1
  # A compiler that runs, succeeds, and says nothing. This is the sharpest
  # probe in the file: every `-x` guard is satisfied, so the gate proceeds and
  # has to decide what an empty answer means.
  printf '#!/bin/sh\nexit 0\n' > "$1/zig-out/bin/idol" || return 1
  chmod +x "$1/zig-out/bin/idol" || return 1

  # A LAUNCHER IS NOT A SUBJECT, and conflating the two is how this harness
  # handed out unearned SOUND verdicts. ELEVEN gates open with
  #
  #     exec "$ROOT/tools/node/dev/idol-lock" -- "$0" "$@"
  #
  # and the plant did not provide it, so the exec failed, the gate exited
  # non-zero WITHOUT EVER REACHING ITS MEASUREMENT, and this file scored that
  # as proof of non-vacuity. It is the exact error being hunted: a red for the
  # wrong reason, credited as evidence. A vacuous check sitting behind a lock
  # wrapper was invisible.
  #
  # So the launcher PASSES THROUGH — `IDOL_LOCK_HELD=1` is the real tool's own
  # contract for "already held, just exec" (tools/node/dev/idol-lock:54), and
  # setting it is what stops the gate re-execing itself forever.
  printf '#!/bin/sh\n[ "$1" = "--" ] && shift\nIDOL_LOCK_HELD=1 exec "$@"\n' > "$1/tools/node/dev/idol-lock" || return 1
  chmod +x "$1/tools/node/dev/idol-lock" || return 1

  # DATA SOURCES, by contrast, EXIST AND ANSWER NOTHING — that is HOLLOW's
  # whole premise, and a gate has to decide what an empty answer means.
  #
  # THE STUB SET IS DERIVED FROM THE REAL TOOL HOME, because a hand-written
  # list of names was WRONG and the wrongness bought an unearned label. The
  # list read `build-mode gapc gapc0 grammar census hostcensus repository`.
  # `grammar` and `census` are DIRECTORIES in this repo, so the plant dropped a
  # REGULAR FILE exactly where `tools/node/dev/grammar/emit` had to be;
  # `gate/grammar-projection.sh` resolved through it, got ENOTDIR, died at 126
  # before its first check, and this harness recorded UNPROVEN. That is an
  # honest label for a defect that belonged to the PLANT, not the gate — and
  # the gate underneath it turned out to be a pass-through that HOLLOW would
  # have convicted outright. A plant that cannot reach a gate's measurement
  # hides whatever the measurement would have said. `gapc` was named too and
  # does not exist at all.
  #
  # So the set is enumerated, not declared: every executable under the real
  # `tools/node/dev` is reproduced at its own relative path as a program that
  # runs, succeeds, and says nothing. A tool added, moved, or turned into a
  # directory needs no edit here, and cannot silently drop out of the plant.
  # `idol-lock` is the one exclusion and keeps the pass-through written above,
  # because a launcher is not a subject.
  #
  # NO `2>/dev/null` ON THIS SCAN. Item 1 of this file's own list of convicted
  # instruments is a swept-away error read as a count of zero, and a plant that
  # enumerated nothing would produce a scaffold with no tools at all — every
  # gate would then die on a missing prerequisite and be scored CRASH, which is
  # not a conviction. So the home is asserted, `find` keeps its stderr, and an
  # empty enumeration is a fatal plant failure rather than an empty plant.
  [ -d tools/node/dev ] || return 1
  devtools=$(find tools/node/dev -type f -perm -u+x | sort)
  [ -n "$devtools" ] || return 1
  plant_rc=0
  plant_ifs=$IFS
  IFS='
'
  for t in $devtools; do
    case $t in tools/node/dev/idol-lock) continue ;; esac
    mkdir -p "$1/${t%/*}" || { plant_rc=1; break; }
    printf '#!/bin/sh\nexit 0\n' > "$1/$t" || { plant_rc=1; break; }
    chmod +x "$1/$t" || { plant_rc=1; break; }
  done
  IFS=$plant_ifs
  [ "$plant_rc" -eq 0 ] || return 1
  ( cd "$1" && git init -q . >/dev/null 2>&1 ) || true
  return 0
}

verdict_of() {
  # $1 empty rc, $2 hollow rc
  if [ "$1" = "124" ] || [ "$2" = "124" ]; then echo TIMEOUT; return; fi
  if [ "$1" = "0" ] || [ "$2" = "0" ]; then echo VACUOUS; return; fi
  # A CRASH UNDER HOLLOW PROVES NOTHING. HOLLOW is the plant built so the gate
  # can actually RUN — every prerequisite present, every answer empty. If it
  # still dies on 126/127/128+, the measurement was never reached, so this
  # harness has not observed the gate deciding anything and must not claim it
  # did. UNPROVEN is its own state precisely so it cannot be read as SOUND.
  case "$(grade "$2")" in crash) echo UNPROVEN; return ;; esac
  echo SOUND
}

# ═══ SELF-TEST: the harness must convict a gate it KNOWS is vacuous ════════
# The worst defect this file could ship is the one it exists to catch, so it
# is not permitted to report on the gate home without first demonstrating, on this
# run, that its own verdict function can say VACUOUS at all. Two canaries: one
# that examines nothing and exits 0, one that refuses when its subject is
# absent. Misclassify either and nothing below is printed.
canary=$(mktemp -d "$scratch/canary.XXXXXX") || exit 2
mkdir -p "$canary/probe/gate"
cat > "$canary/probe/gate/hollowcanary.sh" <<'CANARY'
#!/bin/sh
# Examines nothing, reports clean. MUST be convicted.
n=$(grep -c nothing src/absent.zig 2>/dev/null || true)
[ "${n:-0}" -eq 0 ] && exit 0
exit 1
CANARY
cat > "$canary/probe/gate/soundcanary.sh" <<'CANARY'
#!/bin/sh
# Refuses when its subject is absent. MUST NOT be convicted.
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ -f "$root/src/present.zig" ] || { echo "no subject" >&2; exit 2; }
exit 0
CANARY
chmod +x "$canary/probe/gate/"*.sh

self_fail=0
for c in hollowcanary soundcanary; do
  ce=$(mktemp -d "$scratch/ce.XXXXXX") || { self_fail=1; continue; }
  ch=$(mktemp -d "$scratch/ch.XXXXXX") || { rm -rf "$ce"; self_fail=1; continue; }
  mkdir -p "$ce/gate" "$ch/gate"
  cp "$canary/probe/gate/$c.sh" "$ce/gate/$c.sh"
  cp "$canary/probe/gate/$c.sh" "$ch/gate/$c.sh"
  mkdir -p "$ch/src" "$ch/zig-out/bin"
  printf '#!/bin/sh\nexit 0\n' > "$ch/zig-out/bin/idol"; chmod +x "$ch/zig-out/bin/idol"
  re=$(run_bounded "$ce" "gate/$c.sh"); rh=$(run_bounded "$ch" "gate/$c.sh")
  v=$(verdict_of "$re" "$rh")
  case "$c" in
    hollowcanary) want=VACUOUS ;;
    soundcanary)  want=SOUND ;;
  esac
  if [ "$v" != "$want" ]; then
    printf 'vacuity: SELF-TEST FAILED — %s classified %s, expected %s (empty=%s hollow=%s)\n' \
      "$c" "$v" "$want" "$re" "$rh" >&2
    self_fail=1
  else
    printf 'vacuity: self-test %s -> %s\n' "$c" "$v"
  fi
  rm -rf "$ce" "$ch"
done
rm -rf "$canary"
if [ "$self_fail" -ne 0 ]; then
  printf 'vacuity: REFUSING to report on any gate — the harness cannot classify its own canaries\n' >&2
  exit 2
fi

# ═══ ENUMERATE ═════════════════════════════════════════════════════════════
# THE FILESYSTEM IS THE AUTHORITY, and this file learned that the hard way.
# It enumerated with `git ls-files` first, and the probe that plants a KNOWN
# VACUOUS gate then came back GREEN: the planted gate was untracked, so the
# index never listed it, and the sweep reported clean over a set that silently
# excluded the very subject under test. That is this harness committing the
# exact defect it exists to catch — an enumeration whose blind spot is
# indistinguishable from an absence of findings.
#
# `gate/all.sh` runs `for gate in gate/*.sh`, so what EXECUTES is what is on
# disk, tracked or not. The index is consulted only to REPORT the difference,
# never to decide the subject set.
gates=$(find gate -name '*.sh' -type f 2>/dev/null | sed 's|^\./||' | sort)
tracked=$(git ls-files -- 'gate/*.sh' 'gate/*/*.sh' 2>/dev/null | sort)
untracked=''
# NEWLINE-SAFE. `for g in $gates` splits on spaces too; LAW-ONE forbids a space
# in a path, so today this changes nothing, but a split path would be planted
# as two nonexistent files and the plant failure is fatal, not silent. Making
# it exact costs one variable. The reviewer's suggested `"${untracked} …"` was
# a no-op: that right-hand side was already fully quoted.
oldifs=$IFS; IFS='
'
for g in $gates; do
  case "
$tracked
" in *"
$g
"*) ;; *) untracked="$untracked ${g#gate/}" ;; esac
done
IFS=$oldifs
total=0
for g in $gates; do total=$((total + 1)); done
# A census of zero subjects is this gate's own defect class.
if [ "$total" -eq 0 ]; then
  printf 'vacuity: enumerated ZERO gates — a scan with no subject is not a clean sweep\n' >&2
  exit 2
fi

# A DECLARED name that no longer resolves is a stale exemption, and a stale
# exemption is an unexamined gate wearing a permission slip.
for d in $DECLARED; do
  [ -f "$d" ] || { printf 'vacuity: DECLARED names %s, which does not exist — stale exemption\n' "$d" >&2; exit 2; }
done

# ═══ MEASURE ═══════════════════════════════════════════════════════════════
sound=0; vacuous=0; declared=0; timedout=0; skipped=0
vacuous_names=''; timeout_names=''; declared_sound=''; crashes=''; newvacuous=''; unproven=0; unproven_names=''

oldifs=$IFS; IFS='
'
for g in $gates; do
  IFS=$oldifs
  case " $RUNNERS " in *" $g "*) skipped=$((skipped + 1)); printf '  %-38s RUNNER (excluded by role)\n' "${g#gate/}"; continue ;; esac

  e=$(mktemp -d "$scratch/e.XXXXXX") || exit 2
  h=$(mktemp -d "$scratch/h.XXXXXX") || exit 2
  if ! build_empty "$e" "$g" || ! build_hollow "$h" "$g"; then
    printf 'vacuity: could not plant %s — a plant that fails to apply is not a pass\n' "$g" >&2
    rm -rf "$e" "$h"; exit 2
  fi
  re=$(run_bounded "$e" "$g"); SAY_E=$(said)
  rh=$(run_bounded "$h" "$g"); SAY_H=$(said)
  # Captured immediately after each run, because one transcript file is reused.
  saye=$SAY_E; sayh=$SAY_H
  rm -rf "$e" "$h"
  v=$(verdict_of "$re" "$rh")

  is_declared=0
  case " $DECLARED " in *" $g "*) is_declared=1 ;; esac

  # A DECLARATION EXEMPTS AN INTENTIONAL GREEN, NEVER A HANG. This branch used
  # to `continue` before the TIMEOUT case could count, so `TIMEOUT_CEILING=0`
  # was unenforceable for report-only gates and a newly hanging
  # architecture-roadmap still let the harness exit 0.
  if [ "$is_declared" -eq 1 ] && [ "$v" = "TIMEOUT" ]; then
    timedout=$((timedout + 1)); timeout_names="$timeout_names ${g#gate/}(declared)"
    printf '  %-38s TIMEOUT   empty=%-3s hollow=%-3s  (declared, but a hang is not a declaration)\n' "${g#gate/}" "$re" "$rh"
    IFS='
'
    continue
  fi
  if [ "$is_declared" -eq 1 ]; then
    declared=$((declared + 1))
    if [ "$v" = "SOUND" ]; then
      declared_sound="$declared_sound ${g#gate/}"
      printf '  %-38s DECLARED  empty=%-3s hollow=%-3s  (but SOUND — exemption removable)\n' "${g#gate/}" "$re" "$rh"
    else
      printf '  %-38s DECLARED  empty=%-3s hollow=%-3s\n' "${g#gate/}" "$re" "$rh"
    fi
    continue
  fi

  ge=$(grade "$re"); gh=$(grade "$rh")
  case "$v" in
    SOUND)
      sound=$((sound + 1))
      if [ "$ge" = crash ] || [ "$gh" = crash ]; then crashes="$crashes ${g#gate/}"; fi
      printf '  %-38s SOUND     empty=%-3s(%s) hollow=%-3s(%s)\n' "${g#gate/}" "$re" "$ge" "$rh" "$gh" ;;
    UNPROVEN)
      unproven=$((unproven + 1)); unproven_names="$unproven_names ${g#gate/}"
      printf '  %-38s UNPROVEN  empty=%-3s hollow=%-3s(crash)  <- never reached its measurement\n' "${g#gate/}" "$re" "$rh" ;;
    TIMEOUT)
      timedout=$((timedout + 1)); timeout_names="$timeout_names ${g#gate/}"
      printf '  %-38s TIMEOUT   empty=%-3s hollow=%-3s  (hanging is not noticing)\n' "${g#gate/}" "$re" "$rh" ;;
    VACUOUS)
      vacuous=$((vacuous + 1)); vacuous_names="$vacuous_names ${g#gate/}"
      case " $KNOWNVACUOUS " in *" $g "*) known=" (known)" ;; *) known=" <- NEW"; newvacuous="$newvacuous ${g#gate/}" ;; esac
      [ "$re" = 0 ] && whichsay="$saye" || whichsay="$sayh"
      printf '  %-38s VACUOUS   empty=%-3s hollow=%-3s%s\n' "${g#gate/}" "$re" "$rh" "$known"
      printf '  %-38s   it said: %s\n' "" "$whichsay" ;;
  esac
  IFS='
'
done
IFS=$oldifs

printf 'vacuity: %s gate(s) enumerated — %s sound, %s VACUOUS, %s UNPROVEN, %s declared report-only, %s timeout, %s runner(s) excluded\n' \
  "$total" "$sound" "$vacuous" "$unproven" "$declared" "$timedout" "$skipped"
[ -n "$vacuous_names" ] && printf 'vacuity: VACUOUS:%s\n' "$vacuous_names"
[ -n "$timeout_names" ] && printf 'vacuity: TIMEOUT:%s\n' "$timeout_names"
[ -n "$unproven_names" ] && printf 'vacuity: UNPROVEN (crashed under HOLLOW before measuring; not credited as sound):%s\n' "$unproven_names"
[ -n "$declared_sound" ] && printf 'vacuity: exemption no longer needed:%s\n' "$declared_sound"
[ -n "$untracked" ] && printf 'vacuity: UNTRACKED gate(s) present and examined (they execute under gate/all.sh):%s\n' "$untracked"
[ -n "$crashes" ] && printf 'vacuity: non-zero by CRASH rather than refusal (weaker, still not a false clean):%s\n' "$crashes"

# ═══ THE RATCHET ═══════════════════════════════════════════════════════════
# A gate shipped red is a gate that gets skipped, which `build.zig` already
# records for audit100 and capability-scan and `gate/all.sh` for its citation
# census. So these are CEILINGS THAT FALL, not a demand for zero today. Lower
# them as gates are repaired; raising one is the edit that must be argued for.
TIMEOUT_CEILING=${VACUITY_TIMEOUT_CEILING:-0}

rc=0
for u in $unproven_names; do
  case " $KNOWNUNPROVEN " in
    *" gate/$u "*) ;;
    *) printf 'vacuity: NEW UNPROVEN GATE — %s crashed under HOLLOW before measuring; supply its prerequisite or record it\n' "$u" >&2; rc=1 ;;
  esac
done
if [ -n "$newvacuous" ]; then
  printf 'vacuity: NEW VACUOUS GATE(S) —%s — a gate that stays green with no subject is reporting a fact it did not measure\n' "$newvacuous" >&2
  rc=1
fi
# A name on KNOWNVACUOUS that now passes is a line to delete. Reported loudly
# rather than fatally, matching `gate/all.sh`'s ceilings, which are lowered by
# hand; the ratchet is that it can never quietly grow, not that repair is
# punished with a red build.
for k in $KNOWNVACUOUS; do
  case " $vacuous_names " in
    *" ${k#gate/} "*) ;;
    *) [ -f "$k" ] && printf 'vacuity: %s is no longer vacuous — delete it from KNOWNVACUOUS\n' "$k" ;;
  esac
done
if [ "$timedout" -gt "$TIMEOUT_CEILING" ]; then
  printf 'vacuity: TIMEOUTS ROSE — %s, ceiling %s\n' "$timedout" "$TIMEOUT_CEILING" >&2
  rc=1
fi
[ "$rc" -eq 0 ] && printf 'vacuity: VACUITY OK.\n'
exit $rc
