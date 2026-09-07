#!/bin/sh
# gate/placefold/existence.sh — the existence permit governs the whole-relation
# fold on the production source-to-native path.
#
# ═══ THE ONE PRODUCER AND THE ONE CONSUMER ═════════════════════════════════
#
# PRODUCER. `semantic_graph.liftBodies` publishes `observation.permits(&report,
# .existence)` for every place in a relation's census, under the world the
# `--observer` flag folds into `SemanticGraph.observation_world`. The gating
# class is `allocation_identity` — GAP-170's *allocation identity, address, and
# existence of a place*.
#
# CONSUMER. `dnir_lower.lowerFunction` adopts `comptime.foldRelationBody` only
# when `graph.relationExistenceErasable(relation)` holds. That fold replaces the
# whole body with its answer, so it erases every place the relation binds at
# once; it is the widest erasure the lowering performs, and before this gate it
# took that freedom without asking anyone whether an observer could tell.
#
# ═══ WHY A UNIT DIFFERENTIAL IS NOT ENOUGH, AND THIS GATE EXISTS ═══════════
#
# `src/dnir_lower.zig`'s differential moves the world by assigning
# `graph.observation_world` directly. That is the same field `main.zig` sets, but
# it is not the same PATH: nothing in it proves the `--observer` flag reaches
# the lift, that the compiled artifact changes, or that the answer survives.
# This gate compiles real source with the shipped binary and runs the artifact.
#
# IT FOUND THAT EXACT MISS ON ITS FIRST RUN. `main.zig` set the observation
# world on five graphs and not on the Wasm one, so on a host whose direct
# backend has no native machine realization (`DNB004`) `--observer` reached no
# realization at all and every artifact below was byte-identical.
#
# WASM IS THE REALIZATION THIS HOST EXECUTES, and that is a host fact, not a
# preference: `--backend=direct` answers DNB004 here. The lowering under test —
# `lowerFunction` adopting `foldRelationBody` — is the same one both backends
# consume, so the fold is measured where it can also be RUN. Wasm evidence is
# not direct-native evidence and this gate claims only what it exercised.
#
# ═══ THE ARMS ══════════════════════════════════════════════════════════════
#
#   0  ORACLE PRESENT     wasmtime and the shipped binary are both here. A gate
#                         that skips silently is a gate that passes silently, so
#                         this refuses — with exit 2, "could not measure", never
#                         the exit 1 that means a law was broken.
#   1  ANSWER INVARIANT   the probe exits 22 under BOTH worlds. A realization
#                         that changed the answer is a wrong answer, not a
#                         refused fold, and every arm below would be measuring
#                         the wrong thing.
#   2  REALIZATION MOVED  the two probe artifacts DIFFER and the observed one is
#                         LARGER. The source, the graph facts and the answer are
#                         fixed; the world fact is the only input that moved.
#   3  FEATURE-USE        the ordinary probe must actually fold: its artifact is
#                         BYTE-IDENTICAL to the floor, whose body already IS the
#                         constant. A gate that fails closed everywhere would
#                         satisfy arm 2 while deleting the optimization; this
#                         arm fails in exactly that case.
#   4  FLOOR INVARIANT    a relation with NO place produces byte-identical
#                         artifacts under both worlds. Without this, arm 2 could
#                         be `--observer` perturbing every compilation rather
#                         than the permit refusing one fold.
#   5  STRUCTURAL         `lowerFunction` reads `relationExistenceErasable`
#                         before adopting `foldRelationBody`. Arms 1-4 are
#                         behavioural and a future producer that rules
#                         `.permitted` under a debugger would leave them green
#                         with the consumer deleted; this arm catches the revert.
set -eu

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo"
idol=${IDOL_BIN:-./zig-out/bin/idol}
wasmtime=${WASMTIME:-wasmtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/placefold-existence.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

fail() {
  printf 'gate/placefold/existence.sh: %s\n' "$*" >&2
  exit 1
}

# EXIT 2 IS "I COULD NOT MEASURE", EXIT 1 IS "THE LAW IS BROKEN", and
# `gate/wasm/global.sh` already spends them that way. A missing oracle reported
# as a violated law is a red that names the wrong defect.
absent() {
  printf 'gate/placefold/existence.sh: %s\n' "$*" >&2
  exit 2
}

# ── arm 0: ORACLE PRESENT ──────────────────────────────────────────────────
[ -x "$idol" ] || absent "arm 0: compiler absent: $idol (build it: zig build)"
command -v "$wasmtime" >/dev/null 2>&1 ||
  absent "arm 0: wasmtime absent. This gate RUNS the artifact it measures;
  skipping the run would leave the size arms unable to tell a folded relation
  from a broken one, so it refuses rather than reporting a fact it did not take"

# The answer is 22 against a table whose every other slot reads 7 or 9, so a
# fold that is fast and wrong fails on the value and not merely on the shape.
answer=22
cat >"$work/probe.id" <<'ID'
main: i64 = ()
    t = (1, 7, 7, 7, 9, 7, 7, 7)
    s = 0
    i = 1
    while i <= 4
        s += t[i]
        i += 1
    s
ID

# NO PLACE AT ALL. The permit has nothing to rule on, so no arm below may see a
# difference here — this is what separates "the permit refused one fold" from
# "the flag perturbs every compilation".
cat >"$work/floor.id" <<'ID'
main: i64 = ()
    22
ID

build() {
  src=$1
  out=$2
  shift 2
  "$idol" compile "$src" -o "$out" --backend=wasm --no-cache "$@" >"$out.log" 2>&1 ||
    fail "compile failed: $src $* (see $out.log)"
  [ -f "$out" ] || fail "no artifact produced for $src $*"
}

run_exit() {
  code=0
  "$wasmtime" "$1" >/dev/null 2>&1 || code=$?
  printf '%s' "$code"
}

build "$work/probe.id" "$work/probe.ord.wasm"
build "$work/probe.id" "$work/probe.obs.wasm" --observer=debugger
build "$work/floor.id" "$work/floor.ord.wasm"
build "$work/floor.id" "$work/floor.obs.wasm" --observer=debugger

# ── arm 1: ANSWER INVARIANT ────────────────────────────────────────────────
probe_ord_exit=$(run_exit "$work/probe.ord.wasm")
probe_obs_exit=$(run_exit "$work/probe.obs.wasm")
[ "$probe_ord_exit" = "$answer" ] ||
  fail "arm 1: ordinary probe exited $probe_ord_exit, expected $answer"
[ "$probe_obs_exit" = "$answer" ] ||
  fail "arm 1: observed probe exited $probe_obs_exit, expected $answer — the
  refused fold changed the ANSWER, which is a miscompile and not a realization"

# ── arm 2: REALIZATION MOVED ───────────────────────────────────────────────
# THE FLOOR NAMES WHICH FAILURE THIS IS. Two probe artifacts that agree are
# either both folded (the permit never refuses — fail-open) or both unfolded
# (it never permits — the optimization is gone). The floor's bytes are the
# folded realization, so comparing against them tells the two apart instead of
# reporting one message for opposite defects.
ord_bytes=$(wc -c <"$work/probe.ord.wasm")
obs_bytes=$(wc -c <"$work/probe.obs.wasm")
floor_bytes=$(wc -c <"$work/floor.ord.wasm")
if cmp -s "$work/probe.ord.wasm" "$work/probe.obs.wasm"; then
  if cmp -s "$work/probe.ord.wasm" "$work/floor.ord.wasm"; then
    fail "arm 2: both probe artifacts folded, at $ord_bytes bytes. The permit
  never refused: either the world fact never got to
  \`SemanticGraph.observation_world\` on this backend's graph, or
  \`relationExistenceErasable\` is not consulted before \`foldRelationBody\` is
  adopted. A demanded debugger cannot inspect a place that no longer exists"
  fi
  fail "arm 2: both probe artifacts kept the body, at $ord_bytes bytes against a
  $floor_bytes byte folded floor. The permit never PERMITTED, so the
  whole-relation fold is deleted rather than governed — fail-closed everywhere
  is not a gate, it is the loss of the feature the gate exists to guard"
fi
[ "$obs_bytes" -gt "$ord_bytes" ] ||
  fail "arm 2: the observed artifact ($obs_bytes) is not larger than the
  ordinary one ($ord_bytes). A refused fold must KEEP the body it would have
  deleted, so this direction is the sign of the refusal"

# ── arm 3: FEATURE-USE CONTROL ─────────────────────────────────────────────
# The ordinary probe must reach the SAME BYTES as a relation whose body already
# IS the constant: eight table slots, a loop and four indexed reads leave no
# trace once the fold takes them. Byte equality rather than a slack, because a
# slack is a number nobody can defend and this equality is what folding to the
# same `ret` actually produces.
cmp -s "$work/probe.ord.wasm" "$work/floor.ord.wasm" ||
  fail "arm 3: the ordinary probe ($ord_bytes bytes) did not reach the floor's
  realization ($floor_bytes bytes). The fold this gate guards is not happening,
  so every refusing arm above is green for a feature that no longer exists"

# ── arm 4: FLOOR INVARIANT ─────────────────────────────────────────────────
cmp -s "$work/floor.ord.wasm" "$work/floor.obs.wasm" ||
  fail "arm 4: a relation with no place produced different artifacts under the
  two worlds. \`--observer\` is perturbing compilation generally, so arm 2
  proves nothing about the existence permit"

# ── arm 5: STRUCTURAL ──────────────────────────────────────────────────────
python3 - "$repo" <<'PYARM' || exit 1
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
src = (repo / "src" / "dnir_lower.zig").read_text()


def fail(msg):
    print("gate/placefold/existence.sh: arm 5: " + msg, file=sys.stderr)
    raise SystemExit(1)


# THE GUARD MUST BE BOUND *AND* TESTED, WHICH ARE TWO FACTS. An earlier version
# of this arm searched a window for the name and stayed green while the name was
# bound and dropped from the condition, so it is now read out of the exact `if`
# that admits the fold.
bind = re.search(
    r"const (?P<guard>\w+) = "
    r"if \(id\) \|entity\| graph\.relationExistenceErasable\(entity\) else false;",
    src,
)
if bind is None:
    fail("`relationExistenceErasable` is not bound from the relation's graph "
         "identity in `lowerFunction`. Without it the whole-relation fold takes "
         "the existence freedom on a question never put")
guard = bind.group("guard")

adopt = re.search(
    r"\n\s*if \((?P<cond>[^\n]*)\) \{\n\s*if \(comptime_eval\.foldRelationBody\(",
    src,
)
if adopt is None:
    fail("the `if` that adopts `comptime_eval.foldRelationBody` was not found; "
         "this gate's consumer moved and the gate is stale")
if guard not in adopt.group("cond"):
    fail("`" + guard + "` is bound but not tested by the condition that adopts "
         "`foldRelationBody`: " + adopt.group("cond").strip() + ". That fold "
         "erases every place the relation binds, so admitting it without the "
         "existence permit is fail-open")

graph_src = (repo / "src" / "semantic_graph.zig").read_text()
found = re.search(r"pub fn relationExistenceErasable\(.*?\n    \}", graph_src, re.S)
if found is None:
    fail("`relationExistenceErasable` was not found in src/semantic_graph.zig")
body = found.group(0)
# BOTH ABSENCES REFUSE, AND THAT IS TWO FACTS TOO: no censused body, and a
# censused body carrying no ruling. Counting them separately, because a single
# `orelse return false` left over from one of them keeps a substring check green
# while the other became `orelse return true`.
if len(re.findall(r"orelse return false", body)) < 2:
    fail("`relationExistenceErasable` no longer refuses on BOTH absences — an "
         "uncensused body and a censused body with no ruling. Unknown is not "
         "permission (`law.unknown.one`): neither may receive the fold by "
         "default")
if re.search(r"orelse return true", body):
    fail("`relationExistenceErasable` answers an ABSENT fact with permission. "
         "That is the exact fail-open this consumer exists to close")
if ".permitted" not in body:
    fail("`relationExistenceErasable` no longer compares against `.permitted`, "
         "so it is not reading the permit it claims to read")

# THE WORLD MUST REACH EVERY REALIZATION GRAPH. `--observer` set on five graphs
# and missed on the sixth is how this gate's first run got byte-identical
# artifacts: the flag reached no realization this host can execute.
main_src = (repo / "src" / "main.zig").read_text()
seated = len(re.findall(r"\.observation_world = observedWorld\(\);", main_src))
if seated < 6:
    fail("only " + str(seated) + " graphs in src/main.zig take the observer "
         "demand through `observedWorld()`. A realization graph that misses the "
         "seat is a backend the `--observer` flag silently does not reach")
PYARM

printf 'gate/placefold/existence.sh: PASS (wasm probe ord=%s obs=%s floor=%s exit=%s)\n' \
  "$ord_bytes" "$obs_bytes" "$floor_bytes" "$answer"
