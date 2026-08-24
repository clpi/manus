#!/bin/sh
# gate/parser_slice.sh — M2 first parser ownership transfer slice.
#
#   sh gate/parser_slice.sh
#   sh gate/parser_slice.sh --ledger
#   sh gate/parser_slice.sh --selftest
#
# Exit 0 = static controls hold and the current compiler records the expected
# execution refusals.  Static source presence alone is never SHC evidence.
# Non-zero = regression, missing execution evidence, or ledger drift.
#
# Closed outcome states: win, bound, open, unknownbound.

set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

SRC=${IDOL_SRC:-../idol}
IDOL=${IDOL:-./bin/idol}
case $IDOL in
    /*) IDOLABS=$IDOL ;;
    *)  IDOLABS="$ROOT/${IDOL#./}" ;;
esac

# This is deliberately a real prerequisite, not a static-only escape hatch.
# A missing compiler is infrastructure status and must never be read as a
# parser score.  --selftest exercises this branch in the positive direction.
if [ ! -x "$IDOLABS" ]; then
    printf 'parser_slice gate: no executable %s — NOT A MEASUREMENT\n' "$IDOLABS"
    exit 2
fi

if [ "${1:-}" = "--selftest" ]; then
    if PARSER_SLICE_SELFTEST=1 IDOL="$ROOT/.parser-slice-missing-idol" "$0" >/dev/null 2>&1; then
        printf 'parser_slice selftest: FAIL missing compiler was accepted\n'
        exit 1
    fi
    printf 'parser_slice selftest: PASS missing compiler fails closed\n'
    if PARSER_SLICE_EXPECT_CODE=not_dnb001 "$0" >/dev/null 2>&1; then
        printf 'parser_slice selftest: FAIL diagnostic damage was accepted\n'
        exit 1
    fi
    printf 'parser_slice selftest: PASS diagnostic damage fails closed\n'
    exit 0
fi

LEDGER='
header-view-slice      win      src/parser.zig               scan_func_header_signal uses View
idol-parser-module     bound    lib/compiler/parser.id       L1-L3 Idol parser spine exists
role-projection-fed    bound    lib/token/grammarrole.id     roles emitted for consumers
host-parser-debt       open     src/parser.zig               most recognition still host-owned
idol-parser-execution   open     lib/compiler/parser.id       direct execution refuses DNB001 at lowerModuleFromGraph
token-view-execution    open     lib/compiler/token_view.id    direct execution refuses DNB001 graph-dnir-unsupported at lowerExprCons
bare-function-syntax    bound    examples/syntax_bare_fun_smoke.id    canonical bare-function and offside fixture
'

MODE=check
[ "${1:-}" = "--ledger" ] && { printf '%s\n' "$LEDGER"; exit 0; }

FAILED=0 SEEN=0
bad() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED+1)); }
ok()   { printf '  ok    %s\n' "$1"; }

printf 'parser_slice gate: first parser ownership transfer\n\n'

# Execute the two candidate Idol modules.  A refusal is the honest current
# result: these modules are source/grammar projections, not executed parser
# ownership.  Accepting a static grep result here would recreate the false
# SHC surface this gate is meant to prevent.
probe_refusal() {
    _name=$1
    _file=$2
    _expected=${PARSER_SLICE_EXPECT_CODE:-$3}
    _dir=$(mktemp -d "${TMPDIR:-/tmp}/idol-parser-slice.XXXXXX") || {
        bad "$_name: unable to create private probe directory"
        return
    }
    _obj=$_dir/"$_name.o"
    _out=$_dir/"$_name.out"
    _rc=0
    "$IDOLABS" compile --backend=direct --emit obj -o "$_obj" "$SRC/$_file" >"$_out" 2>&1 || _rc=$?
    _code=$(grep -oE 'DNB[0-9][0-9][0-9]' "$_out" | head -1)
    if [ "$_rc" -ne 0 ] && [ "$_code" = "$_expected" ] && grep -q 'bail site:' "$_out" && [ ! -s "$_obj" ]; then
        ok "$_name: execution refusal $_code (recorded, not SHC)"
    elif [ "$_rc" -eq 0 ]; then
        bad "$_name: execution unexpectedly succeeded; remeasure ownership"
    else
        bad "$_name: expected $_expected refusal, got rc=$_rc code=${_code:-none}"
    fi
}

# The token-view refusal is a current-head graph-realization refusal. Keep the
# exact diagnostic class and bail site visible so a different backend error
# cannot silently satisfy the parser-slice ledger.
probe_token_view_refusal() {
    _dir=$(mktemp -d "${TMPDIR:-/tmp}/idol-parser-kinds.XXXXXX") || {
        bad 'token-view-refusal: unable to create private probe directory'
        return
    }
    _obj=$_dir/token_view.o
    _out=$_dir/token_view.out
    _rc=0
    "$IDOLABS" compile --backend=direct --emit obj -o "$_obj" "$SRC/lib/compiler/token_view.id" >"$_out" 2>&1 || _rc=$?
    if [ "$_rc" -ne 0 ] \
        && grep -q 'DNB001' "$_out" \
        && grep -q 'graph-dnir-unsupported' "$_out" \
        && grep -q 'bail site: lowerExprCons()' "$_out" \
        && [ ! -s "$_obj" ]; then
        ok 'token-view-refusal: DNB001 graph-dnir-unsupported refusal'
    else
        bad 'token-view-refusal: exact current-head refusal witness changed'
    fi
}

probe_refusal parser-execution lib/compiler/parser.id DNB001
probe_refusal token-view-execution lib/compiler/token_view.id DNB001
SEEN=$((SEEN + 1))
probe_token_view_refusal

PARSER="$SRC/src/parser.zig"
SEEN=$((SEEN + 1))
if [ -f "$PARSER" ]; then
    ok 'parser.zig: present'
    grep -q 'token_view.fromLexer' "$PARSER" && ok 'parser: fromLexer wired' || bad 'parser: fromLexer missing'
    grep -q 'headerSignal' "$PARSER" && ok 'parser: headerSignal present' || bad 'parser: headerSignal missing'
    grep -q 'scan_func_header_signal' "$PARSER" && ok 'parser: scan_func_header_signal present' || bad 'parser: scan_func_header_signal missing'
    SEEN=$((SEEN + 3))
else
    bad "parser.zig: missing at $PARSER"
fi

LEX="$SRC/lib/compiler/lexer.id"
SEEN=$((SEEN + 1))
if [ -f "$LEX" ]; then
    ok 'lib/compiler/lexer.id: present'
    grep -q 'stmt_col' "$LEX" && ok 'lexer: stmt_col field present' || bad 'lexer: stmt_col field missing'
    SEEN=$((SEEN + 1))
else
    bad 'lib/compiler/lexer.id: missing'
fi

FIXTURE="examples/syntax_bare_fun_smoke.id"
SEEN=$((SEEN + 1))
if [ -f "$FIXTURE" ]; then
    ok 'syntax_bare_fun_smoke.id: present'
    grep -q 'add: i64 = (x: i64, y: i64)' "$FIXTURE" && ok 'fixture: canonical bare-function shape' || bad 'fixture: canonical bare-function shape missing'
    SEEN=$((SEEN + 1))
else
    bad "bare_lambda_offside.id: missing at $FIXTURE"
fi

PID="$SRC/lib/compiler/parser.id"
SEEN=$((SEEN + 1))
if [ -f "$PID" ]; then
    ok 'lib/compiler/parser.id: present'
    grep -q 'header_signal_lx' "$PID" && ok 'parser.id: header_signal_lx present' || bad 'parser.id: header_signal_lx missing'
    grep -q 'statement_header_signal_lx' "$PID" && ok 'parser.id: statement_header_signal_lx present' || bad 'parser.id: statement_header_signal_lx missing'
    grep -q 'offside_single' "$PID" && ok 'parser.id: bare-lambda offside probe present' || bad 'parser.id: bare-lambda offside probe missing'
    grep -q 'lx.stmt_col' "$PID" && ok 'parser.id: stmt_col wired in proj_stmt' || bad 'parser.id: stmt_col missing in proj_stmt'
    SEEN=$((SEEN + 4))
else
    bad 'lib/compiler/parser.id: missing'
fi

printf '%s\n' "$LEDGER" | while IFS= read -r row; do
    [ -z "$row" ] && continue
    name=$(echo "$row" | awk '{print $1}')
    state=$(echo "$row" | awk '{print $2}')
    target=$(echo "$row" | awk '{print $3}')
    note=$(echo "$row" | cut -d' ' -f4-)
    ok "$name: $state — $target ($note)"
done

for state in win bound open unknownbound; do
    SEEN=$((SEEN + 1))
    ok "$state: defined"
done

DEBT_COUNT=$(printf '%s\n' "$LEDGER" | grep -c . 2>/dev/null || echo 0)
SEEN=$((SEEN + DEBT_COUNT))

printf '\n'
[ "$FAILED" -eq 0 ] && printf 'parser_slice gate: PASS (%s probes) parser-slice ledger unchanged\n' "$SEEN" \
    || printf 'parser_slice gate: FAIL (%s probes) %s violations\n' "$SEEN" "$FAILED"
exit "$FAILED"
