#!/bin/sh
# gate/agentlaw.sh — agent-instruction files must not contradict supreme law.
#
#   sh gate/agentlaw.sh
#
# law.md §115 CANONICALITY: git history and repository frequency are not
# language law. An instruction that steers agents toward a retired directive
# namespace or toward "follow existing patterns" for .id source — without
# resolving those patterns against docs/spec/law.md first — manufactures
# stale-law authority and fails here.
#
# Checks, over the agent-instruction surface (AGENTS.md, CLAUDE.md,
# .agents/AGENT_CANONICAL.md, .agents/HARNESS.md, docs/spec/agent.md),
# evaluated per PARAGRAPH BLOCK (text between blank lines), because a ban
# names its spellings on the lines after the word that bans them:
#   1. a block mentioning a compiler-namespace @ directive (@comp. @meta.
#      @compiler. @host. @runtime. @emit @pipeline @c.) must contain a
#      forbidding marker (invalid/retired/not lawful/unlawful/forbidden/
#      never/removed/deleted/denied/does not exist/rejected/refused/
#      do not) — naming them to ban them is lawful, recommending is not;
#   2. no block may carry "follow existing patterns"-style guidance;
#   3. a block teaching an annotation-position open type (`: any`) or void
#      descriptor must contain a forbidding marker (law.md §112/§113; the
#      relation faces `xs:any(p)` and `:any` pass).
#
# Every pattern carries a positive control before the census runs: a gate
# whose patterns cannot fail is deleted. Exit code = violation count;
# exit 2 = the census examined nothing or a control failed.
set -u
cd "$(dirname "$0")/.." || exit 2

FILES="AGENTS.md CLAUDE.md .agents/AGENT_CANONICAL.md .agents/HARNESS.md docs/spec/agent.md"

DIRECTIVE_RE='@(comp|meta|compiler|host|runtime|emit|pipeline|c)\.?'
FORBID_RE='(invalid|retired|not lawful|unlawful|forbidden|never|removed|deleted|denied|does not exist|rejected|refus|do not)'
PATTERN_RE='(follow (the )?existing patterns?|match existing patterns?)'
ANYDESC_RE=':[[:space:]]*any([[:space:]]*[,)=]|[[:space:]]*$)'
VOIDDESC_RE=':[[:space:]]*void([[:space:]]*[,)=]|[[:space:]]*$)'

viol=0
checked=0

bad() {
  printf '  FAIL %s\n' "$*"
  viol=$((viol + 1))
}

control() {
  # $1: string, $2: regex, $3: must_match (1) or must_decline (0)
  if [ "$3" -eq 1 ]; then
    printf '%s\n' "$1" | grep -qE "$2" || {
      bad "control: pattern [$2] no longer matches its probe — the gate is blind, fix the pattern"
    }
  else
    if printf '%s\n' "$1" | grep -qE "$2"; then
      bad "control: pattern [$2] matches its lawful probe [$1]"
    fi
  fi
}

# Controls — every regex must see its defect and decline the lawful face.
control "the canonical spelling is @comp.dialect" "$DIRECTIVE_RE" 1
control "@comp.* and every @c.* form are not lawful Idol source" "$FORBID_RE" 1
control "the world injection face is lawful" "$DIRECTIVE_RE" 0
control "follow existing patterns when editing .id files" "$PATTERN_RE" 1
control "resolve spellings against docs/spec/law.md before reuse" "$PATTERN_RE" 0
control "value: any = boxed" "$ANYDESC_RE" 1
control "users:any(.active)" "$ANYDESC_RE" 0
control "f = (n: void) nil" "$VOIDDESC_RE" 1
control "never: @host.* as generic source APIs" "$FORBID_RE" 1
scan_file() {
  f=$1
  n=$(awk -v directive="$DIRECTIVE_RE" -v forbid="$FORBID_RE" \
        -v pattern="$PATTERN_RE" -v anydesc="$ANYDESC_RE" -v voiddesc="$VOIDDESC_RE" \
        -v file="$f" '
    function flush() {
      low = tolower(block)
      if (block ~ directive && low !~ forbid) {
        printf "  FAIL %s: block recommends a compiler-namespace @ directive without forbidding it:\n    %s\n", file, head
        v++
      }
      if (low ~ pattern) {
        printf "  FAIL %s: follow-existing-patterns guidance — frequency is not law:\n    %s\n", file, head
        v++
      }
      if (block ~ anydesc && low !~ forbid) {
        printf "  FAIL %s: block teaches an annotation-position open type without a ban:\n    %s\n", file, head
        v++
      }
      if (block ~ voiddesc && low !~ forbid) {
        printf "  FAIL %s: block teaches an annotation-position void descriptor without a ban:\n    %s\n", file, head
        v++
      }
      block = ""
    }
    BEGIN { block = ""; head = ""; v = 0 }
    /^[[:space:]]*$/ { flush(); next }
    {
      if (block == "") head = $0
      block = block "\n" $0
    }
    END { flush(); print v }
  ' "$f")
  add=$(printf '%s\n' "$n" | tail -1)
  case $add in
    ''|*[!0-9]*) add=0 ;;
  esac
  viol=$((viol + add))
}

for f in $FILES; do
  if [ ! -f "$f" ]; then
    continue
  fi
  checked=$((checked + 1))
  scan_file "$f"
done

[ "$checked" -gt 0 ] || {
  printf '%s\n' "agentlaw: examined 0 agent-instruction files — the census did not run" >&2
  exit 2
}

printf '%s\n' "agentlaw: $checked agent-instruction files checked, $viol violations"
exit "$viol"
