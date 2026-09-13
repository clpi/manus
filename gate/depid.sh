#!/bin/sh
# gate/depid.sh — dependency identity for generated projections.
#
# A generated artifact's dependencies are: its generator meaning, the
# executing emitter, its inputs, configuration, target, and the artifact
# bytes themselves. This tool computes that identity from the producing
# computation (never from a filename) and records it in
# gate/generated.depid; gate/layering.sh L2b verifies the recorded
# identity instead of demanding the generator appear in the diff.
#
# The sanctioned resync path is `gate/depid.sh stamp <projection>`: it
# runs the producing computation declared in gate/generated.manifest,
# refuses when the producer is nondeterministic across two runs (a
# world observation leaking into the artifact), and only then records
# the identity. A hand edit, a stale emitter, or a forged row fails the
# L2b check, and the failure names the diverged component.
#
# `stamp --bootstrap` records the current bytes without running the
# producer, for producers unrunnable on this host. It is an explicit
# operator attestation, not a verification; the basis belongs in the
# commit message, and the next real regen restamps with verification.
#
# Subcommands:
#   stamp [--bootstrap] <generated>...   regenerate + verify + record
#   check <generated>...                 recompute from the tree, compare
#   show <generated>                      print recorded vs recomputed rows
#
# Environment:
#   IDOL_ROOT      tree under test (default: this script's repo)
#   IDOL_BIN       executing idol binary (default: $IDOL_ROOT/zig-out/bin/idol)
#   DEPID_MODE     staged | worktree | scratch (default: worktree)
#   DEPID_SCRATCH  scratch tree root (DEPID_MODE=scratch)
#
# Tree content is identified by git blob hash in every mode, so a row
# stamped from the worktree verifies against the index and vice versa.
# stamp is always a worktree operation.
#
# gate/generated.depid row (tab-separated, no header):
#   generated  depid  gen  emit  inputstree  inputsextra  config  target  out
# gate/generated.manifest row:
#   generated  generator  marker  emit  regen  inputs  config  target
# where emit is `idolbin` or `tool:<name>`, regen is `redir:<sh>` or
# `run:<sh>` ($idolbin and $root expand), and inputs is a
# space-separated list of tree paths, `a/**/*.b` globs, `self:prev`
# (the artifact's pre-regen bytes, carried), `tool:<name>` (a versioned
# toolchain, carried), or `-`.

set -eu

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=${IDOL_ROOT:-$(cd "$here/.." && pwd)}
idolbin=${IDOL_BIN:-$root/zig-out/bin/idol}
mode=${DEPID_MODE:-worktree}
scratchdir=${DEPID_SCRATCH:-}

die() { printf '%s: FAIL -- %s\n' "$prog" "$*" >&2; exit 1; }
note() { printf '%s: %s\n' "$prog" "$*" >&2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-depid.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

blobbase=$root
if [ "$mode" = scratch ]; then
    [ -n "$scratchdir" ] || die "DEPID_MODE=scratch needs DEPID_SCRATCH"
    blobbase=$scratchdir
fi
case "$mode" in
    staged|worktree|scratch) ;;
    *) die "unknown DEPID_MODE '$mode'" ;;
esac

# treefile <rel> : bytes of a tracked file in the tree under test.
treefile() {
    case "$mode" in
        staged) git -C "$root" show ":$1" 2>/dev/null ;;
        scratch) cat "$scratchdir/$1" 2>/dev/null ;;
        *) cat "$root/$1" 2>/dev/null ;;
    esac
}

treefile gate/generated.manifest >"$tmp/manifest.txt" \
    || die "gate/generated.manifest is missing from the tree under test ($mode)"
treefile gate/generated.depid >"$tmp/sidecar.txt" 2>/dev/null || : >"$tmp/sidecar.txt"

manrow() { # <generated> : the 8-col manifest row or fails
    LC_ALL=C awk -F'\t' -v k="$1" '
        /^[[:space:]]*(#|$)/ { next }
        NF < 8 { bad = 1; next }
        $1 == k { print; found = 1 }
        END { if (bad) exit 3; exit found ? 0 : 1 }' "$tmp/manifest.txt"
}

scarow() { # <generated> : the 9-col sidecar row or fails
    LC_ALL=C awk -F'\t' -v k="$1" '
        /^[[:space:]]*$/ { next }
        NF < 9 { bad = 1; next }
        $1 == k { print; found = 1 }
        END { if (bad) exit 3; exit found ? 0 : 1 }' "$tmp/sidecar.txt"
}

bhash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{ print $1 }'
    else
        shasum -a 256 | awk '{ print $1 }'
    fi
}

# content_id <rel> : git blob hash of a tree path in the tree under test.
content_id() {
    case "$mode" in
        staged)
            git -C "$root" ls-files -s -- "$1" 2>/dev/null | awk '{ print $2; exit }'
            ;;
        *)
            git hash-object "$blobbase/$1" 2>/dev/null
            ;;
    esac
}

# expand_tree_inputs <cell> : relative paths, one per line, sorted -u later.
expand_tree_inputs() {
    cell=$1
    [ "$cell" = "-" ] && return 0
    for tok in $cell; do
        case "$tok" in
            self:*|tool:*) continue ;;
            *'*'*)
                case "$mode" in
                    staged)
                        git -C "$root" ls-files -- "$tok" 2>/dev/null
                        ;;
                    *)
                        pre=${tok%%\**}
                        dir=${pre%/*}
                        [ "$dir" = "$pre" ] && dir=.
                        pat=${tok##*/}
                        case "$tok" in
                            *'**'*)
                                (cd "$blobbase" && find "$dir" -name "$pat" -type f 2>/dev/null)
                                ;;
                            *)
                                (cd "$blobbase" && find "$dir" -maxdepth 1 -name "$pat" -type f 2>/dev/null)
                                ;;
                        esac | sed 's|^\./||'
                        ;;
                esac
                ;;
            *)
                printf '%s\n' "$tok"
                ;;
        esac
    done
}

# inputs_tree_hash <cell> : hash over sorted path=blobhash lines, or '-'.
inputs_tree_hash() {
    cell=$1
    if [ "$cell" = "-" ]; then printf '-'; return 0; fi
    expand_tree_inputs "$cell" | LC_ALL=C sort -u >"$tmp/inputs.txt"
    [ -s "$tmp/inputs.txt" ] || die "inputs '$cell' matched nothing in the tree under test ($mode)"
    : >"$tmp/ihash.txt"
    while IFS= read -r p; do
        h=$(content_id "$p")
        [ -n "$h" ] || die "input $p has no bytes in the tree under test ($mode)"
        printf '%s=%s\n' "$p" "$h" >>"$tmp/ihash.txt"
    done <"$tmp/inputs.txt"
    bhash <"$tmp/ihash.txt"
}

tool_version() { # <name> : version string or fails
    case "$1" in
        zig) zig version 2>/dev/null ;;
        tree-sitter) tree-sitter --version 2>/dev/null ;;
        *) return 1 ;;
    esac
}

# extra_cell <inputs-cell> <prevhash> <mode:stamp|check>
# carried k=v pairs, comma-joined and sorted, or '-'.
extra_cell() {
    cell=$1; prev=$2; cmode=$3
    [ "$cell" = "-" ] && { printf '-'; return 0; }
    : >"$tmp/extra.txt"
    for tok in $cell; do
        case "$tok" in
            self:prev)
                if [ "$cmode" = stamp ]; then
                    [ -n "$prev" ] || die "no pre-regen bytes for a self:prev input -- restamp"
                    printf 'prev=%s\n' "$prev" >>"$tmp/extra.txt"
                else
                    v=$(printf '%s' "$carried_extra" | tr ',' '\n' | awk -F= '$1=="prev" { print $2; exit }')
                    [ -n "$v" ] || die "no carried prev bytes recorded -- restamp"
                    printf 'prev=%s\n' "$v" >>"$tmp/extra.txt"
                fi
                ;;
            tool:*)
                name=${tok#tool:}
                if [ "$cmode" = stamp ]; then
                    if [ "$bootstrap" = yes ]; then
                        printf 'tool:%s=unknown\n' "$name" >>"$tmp/extra.txt"
                    else
                        v=$(tool_version "$name" 2>/dev/null || true)
                        [ -n "$v" ] || die "cannot version toolchain '$name' -- install it or stamp --bootstrap"
                        printf 'tool:%s=%s\n' "$name" "$v" >>"$tmp/extra.txt"
                    fi
                else
                    v=$(printf '%s' "$carried_extra" | tr ',' '\n' | awk -F= -v k="tool:$name" '$1==k { print $2; exit }')
                    [ -n "$v" ] || die "no carried version recorded for $tok -- restamp"
                    printf 'tool:%s=%s\n' "$name" "$v" >>"$tmp/extra.txt"
                fi
                ;;
        esac
    done
    if [ -s "$tmp/extra.txt" ]; then
        LC_ALL=C sort -u "$tmp/extra.txt" | paste -sd, -
    else
        printf '-'
    fi
}

# emit_cell <spec> <mode:stamp|check> : the recorded emit value.
emit_cell() {
    spec=$1; cmode=$2
    case "$spec" in
        idolbin)
            [ -f "$idolbin" ] || die "emitter binary is missing: $idolbin -- build it (zig build) or set IDOL_BIN"
            eh=$(bhash <"$idolbin") || die "cannot hash $idolbin"
            printf 'idolbin:%s' "$eh"
            ;;
        tool:*)
            name=${spec#tool:}
            if [ "$cmode" = stamp ]; then
                if [ "$bootstrap" = yes ]; then
                    printf 'tool:%s:unknown' "$name"; return 0
                fi
                v=$(tool_version "$name" 2>/dev/null || true)
                [ -n "$v" ] || die "cannot version toolchain '$name' -- install it or stamp --bootstrap"
                printf 'tool:%s:%s' "$name" "$v"
            else
                case "$carried_emit" in
                    "tool:$name:"*) printf '%s' "$carried_emit" ;;
                    *) die "recorded emitter '$carried_emit' mismatches producer spec '$spec' -- restamp" ;;
                esac
            fi
            ;;
        *) die "unknown emitter spec '$spec'" ;;
    esac
}

# row_core <generated> <cmode> : the 9-col row. In check mode the carried
# cells come from the recorded sidecar row (globals carried_emit/_extra).
row_core() {
    g=$1; cmode=$2
    mrow=$(manrow "$g") || die "$g is not a declared projection in gate/generated.manifest"
    gen_path=$(printf '%s' "$mrow" | awk -F'\t' '{ print $2 }')
    emit_spec=$(printf '%s' "$mrow" | awk -F'\t' '{ print $4 }')
    inputs_cell=$(printf '%s' "$mrow" | awk -F'\t' '{ print $6 }')
    cfg=$(printf '%s' "$mrow" | awk -F'\t' '{ print $7 }')
    target=$(printf '%s' "$mrow" | awk -F'\t' '{ print $8 }')

    gen=$(content_id "$gen_path")
    [ -n "$gen" ] || die "generator $gen_path has no bytes in the tree under test ($mode)"
    emit=$(emit_cell "$emit_spec" "$cmode")
    itree=$(inputs_tree_hash "$inputs_cell")
    iextra=$(extra_cell "$inputs_cell" "$prevhash" "$cmode")
    out=$(content_id "$g")
    [ -n "$out" ] || die "projection $g has no bytes in the tree under test ($mode)"

    depid=$(printf 'idol-depid-v1\ngen=%s\nemit=%s\ninputstree=%s\ninputsextra=%s\nconfig=%s\ntarget=%s\nout=%s\n' \
        "$gen" "$emit" "$itree" "$iextra" "$cfg" "$target" "$out" | bhash)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$g" "$depid" "$gen" "$emit" "$itree" "$iextra" "$cfg" "$target" "$out"
}

report_diff() { # <recorded row> <recomputed row>
    i=3
    for n in gen emit inputstree inputsextra config target out; do
        a=$(printf '%s' "$1" | awk -F'\t' -v i="$i" '{ print $i }')
        b=$(printf '%s' "$2" | awk -F'\t' -v i="$i" '{ print $i }')
        if [ "$a" != "$b" ]; then
            printf '    %s diverged:\n      recorded  %s\n      computed  %s\n' "$n" "$a" "$b" >&2
        fi
        i=$((i + 1))
    done
    printf '    lawful resync: gate/depid.sh stamp %s (then stage it with gate/generated.depid)\n' \
        "$(printf '%s' "$1" | awk -F'\t' '{ print $1 }')" >&2
}

cmd_check() {
    [ $# -gt 0 ] || die "check needs at least one generated path"
    rc=0
    for g in "$@"; do
        srow=$(scarow "$g") || {
            note "$g: no dependency identity recorded -- resync via gate/depid.sh stamp $g"
            rc=1; continue
        }
        carried_emit=$(printf '%s' "$srow" | awk -F'\t' '{ print $4 }')
        carried_extra=$(printf '%s' "$srow" | awk -F'\t' '{ print $6 }')
        want=$(printf '%s' "$srow" | awk -F'\t' '{ print $2 }')
        prevhash=
        if ! got=$(row_core "$g" check); then rc=1; continue; fi
        have=$(printf '%s' "$got" | awk -F'\t' '{ print $2 }')
        if [ "$have" = "$want" ]; then
            note "$g: dependency identity matches"
        else
            note "$g: DEPENDENCY IDENTITY MISMATCH"
            report_diff "$srow" "$got"
            rc=1
        fi
    done
    return "$rc"
}

cmd_show() {
    [ $# -gt 0 ] || die "show needs at least one generated path"
    for g in "$@"; do
        srow=$(scarow "$g") || die "$g: no dependency identity recorded"
        carried_emit=$(printf '%s' "$srow" | awk -F'\t' '{ print $4 }')
        carried_extra=$(printf '%s' "$srow" | awk -F'\t' '{ print $6 }')
        prevhash=
        got=$(row_core "$g" check) || die "$g: recompute failed"
        printf 'recorded:  %s\n' "$srow"
        printf 'computed:  %s\n' "$got"
    done
}

# run_producer <kind> <frag> <outdir>
# redir: <frag> stdout -> $outdir/<member>; run: <frag> writes the tree.
run_producer() {
    kind=$1; frag=$2; outdir=$3
    mkdir -p "$outdir"
    if [ "$kind" = redir ]; then
        m=$4
        (cd "$root" && idolbin="$idolbin" root="$root" \
            env -u TSEMIT_CHECK -u TSEMIT_OUT -u TSEMIT_RESIDUE \
            sh -c "$frag" >"$outdir/$(basename "$m").out" 2>"$outdir/stderr.txt") \
            || { sed 's/^/    /' "$outdir/stderr.txt" >&2; return 1; }
    else
        (cd "$root" && idolbin="$idolbin" root="$root" \
            env -u TSEMIT_CHECK -u TSEMIT_OUT -u TSEMIT_RESIDUE \
            sh -c "$frag" >"$outdir/stdout.txt" 2>"$outdir/stderr.txt") \
            || { sed 's/^/    /' "$outdir/stderr.txt" >&2; return 1; }
    fi
}

restore_snap() {
    i=0
    while IFS= read -r m; do
        i=$((i + 1))
        if [ -f "$tmp/snap/m$i.pre" ]; then
            cp "$tmp/snap/m$i.pre" "$root/$m"
        else
            rm -f "$root/$m"
        fi
    done <"$tmp/members.txt"
}

upsert_sidecar() { # <new row>
    g=$(printf '%s' "$1" | awk -F'\t' '{ print $1 }')
    { LC_ALL=C awk -F'\t' -v k="$g" '$1 != k' "$tmp/sidecar.txt"; printf '%s\n' "$1"; } \
        | LC_ALL=C sort >"$tmp/depid.new"
    cp "$tmp/depid.new" "$tmp/sidecar.txt"
    cp "$tmp/depid.new" "$root/gate/generated.depid"
    note "recorded: $g"
}

# stamp_family <regen> : regenerate, determinism-check, install, record.
stamp_family() {
    regen=$1
    : >"$tmp/members.txt"
    LC_ALL=C awk -F'\t' -v r="$regen" '$1 == r { print $2 }' "$tmp/families.txt" >"$tmp/members.txt"
    [ -s "$tmp/members.txt" ] || die "no members for producer '$regen'"
    kind=${regen%%:*}
    frag=${regen#*:}
    case "$kind" in redir|run) ;; *) die "unknown regen kind '$kind' in '$regen'" ;; esac
    nmem=$(wc -l <"$tmp/members.txt" | tr -d ' ')
    if [ "$kind" = redir ] && [ "$nmem" -ne 1 ]; then
        die "redir producer must declare exactly one member: $regen"
    fi

    mkdir -p "$tmp/snap"
    if [ "$bootstrap" = yes ]; then
        note "bootstrap: recording current bytes without running the producer"
    else
        i=0
        while IFS= read -r m; do
            i=$((i + 1))
            [ -f "$root/$m" ] && cp "$root/$m" "$tmp/snap/m$i.pre"
        done <"$tmp/members.txt"
        m1=$(head -n 1 "$tmp/members.txt")
        b1=$(basename "$m1")
        if [ "$kind" = redir ]; then
            run_producer "$kind" "$frag" "$tmp/run1" "$m1" \
                || { restore_snap; die "producer failed: $regen"; }
            run_producer "$kind" "$frag" "$tmp/run2" "$m1" \
                || { restore_snap; die "producer failed on the determinism rerun: $regen"; }
            cmp -s "$tmp/run1/$b1.out" "$tmp/run2/$b1.out" \
                || { restore_snap; die "producer is nondeterministic for $m1 -- refusing to certify"; }
            cmp -s "$tmp/run2/$b1.out" "$root/$m1" \
                || note "$m1: regenerated bytes differ from the tree -- installing the producer's output"
            cp "$tmp/run2/$b1.out" "$root/$m1"
        else
            run_producer "$kind" "$frag" "$tmp/run1" "$m1" \
                || { restore_snap; die "producer failed: $regen"; }
            mkdir -p "$tmp/run1snap"
            i=0
            while IFS= read -r m; do
                i=$((i + 1))
                [ -f "$root/$m" ] && cp "$root/$m" "$tmp/run1snap/m$i.run1"
            done <"$tmp/members.txt"
            run_producer "$kind" "$frag" "$tmp/run2" "$m1" \
                || { restore_snap; die "producer failed on the determinism rerun: $regen"; }
            i=0
            while IFS= read -r m; do
                i=$((i + 1))
                if [ -f "$tmp/run1snap/m$i.run1" ]; then
                    if cmp -s "$tmp/run1snap/m$i.run1" "$root/$m"; then
                        :
                    else
                        restore_snap
                        die "producer is nondeterministic for $m -- refusing to certify"
                    fi
                elif [ -f "$root/$m" ]; then
                    restore_snap
                    die "producer wrote $m only on the rerun -- refusing to certify"
                fi
            done <"$tmp/members.txt"
        fi
    fi

    i=0
    while IFS= read -r m; do
        i=$((i + 1))
        mrow=$(manrow "$m") || { restore_snap; die "$m vanished from the manifest"; }
        inputs_cell=$(printf '%s' "$mrow" | awk -F'\t' '{ print $6 }')
        case "$inputs_cell" in
            *self:prev*)
                if [ -f "$tmp/snap/m$i.pre" ]; then
                    prevhash=$(bhash <"$tmp/snap/m$i.pre")
                else
                    [ -f "$root/$m" ] || { restore_snap; die "$m has no bytes to carry for self:prev"; }
                    prevhash=$(bhash <"$root/$m")
                fi
                ;;
            *) prevhash= ;;
        esac
        carried_emit=; carried_extra=
        row=$(row_core "$m" stamp) || { restore_snap; die "row compute failed for $m"; }
        upsert_sidecar "$row"
    done <"$tmp/members.txt"
}

cmd_stamp() {
    bootstrap=no
    if [ "${1:-}" = "--bootstrap" ]; then bootstrap=yes; shift; fi
    [ $# -gt 0 ] || die "stamp needs at least one generated path"
    [ "$mode" = worktree ] || die "stamp is a worktree operation (DEPID_MODE=$mode)"
    : >"$tmp/regens.req"
    for g in "$@"; do
        mrow=$(manrow "$g") || die "$g is not a declared projection in gate/generated.manifest"
        regen=$(printf '%s' "$mrow" | awk -F'\t' '{ print $5 }')
        printf '%s\n' "$regen" >>"$tmp/regens.req"
    done
    # A family stamps atomically: requesting one member pulls in every row
    # sharing its producer, so a regen can never record a partial family.
    : >"$tmp/families.txt"
    LC_ALL=C sort -u "$tmp/regens.req" | while IFS= read -r regen; do
        LC_ALL=C awk -F'\t' -v r="$regen" '
            /^[[:space:]]*(#|$)/ { next }
            $5 == r { print r "\t" $1 }' "$tmp/manifest.txt"
    done | LC_ALL=C sort -u >"$tmp/families.txt"
    [ -s "$tmp/families.txt" ] || die "no producer families matched"
    LC_ALL=C awk -F'\t' '{ print $1 }' "$tmp/families.txt" | LC_ALL=C sort -u >"$tmp/regens.txt"
    while IFS= read -r regen; do
        stamp_family "$regen"
    done <"$tmp/regens.txt"
    note "stamp complete: $root/gate/generated.depid"
}

usage() {
    printf 'usage: %s stamp [--bootstrap] <generated>... | check <generated>... | show <generated>\n' "$prog" >&2
    exit 2
}

bootstrap=no
prevhash=
carried_emit=
carried_extra=
[ $# -ge 1 ] || usage
sub=$1; shift
case "$sub" in
    stamp) cmd_stamp "$@" ;;
    check) cmd_check "$@" ;;
    show) cmd_show "$@" ;;
    -h|--help) usage ;;
    *) usage ;;
esac
