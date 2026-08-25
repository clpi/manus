#!/bin/sh
# gate/cachedeps.sh — the cache key is DERIVED from a typed dependency record,
# and every dependency in that record is causally operative.
#
# ═══ WHY A RECORD, AND WHY A GATE ON IT ════════════════════════════════════
#
# The key used to be a bare `Sha256` fed by a hand-ordered run of `h.update`
# calls. The comment above `behaviour_env_table` records what that cost:
#
#     "`buildCacheKey` has now been corrected at this site SIX TIMES and every
#      correction had one shape: a new behaviour flag shipped, nobody added it
#      to the key…"
#
# A seventh is catalogued inline. Six of those are not six mistakes; they are
# one missing structure, made six times, because nothing ENUMERATED what a
# build outcome depends on. There was no list to fail to update — only a
# function to forget to edit. Each occurrence served an artifact built under
# rules the consuming compile did not have: a severing control measuring 1.00x
# against itself, `idol check` refusing a program while `idol compile` handed
# back a working binary for it.
#
# `BuildDependencies` is that list, and the digest is derived from its fields
# by reflection, so a dependency enters the key by being DECLARED rather than
# by being remembered at the hashing site.
#
# ═══ THE FAILURE MODE THIS GATE IS AIMED AT ════════════════════════════════
#
# A record is easy to fake. A field can be declared, documented, printed, and
# never actually differ — and that is WORSE than an absent field, because a
# reader trusts it. So this gate does not check that fields EXIST. It checks
# that each one MOVES when its dependency moves and STAYS when it does not,
# which is a two-sided measurement no hollow producer passes.
#
# It is also why the arms below are DIFFERENCES between two runs, never a
# pinned digest for one program. A pinned digest is a frozen count: it would
# have to be rewritten by every honest change to the compiler.
#
# ═══ THE ARMS ══════════════════════════════════════════════════════════════
#
#   1  THE RECORD EXISTS AND IS NON-TRIVIAL   `idol cache-deps` names at least
#      the categories below, and no two fields share a digest on one program
#      (two fields that always agree are one field with two names).
#   2  DETERMINISM   the same program twice gives the same record. Without it
#      every "moved" arm passes by noise.
#   3  ISOLATION, per dependency   changing ONE dependency must move ITS field
#      and the key, and must move NO OTHER field. This is the arm that convicts
#      both a hollow field (moves nothing) and a smeared one (moves everything).
#   4  THE SUBJECT IS THE PROGRAM   two different programs differ in `subject`;
#      the same program reflowed does NOT (the subject is the parser's quotient
#      of the source, not its bytes).
#   5  THE KEY IS DERIVED, NOT MAINTAINED BESIDE THE RECORD   the digest must
#      change whenever any field changes — asserted across every arm above.
#   6  CONSERVATIVE INVALIDATION   an unmodelled `.affects` variable must make
#      the record DECLINE, not produce a key anyway.
#   7  STRUCTURAL   `buildCacheKey` derives from `buildDependencies` and does
#      not carry a hand-ordered `h.update` sequence of its own.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "cachedeps: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "cachedeps: python3 absent" >&2; exit 2; }
main_zig="$root/src/main.zig"
[ -f "$main_zig" ] || { echo "cachedeps: no $main_zig" >&2; exit 2; }

work="$(mktemp -d)" || { echo "cachedeps: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT

cat > "$work/p.id" <<'ID'
main: i64 = ()
    41 + 1
ID

# THE SAME PROGRAM, REFLOWED. Same meaning, different bytes: a comment and a
# blank line. `subject` is the parser's quotient of the source, so this must
# NOT move it — which is the two-sided half of arm 4.
cat > "$work/reflow.id" <<'ID'
# the same program, said with a comment in front of it

main: i64 = ()
    41 + 1
ID

# A DIFFERENT PROGRAM.
cat > "$work/other.id" <<'ID'
main: i64 = ()
    41 + 2
ID

# deps <label> <file> [env assignments...]
deps() {
  label="$1"; shift
  f="$1"; shift
  if [ "$#" -gt 0 ]; then
    env "$@" "$idol" cache-deps "$f" > "$work/$label.tsv" 2>"$work/$label.err"
  else
    "$idol" cache-deps "$f" > "$work/$label.tsv" 2>"$work/$label.err"
  fi
}

deps base      "$work/p.id"
deps again     "$work/p.id"
deps reflow    "$work/reflow.id"
deps other     "$work/other.id"
deps sdk       "$work/p.id" SDKROOT=/gate-cachedeps.sdk
deps devdir    "$work/p.id" DEVELOPER_DIR=/gate-cachedeps.dev
# Observer demand is a CLI face, not an environment one.
"$idol" cache-deps "$work/p.id" --observer=debugger > "$work/observer.tsv" 2>"$work/observer.err"
deps unroll    "$work/p.id" IDOL_UNROLL=7
deps promote   "$work/p.id" DUO_NO_MODULE_PROMOTE=1
# An `.affects` variable the key does not model. `behaviourEnvClass` defaults
# to `.affects` for anything unclassified, so an invented name is exactly the
# "flag that ships next" the fail-closed default exists for.
deps unmodelled "$work/p.id" IDOL_A_FLAG_THAT_SHIPPED_TODAY=1

python3 - "$work" "$main_zig" <<'PY'
import os, re, sys

work, main_zig = sys.argv[1], sys.argv[2]
bad = 0
def fail(m):
    global bad
    print("cachedeps: FAIL — " + m)
    bad += 1

def load(label):
    path = os.path.join(work, label + ".tsv")
    rows = {}
    for line in open(path):
        line = line.rstrip("\n")
        if not line or "\t" not in line: continue
        k, v = line.split("\t", 1)
        rows[k] = v
    return rows

R = {n: load(n) for n in ("base", "again", "reflow", "other", "sdk", "devdir",
                          "observer", "unroll", "promote", "unmodelled")}

# ── arm 1: THE RECORD EXISTS AND IS NON-TRIVIAL ────────────────────────────
base = R["base"]
if not base or "(key)" in base and len(base) < 3:
    fail("`idol cache-deps` printed no dependency record; this gate examined "
         "nothing (GAP-201)")
if "(declined)" in base:
    fail("`idol cache-deps` DECLINED on an ordinary program with no unmodelled "
         "environment; with no record there is nothing to measure")
if bad:
    sys.exit(1)

# The categories a build outcome depends on. Named here so a field that is
# quietly deleted is a FAIL rather than a silently smaller record.
CATEGORIES = [
    "subject", "subject_form", "reach", "home",
    "target", "backend_mode", "opt",
    "compiler_size", "compiler_mtime",
    "gate_transport_waived",
    "worlds", "observer_demand",
    "unroll_factor", "module_promote",
    "sdkroot", "developer_dir",
]
missing = [c for c in CATEGORIES if c not in base]
if missing:
    fail(f"the dependency record does not name {missing}. A build outcome that "
         f"depends on something the record does not carry is served across that "
         f"difference — which is how this site was corrected six times.")
if "(key)" not in base:
    fail("the record prints no `(key)` row, so nothing connects the fields to "
         "the digest the cache is actually addressed by")
if bad:
    sys.exit(1)

fields = [k for k in base if k != "(key)"]

# TWO FIELDS THAT ALWAYS AGREE ARE ONE FIELD WITH TWO NAMES. The per-field
# digest folds the field ORDINAL, so equal digests mean a genuine encoder
# collision, not merely equal values.
seen = {}
for f in fields:
    if base[f] in seen:
        fail(f"fields {seen[base[f]]!r} and {f!r} produced the SAME digest; the "
             f"framing that keeps two dependencies from colliding is not doing it")
    seen[base[f]] = f

# ── arm 2: DETERMINISM ─────────────────────────────────────────────────────
if R["again"] != base:
    diff = [f for f in base if R["again"].get(f) != base[f]]
    fail(f"the same program measured twice produced different records ({diff}); "
         f"every 'this dependency moved' arm below would then be noise")
    sys.exit(1)

# ── arms 3 and 5: ISOLATION, PER DEPENDENCY ────────────────────────────────
# Each row: the arm label, the field that MUST move, and why the dependency is
# real. Everything else in the record must hold still.
ISOLATED = [
    ("sdk", "sdkroot",
     "`SDKROOT` selects the platform SDK and changes the emitted "
     "LC_BUILD_VERSION; measured, a warm cache served the SDKROOT-unset "
     "artifact to a compile that set it"),
    ("devdir", "developer_dir",
     "`DEVELOPER_DIR` selects which toolchain every `xcrun` this compiler "
     "spawns resolves to — the assembler, the linker and the default SDK. It "
     "carries neither the DUO_ nor the IDOL_ prefix, so `surveyBehaviourEnv` "
     "is structurally unable to decline on it, exactly as with SDKROOT"),
    ("observer", "observer_demand",
     "`--observer=debugger` changes which realizations are lawful; a "
     "watched compilation was served the UNWATCHED artifact"),
    ("unroll", "unroll_factor",
     "`IDOL_UNROLL` changes which machine code a source lowers to, so a key "
     "without it hands a severing control's two arms one binary"),
    ("promote", "module_promote",
     "`DUO_NO_MODULE_PROMOTE` changes which machine code a source lowers to; "
     "this one was LIVE and three lanes were bitten by its shape"),
]
for label, field, why in ISOLATED:
    arm = R[label]
    if "(declined)" in arm:
        fail(f"the {label} arm DECLINED to produce a record. That is sound but "
             f"it is not what is being measured: {field} is declared MODELLED, "
             f"so it must move the field, not disable the cache")
        continue
    if arm.get(field) == base.get(field):
        fail(f"{field} did not move when its dependency did. {why}. A field "
             f"that never differs is published, not produced.")
    if arm.get("(key)") == base.get("(key)"):
        fail(f"the KEY did not move when {field}'s dependency did, so the digest "
             f"is not derived from the field that changed")
    smeared = [f for f in fields
               if f != field and arm.get(f) != base.get(f)]
    if smeared:
        fail(f"changing {field}'s dependency also moved {smeared}. A dependency "
             f"that smears across unrelated fields makes the record unreadable "
             f"and every other isolation arm here unfalsifiable")

# ── arm 4: THE SUBJECT IS THE PROGRAM, NOT ITS BYTES ───────────────────────
if R["other"].get("subject") == base.get("subject"):
    fail("two different programs produced the same `subject`; the record cannot "
         "tell one program from another")
if R["other"].get("(key)") == base.get("(key)"):
    fail("two different programs produced the same KEY")
if R["reflow"].get("subject") != base.get("subject"):
    fail("the same program with a comment and a blank line added produced a "
         "DIFFERENT `subject`. The subject is the parser's quotient of the "
         "source, never its bytes — otherwise arm 3's 'it moved' means only "
         "that something, somewhere, was different")

# ── arm 6: CONSERVATIVE INVALIDATION ───────────────────────────────────────
un = R["unmodelled"]
if "(declined)" not in un:
    fail("an UNCLASSIFIED `IDOL_*` variable — the one that ships next — did not "
         "make the record decline. `behaviourEnvClass` defaults to `.affects` "
         "precisely so an unmodelled input costs a rebuild instead of a "
         "measurement that reads 1.00x on one artifact handed to both arms")

# ── arm 7: STRUCTURAL ──────────────────────────────────────────────────────
src = open(main_zig, encoding="utf-8", errors="replace").read()
m = re.search(r'^fn buildCacheKey\(', src, re.M)
if not m:
    fail("`fn buildCacheKey` was not found; the structural arm examined nothing")
else:
    i = src.index("{", m.start())
    d, j = 0, i
    while j < len(src):
        if src[j] == "{": d += 1
        elif src[j] == "}":
            d -= 1
            if d == 0: break
        j += 1
    body = re.sub(r'//[^\n]*', '', src[i + 1:j])
    if "buildDependencies(" not in body:
        fail("`buildCacheKey` does not derive from `buildDependencies`. The key "
             "must be a projection of the typed record; a hash may ACCELERATE "
             "the record and may never replace it")
    updates = re.findall(r'\bh\.update\(', body)
    if updates:
        fail(f"`buildCacheKey` carries {len(updates)} hand-ordered `h.update` "
             f"call(s) of its own. That is the ad hoc accumulation this record "
             f"replaced: a dependency hashed there is invisible to "
             f"`idol cache-deps`, so it cannot be gated, and the next flag to "
             f"ship gets forgotten in exactly the documented way")

if bad:
    print(f"cachedeps: {len(fields)} dependency field(s) examined, {bad} finding(s)")
    sys.exit(1)
print(f"cachedeps: {len(fields)} typed dependency field(s), all distinct and "
      f"deterministic; {len(ISOLATED)} dependencies each moved their own field "
      f"and the key and nothing else; subject is quotient-stable and "
      f"program-sensitive; an unmodelled flag declines.")
PY