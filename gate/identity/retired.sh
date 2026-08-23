#!/bin/sh
# gate/identity/retired.sh -- the retired project identity, in what a person reads.
#
# docs/spec/law.md 0: "The project and language are **Idol**. The compiler
# executable is `idol`." docs/spec/canonical.md 25 lists `(?i)(duo|duon|idsem)`
# as a hard lexical reject pattern, and docs/spec/convergence-directive.md
# orders retired `duo_*` symbols repaired immediately.
#
# WHAT WAS ACTUALLY SHIPPING, measured before this gate existed:
#   src/term.zig printed "the marked source construct is the one Duo rejected"
#   underneath EVERY error and "Duo accepted the code" underneath EVERY warning.
#   src/main.zig printed `usage: duo`, told `idol init` users to run
#   `duo build/test/run/shell`, banner'd `duo build`, and generated
#   bash/zsh/fish/nu completions installing and describing a command named
#   `duo` -- completing an executable that DOES NOT EXIST -- with a
#   `*.(duo|lua)` source glob naming a retired extension. The shell session
#   exported history headed "canonical Duo" and wrote `.duo` temp artifacts.
#
# THREE PARTS, each stating exactly what it covers rather than one broad claim:
#   F1 HARD ZERO over the OUTPUT-OWNING files -- every string literal, ordinary
#      and `\\` multiline, with no allowlist of function names at all.
#   F2 HARD ZERO over `term.*` call sites in every src/*.zig, where the list of
#      `term.*` names is DERIVED FROM `pub fn` in src/term.zig AT RUN TIME.
#      The first version of this rule hand-wrote ten of term's forty-seven
#      public functions and therefore could not see `term.dim` or
#      `term.banner`; it reported a hard zero over a surface it had never
#      looked at. A literal restating part of a table agrees until it doesn't,
#      which is the same defect `isCInterfaceDirective`'s six string compares
#      were. Derive it or do not check it.
#   F3 CEILING over the remaining string literals elsewhere in src/*.zig. This
#      is named REMAINING WORK, not a clean bill: it is mostly generated-C
#      payload text in the unreachable AST/Lua bridge, plus JSON/graph export
#      field values.
#
# Generated C SYMBOLS (`duo_g_x`, `duo_task_poll`) are out of scope, and they
# are excluded by the WORD BOUNDARY in the pattern rather than by an exemption
# list. They are a separate physical surface with a separate deletion gate.
#
# NON-NEGOTIABLES: subjects come from `gate/subject.sh`, the one fail-closed
# producer (GAP-201/GAP-220); awk, not `grep`; LC_ALL=C, because tracked bytes
# abort a UTF-8 awk mid-stream and silently shorten a count; every part prints
# its DENOMINATOR so a zero can be told from a scan that never ran; and each
# pattern is controlled against a planted violation before anything is counted.
#
# USAGE:
#   sh gate/identity/retired.sh
set -eu
LC_ALL=C
export LC_ALL

prog=identity/retired
root=${IDENTITYRETIREDROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$root" || exit 2

# The retired identity as a WHOLE WORD. `\<`/`\>` are not portable in awk EREs,
# so the boundary is spelled out. The doubled backslash elsewhere in this file
# is load-bearing for the same reason it is in every gate here: `awk -v`
# processes escapes in the assigned value.
RETIRED_RE='(^|[^A-Za-z0-9_])[Dd]uo([^A-Za-z0-9_]|$)'

# Files whose entire string-literal surface is what a person reads.
OUTPUT_FILES='src/main.zig src/term.zig src/shell_session.zig'

# Remaining string-literal carriers elsewhere in src/*.zig. Pinned 2026-08-23
# against idol@debad1df at 125 across 158,148 scanned lines.
#
# It read 113 until the multiline branch above was repaired. The awk source had
# `"\\"` -- ONE backslash -- where it needed `"\\\\"`, so `substr(line,1,2)` was
# compared against a 1-character string, the `\\` continuation branch was dead,
# and every Zig multiline string in the tree went unscanned. That is the whole
# usage block and all four completion payloads: the surface a person reads
# first. A planted `usage: duo` was invisible to the gate until this was fixed.
#
#   src/codegen.zig ............ 59  the AST/Lua C bridge `main.zig` refuses to
#                                    route to; generated-C payload text
#   src/sema.zig ............... 14
#   src/sim.zig ................ 12
#   src/token_classify_gen.zig ..5
#   src/lexer.zig ............... 4
#   src/abi_specialize.zig ...... 4
#   ...and 15 more files with 1-3 each.
IDENTITY_BUDGET=125

viol=0
fail() { viol=$((viol + 1)); printf '  FAIL %s\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
die()  { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idolidentity.XXXXXX") || die 'mktemp failed'
trap 'rm -rf "$tmp"' EXIT INT TERM

probe() {
  got=$(printf '%s\n' "$3" | awk -v re="$2" '{ if ($0 ~ re) f = 1 } END { print f + 0 }')
  if [ "$4" -eq 1 ] && [ "$got" -ne 1 ]; then
    fail "control $1: pattern is BLIND to [$3] -- fix the pattern, the gate is not measuring"
  elif [ "$4" -eq 0 ] && [ "$got" -ne 0 ]; then
    fail "control $1: pattern matches the lawful face [$3]"
  fi
}

# The string-literal scanner, shared by F1 and F3, written to a file rather
# than inlined. Nested `sh -c '... awk '"'"' ...'` quoting is how a scanner
# stops scanning while still exiting zero; a program file has one level of
# quoting and can be read.
#
# It emits `file:line:content` for every string literal whose content carries
# the retired identity, then a COUNT line carrying findings and the DENOMINATOR
# it scanned. Both `"..."` and `\\` multiline content are literals; `//` lines
# are comments and are not output.
write_scanner() {
  cat > "$tmp/literals.awk" <<'AWK'
BEGIN { n = split(skip, s, " "); for (i = 1; i <= n; i++) exempt[s[i]] = 1 }
function emit(body) { if (body ~ retired) { printf "    %s:%d:%s\n", FILENAME, FNR, body; hits++ } }
FILENAME in exempt { next }
{
  line = $0; sub(/^[ \t]*/, "", line)
  if (substr(line, 1, 2) == "//") next
  scanned++
  if (substr(line, 1, 2) == "\\\\") { emit(substr(line, 3)); next }
  len = length($0); inq = 0; buf = ""
  for (i = 1; i <= len; i++) {
    c = substr($0, i, 1)
    if (inq && c == "\\") { buf = buf c; i++; buf = buf substr($0, i, 1); continue }
    if (c == "\"") { if (inq) { emit(buf); inq = 0; buf = "" } else inq = 1; continue }
    if (!inq && c == "/" && substr($0, i + 1, 1) == "/") break
    if (inq) buf = buf c
  }
}
END { printf "COUNT %d %d\n", hits + 0, scanned + 0 }
AWK
  [ -s "$tmp/literals.awk" ] || die 'could not write the literal scanner -- refusing to report'
}

# ------------------------------------------------------------------ controls --
printf '%s: controls\n' "$prog"
probe 'retired/diagnostic' "$RETIRED_RE" 'the marked source construct is the one Duo rejected'      1
probe 'retired/usage'      "$RETIRED_RE" 'usage: duo [command] [options] [file]'                    1
probe 'retired/completion' "$RETIRED_RE" "complete -c duo -n '__fish_use_subcommand' -a 'shell'"    1
probe 'retired/extension'  "$RETIRED_RE" "_arguments \$opts '*:source:_files -g \"*.(duo|lua)\"'"   1
probe 'retired/repaired'   "$RETIRED_RE" 'the marked source construct is the one Idol rejected'     0
probe 'retired/csymbol'    "$RETIRED_RE" '    lua_Value duo_args[4] = { __self };'                  0
probe 'retired/csymbol2'   "$RETIRED_RE" '    duo_task_poll(frame->child)'                          0
[ "$viol" -eq 0 ] || { printf '%s: CONTROLS FAILED (%s)\n' "$prog" "$viol"; exit 2; }
ok '7 pattern controls: the pattern sees the shipped defects and declines repaired text and C symbols'

# ------------------------------------------------------------------ subjects --
sh gate/subject.sh 'src/*.zig' > "$tmp/zigs" || die 'gate/subject.sh refused the src/*.zig enumeration -- refusing to report'
zigcount=$(awk 'END { print NR + 0 }' "$tmp/zigs")
[ "$zigcount" -ge 50 ] || die "enumerated only $zigcount src/*.zig subjects -- enumeration is broken, refusing to report clean"
for f in $OUTPUT_FILES; do
  [ -s "$f" ] || die "output-owning subject '$f' is missing or empty -- refusing to report"
done

printf '%s: rules\n' "$prog"

# ---- scanner control: BOTH literal faces, before either rule counts --------
# The `\\` branch was dead once (see IDENTITY_BUDGET) and nothing noticed,
# because a scanner that silently skips a face still exits zero and still
# prints a denominator. This plants one violation in each face and demands the
# scanner find exactly two.
write_scanner
cat > "$tmp/fixture.zig" <<'FIXTURE'
// a comment naming duo must NOT count -- prose is not output
const ordinary = "usage: duo [command]";
const multi =
    \\# fish completion for duo
    \\complete -c idol -f
;
const csymbol = "duo_task_poll(frame)";
FIXTURE
fixhits=$(awk -v retired="$RETIRED_RE" -v skip='' -f "$tmp/literals.awk" "$tmp/fixture.zig" | awk '/^COUNT /{ print $2 }')
if [ "$fixhits" -ne 2 ]; then
  fail "control scanner: fixture plants one ordinary and one multiline violation, scanner found $fixhits -- a literal face is not being scanned"
fi
[ "$viol" -eq 0 ] || { printf '%s: SCANNER CONTROL FAILED (%s)\n' "$prog" "$viol"; exit 2; }
ok 'scanner control: both literal faces scanned; comments and C symbols declined'

# ---- F1: every string literal in the output-owning files -------------------
# shellcheck disable=SC2086  # OUTPUT_FILES is a deliberate word list
f1=$(awk -v retired="$RETIRED_RE" -v skip='' -f "$tmp/literals.awk" $OUTPUT_FILES)
f1n=$(printf '%s\n' "$f1" | awk '/^COUNT /{ print $2 }')
f1lines=$(printf '%s\n' "$f1" | awk '/^COUNT /{ print $3 }')
[ "$f1lines" -gt 0 ] || die 'F1 scanned zero lines of the output-owning files -- refusing to report clean'

# ---- F2: term.* call sites, against a DERIVED name list --------------------
api=$(awk '/^pub fn [a-zA-Z]/ { n = $3; sub(/\(.*/, "", n); print n }' src/term.zig | sort -u | tr '\n' '|' | sed 's/|$//')
[ -n "$api" ] || die 'F2 derived ZERO term.* names from src/term.zig -- the derivation broke'
apicount=$(printf '%s\n' "$api" | awk -F'|' '{ print NF }')
[ "$apicount" -ge 20 ] || die "F2 derived only $apicount term.* names from src/term.zig -- the derivation broke"
diag_re="term\\\\.($api)\\\\("
probe 'derived/locwarn' "$diag_re" '        term.locWarn(loc, "warning: x", .{});' 1
probe 'derived/dim'     "$diag_re" '        term.dim("faint", .{});'               1
probe 'derived/banner'  "$diag_re" '        term.banner("idol build");'            1
probe 'derived/decline' "$diag_re" '        const x = terminal.errno;'             0
[ "$viol" -eq 0 ] || { printf '%s: DERIVED-PATTERN CONTROLS FAILED (%s)\n' "$prog" "$viol"; exit 2; }

f2=$(xargs -n 200 < "$tmp/zigs" awk -v diag="$diag_re" -v retired="$RETIRED_RE" '
    $0 ~ diag { sites++ }
    $0 ~ diag && $0 ~ retired { printf "    %s:%d: %s\n", FILENAME, FNR, $0; hits++ }
    END { printf "COUNT %d %d\n", hits + 0, sites + 0 }
  ')
f2n=$(printf '%s\n' "$f2" | awk '/^COUNT /{ s += $2 } END { print s + 0 }')
f2sites=$(printf '%s\n' "$f2" | awk '/^COUNT /{ s += $3 } END { print s + 0 }')
[ "$f2sites" -gt 0 ] || die 'F2 found ZERO term.* call sites in src/*.zig -- the scan broke; refusing to report clean'

# ---- F3: the remaining string-literal surface, a ceiling -------------------
f3=$(xargs -n 200 < "$tmp/zigs" awk -v retired="$RETIRED_RE" -v skip="$OUTPUT_FILES" -f "$tmp/literals.awk")
f3n=$(printf '%s\n' "$f3" | awk '/^COUNT /{ s += $2 } END { print s + 0 }')
f3lines=$(printf '%s\n' "$f3" | awk '/^COUNT /{ s += $3 } END { print s + 0 }')
[ "$f3lines" -gt 0 ] || die 'F3 scanned zero lines -- refusing to report clean'

printf '  identity F1 %s in %s output line(s) | F2 %s of %s term.* site(s) via %s derived name(s) | F3 %s in %s line(s), budget %s\n' \
  "$f1n" "$f1lines" "$f2n" "$f2sites" "$apicount" "$f3n" "$f3lines" "$IDENTITY_BUDGET"

if [ "$f1n" -gt 0 ] || [ "$f2n" -gt 0 ]; then
  fail '(F1/F2) retired project identity in user-visible compiler text -- the project is Idol and the executable is idol (law.md 0)'
  printf '%s\n' "$f1" | awk '!/^COUNT /' | sed -n '1,12p'
  printf '%s\n' "$f2" | awk '!/^COUNT /' | sed -n '1,12p'
else
  ok '(F1/F2) no retired identity in output-owning string literals or term.* call sites'
fi

# A pinned budget above zero is a standing claim that the debt EXISTS. Measuring
# zero against it means the scan broke, not that the debt vanished.
if [ "$IDENTITY_BUDGET" -gt 0 ] && [ "$f3n" -eq 0 ]; then
  fail "(F3) measured ZERO remaining carriers against a pinned budget of $IDENTITY_BUDGET -- the measurement broke; a ratchet that stops counting must never report clean"
elif [ "$f3n" -gt "$IDENTITY_BUDGET" ]; then
  fail "(F3) $f3n remaining identity carrier(s) EXCEEDS budget $IDENTITY_BUDGET -- the ratchet only turns down"
else
  ok '(F3) remaining identity carriers within budget (REMAINING WORK, not a clean bill)'
  [ "$f3n" -eq "$IDENTITY_BUDGET" ] || \
    printf '  note     budget is stale by %s; lower IDENTITY_BUDGET to %s\n' "$((IDENTITY_BUDGET - f3n))" "$f3n"
fi

if [ "$viol" -eq 0 ]; then
  printf '%s: PASS\n' "$prog"
  exit 0
fi
printf '%s: FAIL (%s finding(s))\n' "$prog" "$viol"
exit 1
