#!/bin/sh

set -eu

root=${OUTCOME_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'outcome gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-outcome.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'outcome gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'outcome gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasm runner on PATH; this host cannot observe an execution outcome at all"

answers() {
    [ "$1" = "$2" ]
}

outcomeOf() {
    _status=0
    ( cd "$work" && "$idol" run --backend=wasm --target=wasm32-wasi "$root/$1" >run.out 2>run.err ) || _status=$?
    printf '%s\n' "$_status"
}


answers 7 7 || fail "arm 0: answers rejected an agreeing pair"
if answers 7 0; then
    fail "arm 0: answers accepted 7 as 0 — the comparison is dead"
fi


for pair in examples/outcome/zero.id:0 examples/outcome/seven.id:7 \
            examples/outcome/hold.id:0 examples/outcome/miss.id:7; do
    src=${pair%:*}
    want=${pair##*:}
    [ -f "$src" ] || fail "arm 1: $src is missing"
    got=$(outcomeOf "$src")
    answers "$got" "$want" ||
        fail "arm 1: idol run $src reported $got, the program's outcome is $want"
done

printf 'outcome gate: arm 1 four paired controls discriminated 0 from 7\n'


"$idol" compile --backend=wasm --target=wasm32-wasi "$root/examples/outcome/miss.id" -o "$work/miss.artifact" \
    >"$work/compile.log" 2>&1 ||
    fail "arm 2: examples/outcome/miss.id did not compile: $(head -3 "$work/compile.log" | tr '\n' ' ')"
[ -s "$work/miss.artifact" ] || fail "arm 2: compile reported success without leaving an artifact"
got=$(outcomeOf examples/outcome/miss.id)
answers "$got" 7 ||
    fail "arm 2: the source that compiles clean ran to $got, not its own outcome 7"

printf 'outcome gate: arm 2 compile 0, artifact present, run 7 — three distinct facts\n'


if ( cd "$work" && WASMTIME_BIN="$work/absent-runner" "$idol" run --backend=wasm --target=wasm32-wasi \
        "$root/examples/outcome/zero.id" >closed.out 2>closed.err ); then
    fail "arm 3: idol run returned 0 with no runner to execute the artifact"
fi
grep -q RUN101 "$work/closed.err" ||
    fail "arm 3: refusal did not name RUN101: $(head -2 "$work/closed.err" | tr '\n' ' ')"

printf 'outcome gate: arm 3 unobservable outcome refused as RUN101\n'
printf 'outcome gate: PASS\n'
