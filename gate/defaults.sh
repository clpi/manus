#!/bin/sh
# Census default operands and descriptor fields across parse, check, direct,
# and execution. Expected refusals are evidence rows, not capability passes.

set -eu

root=${IDOL_DEFAULT_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
mode=${IDOL_BUILD_MODE:-unknown}
case "$mode" in
    ReleaseFast|fast) mode=ReleaseFast ;;
esac
fixtures=$root/examples/default
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-defaults.XXXXXX")

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'defaults gate: FAIL %s\n' "$1" >&2
    exit 1
}

hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

safe() {
    printf '%s' "$1" | tr '/' '-'
}

copycase() {
    cc_name=$1
    cc_source=$2
    cc_target=$work/$(safe "$cc_name").id
    cp "$cc_source" "$cc_target"
    printf '%s' "$cc_target"
}

parsekeep() {
    pk_name=$1
    pk_source=$2
    pk_marker=$3
    pk_parsed=$work/$(safe "$pk_name").parse.id
    pk_log=$work/$(safe "$pk_name").parse.log
    cp "$pk_source" "$pk_parsed"
    grep -Fq "$pk_marker" "$pk_parsed" || fail "$pk_name fixture lacks its default marker"
    "$idol" fmt "$pk_parsed" >"$pk_log" 2>&1 || fail "$pk_name did not parse"
    grep -Fq "$pk_marker" "$pk_parsed" || fail "$pk_name parser round-trip lost its function default"
}

parseloss() {
    pl_name=$1
    pl_source=$2
    pl_marker=$3
    pl_parsed=$work/$(safe "$pl_name").parse.id
    pl_log=$work/$(safe "$pl_name").parse.log
    cp "$pl_source" "$pl_parsed"
    grep -Fq "$pl_marker" "$pl_parsed" || fail "$pl_name fixture lacks its field default marker"
    "$idol" fmt "$pl_parsed" >"$pl_log" 2>&1 || fail "$pl_name legacy field ingress did not parse"
    if grep -Fq "$pl_marker" "$pl_parsed"; then
        fail "$pl_name unexpectedly retained its descriptor-field default"
    fi
}

checkpass() {
    cp_name=$1
    cp_source=$2
    cp_log=$work/$(safe "$cp_name").check.log
    "$idol" check "$cp_source" >"$cp_log" 2>&1 || fail "$cp_name did not pass semantic check"
}

directrefusal() {
    dr_name=$1
    dr_source=$2
    dr_reason=$3
    dr_out=$work/$(safe "$dr_name").out
    dr_log=$work/$(safe "$dr_name").direct.log
    if "$idol" compile --backend=direct "$dr_source" -o "$dr_out" \
        --build-report=compact >"$dr_log" 2>&1; then
        fail "$dr_name unexpectedly direct-compiled"
    else
        dr_rc=$?
    fi
    [ "$dr_rc" -eq 1 ] || fail "$dr_name direct refusal returned $dr_rc"
    [ ! -e "$dr_out" ] || fail "$dr_name refusal left an executable artifact"
    grep -Fq "$dr_reason" "$dr_log" || fail "$dr_name did not reach $dr_reason"
    grep -Fq 'hint: refused with:' "$dr_log" || fail "$dr_name lacked a structured direct refusal"
}

paramrow() {
    pr_name=$1
    pr_marker=$2
    pr_note=$3
    pr_source=$(copycase "$pr_name" "$fixtures/$pr_name.case")
    parsekeep "$pr_name" "$pr_source" "$pr_marker"
    checkpass "$pr_name" "$pr_source"
    directrefusal "$pr_name" "$pr_source" 'native-scalar precheck — param-default'
    rows=$((rows + 1))
    printf 'ROW %s parse=PASS check=PASS direct=REFUSE:param-default run=NOT_REACHED first=direct:param-default note=%s\n' \
        "$pr_name" "$pr_note"
}

fieldrow() {
    fr_name=$1
    fr_marker=$2
    fr_direct=$3
    fr_source=$(copycase "field/$fr_name" "$fixtures/field/$fr_name.case")
    parseloss "field/$fr_name" "$fr_source" "$fr_marker"
    checkpass "field/$fr_name" "$fr_source"
    directrefusal "field/$fr_name" "$fr_source" "$fr_direct"
    rows=$((rows + 1))
    printf 'ROW field/%s parse=ACCEPT_DEFAULT_LOST check=PASS direct=REFUSE:%s run=NOT_REACHED first=parse:default-retention\n' \
        "$fr_name" "$fr_direct"
}

control() {
    ct_source=$(copycase control "$fixtures/control.case")
    parsekeep control "$ct_source" 'add: i64 = (x: i64, y: i64)'
    checkpass control "$ct_source"
    ct_out=$work/control.out
    ct_log=$work/control.direct.log
    "$idol" compile --backend=direct "$ct_source" -o "$ct_out" \
        --build-report=compact >"$ct_log" 2>&1 || fail 'positive control did not direct-compile'
    if "$ct_out" >/dev/null 2>&1; then
        ct_rc=0
    else
        ct_rc=$?
    fi
    [ "$ct_rc" -eq 42 ] || fail "positive control answered $ct_rc instead of 42"
    rows=$((rows + 1))
    printf 'ROW control parse=PASS check=PASS direct=PASS run=PASS:42 first=none\n'
}

surface() {
    sf_name=field/surface
    sf_source=$(copycase "$sf_name" "$fixtures/field/surface.case")
    sf_diagnostic='write `}` at this token edge'
    for sf_stage in parse check direct; do
        sf_log=$work/field-surface.$sf_stage.log
        case "$sf_stage" in
            parse)
                sf_probe=$work/field-surface.parse.id
                cp "$sf_source" "$sf_probe"
                if "$idol" fmt "$sf_probe" >"$sf_log" 2>&1; then sf_rc=0; else sf_rc=$?; fi
                ;;
            check)
                if "$idol" check "$sf_source" >"$sf_log" 2>&1; then sf_rc=0; else sf_rc=$?; fi
                ;;
            direct)
                if "$idol" compile --backend=direct "$sf_source" -o "$work/field-surface.out" \
                    --build-report=compact >"$sf_log" 2>&1; then sf_rc=0; else sf_rc=$?; fi
                ;;
        esac
        [ "$sf_rc" -eq 1 ] || fail "$sf_name $sf_stage returned $sf_rc instead of parse refusal"
        grep -Fq "$sf_diagnostic" "$sf_log" || fail "$sf_name $sf_stage did not preserve its parse refusal"
    done
    [ ! -e "$work/field-surface.out" ] || fail "$sf_name parse refusal left an artifact"
    rows=$((rows + 1))
    printf 'ROW field/surface parse=REFUSE:field-default-syntax check=NOT_REACHED direct=NOT_REACHED run=NOT_REACHED first=parse:field-default-syntax\n'
}

cross() {
    cr_dir=$work/cross
    mkdir -p "$cr_dir"
    cp "$fixtures/cross/provider.case" "$cr_dir/provider.id"
    cp "$fixtures/cross/caller.case" "$cr_dir/caller.id"
    parsekeep cross/provider "$cr_dir/provider.id" 'value: i64 = 4'
    parsekeep cross/caller "$cr_dir/caller.id" 'provider.score()'
    checkpass cross/caller "$cr_dir/caller.id"
    cr_out=$work/cross.out
    cr_log=$work/cross.direct.log
    if "$idol" compile --backend=direct -v "$cr_dir/caller.id" -o "$cr_out" \
        --build-report=compact >"$cr_log" 2>&1; then
        fail 'cross-home default unexpectedly linked'
    else
        cr_rc=$?
    fi
    [ "$cr_rc" -eq 1 ] || fail "cross-home direct refusal returned $cr_rc"
    [ ! -e "$cr_out" ] || fail 'cross-home refusal left an executable artifact'
    grep -Fq '_provider__score' "$cr_log" || fail 'cross-home refusal did not name the missing provider relation'
    grep -Fq 'error: native linker failed' "$cr_log" || fail 'cross-home refusal was not attributed to the linker boundary'
    rows=$((rows + 1))
    printf 'ROW cross parse=PASS check=PASS direct=INFRA_REFUSE:cross-home-object run=NOT_REACHED first=direct:cross-home-object semantic=UNKNOWN\n'
}

controls() {
    cs_broken=$work/control-broken.id
    sed 's/add(19, 23)/add(19, 23/' "$fixtures/control.case" >"$cs_broken"
    for cs_stage in parse check direct; do
        cs_log=$work/control-broken.$cs_stage.log
        case "$cs_stage" in
            parse)
                cs_probe=$work/control-broken.parse.id
                cp "$cs_broken" "$cs_probe"
                if "$idol" fmt "$cs_probe" >"$cs_log" 2>&1; then cs_rc=0; else cs_rc=$?; fi
                ;;
            check)
                if "$idol" check "$cs_broken" >"$cs_log" 2>&1; then cs_rc=0; else cs_rc=$?; fi
                ;;
            direct)
                if "$idol" compile --backend=direct "$cs_broken" -o "$work/control-broken.out" \
                    --build-report=compact >"$cs_log" 2>&1; then cs_rc=0; else cs_rc=$?; fi
                ;;
        esac
        [ "$cs_rc" -eq 1 ] || fail "syntax damage did not make $cs_stage red"
        grep -Fq 'error:' "$cs_log" || fail "syntax damage lacked a $cs_stage diagnostic"
    done

    cs_changed=$work/control-changed.id
    sed 's/add(19, 23)/add(19, 22)/' "$fixtures/control.case" >"$cs_changed"
    checkpass control/changed "$cs_changed"
    cs_out=$work/control-changed.out
    cs_log=$work/control-changed.direct.log
    "$idol" compile --backend=direct "$cs_changed" -o "$cs_out" \
        --build-report=compact >"$cs_log" 2>&1 || fail 'answer damage did not compile'
    if "$cs_out" >/dev/null 2>&1; then cs_rc=0; else cs_rc=$?; fi
    [ "$cs_rc" -eq 41 ] || fail "answer damage did not land: got $cs_rc"
    if [ "$cs_rc" -eq 42 ]; then
        fail 'answer comparator accepted the damaged result'
    fi
    printf 'CONTROL syntax=RED answer-damage=RED\n'
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
[ "$mode" = ReleaseFast ] || fail "requires a source-built ReleaseFast compiler, got $mode"
[ -d "$fixtures" ] || fail "missing fixture directory: $fixtures"

rows=0
control

paramrow constant 'y: i64 = 1' constant
paramrow subject 'count: i64 = text:len()' subject-dependent-check-accepted
paramrow earlier 'offset: i64 = base + 1' earlier-role-check-accepted
paramrow later 'count: i64 = limit + base' later-role-check-accepted
paramrow undemanded 'right: i64 = spin()' omitted-undemanded-still-refused
paramrow effect 'value: f64 = clock()' effectful-check-accepted
paramrow world 'text: str = arg(1)' world-dependent-check-accepted
paramrow cycle 'left: i64 = right' dependency-cycle-check-accepted
paramrow omitted 'value: i64 = 5' omitted
paramrow explicit 'value: i64 = 5' explicit-nil-not-distinguished-before-direct
paramrow structured 'value: i64 = 4' structured-result
paramrow multiple 'value: i64 = 4' multiple-result

fieldrow scalar 'x: i64 = 3' unresolved-application-facts
fieldrow string 'text: str = "ready"' method-unresolved:len
fieldrow pointer 'address: *u8 = nil' unresolved-application-facts
fieldrow fresh 'state: { value: i64 } = { value = 0 }' unresolved-application-facts
fieldrow dependent 'right: i64 = left + 4' unresolved-application-facts
fieldrow spread 'x: i64 = 1' assign-value:call
surface
cross
controls

expected=21
[ "$rows" -gt 0 ] || fail 'subject census examined zero rows'
[ "$rows" -eq "$expected" ] || fail "subject census examined $rows rows instead of $expected"

dirty=clean
git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet || dirty=dirty
printf 'SUBJECT revision=%s dirty=%s compiler_sha256=%s gate_sha256=%s build_mode=%s backend=direct host=%s-%s rows=%s\n' \
    "$(git -C "$root" rev-parse HEAD)" "$dirty" "$(hash "$idol")" "$(hash "$0")" \
    "$mode" "$(uname -s)" "$(uname -m)" "$rows"
printf 'defaults gate: PASS\n'
