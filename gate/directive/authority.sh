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
#   does not touch. Its own header names the defect -- "src/legacy_directives.zig
#   nevertheless calls the dotted `@comp.*` forms canonical" -- without gating
#   it. These three rules gate it.
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
# THREE RULES:
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
#   sh gate/directive/authority.sh              controls + the three rules
#   sh gate/directive/authority.sh --control    controls only, plus the compiler
#                                               measurement behind lib/jit.id
set -eu
LC_ALL=C
export LC_ALL

prog=directive/authority
root=${DIRECTIVEAUTHORITYROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$root" || exit 2

# ---------------------------------------------------------------- constants --
# Pinned 2026-08-23 against idol@debad1df.
#
# DENOMINATOR, because a numerator alone is a rumour: 569 dotted rows in
# src/meta_module.zig, three spellings per operation, i.e. ~190 distinct
# operations behind them.
CATALOG_FILE=src/meta_module.zig
CATALOG_BUDGET=569

CATALOG_RE='\\.public = "(comp|meta|compiler)\\.'
CANONICAL_RE='\\.canonical'
RECOMMEND_RE='deprecated, use @'

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
[ "$viol" -eq 0 ] || { printf '%s: CONTROLS FAILED (%s)\n' "$prog" "$viol"; exit 2; }
ok '8 pattern controls: every pattern sees its defect and declines the lawful face'

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

if [ "$viol" -eq 0 ]; then
  printf '%s: PASS\n' "$prog"
  exit 0
fi
printf '%s: FAIL (%s finding(s))\n' "$prog" "$viol"
exit 1
