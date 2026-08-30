#!/bin/sh
# Four-OS portability admission for one graph-owned callable application.
# A source "kind" is deliberately absent: relation/application identity stays
# fixed while target/ABI/world facts select a platform call realization. Raw
# syscalls are target-local controls and must refuse outside Linux.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

fail() { printf 'native-call gate: FAIL — %s\n' "$*" >&2; exit 1; }
hash256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d ' ' -f 1
    else
        fail 'no SHA-256 implementation is available'
    fi
}

check() {
    manifest=$1
    expected_subject=$2
    [ -s "$manifest" ] || { printf 'native-call gate: FAIL — evidence manifest is absent or empty\n' >&2; return 2; }
    awk -F '\t' -v expected_subject="$expected_subject" '
        function bad(message) { print "native-call gate: FAIL — " message > "/dev/stderr"; failed=1 }
        NR == 1 {
            if ($0 != "idol.native.call.v1") bad("schema must be idol.native.call.v1")
            next
        }
        {
            if (NF != 10) { bad("row " NR " has " NF " fields, expected 10"); next }
            host=$1; os=$2; arch=$3; revision=$4; compiler=$5; subject=$6
            mode=$7; outcome=$8; observation=$9; diagnostic=$10
            if (host == "" || arch == "") bad("row " NR " omits host or arch")
            if (length(compiler) != 64 || compiler !~ /^[0-9a-f]+$/) bad("row " NR " compiler sha256 is malformed")
            if (length(subject) != 64 || subject !~ /^[0-9a-f]+$/) bad("row " NR " subject sha256 is malformed")
            if (subject != expected_subject) bad("row " NR " does not name the tracked conformance subject")
            if (base_revision == "") { base_revision=revision; base_subject=subject }
            if (revision != base_revision || subject != base_subject) bad("row " NR " changed compiler revision or semantic subject")
            key=os SUBSEP mode
            if (seen[key]++) bad("duplicate " os " " mode " row")
            if (!(os == "linux" || os == "macos" || os == "windows" || os == "freebsd")) bad("unknown OS " os)
            if (mode == "native-call") {
                native[os]=1
                if (outcome != "pass") bad(os " native-call did not pass")
                if (length(observation) != 64 || observation !~ /^[0-9a-f]+$/) bad(os " native-call observation is malformed")
                if (native_observation == "") native_observation=observation
                if (observation != native_observation) bad(os " native-call semantic observation differs")
            } else if (mode == "raw-syscall") {
                raw[os]=1
                if (os == "linux") {
                    if (outcome != "pass") bad("linux raw-syscall positive control did not pass")
                    if (observation != native_observation) bad("linux raw-syscall control changed the semantic observation")
                } else {
                    if (outcome != "refused") bad(os " raw syscall did not refuse")
                    if (diagnostic == "" || diagnostic == "-") bad(os " raw-syscall refusal has no diagnostic")
                }
            } else bad("unknown realization mode " mode)
            rows++
        }
        END {
            split("linux macos windows freebsd", required, " ")
            for (i in required) {
                os=required[i]
                if (!native[os]) bad("missing " os " native-call evidence")
                if (!raw[os]) bad("missing " os " raw-syscall control")
            }
            if (rows != 8) bad("expected exactly 8 evidence rows, got " rows)
            if (failed) exit 1
            print "native-call gate: PASS — four OS platform calls agree; raw syscalls refuse on every non-Linux OS"
        }
    ' "$manifest"
}

selftest() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/idol-native-call.XXXXXX") || exit 2
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    z=0000000000000000000000000000000000000000000000000000000000000000
    o=1111111111111111111111111111111111111111111111111111111111111111
    {
        printf '%s\n' idol.native.call.v1
        printf 'x64\tlinux\tx86_64\trev\t%s\t%s\tnative-call\tpass\t%s\t-\n' "$z" "$z" "$o"
        printf 'mseries\tmacos\taarch64\trev\t%s\t%s\tnative-call\tpass\t%s\t-\n' "$z" "$z" "$o"
        printf 'win\twindows\tx86_64\trev\t%s\t%s\tnative-call\tpass\t%s\t-\n' "$z" "$z" "$o"
        printf 'bsd\tfreebsd\tx86_64\trev\t%s\t%s\tnative-call\tpass\t%s\t-\n' "$z" "$z" "$o"
        printf 'x64\tlinux\tx86_64\trev\t%s\t%s\traw-syscall\tpass\t%s\t-\n' "$z" "$z" "$o"
        printf 'mseries\tmacos\taarch64\trev\t%s\t%s\traw-syscall\trefused\t-\traw-syscall-not-admitted\n' "$z" "$z"
        printf 'win\twindows\tx86_64\trev\t%s\t%s\traw-syscall\trefused\t-\traw-syscall-not-admitted\n' "$z" "$z"
        printf 'bsd\tfreebsd\tx86_64\trev\t%s\t%s\traw-syscall\trefused\t-\traw-syscall-not-admitted\n' "$z" "$z"
    } > "$work/good.tsv"
    check "$work/good.tsv" "$z" >/dev/null

    awk -F '\t' 'BEGIN{OFS="\t"} $2=="windows" && $7=="raw-syscall" {$8="pass"} {print}' "$work/good.tsv" > "$work/damaged.tsv"
    if check "$work/damaged.tsv" "$z" >"$work/damaged.out" 2>"$work/damaged.err"; then
        fail 'damage control admitted a non-Linux raw syscall'
    fi
    grep -q 'windows raw syscall did not refuse' "$work/damaged.err" || fail 'damage control did not reach the raw-syscall verdict'

    awk -F '\t' '$2!="freebsd" {print}' "$work/good.tsv" > "$work/missing.tsv"
    if check "$work/missing.tsv" "$z" >"$work/missing.out" 2>"$work/missing.err"; then
        fail 'missing-host control was admitted'
    fi
    grep -q 'missing freebsd native-call evidence' "$work/missing.err" || fail 'missing-host control did not name the absent OS'
    printf '%s\n' 'native-call control: PASS — valid matrix admitted; raw-syscall damage and missing OS refused'
}

case ${1-} in
    --selftest) selftest ;;
    --check)
        manifest=${2:-${IDOL_NATIVE_CALL_FLEET:-}}
        subject=${IDOL_NATIVE_CALL_SOURCE:-"$root/test/native/call.id"}
        [ -n "$manifest" ] || fail 'set IDOL_NATIVE_CALL_FLEET or pass a manifest path'
        [ -f "$subject" ] || fail "conformance subject is absent: $subject"
        check "$manifest" "$(hash256 "$subject")"
        ;;
    *) printf 'usage: %s --selftest | --check [manifest.tsv]\n' "$0" >&2; exit 2 ;;
esac
