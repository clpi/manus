#!/bin/sh
# Idol authority convergence gate.
#
# Checks durable authority/projection invariants only. Exit 0 is not compiler,
# self-host, or performance acceptance evidence.
set -u

ROOT=${AUTHORITY_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
CONSTITUTION="$ROOT/docs/spec/constitution.md"
LAW="$ROOT/docs/spec/law.md"
SOURCE="$ROOT/docs/spec/source.md"
AUTHORITY_JSON="$ROOT/docs/spec/AUTHORITY.json"
RESEARCH_MANIFEST="$ROOT/research/archive/pass-2/manifest.json"
RESEARCH_ARCHIVE="$ROOT/research/archive/pass-2/pass-2-source.tar.gz"
NATIVE=${IDOL_NATIVE_ROOT:-"$ROOT/../idol-native"}

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'authority gate: FAIL %s\n' "$*"
}

require_file() {
    path=$1
    label=$2
    if [ ! -r "$path" ]; then
        bad "$label missing or unreadable: $path"
        return 1
    fi
    examined=$((examined + 1))
    return 0
}

contains() {
    path=$1
    text=$2
    label=$3
    grep -Fq "$text" "$path" || bad "$label"
}

rejects() {
    path=$1
    text=$2
    label=$3
    if grep -Fq "$text" "$path"; then bad "$label"; fi
}

require_file "$CONSTITUTION" constitution
require_file "$LAW" compact-law
require_file "$SOURCE" source-projection
require_file "$AUTHORITY_JSON" authority-manifest
require_file "$RESEARCH_MANIFEST" pass2-manifest
require_file "$RESEARCH_ARCHIVE" pass2-archive

GAP134="$ROOT/gaps/GAP-134.md"

if [ -r "$CONSTITUTION" ]; then
    contains "$CONSTITUTION" '# Idol constitution projection' 'constitution no longer declares itself a projection of compact law'
    contains "$CONSTITUTION" 'sole supreme compact law' 'constitution no longer subordinates to compact law'
    contains "$CONSTITUTION" 'the compact law wins' 'constitution lost compact-law-wins-on-drift ruling'
    contains "$CONSTITUTION" 'Computed or indexed aggregate access is projection — `table[key]`' 'constitution access section lost bracket projection law'
    contains "$CONSTITUTION" 'never `table(key)`' 'constitution access section no longer rejects call-shaped indexing'
    contains "$CONSTITUTION" 'names = { "Idol", "idol" }' 'constitution current-name set drifted'
    rejects "$CONSTITUTION" 'This is the sole living semantic law' 'constitution claims independent supreme authority'
    rejects "$CONSTITUTION" 'holds = .sole' 'constitution authority law still claims sole hold instead of expansion'
    rejects "$CONSTITUTION" '[] is legacy' 'constitution marks brackets as legacy compatibility'
    rejects "$CONSTITUTION" 'table access is table(key)' 'constitution revives call-shaped table access'
fi

if [ -r "$GAP134" ]; then
    examined=$((examined + 1))
    rejects "$GAP134" 'SUPREME one-page law' 'GAP-134 carries duplicate supreme-law authority'
    rejects "$GAP134" 'Supreme-law surface obligations' 'GAP-134 carries a second normative constitution section'
fi

if [ -r "$LAW" ]; then
    contains "$LAW" '# Idol — supreme language, semantic-graph, compiler, and performance law' 'compact law identity/title drifted'
    contains "$LAW" '`()` is ordinary application.' 'law no longer fixes parentheses as application'
    contains "$LAW" '`[]` is computed/indexed projection.' 'law no longer fixes brackets as projection'
    contains "$LAW" '`{}` carries structured pack/table/descriptor structure.' 'law no longer fixes braces as structure'
    rejects "$LAW" 'A runtime key uses application: `table(key)`' 'compact law contains retired call-shaped indexing'
fi

if [ -r "$SOURCE" ]; then
    contains "$SOURCE" 'This file is a **non-authoritative projection**' 'source guide claims or obscures authority'
    contains "$SOURCE" 'Canonical computed projection is indexed projection: `table[key]`.' 'source guide no longer carries bracket projection law'
    contains "$SOURCE" 'Parentheses remain ordinary relation application.' 'source guide no longer separates call from projection'
    rejects "$SOURCE" 'Canonical computed projection is ordinary application: `table(key)`.' 'retired call-shaped indexing is active'
fi

if [ -r "$AUTHORITY_JSON" ]; then
    contains "$AUTHORITY_JSON" '"name": "Idol"' 'authority manifest identity is not Idol'
    contains "$AUTHORITY_JSON" '"binary": "idol"' 'authority manifest binary drifted'
    contains "$AUTHORITY_JSON" '"source_suffix": ".id"' 'authority manifest suffix drifted'
    contains "$AUTHORITY_JSON" '"repository": "clpi/idol"' 'authority manifest repository drifted'
    contains "$AUTHORITY_JSON" '"sole_semantic_authority": true' 'authority manifest allows a second semantic authority'
    contains "$AUTHORITY_JSON" '"application": "()"' 'authority manifest application delimiter drifted'
    contains "$AUTHORITY_JSON" '"computed_projection": "[]"' 'authority manifest projection delimiter drifted'
fi

AUTHORITY_MD="$ROOT/docs/spec/AUTHORITY.md"
if [ -r "$AUTHORITY_MD" ]; then
    examined=$((examined + 1))
    contains "$AUTHORITY_MD" 'docs/spec/law.md' 'AUTHORITY.md no longer names compact law'
    contains "$AUTHORITY_MD" 'supreme compact law' 'AUTHORITY.md no longer ranks compact law supreme'
    contains "$AUTHORITY_MD" 'compact law is the current owner ruling' 'AUTHORITY.md lost compact-law-wins ruling'
fi

if [ -e "$ROOT/.agents/SESSION_STATE.md" ]; then
    bad '.agents/SESSION_STATE.md is ephemeral state masquerading as durable authority'
fi

archive_sha='0ac4b3a198a45f51ec6e3f3387977ecf9e964663ce6652dca499da4e99e9f139'
if [ -r "$RESEARCH_MANIFEST" ]; then
    contains "$RESEARCH_MANIFEST" "$archive_sha" 'Pass 2 manifest archive digest drifted'
    contains "$RESEARCH_MANIFEST" '"files": [' 'Pass 2 manifest lost its file census'
    contains "$RESEARCH_MANIFEST" '"superseded-identity-ruling"' 'superseded Idsem research disposition disappeared'
fi
if [ -r "$RESEARCH_ARCHIVE" ]; then
    actual=''
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$RESEARCH_ARCHIVE" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$RESEARCH_ARCHIVE" | awk '{print $1}')
    fi
    if [ -n "$actual" ] && [ "$actual" != "$archive_sha" ]; then
        bad "Pass 2 archive digest mismatch: $actual"
    fi
fi

# Optional sibling check. Native is a realization/evidence projection and may
# never mint a second language law.
if [ -d "$NATIVE" ]; then
    NATIVE_AUTHORITY="$NATIVE/docs/spec/AUTHORITY.json"
    require_file "$NATIVE_AUTHORITY" native-authority-projection
    if [ -r "$NATIVE_AUTHORITY" ]; then
        contains "$NATIVE_AUTHORITY" '"repository": "clpi/idol"' 'native repository does not project clpi/idol authority'
        contains "$NATIVE_AUTHORITY" '"local_law_is_authority": false' 'native repository claims independent semantic law'
        contains "$NATIVE_AUTHORITY" '"name": "Idol"' 'native repository current identity drifted'
    fi
fi

if [ "$examined" -eq 0 ]; then bad 'no authority artifacts examined'; fi

if [ "$violations" -eq 0 ]; then
    printf 'authority gate: PASS (%s file(s)); authority convergence only\n' "$examined"
else
    printf 'authority gate: FAIL (%s violation(s), %s file(s))\n' "$violations" "$examined"
fi
exit "$violations"
