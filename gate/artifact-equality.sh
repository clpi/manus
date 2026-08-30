#!/bin/sh
# Cross-host artifact equality contract. Rows compare only one exact artifact key:
# compiler revision, toolchain revision, target, source, and configuration.
# Different targets are never expected to produce identical bytes.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

fail() { printf 'artifact-equality gate: FAIL — %s\n' "$*" >&2; exit 1; }
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
    expected_source=$2
    [ -s "$manifest" ] || { printf 'artifact-equality gate: FAIL — evidence manifest is absent or empty\n' >&2; return 2; }
    awk -F '\t' -v expected_source="$expected_source" '
        function bad(message) { print "artifact-equality gate: FAIL — " message > "/dev/stderr"; failed=1 }
        NR == 1 {
            if ($0 != "idol.artifact.equality.v1") bad("schema must be idol.artifact.equality.v1")
            next
        }
        {
            if (NF != 10) { bad("row " NR " has " NF " fields, expected 10"); next }
            host=$1; os=$2; arch=$3; revision=$4; compiler=$5; toolchain=$6
            target=$7; source=$8; config=$9; artifact=$10
            if (!(host == "x86-64" || host == "m-series" || host == "pi-5")) bad("unknown required host class " host)
            if (seen[host]++) bad("duplicate host class " host)
            if (host == "x86-64" && arch != "x86_64") bad("x86-64 row has wrong arch")
            if (host == "m-series" && !(os == "macos" && arch == "aarch64")) bad("m-series row must be macos aarch64")
            if (host == "pi-5" && !(os == "linux" && arch == "aarch64")) bad("pi-5 row must be linux aarch64")
            if (length(compiler) != 64 || compiler !~ /^[0-9a-f]+$/) bad(host " compiler sha256 is malformed")
            if (length(source) != 64 || source !~ /^[0-9a-f]+$/) bad(host " source sha256 is malformed")
            if (source != expected_source) bad(host " row does not name the tracked conformance source")
            if (length(config) != 64 || config !~ /^[0-9a-f]+$/) bad(host " configuration sha256 is malformed")
            if (length(artifact) != 64 || artifact !~ /^[0-9a-f]+$/) bad(host " artifact sha256 is malformed")
            if (base_revision == "") {
                base_revision=revision; base_toolchain=toolchain; base_target=target
                base_source=source; base_config=config; base_artifact=artifact
            }
            if (revision != base_revision || toolchain != base_toolchain || target != base_target || source != base_source || config != base_config)
                bad(host " row changed the artifact identity key")
            if (artifact != base_artifact) bad(host " artifact bytes differ for the same identity key")
            hosts[host]=1
            rows++
        }
        END {
            split("x86-64 m-series pi-5", required, " ")
            for (i in required) if (!hosts[required[i]]) bad("missing " required[i] " evidence")
            if (rows != 3) bad("expected exactly 3 evidence rows, got " rows)
            if (failed) exit 1
            print "artifact-equality gate: PASS — x86-64, M-series, and Pi 5 produced one byte-identical artifact for one exact key"
        }
    ' "$manifest"
}

selftest() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/idol-artifact-equality.XXXXXX") || exit 2
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    z=0000000000000000000000000000000000000000000000000000000000000000
    o=1111111111111111111111111111111111111111111111111111111111111111
    t=2222222222222222222222222222222222222222222222222222222222222222
    {
        printf '%s\n' idol.artifact.equality.v1
        printf 'x86-64\tlinux\tx86_64\trev\t%s\tzig-rev\tc-source\t%s\t%s\t%s\n' "$z" "$z" "$z" "$o"
        printf 'm-series\tmacos\taarch64\trev\t%s\tzig-rev\tc-source\t%s\t%s\t%s\n' "$t" "$z" "$z" "$o"
        printf 'pi-5\tlinux\taarch64\trev\t%s\tzig-rev\tc-source\t%s\t%s\t%s\n' "$o" "$z" "$z" "$o"
    } > "$work/good.tsv"
    check "$work/good.tsv" "$z" >/dev/null

    awk -F '\t' 'BEGIN{OFS="\t"} $1=="pi-5" {$10="3333333333333333333333333333333333333333333333333333333333333333"} {print}' "$work/good.tsv" > "$work/damaged.tsv"
    if check "$work/damaged.tsv" "$z" >"$work/damaged.out" 2>"$work/damaged.err"; then
        fail 'artifact damage control was admitted'
    fi
    grep -q 'pi-5 artifact bytes differ' "$work/damaged.err" || fail 'artifact damage did not reach equality verdict'

    awk -F '\t' '$1!="m-series" {print}' "$work/good.tsv" > "$work/missing.tsv"
    if check "$work/missing.tsv" "$z" >"$work/missing.out" 2>"$work/missing.err"; then
        fail 'missing-host control was admitted'
    fi
    grep -q 'missing m-series evidence' "$work/missing.err" || fail 'missing-host control did not name M-series'

    awk -F '\t' 'BEGIN{OFS="\t"} $1=="x86-64" {$7="native-object"} {print}' "$work/good.tsv" > "$work/key.tsv"
    if check "$work/key.tsv" "$z" >"$work/key.out" 2>"$work/key.err"; then
        fail 'mixed-target control was admitted'
    fi
    grep -q 'artifact identity key' "$work/key.err" || fail 'mixed-target control did not reach key verdict'

    if IDOL_ARTIFACT_FLEET= sh "$0" >"$work/default.out" 2>"$work/default.err"; then
        fail 'no-argument gate execution admitted absent fleet evidence'
    fi
    grep -q 'set IDOL_ARTIFACT_FLEET' "$work/default.err" || fail 'no-argument gate execution did not reach the fleet blocker'
    printf '%s\n' 'artifact-equality control: PASS — equality admitted; damage, missing host, and mixed target refused'
}

mode=--check
[ "$#" -eq 0 ] || mode=$1
case $mode in
    --selftest) selftest ;;
    --check)
        manifest=${2:-${IDOL_ARTIFACT_FLEET:-}}
        subject=${IDOL_ARTIFACT_SOURCE:-"$root/test/native/call.id"}
        [ -n "$manifest" ] || fail 'set IDOL_ARTIFACT_FLEET or pass a manifest path'
        [ -f "$subject" ] || fail "artifact subject is absent: $subject"
        check "$manifest" "$(hash256 "$subject")"
        ;;
    *) printf 'usage: %s --selftest | --check [manifest.tsv]\n' "$0" >&2; exit 2 ;;
esac
