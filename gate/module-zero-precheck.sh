#!/bin/sh
# gate/module-zero-precheck.sh — gap[166] MODULE-ZERO, pre-graph gate.
#
# WHAT IT PROTECTS. `can_emit_native_scalar_module` runs 210 lines BEFORE the
# graph is lifted and its verdict is a hard gate on the direct backend. It must
# therefore have NO OPINION about what a home binding lowers to: it cannot have
# a sound one, and `main.zig` binds the graph's own refusal only when the
# precheck has no reason of its own — so any reason minted here PREEMPTS the
# graph and replaces `DNB011 … producer: graph` with `DNB001 … bail site:
# native-scalar precheck — <module-shaped>`.
#
# WHY A GATE AND NOT A CORPUS ROW. Measured 2026-08-22 over all 1005 tracked
# `.id`: the module arms of `stmt_is_native_scalar` are reached by 10 programs
# and mint a reason on exactly 1 (`lib/token/grammarrole.id`). The arms of
# `module_top_level_is_native` are reached by 0 on every path. Ablating the
# whole thing left all 21 shell gates green. These fixtures are the witness the
# corpus does not carry.
#
# Exit 0 = every subject refused with the GRAPH as producer.
set -u

ROOT=${MODULE_ZERO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
IDOL=${IDOL_BIN:-$ROOT/zig-out/bin/idol}
[ -x "$IDOL" ] || { echo "module-zero-precheck: no compiler at $IDOL"; exit 64; }

work=$(mktemp -d) || exit 64
trap 'rm -rf "$work"' EXIT

# EVERY SUBJECT IS A DIRECT-BACKEND COMPILE, so a host without that realization
# refuses all three at TARGET SELECTION and the graph never sees the module
# question this gate is about. It used to notice that per subject, which reported
# the one host fact three times. Established once, said once.
. "$ROOT/gate/realization/direct.sh"
direct_native_probe "$IDOL"
if direct_native_absent; then
  direct_native_note 'where the unresolvable-home refusal comes from (target selection refuses before the graph sees the module)'
  exit 1
fi

examined=0
bad=0

# Each subject binds a home that resolves to no file, in one of the three
# spellings the deleted arms recognised. All three must refuse; none may refuse
# with a module-shaped precheck reason.
write_subject() {
  name=$1
  binding=$2
  {
    printf '%s\n\n' "$binding"
    printf 'main: i64 = ()\n  0\n'
  } > "$work/$name.id"
}

write_subject assign  'grammar = req("std.compiler.token")'
write_subject global  'global grammar = req("std.compiler.token")'
write_subject pack    'grammar, n = req("std.compiler.token"), 1'

for f in "$work"/*.id; do
  examined=$((examined + 1))
  out=$("$IDOL" compile --backend=direct -o "$work/out.bin" "$f" 2>&1 </dev/null)
  code=$?
  rm -f "$work/out.bin"
  if [ "$code" = 0 ]; then
    echo "module-zero-precheck: FAIL $(basename "$f") — an unresolvable home compiled (exit 0)"
    bad=$((bad + 1))
    continue
  fi
  case $out in
    *"bail site: native-scalar precheck"*)
      echo "module-zero-precheck: FAIL $(basename "$f") — the pre-graph gate answered a module question:"
      printf '%s\n' "$out" | sed -n 's/^.*bail site: /    bail site: /p'
      bad=$((bad + 1))
      continue
      ;;
  esac
  # A host limit cannot reach here: the producer above refuses the whole gate,
  # so a DNB004 arriving per subject would mean the control disagreed with the
  # subjects, which is a defect and must not be filed under the host.
  case $out in
    *DNB004*)
      echo "module-zero-precheck: FAIL $(basename "$f") — DNB004 on a subject after the host control said this host CAN realize direct native code; the control and the subjects disagree"
      bad=$((bad + 1))
      continue
      ;;
  esac
  case $out in
    *"producer: graph"*) : ;;
    *)
      echo "module-zero-precheck: FAIL $(basename "$f") — refusal did not come from the graph:"
      printf '%s\n' "$out" | sed -n 's/^.*error: direct backend: /    /p'
      bad=$((bad + 1))
      continue
      ;;
  esac
done

# GAP-201 permanent negative control: a gate examining zero subjects FAILS.
if [ "$examined" -eq 0 ]; then
  echo "module-zero-precheck: FAIL — examined 0 subjects"
  exit 1
fi

if [ "$bad" -ne 0 ]; then
  # Not "answered by the pre-graph gate" — that names one of the three causes
  # above and asserted it for all of them, including the host limit that
  # answers nothing.
  echo "module-zero-precheck: $bad of $examined subject(s) did NOT have their refusal produced by the graph; each line above says which cause"
  exit 1
fi
echo "module-zero-precheck: $examined subject(s) — every refusal produced by the graph"
exit 0
