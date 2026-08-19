#!/bin/sh
# STANDALONE CROSS-REPOSITORY GATE: it checks compiler authority together with
# the sibling native surface. It remains directly runnable when either checkout
# is tested alone; the native aggregate may invoke it only when both are present.
#
# gate/authority.sh — reject contradictions between law, execution, and human
# projections. The checked set is deliberately small: these are the authority
# artifacts and consumers that block the next architecture injection.
#
# Exit 0 = every checked artifact is classified and agrees with the current law.
# Non-zero = the contradiction count. The final line reports files examined.

set -u

ROOT=${AUTHORITY_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
SOURCE="$ROOT/docs/spec/source.md"
CONVERGE="$ROOT/../idol-native/gate/converge.sh"
SUBJECT_HOME="$ROOT/src/subject_home.zig"
LAUNCH_ROLE="$ROOT/src/launch_role.zig"
MAIN="$ROOT/src/main.zig"
SEMA="$ROOT/src/sema.zig"
GRAPH="$ROOT/src/semantic_graph.zig"
RELEASE="$ROOT/.agents/RELEASE_READINESS.md"

violations=0
examined=0

# `primary|state` is the classification, not a second semantic law. The state
# is allowed to be stale only while the corresponding contradiction is red.
CLASSIFICATIONS='source|semantic-authority|current;converge|executed-implementation-authority|current;subject-home|semantic-authority|current;launch-role|transitional-bridge|current;main|executed-implementation-authority|current;sema|executed-implementation-authority|current;semantic-graph|executed-implementation-authority|current;release-readiness|human-projection|current'

bad() {
    violations=$((violations + 1))
    printf 'FAIL %s\n' "$*"
}

check_file() {
    path=$1
    label=$2
    if [ ! -r "$path" ]; then
        bad "$label is missing or unreadable: $path"
        return 1
    fi
    examined=$((examined + 1))
    return 0
}

check_classifications() {
    seen=0
    old_ifs=$IFS
    IFS=';'
    for row in $CLASSIFICATIONS; do
        [ -n "$row" ] || continue
        IFS='|'
        set -- $row
        if [ "$#" -ne 3 ]; then
            bad "malformed classification row: $row"
            continue
        fi
        case "$2" in
            semantic-authority|executed-implementation-authority|transitional-bridge|human-projection|historical-evidence|stale-contradiction) ;;
            *) bad "unknown primary authority class '$2' for $1" ;;
        esac
        case "$3" in
            current|stale-contradiction) ;;
            *) bad "unknown authority state '$3' for $1" ;;
        esac
        seen=$((seen + 1))
        printf 'CLASS %s %s %s\n' "$1" "$2" "$3"
        IFS=';'
    done
    IFS=$old_ifs
    [ "$seen" -gt 0 ] || bad 'authority classification is empty'
}

check_classifications
check_file "$SOURCE" source
check_file "$CONVERGE" converge
check_file "$SUBJECT_HOME" subject-home
check_file "$LAUNCH_ROLE" launch-role
check_file "$MAIN" main
check_file "$SEMA" sema
check_file "$GRAPH" semantic-graph
check_file "$RELEASE" release-readiness

# C0 §7/§51: runtime computed projection is ordinary application. A document
# may mention the retired face as history, but it must not call it canonical.
if [ -r "$SOURCE" ] && grep -Fq 'Canonical computed projection remains `table[key]`' "$SOURCE"; then
    bad 'source law canonizes table[key], while C0 canonizes table(key)'
fi
if [ -r "$SOURCE" ] && ! grep -Fq 'Canonical computed projection is ordinary application: `table(key)`.' "$SOURCE"; then
    bad 'source projection no longer carries the canonical table(key) ruling'
fi

# The supreme source law fixes physical `main/` as the source-root convention.
# `app/` in the projection is not merely a different example: it teaches a
# second root topology while claiming to project the same filesystem algebra.
if [ -r "$SOURCE" ] && grep -Fq 'app/' "$SOURCE" \
    && grep -Fq '  main.id' "$SOURCE"; then
    bad 'source projection teaches an app/main.id root beside the ruled main/ root'
fi
if [ -r "$SOURCE" ] && ! grep -Fq 'main/' "$SOURCE"; then
    bad 'source projection no longer carries the physical main/ root convention'
fi

# Source/home law does not require a src/ directory above a source file. This
# check names the executable gate that still imposes that topology.
if [ -r "$CONVERGE" ] && grep -Fq 'mkdir -p "$WORK/src"' "$CONVERGE"; then
    bad 'converge gate manufactures a src/ project root contrary to source law'
fi

# World authority comes from launcher witnesses; filesystem structure may be
# provenance or launch-role input, but it must not grant the testing world.
if [ -r "$SUBJECT_HOME" ] && grep -Fq '.home = .testing' "$SUBJECT_HOME" \
    && grep -Fq '.directory = "test"' "$SUBJECT_HOME" \
    && grep -Fq '.stem_suffix = "_test.id"' "$SUBJECT_HOME"; then
    bad 'subject_home grants testing authority from test paths and file names'
fi
if [ -r "$SUBJECT_HOME" ]; then
    grep -Fq '.injection = .witnessed' "$SUBJECT_HOME" \
        || bad 'testing world no longer requires an explicit witness'
    if grep -Eq 'by_structure|pub const Structure|fileInhabits' "$SUBJECT_HOME"; then
        bad 'subject_home has regained a filesystem-to-world authority path'
    fi
fi

# Source structure may select a launch ROLE. Only the launcher may turn that
# role into exact world identities; sema and graph consumers receive the set.
if [ -r "$LAUNCH_ROLE" ]; then
    grep -Fq 'pub fn forSource(path: []const u8) Role' "$LAUNCH_ROLE" \
        || bad 'launch-role classifier is missing'
fi
if [ -r "$MAIN" ]; then
    grep -Fq 'launch_role.forSource(src_path)' "$MAIN" \
        || bad 'launcher no longer classifies source provenance once at ingress'
    grep -Fq 'sem.worlds = launchWorlds(src_path);' "$MAIN" \
        || bad 'launcher worlds no longer reach semantic checking'
    grep -Fq 'const worlds = launchWorlds(src_path);' "$MAIN" \
        || bad 'build cache no longer hashes the launcher world set'
fi
if [ -r "$SEMA" ]; then
    grep -Fq 'worlds: subject_home.WorldSet' "$SEMA" \
        || bad 'sema no longer carries exact launcher worlds'
    if grep -Eq 'subject_home\.[A-Za-z0-9_]+\(self\.source_path' "$SEMA"; then
        bad 'sema reconstructs world authority from source provenance'
    fi
fi
if [ -r "$GRAPH" ]; then
    grep -Fq 'self.launch_worlds = checked.worlds;' "$GRAPH" \
        || bad 'semantic graph no longer consumes checked launcher worlds'
    if grep -Eq 'subject_home\.[A-Za-z0-9_]+\([^)]*module_path' "$GRAPH"; then
        bad 'semantic graph reconstructs world authority from module provenance'
    fi
fi

# Release identity comes from repository configuration, not the checkout
# directory's basename. The live `origin`, orient, doctor, and generated harness
# all agree that clpi/duo remains the development repository. Detect drift in
# either direction instead of treating `/x/idol` as evidence of a migration.
if [ -r "$RELEASE" ]; then
    origin=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
    case "$origin" in
        *clpi/duo*)
            grep -Fq 'Active development stays in **`clpi/duo`**' "$RELEASE" \
                || bad 'release readiness no longer matches the clpi/duo development origin'
            ;;
        *)
            grep -Fq 'Active development stays in **`clpi/duo`**' "$RELEASE" \
                && bad 'release readiness declares clpi/duo without a matching development origin'
            ;;
    esac
fi

if [ "$examined" -eq 0 ]; then
    printf 'authority gate: FAIL (0 file(s)) no authority artifacts examined\n'
    exit 1
fi

if [ "$violations" -eq 0 ]; then
    printf 'authority gate: PASS (%s file(s))\n' "$examined"
else
    printf 'authority gate: FAIL (%s file(s))\n' "$examined"
fi
exit "$violations"
