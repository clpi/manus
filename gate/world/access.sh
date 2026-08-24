#!/bin/sh
# WORLD-ACCESS-ONE — `@x` is one exact static access of the CURRENT WORLD.
#
# `law.md` §6 and `docs/spec/world.md` give the sigil three uses of one algebra
# and this is the first: "`@` is itself the accessor: write `@x`, never `@.x`".
# gap[203] measured it at ZERO — `@name` was the directive reader and its
# `expect(.lparen)` was unconditional, so no spelling of a world access parsed
# at all. This gate is the face's executable definition.
#
# WHAT THE FACE IS FOR, and why "it parses" is not the test. `world.md` rules
# that a bare lexical name wins for the bare spelling and that `@x` accesses the
# world member EXPLICITLY. So the whole capability is the disagreement case: a
# program that binds `env` itself must keep `env`, and must still be able to
# reach the world's `env`. A gate that only compiled `@env("HOME")` in a file
# with no binding would pass against a compiler that resolved `@x` as `x`.
#
#   §1 ADMISSION   the access compiles and RUNS, and its value is the world's.
#   §2 REFUSAL     a member the current world does not have fails closed, by
#                  name, with no fallback — controlled against §1 so a compiler
#                  that refused everything could not read green.
#   §3 SHADOW      THE CAPABILITY. Both halves executed, in one program.
#   §4 GRAPH       the occurrence DRAWS the world, and still draws it under the
#                  shadow — controlled against a call that draws none.
#   §5 FORMATTER   the sigil survives a reprint. Dropping it would emit a legal
#                  file with a DIFFERENT meaning (the gap[223] class, worse).
set -eu
root=${WORLDACCESSROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-world-access.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
fail() { printf 'world/access gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"
cd "$work"

# `run` writes its artifact beside the subject, so every subject lives here.
runout() {
    set +e
    out=$("$idol" run "$work/$1.id" 2>&1)
    rc=$?
    set -e
}

# --------------------------------------------------------------- §1 ADMISSION
# The access must reach a VALUE, not merely a parse. `cwd()` is chosen because
# its answer is checkable from the shell without trusting the compiler for it.
cat >"$work/admit_cwd.id" <<'ID'
print(@cwd())
ID
runout admit_cwd
[ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; fail "§1 '@cwd()' did not run"; }
case $out in
    *"$work"*) : ;;
    *) printf '%s\n' "$out" >&2; fail "§1 '@cwd()' ran but did not answer the working directory — the access parsed and resolved to something else" ;;
esac

# NOT ADMITTED, AND MEASURED RATHER THAN ASSUMED. `world.md` rules that `@x.y`
# is one world access then one ordinary projection, so `@os.env("HOME")` ought
# to be `(@os).env("HOME")`. It is not: the sigil's DOTTED path is still the
# directive reader's, and it must stay that way while `@c.type(…)`, `@c.call(…)`
# and `@c.export` are live — `c` is a declared world NAME, so a rule that turned
# `@world.member` into an access would take those four spellings with it. The
# dotted face closes with the directive catalog, not before it, and this row
# holds the fact so the next reader does not have to rediscover it.
printf 'print(@os.env("HOME"))\n' >"$work/dotted.id"
set +e
"$idol" check "$work/dotted.id" >/dev/null 2>&1
dotted_rc=$?
set -e
[ "$dotted_rc" -ne 0 ] || fail "§1 '@os.env(…)' now CHECKS — the dotted world face landed and this row is stale; move it to admission and say what happened to the '@c.*' spellings"

# ---------------------------------------------------------------- §2 REFUSAL
# `world.md`, projection and injection edge cases: "Missing access (`@missing`)
# fails; there is no parent-directory, other-world, global-registry, library, or
# default-namespace fallback." The refusal must NAME that, or the next reader
# concludes the member merely has not been added yet.
refuse() {
    name=$1; src=$2; want=$3
    printf '%s\n' "$src" >"$work/$name.id"
    set +e
    out=$("$idol" check "$work/$name.id" 2>&1)
    ec=$?
    set -e
    [ "$ec" -ne 0 ] || { printf '%s\n' "$out" >&2; fail "§2 $name: CHECKED CLEAN — the access falls back instead of failing: $src"; }
    case $out in
        *"$want"*) : ;;
        *) printf '%s\n' "$out" >&2; fail "§2 $name: refused, but not by name — expected \"$want\"" ;;
    esac
}
refuse missing 'x = @nosuchmember' \
    "the current world has no member 'nosuchmember'"
# A LEXICAL BINDING IS NOT A WORLD MEMBER, and this is the row that proves the
# face is not merely `x` with extra bytes. `k` is bound at module scope and
# `@k` must STILL refuse: the sigil reads the world, and the world has no `k`.
refuse lexical_is_not_world 'k = 7
x = @k' \
    "the current world has no member 'k'"

# ----------------------------------------------------------------- §3 SHADOW
# THE CAPABILITY, and it is one program with two lines so neither half can be
# satisfied by a compiler that simply picked one meaning for the spelling.
#
#   `env` bound to a relation  ->  bare `env(k)` is THE RELATION (99)
#                              ->  `@env(k)`     is THE WORLD MEMBER
#
# Both directions are load-bearing. Losing the first breaks "an injected world
# adds REACH and never takes a NAME" (AGENTS.md consequence 3, recorded there as
# a defect that silently returned a descriptor address). Losing the second
# deletes the face.
IDOLWORLDACCESSPROBE=world-access-probe-value
export IDOLWORLDACCESSPROBE
cat >"$work/shadow.id" <<'ID'
env = (k) "shadowed"
print(@env("IDOLWORLDACCESSPROBE"))
ID
runout shadow
[ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; fail "§3 the shadowed sigil access did not run"; }
case $out in
    *world-access-probe-value*) : ;;
    *shadowed*) printf '%s\n' "$out" >&2; fail "§3 '@env' answered the MODULE RELATION — the sigil resolved lexically and the face does not exist" ;;
    *) printf '%s\n' "$out" >&2; fail "§3 '@env' answered neither the world nor the relation: $out" ;;
esac

# CONTROL, and without it §3 passes against a compiler that has simply stopped
# letting a program bind `env` at all. The BARE spelling in the same shape must
# still answer the relation.
cat >"$work/shadow_bare.id" <<'ID'
env = (k) "shadowed"
print(env("IDOLWORLDACCESSPROBE"))
ID
runout shadow_bare
[ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; fail "§3 control: the shadowing relation does not even run — §3 has no shadow to step past"; }
case $out in
    *shadowed*) : ;;
    *) printf '%s\n' "$out" >&2; fail "§3 control: bare 'env(k)' answered the WORLD — injection has taken a name, which is the defect the sigil exists to make unnecessary" ;;
esac

# ------------------------------------------------------------------ §4 GRAPH
# The machine answering correctly is not the same as the graph SAYING so, and
# these were measured disagreeing: with sema selecting the relation by spelling,
# `env = (k) 99` + `@env("HOME")` ran `getenv` and exported `world: none`. One
# token, two authorities. The draw is the fact that settles it.
drawn() {
    "$idol" graph "$work/$1.id" 2>/dev/null | tr ',' '\n' | grep -c '"card": *"one"' || true
}
worldrow() {
    "$idol" graph "$work/$1.id" 2>/dev/null | grep -c '"home": *"os"' || true
}
cat >"$work/graph_plain.id" <<'ID'
x = @env("HOME")
ID
cat >"$work/graph_shadow.id" <<'ID'
env = (k) "shadowed"
x = @env("HOME")
ID
# NEGATIVE CONTROL FIRST. A call that draws no world must export no `os` world
# row, or the two positive rows below prove nothing about the sigil.
cat >"$work/graph_none.id" <<'ID'
step = (k) k
x = step(1)
ID
[ "$(worldrow graph_none)" = 0 ] || fail "§4 control: a program that draws no world exported an 'os' world row — the row does not measure the draw"
[ "$(worldrow graph_plain)" != 0 ] || fail "§4 '@env(…)' exported NO world row — the access resolves without a world fact"
[ "$(worldrow graph_shadow)" != 0 ] || fail "§4 '@env(…)' under a same-named module relation exported no world row — the declaration claimed an occurrence the machine realizes through the world"

# --------------------------------------------------------------- §5 FORMATTER
# gap[223] is the standing lesson: a printer that drops half of an `@` face
# turns a legal file into one the parser refuses. Dropping THIS sigil is worse —
# the reprint still compiles and means something else. Round trip, then re-check
# the shadow behaviour of the REPRINT, which is the only assertion that can tell
# `@env` from `env` after formatting.
cp "$work/shadow.id" "$work/fmt_shadow.id"
"$idol" fmt "$work/fmt_shadow.id" >/dev/null 2>&1 || fail "§5 fmt refused a world access"
grep -q '@env' "$work/fmt_shadow.id" || {
    cat "$work/fmt_shadow.id" >&2
    fail "§5 the formatter DROPPED the sigil — the reprint still compiles and resolves to the module relation instead of the world"
}
runout fmt_shadow
[ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; fail "§5 the reprint does not run"; }
case $out in
    *world-access-probe-value*) : ;;
    *) printf '%s\n' "$out" >&2; fail "§5 the reprint changed the program's ANSWER: $out" ;;
esac
cp "$work/fmt_shadow.id" "$work/fmt_shadow.once"
"$idol" fmt "$work/fmt_shadow.id" >/dev/null 2>&1 || fail "§5 fmt refused its own output"
cmp -s "$work/fmt_shadow.once" "$work/fmt_shadow.id" || fail "§5 fmt is not a fixed point on '@x'"

printf 'world/access gate: PASS — @x is a world access (runs and answers; missing member refused by name; the sigil steps past a same-named binding while the bare name does not; the draw is on the graph; the reprint keeps the sigil and the answer)\n'
printf 'world/access gate: NOTE — this closes ONE face, in its SINGLE-SEGMENT form. `@x.y` is still the directive path, `@k = v` still has no world place, and `@{ … }` still derives no world (gap[203]).\n'
