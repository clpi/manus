#!/bin/sh
# gate/directive/authority.sh -- the compiler's own claims about the directive
# namespace. Mechanical. Not arguable.
#
# SCOPE, stated first so this is not confused with its sibling.
#   `gate/directive.sh` owns `@comp.*` USAGE in `.id` source: a per-form ledger,
#   code positions only, refusing a new form and refusing a rising count. That
#   is the corpus side and it is not restated here.
#
#   This gate owns the AUTHORITY side, in `src/`, which that ledger explicitly
#   does not touch. Compatibility aliases and positive source teaching can keep
#   a retired family authoritative after its `@comp.*` uses reach zero. These
#   six rules gate that residue.
#
# THE LAW. docs/metaprogramming.md: metaprogramming operates on graph-owned
# identities, relations, facts, dependencies, demands, laws, worlds, provenance
# and transformations, and needs "no independent macro language, AST kingdom,
# directive namespace, or string-dispatched compiler API". Its last line: "No
# compiler-directive syntax is admitted." docs/spec/law.md 5/6 gives `@`
# permanently to current-world access, injection and qualification, so a
# directive namespace is an illegal occupant of that sigil. And
# docs/spec/canonical.md 25 lists `@(comp|host|runtime).` as a hard lexical
# reject pattern.
#
# SIX RULES:
#   (B) CATALOG. Dotted directive entries in src/meta_module.zig may not EXCEED
#       the pinned budget. The ledger next door counts `.id` source only, so the
#       Zig-side catalog -- three spellings per operation, `comp.`/`meta.`/
#       `compiler.` -- is uncounted by it. Renaming a corpus site onto a NEW
#       catalog entry would lower the ledger and is caught here.
#   (D) NO CANONICAL CLAIM. src/legacy_directives.zig may not carry a
#       `.canonical` field. The table is compatibility parsing; naming it
#       canonical is the authority defect this gate was written for. The field
#       is spelled `compatibility` today and this is what keeps it that way.
#   (E) NO RECOMMENDATION. No diagnostic may tell a programmer to write a
#       directive namespace. The parser used to answer `@ctz` with "deprecated,
#       use @comp.bit.ctz instead", which made the compiler the loudest
#       publisher of the namespace its own law retires.
#   (F) REMOVED FAMILY. The text `contains` relation now carries its own
#       compile-time contraction and dynamic realization. None of the three
#       former `*.str.contains` catalog aliases or source faces may return,
#       even if another catalog row is deleted to keep the gross budget
#       unchanged.
#   (G) DORMANT FAMILY. `codegen` had six dotted rows, one bare classifier and
#       two catalog-category branches, but zero tracked source faces, no
#       `__codegen` consumer and no module-registration branch. None may return:
#       a catalog entry with no semantic producer is still host authority.
#   (H) SECOND CATALOG. `.public = ` is not the only place this file writes
#       directive names down. `isMetaAttribute` carries `expression_combinators`,
#       a parallel list keyed on the SAME public names, deciding whether a name
#       parses in expression position or as a module directive. Rule (B) is
#       BLIND to it -- measured at 126 entries while (B) reported 566, so the
#       true host authority was 692 and the pinned ceiling understated it by a
#       fifth. Rows could be added there for free, and a rename from the first
#       catalog into the second would have LOWERED (B) while changing nothing.
#
# NON-NEGOTIABLES, learned from gate/admission.sh and GAP-201/GAP-220:
#   * A CEILING WITHOUT A FLOOR REPORTS CLEAN WHEN IT BREAKS. Rule (B) was
#     written as `rows > BUDGET -> fail` and MEASURED: repointing the catalog
#     file at a file with no rows printed `0 dotted entries` and then `ok`.
#     `assert_live` fails closed on that -- see its comment.
#   * Subjects come from `gate/subject.sh`, the one fail-closed producer. No
#     gate-local `git ls-files`/`find` policy beside it.
#   * `assert_read` refuses a missing or empty subject rather than reporting.
#   * Every pattern carries a control BEFORE anything is counted: it must see a
#     planted violation and decline the lawful face. A gate whose patterns
#     cannot fail is deleted.
#   * awk, not `grep`: `grep` on a contributor machine may be a shell function
#     wrapping ugrep, whose regex dialect differs.
#   * LC_ALL=C. Tracked files carry bytes that abort a UTF-8 awk mid-stream,
#     which would silently SHORTEN a count.
#   * The doubled backslash in every pattern is load-bearing. `awk -v` processes
#     escape sequences in the assigned value, so a single `\.` reaches the regex
#     engine as a bare `.` -- ANY byte -- and the count inflates. Measured once
#     at 1642 against a true 1586.
#
# USAGE:
#   sh gate/directive/authority.sh              controls + the six rules
#   sh gate/directive/authority.sh --control    controls only, plus the compiler
#                                               measurement behind lib/jit.id
set -eu
LC_ALL=C
export LC_ALL

prog=directive/authority
root=${DIRECTIVEAUTHORITYROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$root" || exit 2

# ---------------------------------------------------------------- constants --
# Pinned 2026-08-23 by the executable rule below.
#
# DENOMINATOR, because a numerator alone is a rumour: 240 dotted rows in
# src/meta_module.zig over 158 distinct operations. `comp.` is the only full
# spelling (190 rows); `meta.` survives on 50 rows, ONLY where a `.id` site or
# a host caller actually names it.
#
# FOUR DELETIONS GOT US HERE, all measured with this rule, none a rename:
#   560 -> 381  the `compiler.` spelling entire. 179 rows carrying zero
#               distinct meaning -- every one resolved to the same internal
#               hook as its `comp.`/`meta.` siblings -- and zero `.id` users.
#   381 -> 253  128 `meta.` rows with NO REFERENT ANYWHERE: not in `.id`, not
#               in `src/`, not in `docs/`. Absence of callers is the reason to
#               delete, not a reason to keep. A dormant row is a claim, and an
#               agent can discover and revive it.
#   253 -> 252  the bare `@comp.emit` alias, a fourth spelling of `__emit`
#               beside `@comp.c.emit`, `@c.emit` and `@emit`, with no users.
#   252 -> 240  the SELF-DESCRIBING family: `@comp.catalog`, `@comp.ladder`,
#               `@comp.agent.*`. These described the directive namespace, not
#               any program, so once the namespace stops being authority they
#               have no referent to describe. Deleted, not classified.
#
# WITNESSED, so none of it is a vacuous edit. Each deleted spelling compiled
# before and is refused after, while the surviving spelling of the same
# operation still does exactly what it did:
#   @compiler.c.emit  1 machine-word store -> REFUSED
#   @comp.emit        1 machine-word store -> REFUSED
#   @comp.c.emit      1 store              -> 1 store   (unchanged)
#   @comp.catalog/@comp.ladder/@comp.agent.dedupe  compiled -> REFUSED
#
# The corpus ledger next door moved only where corpus code was deleted with the
# rows: 108 forms/807 uses -> 101/790, all 17 lost uses belonging to the
# self-describing family. Across the first three deletions it did not move at
# all, which is the evidence they were behaviour-preserving for every program
# that exists.
CATALOG_FILE=src/meta_module.zig
CATALOG_BUDGET=240

CATALOG_RE='\\.public = "(comp|meta|compiler)\\.'
CANONICAL_RE='\\.canonical'
RECOMMEND_RE='deprecated, use @'
REMOVED_ALIAS_RE='\\.public = "(comp|meta|compiler)\\.str\\.contains"'
REMOVED_FACE_RE='@(comp|meta|compiler)\\.str\\.contains'
DORMANT_NAME_RE='"((meta|comp|compiler)\\.)?codegen"'
DORMANT_INTERNAL_RE='"__codegen"'
DORMANT_FACE_RE='@(codegen|(comp|meta|compiler)\\.codegen)([^a-z0-9.]|$)'
DORMANT_REALIZER_RE='(register(Codegen|codegen)|eql\\(u8, name, "codegen"\\))'

# (H) The second catalog. Block-scoped, not whole-file: the same names appear in
# doc comments and in test assertions, and charging those would make the ratchet
# fight its own test suite instead of the catalog.
COMBINATOR_RE='"(comp|meta|compiler)\\.[a-zA-Z0-9_.]+"'
COMBINATOR_BUDGET=66

viol=0
fail() { viol=$((viol + 1)); printf '  FAIL %s\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
die()  { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idoldirauth.XXXXXX") || die 'mktemp failed'
trap 'rm -rf "$tmp"' EXIT INT TERM

count_re() {
  re=$1
  shift
  awk -v re="$re" '
    { line = $0
      while (match(line, re)) { n++; line = substr(line, RSTART + RLENGTH) }
    }
    END { print n + 0 }
  ' "$@"
}

# Count COMBINATOR_RE inside the `expression_combinators` literal only.
count_combinators() {
  awk -v re="$COMBINATOR_RE" '
    /const expression_combinators = \[_\]\[\]const u8\{/ { inblk = 1; next }
    inblk && /^[ \t]*\};[ \t]*$/ { inblk = 0 }
    inblk { line = $0
      while (match(line, re)) { n++; line = substr(line, RSTART + RLENGTH) }
    }
    END { print n + 0 }
  ' "$1"
}

assert_read() {
  rule=$1
  shift
  for f in "$@"; do
    [ -f "$f" ] || die "rule $rule: subject '$f' is missing -- refusing to report"
    [ -s "$f" ] || die "rule $rule: subject '$f' is empty -- refusing to report"
  done
}

# assert_live <rule> <measured> <budget> <what>
#
# A pinned budget above zero is a standing claim that the debt EXISTS. Measuring
# zero against it means the counter, the pattern, or the subject list broke --
# not that the debt vanished overnight. When a migration genuinely reaches zero
# the budget is pinned to zero and this guard relaxes itself.
assert_live() {
  if [ "$3" -gt 0 ] && [ "$2" -eq 0 ]; then
    fail "($1) measured ZERO $4 against a pinned budget of $3 -- the measurement broke; a ratchet that stops counting must never report clean"
    return 1
  fi
  return 0
}

probe() {
  got=$(printf '%s\n' "$3" | awk -v re="$2" '{ if ($0 ~ re) f = 1 } END { print f + 0 }')
  if [ "$4" -eq 1 ] && [ "$got" -ne 1 ]; then
    fail "control $1: pattern is BLIND to [$3] -- fix the pattern, the gate is not measuring"
  elif [ "$4" -eq 0 ] && [ "$got" -ne 0 ]; then
    fail "control $1: pattern matches the lawful face [$3]"
  fi
}

# ------------------------------------------------------------------ controls --
printf '%s: controls\n' "$prog"
probe 'catalog/hit'      "$CATALOG_RE"   '    .{ .public = "comp.map", .internal = "__comptimemap" },'      1
probe 'catalog/meta'     "$CATALOG_RE"   '    .{ .public = "meta.map", .internal = "__comptimemap" },'      1
probe 'catalog/decline'  "$CATALOG_RE"   '    .{ .public = "popcount", .internal = "__popcount" },'         0
probe 'canonical/hit'    "$CANONICAL_RE" '    .{ .public = "ctz", .canonical = "comp.bit.ctz" },'           1
probe 'canonical/declin' "$CANONICAL_RE" '    .{ .public = "ctz", .compatibility = "comp.bit.ctz" },'       0
probe 'canonical/prose'  "$CANONICAL_RE" 'the retired namespace is not canonical'                           0
probe 'recommend/hit'    "$RECOMMEND_RE" 'warning: @ctz is deprecated, use @comp.bit.ctz instead'           1
probe 'recommend/declin' "$RECOMMEND_RE" '@{s} is retained compatibility syntax; no canonical Idol spelling' 0
probe 'alias/hit'        "$REMOVED_ALIAS_RE" '    .{ .public = "comp.str.contains", .internal = "__strcontains" },' 1
probe 'alias/decline'    "$REMOVED_ALIAS_RE" '    .{ .public = "comp.str.countlines", .internal = "__strcountlines" },' 0
probe 'face/hit'         "$REMOVED_FACE_RE"  '@meta.str.contains(haystack, needle)' 1
probe 'face/decline'     "$REMOVED_FACE_RE"  'needle in haystack' 0
probe 'dormant/name'     "$DORMANT_NAME_RE" '    .{ .public = "comp.codegen", .internal = "__codegen" },' 1
probe 'dormant/name-no'  "$DORMANT_NAME_RE" '    .{ .public = "comp.pipeline", .internal = "__pipeline" },' 0
probe 'dormant/hook'     "$DORMANT_INTERNAL_RE" 'const handler = "__codegen";' 1
probe 'dormant/hook-no'  "$DORMANT_INTERNAL_RE" 'const handler = "__schema";' 0
probe 'dormant/face'     "$DORMANT_FACE_RE" '@compiler.codegen("payload")' 1
probe 'dormant/face-no'  "$DORMANT_FACE_RE" '@compiler.schema("payload")' 0
probe 'dormant/realize'  "$DORMANT_REALIZER_RE" 'else if (std.mem.eql(u8, name, "codegen")) {' 1
probe 'dormant/real-no'  "$DORMANT_REALIZER_RE" 'else if (std.mem.eql(u8, name, "pipeline")) {' 0
probe 'combin/hit'       "$COMBINATOR_RE"       '        "comp.map",             "meta.map",' 1
probe 'combin/decline'   "$COMBINATOR_RE"       '        "popcount",             "clz",'      0
[ "$viol" -eq 0 ] || { printf '%s: CONTROLS FAILED (%s)\n' "$prog" "$viol"; exit 2; }
ok '22 pattern controls: every pattern sees its defect and declines the lawful face'

# --------------------------------------------------------- compiler control --
# The measurement behind lib/jit.id's note. Statement-position and
# expression-position `c.emit` must produce the SAME store. When the C emitter
# compared the short spelling while the parser recorded the dotted one, the
# payload was DROPPED: the JIT's word writer compiled to nothing, sealed a page
# of zeros and branched into it -- on ARM64 an all-zero word is `udf`, so the
# failure surfaced as SIGILL thousands of lines from the primitive that lied.
compiler_control() {
  bin=${IDOL_BIN:-./zig-out/bin/idol}
  [ -x "$bin" ] || die "compiler control needs $bin -- run: zig build"
  cat > "$tmp/dotted.id" <<'PROBE'
wstmt: any = (buf: any, idx: i64, word: i64)
  @comp.c.emit("((uint32_t*)buf.as.tval)[idx] = (uint32_t)word;")
PROBE
  cat > "$tmp/short.id" <<'PROBE'
wstmt: any = (buf: any, idx: i64, word: i64)
  @c.emit("((uint32_t*)buf.as.tval)[idx] = (uint32_t)word;")
PROBE
  if ! "$bin" dump-c "$tmp/dotted.id" > "$tmp/dotted.c" 2>"$tmp/dotted.err"; then
    fail 'compiler control: dump-c refused the dotted statement-position probe'
    return
  fi
  if ! "$bin" dump-c "$tmp/short.id" > "$tmp/short.c" 2>"$tmp/short.err"; then
    fail 'compiler control: dump-c refused the short statement-position probe'
    return
  fi
  a=$(count_re 'uint32_t\\*\\)buf' "$tmp/dotted.c")
  b=$(count_re 'uint32_t\\*\\)buf' "$tmp/short.c")
  if [ "$a" -lt 1 ]; then
    fail "compiler control: DOTTED statement-position payload was DROPPED (machine-word writes vanish) -- $a store(s) emitted"
  elif [ "$a" -ne "$b" ]; then
    fail "compiler control: spellings disagree -- dotted emitted $a store(s), short emitted $b"
  else
    ok "compiler control: both spellings emit the same $a store(s); no name can drop a machine-word write"
  fi
}

if [ "${1:-}" = '--control' ]; then
  compiler_control
  if [ "$viol" -eq 0 ]; then printf '%s: PASS\n' "$prog"; exit 0; fi
  printf '%s: FAIL (%s finding(s))\n' "$prog" "$viol"
  exit 1
fi
[ $# -eq 0 ] || die "unknown argument '$1'"

# -------------------------------------------------------------------- rules --
printf '%s: rules\n' "$prog"

# Assert a real work tree through the one producer before reading fixed paths:
# a `git archive` mirror is the shape that made forty-three gates vacuous.
sh gate/subject.sh --tree || die 'gate/subject.sh refused the work tree -- refusing to report'

assert_read B "$CATALOG_FILE"
rows=$(count_re "$CATALOG_RE" "$CATALOG_FILE")
printf '  catalog  %s dotted entries in %s, budget %s\n' "$rows" "$CATALOG_FILE" "$CATALOG_BUDGET"
if ! assert_live B "$rows" "$CATALOG_BUDGET" 'catalog entr(ies)'; then
  :
elif [ "$rows" -gt "$CATALOG_BUDGET" ]; then
  fail "(B) catalog $rows EXCEEDS budget $CATALOG_BUDGET -- a new directive was added to the catalog"
else
  ok '(B) catalog within budget'
  [ "$rows" -eq "$CATALOG_BUDGET" ] || \
    printf '  note     budget is stale by %s; lower CATALOG_BUDGET to %s\n' "$((CATALOG_BUDGET - rows))" "$rows"
fi

compat=src/legacy_directives.zig
assert_read D "$compat"
claims=$(count_re "$CANONICAL_RE" "$compat")
if [ "$claims" -gt 0 ]; then
  fail "(D) $compat carries $claims .canonical field(s) -- the compatibility table may not name a canonical directive"
else
  ok '(D) compatibility table claims no canonical directive'
fi

assert_read E src/parser.zig src/sema.zig
rec=$(count_re "$RECOMMEND_RE" src/parser.zig src/sema.zig)
if [ "$rec" -gt 0 ]; then
  fail "(E) $rec diagnostic(s) recommend a directive namespace -- name a retired spelling, never prescribe one"
else
  ok '(E) no diagnostic recommends a directive namespace'
fi

removed_aliases=$(count_re "$REMOVED_ALIAS_RE" "$CATALOG_FILE")
subjects="$tmp/id-subjects"
sh gate/subject.sh '*.id' >"$subjects" || die 'rule F: Idol source enumeration failed'
removed_faces=0
while IFS= read -r source; do
  assert_read F "$source"
  n=$(count_re "$REMOVED_FACE_RE" "$source")
  removed_faces=$((removed_faces + n))
done <"$subjects"
if [ "$removed_aliases" -gt 0 ] || [ "$removed_faces" -gt 0 ]; then
  fail "(F) removed text-contains directive returned: $removed_aliases catalog alias(es), $removed_faces source face(s) -- use the ordinary contains relation"
else
  ok '(F) text contains has no directive-catalog alias or source face'
fi

dormant_names=$(count_re "$DORMANT_NAME_RE" "$CATALOG_FILE")
zig_subjects="$tmp/zig-subjects"
sh gate/subject.sh 'src/*.zig' >"$zig_subjects" || die 'rule G: compiler source enumeration failed'
dormant_internal=0
while IFS= read -r source; do
  assert_read G "$source"
  n=$(count_re "$DORMANT_INTERNAL_RE" "$source")
  dormant_internal=$((dormant_internal + n))
done <"$zig_subjects"
dormant_faces=0
while IFS= read -r source; do
  n=$(count_re "$DORMANT_FACE_RE" "$source")
  dormant_faces=$((dormant_faces + n))
done <"$subjects"
realizer=src/meta_directives.zig
assert_read G "$realizer"
dormant_realizers=$(count_re "$DORMANT_REALIZER_RE" "$realizer")
if [ "$dormant_names" -gt 0 ] || [ "$dormant_internal" -gt 0 ] || \
   [ "$dormant_faces" -gt 0 ] || [ "$dormant_realizers" -gt 0 ]; then
  fail "(G) dormant codegen directive returned: $dormant_names host name(s), $dormant_internal internal hook(s), $dormant_faces source face(s), $dormant_realizers realizer(s)"
else
  ok '(G) dormant codegen directive has no host name, hook, source face or realizer'
fi

combinators=$(count_combinators "$CATALOG_FILE")
printf '  second   %s expression_combinators entries, budget %s\n' "$combinators" "$COMBINATOR_BUDGET"
if ! assert_live H "$combinators" "$COMBINATOR_BUDGET" 'expression_combinators entr(ies)'; then
  :
elif [ "$combinators" -gt "$COMBINATOR_BUDGET" ]; then
  fail "(H) expression_combinators $combinators EXCEEDS budget $COMBINATOR_BUDGET -- a directive name was added to the SECOND catalog, which rule (B) cannot see"
else
  ok '(H) second catalog within budget'
  [ "$combinators" -eq "$COMBINATOR_BUDGET" ] || \
    printf '  note     second-catalog budget is stale by %s; lower COMBINATOR_BUDGET to %s\n' "$((COMBINATOR_BUDGET - combinators))" "$combinators"
fi

if [ "$viol" -eq 0 ]; then
  printf '%s: PASS\n' "$prog"
  exit 0
fi
printf '%s: FAIL (%s finding(s))\n' "$prog" "$viol"
exit 1
