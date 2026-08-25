#!/bin/sh
# STAGE-IS-A-WORLD — `@(expr)` is `expr@{ stage = compile }`, and the algebra's
# identities hold on RUNNING PROGRAMS.
#
# `law.stage.world` (C0 §52) rules that compile-time evaluation is evaluation
# under a world: stage is a fact a world CARRIES (`law.md` §6, §11), so
# `@(expr)` is the current world applied to an expression and equals
# `expr@{ stage = compile }`. That ruling keeps `@` a single algebra. This gate
# is the ruling's executable half — without it the ruling is prose, and prose
# in this tree decays.
#
# WHAT WAS MEASURED BEFORE THE FACE LANDED, because it changes what "128 live
# sites" was worth: `@(expr)` DID NOT EXECUTE ON ANY BACKEND. `print(@(1 + 2))`
# refused with `DNB001 compile-nontable` on direct and
# `graph-to-DNIR refused (UnsupportedConstruct)` on C. Ninety-six code-position
# `@(` occurrences, every one of them in `examples/`, none of them running. So
# §1 is not decoration: it is the first evidence the face exists at all.
#
#   §1 EXECUTION    the compile stage evaluates, and the value is the program's.
#   §2 DIFFERENTIAL the two spellings are ONE meaning — same answer, same
#                   formatted output, over the same subject.
#   §3 IDENTITY     derive(W, {}) = W, on a running program.
#   §4 IDEMPOTENCE  derive(derive(W,D),D) = derive(W,D), structurally and by
#                   value.
#   §5 NO FALLTHROUGH  a value absent at the stage is absent from that world and
#                   refuses; it does not fall back to the runtime world.
#   §6 REFUSAL      every delta with no derived-world fact refuses BY NAME, and
#                   a duplicate member in one literal is an error.
#   §7 FORMATTER    the canonical face survives a reprint. A printer that
#                   migrated it back to the compatibility spelling would be
#                   migration pressure pointed the wrong way.
set -eu
root=${WORLDSTAGEROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-world-stage.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
fail() { printf 'world/stage gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"
cd "$work"

# `run` prints a compile line then the program's output; the LAST line is the
# answer. THE EXIT CODE IS NOT THE VERDICT and must not be read as one — a
# module's value becomes the process status here, so `print(42)` exits 42 and a
# gate that demanded 0 would refuse its own passing subject. What separates a
# refusal from an answer is the diagnostic, so that is what is read.
answer() {
    printf '%s\n' "$2" >"$work/$1.id"
    set +e
    raw=$("$idol" run "$work/$1.id" 2>&1)
    set -e
    out=$(printf '%s\n' "$raw" | tail -1)
    case $raw in
        *"error:"*) ran=no ;;
        *) ran=yes ;;
    esac
}
expect() {
    answer "$1" "$2"
    [ "$ran" = yes ] || { printf '%s\n' "$raw" >&2; fail "$4: did not run — $2"; }
    [ "$out" = "$3" ] || { printf '%s\n' "$raw" >&2; fail "$4: answered '$out', wanted '$3' — $2"; }
}
refuse() {
    answer "$1" "$2"
    [ "$ran" = no ] || { printf '%s\n' "$raw" >&2; fail "$4: RAN — $2"; }
    case $raw in
        *"$3"*) : ;;
        *) printf '%s\n' "$raw" >&2; fail "$4: refused, but not by name — expected \"$3\"" ;;
    esac
}

# --------------------------------------------------------------- §1 EXECUTION
expect exec_paren 'print(@(1 + 2))'                     3 '§1 compatibility face'
expect exec_world 'print((1 + 2)@{ stage = compile })'  3 '§1 canonical face'
expect exec_bigger 'print(@(2 * 3 + 4))'                10 '§1 the fold is the evaluator, not a peephole on one shape'
# CONTROL. §1 would pass against a compiler that evaluated the operand at RUN
# time and got the same number. The stage has to be observable, and §5 is where
# it is: a runtime value must NOT be reachable through this face.

# ------------------------------------------------------------- §2 DIFFERENTIAL
# Not two assertions that happen to agree — the SAME subject, both spellings,
# compared. This is the ruling's `==`.
expect diff_a 'print(@(7 * 6))'                       42 '§2 compatibility'
expect diff_b 'print((7 * 6)@{ stage = compile })'    42 '§2 canonical'
# And the formatter proves they are one node: reprinting either keeps its own
# face, which can only be true if a single node carries the spelling as
# provenance rather than two constructs carrying two meanings.
printf 'x = @(7 * 6)\n' >"$work/face_a.id"
printf 'x = (7 * 6)@{ stage = compile }\n' >"$work/face_b.id"
"$idol" fmt "$work/face_a.id" >/dev/null 2>&1 || fail "§2 fmt refused the compatibility face"
"$idol" fmt "$work/face_b.id" >/dev/null 2>&1 || fail "§2 fmt refused the canonical face"
grep -q '@(7 \* 6)' "$work/face_a.id" || { cat "$work/face_a.id" >&2; fail "§2 the compatibility face did not survive its reprint"; }
grep -q 'stage = compile' "$work/face_b.id" || { cat "$work/face_b.id" >&2; fail "§2 the formatter migrated the CANONICAL face back to the compatibility one"; }

# ----------------------------------------------------------------- §3 IDENTITY
# `derive(W, {}) = W`. The empty injection forms no world, so qualification
# under it is the subject itself — and the subject keeps every runtime meaning
# it had, which is the half that makes this the identity and not a stage change.
expect id_empty 'print(5@{})' 5 '§3 empty injection is identity'
expect id_empty_runtime 'x = 41 + 1
print(x@{})' 42 '§3 the identity does NOT stage its subject — a runtime value survives it'

# -------------------------------------------------------------- §4 IDEMPOTENCE
# `derive(derive(W, D), D) = derive(W, D)`. Reinjecting the exact same fact into
# a world that already carries it yields the same world, so the doubled spelling
# is the single one — by VALUE here, and structurally in the reprint below.
expect idem_value '(1 + 2)@{ stage = compile }@{ stage = compile }
print((1 + 2)@{ stage = compile }@{ stage = compile })' 3 '§4 doubled interjection'
expect idem_mixed 'print(@((1 + 2)@{ stage = compile }))' 3 '§4 mixed faces'
printf 'x = (1 + 2)@{ stage = compile }@{ stage = compile }\n' >"$work/idem.id"
"$idol" fmt "$work/idem.id" >/dev/null 2>&1 || fail "§4 fmt refused the doubled face"
doubled=$(grep -c 'stage = compile' "$work/idem.id" || true)
[ "$doubled" = 1 ] || {
    cat "$work/idem.id" >&2
    fail "§4 the reprint carries $doubled copies of the same fact — reinjection formed a second world instead of the same one"
}

# ------------------------------------------------------- §5 NO FALLTHROUGH
# `world.md`: "Resolution does not search `trial` and then fall back to the root
# world — the deltas are established when the world is formed." A value that
# does not exist at the compile stage is not a fact of the compile-stage world,
# so it refuses. THIS IS THE ROW THAT PROVES §1 MEASURED A STAGE: if the fold
# were ordinary run-time evaluation, `cwd()` would simply work.
refuse fall_world 'print(@(cwd()))' 'compile-stage-absent' '§5 a world call is a runtime fact'
refuse fall_world_face 'print(cwd()@{ stage = compile })' 'compile-stage-absent' '§5 same, through the canonical face'
# CONTROL: the same expression WITHOUT the stage qualification must run, or §5
# is passing because `cwd()` is broken rather than because the stage excludes it.
answer fall_control 'print(cwd())'
[ "$ran" = yes ] || { printf '%s\n' "$raw" >&2; fail "§5 control: 'cwd()' does not run at all — §5 proves nothing about the stage"; }

# ------------------------------------------------------------------ §6 REFUSAL
# Every delta that is not the compile stage has NO derived-world fact behind it
# (gap[203] closure item 1: WorldFact still records home/reach/members with no
# parent and no fact-delta range). Admitting the shape and ignoring the delta
# would compile a program that does not mean what it says, so each refuses and
# each says which fact is missing.
refuse delta_other 'print((1 + 2)@{ tax = 1 })' \
    "no derived-world fact for delta 'tax'" '§6 an unrepresentable delta'
refuse delta_stage 'print((1 + 2)@{ stage = runtime })' \
    "the 'runtime' stage has no realization to evaluate under" '§6 a stage with no evaluator'
refuse delta_positional 'print((1 + 2)@{ 7 })' \
    "a world delta names one exact fact" '§6 a positional entry names no fact'
refuse delta_duplicate 'print((1 + 2)@{ stage = compile, stage = compile })' \
    "injected twice in one literal" '§6 a duplicate member in one literal'
# The PREFIX injection literal is still refused, and must stay refused while a
# derived world has no value realization — `gate/world/face.sh` §1 depends on it.
refuse prefix_literal 'w = @{ stage = compile }' \
    "injection '@{ … }' has no derived-world fact yet" '§6 the bare injection literal'

# ---------------------------------------------------------------- §7 FORMATTER
# gap[223]'s standing lesson, applied to the new face. Reprint, re-run, reprint
# again and demand byte identity — a spelling assertion alone passes against any
# printer that happens to avoid the bytes.
printf 'print((1 + 2)@{ stage = compile })\n' >"$work/rt.id"
"$idol" fmt "$work/rt.id" >/dev/null 2>&1 || fail "§7 fmt refused the canonical face"
cp "$work/rt.id" "$work/rt.once"
"$idol" fmt "$work/rt.id" >/dev/null 2>&1 || fail "§7 fmt refused its own output"
cmp -s "$work/rt.once" "$work/rt.id" || { diff -u "$work/rt.once" "$work/rt.id" >&2 || true; fail "§7 fmt is not a fixed point on the canonical face"; }
set +e
rtraw=$("$idol" run "$work/rt.id" 2>&1)
set -e
rtout=$(printf '%s\n' "$rtraw" | tail -1)
[ "$rtout" = 3 ] || { cat "$work/rt.id" >&2; printf '%s\n' "$rtraw" >&2; fail "§7 the reprint changed the program's answer: $rtout"; }

printf 'world/stage gate: PASS — the compile stage is a world (both faces execute and agree; empty injection is identity; same-fact reinjection is idempotent by value and in the reprint; a runtime value does not fall through; five deltas refused by name; the canonical face survives its reprint)\n'
printf 'world/stage gate: NOTE — the STAGE world is the only derived world with a realization. WorldFact still carries no parent and no fact-delta range, so no derived world is a graph fact yet (gap[203] item 1, gap[227]).\n'
