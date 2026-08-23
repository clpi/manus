#!/bin/sh
# Idol authority convergence gate.
#
# Checks durable authority/projection invariants only. Exit 0 is not compiler,
# self-host, or performance acceptance evidence.
set -u

ROOT=${AUTHORITY_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
CONSTITUTION="$ROOT/docs/spec/constitution.md"
LAW="$ROOT/docs/spec/law.md"
SOURCE="$ROOT/docs/spec/source.md"
AUTHORITY_JSON="$ROOT/docs/spec/AUTHORITY.json"
AUTHORITY_PROJECTION="$ROOT/src/authority_projection.zig"
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
require_file "$AUTHORITY_PROJECTION" authority-compiler-projection
require_file "$RESEARCH_MANIFEST" pass2-manifest
require_file "$RESEARCH_ARCHIVE" pass2-archive

if ! command -v python3 >/dev/null 2>&1; then
    bad 'python3 is required for duplicate-safe authority manifest validation'
elif ! python3 - "$AUTHORITY_JSON" "$RESEARCH_MANIFEST" "$AUTHORITY_PROJECTION" <<'PY'
import json
import re
import sys
from pathlib import Path

def unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out

def load(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=unique_object)

def need(condition, message):
    if not condition:
        raise ValueError(message)

try:
    authority = load(sys.argv[1])
    research = load(sys.argv[2])
    projection_text = Path(sys.argv[3]).read_text()

    need(authority.get("schema") == "idol.authority.v2", "authority schema")
    owner = authority["authority"]
    need(owner.get("repository") == "clpi/idol", "authority repository")
    need(owner.get("sole_semantic_authority") is True, "sole authority")
    need(owner["compact_law"].get("path") == "docs/spec/law.md", "compact law path")
    need(owner["long_form_law"].get("path") == "docs/spec/constitution.md", "long-form law path")
    need(owner["source_projection"].get("path") == "docs/spec/source.md", "source projection path")
    need(authority["identity"] == {
        "name": "Idol",
        "binary": "idol",
        "source_suffix": ".id",
        "superseded_current_names": ["Duo", "Duon", "Idsem"],
    }, "current identity")
    need(authority["delimiters"]["application"] == "()", "application delimiter")
    need(authority["delimiters"]["computed_projection"] == "[]", "projection delimiter")

    edition = authority["source_law_edition"]
    need(edition.get("schema") == "idol.source.law.v1", "edition schema")
    need(re.fullmatch(r"[0-9a-f]{64}", edition.get("sha256", "")) is not None, "edition digest")
    need(edition.get("algorithm") == "sha256 of schema UTF-8, NUL, compact-law bytes, NUL, long-form-law bytes", "edition algorithm")
    need(edition.get("input_blob_ids") == {
        "compact_law": owner["compact_law"]["blob"],
        "long_form_law": owner["long_form_law"]["blob"],
    }, "edition input blob ids")

    rulings = authority["rulings"]
    need(str(rulings.get("coverage", "")).startswith("seed;"), "ruling coverage")
    need(set(rulings.get("status_vocabulary", [])) == {"current", "superseded", "historical", "compatibility"}, "ruling status vocabulary")
    rows = rulings.get("rows", [])
    laws = [row.get("law") for row in rows]
    need(len(laws) == len(set(laws)), "duplicate ruling law")
    required_laws = {
        "law.identity.current",
        "law.application.parentheses",
        "law.projection.computed",
        "law.structure.braces",
        "law.block.offside",
        "law.at.one",
    }
    need(required_laws.issubset(set(laws)), "required ruling missing")
    required_faces = {
        "law.identity.current": [".id"],
        "law.application.parentheses": ["()"],
        "law.projection.computed": ["[]"],
        "law.structure.braces": ["{}"],
        "law.block.offside": ["offside indentation"],
        "law.at.one": ["@x", "@{ k = v }", "thing@world", "thing@{ k = v }", "@k = v"],
    }
    required_fields = {
        "law", "identity", "status", "effective", "supersedes",
        "source_faces", "semantic_form", "negative_controls",
        "generated_consumers", "implementation_state",
    }
    for row in rows:
        need(required_fields.issubset(row), f"ruling fields: {row.get('law')}")
        need(row["status"] in rulings["status_vocabulary"], f"ruling status: {row['law']}")
        if row["status"] == "current":
            need(row["effective"] == edition["sha256"], f"ruling edition: {row['law']}")
        if row["law"] in required_faces:
            need(row["status"] == "current", f"required ruling disposition: {row['law']}")
            need(row["effective"] == edition["sha256"], f"required ruling edition: {row['law']}")
            need(row["source_faces"] == required_faces[row["law"]], f"required ruling source faces: {row['law']}")
    at = next(row for row in rows if row["law"] == "law.at.one")
    need({
        "historical.at.descriptor-anchor",
        "historical.at.directive-namespace",
    }.issubset(set(at["supersedes"])), "@ supersession")
    typed_gap = authority["open_architecture_gaps"]["typed_identity_and_lineage"]
    need(typed_gap.get("status") == "open", "typed identity gap is overstated")
    need("not a claim" in typed_gap.get("implementation_state", ""), "typed identity implementation honesty")

    schemas = re.findall(r'^pub const source_law_schema = "([^"]+)";$', projection_text, re.MULTILINE)
    digests = re.findall(r'^pub const source_law_sha256 = "([0-9a-f]+)";$', projection_text, re.MULTILINE)
    need(schemas == [edition["schema"]], "compiler projection schema declaration")
    need(digests == [edition["sha256"]], "compiler projection digest declaration")

    need(research.get("schema") == "idol.research.archive.v2", "research schema")
    need(research.get("archive") == "pass-2-source.tar.gz", "research archive path")
    need(research.get("archive_sha256") == "e66fe6cd2470eb7ce73a82ed0f758b84044715c4a8102e55e95b61435e32ed78", "research archive digest")
    need(research.get("archive_bytes") == 88492, "research archive byte count")
    integrity = research.get("archive_integrity", {})
    need(integrity.get("status") in {"complete", "corrupt"}, "research archive integrity status")
    if integrity["status"] == "corrupt":
        need(integrity.get("observed_sha256") == "0ac4b3a198a45f51ec6e3f3387977ecf9e964663ce6652dca499da4e99e9f139", "corrupt archive observed digest")
        need(integrity.get("observed_bytes") == 15008, "corrupt archive observed bytes")
    policy = research["archive_policy"]
    need(set(policy.get("allowed_status", [])) == {"historical", "superseded"}, "research status policy")
    need(str(policy.get("training_disposition", "")).startswith("non-authoritative:"), "research training disposition")
    files = research.get("files", [])
    need(len(files) == 25, "research row count")
    names = [row.get("name") for row in files]
    need(len(names) == len(set(names)), "duplicate research filename")
    for row in files:
        name = row.get("name")
        need(isinstance(name, str) and name not in {"", ".", ".."}, "research filename")
        need("/" not in name and "\\" not in name, f"unsafe research filename: {name}")
        need(isinstance(row.get("bytes"), int) and not isinstance(row.get("bytes"), bool) and row["bytes"] >= 0, f"research byte count: {name}")
        need(re.fullmatch(r"[0-9a-f]{64}", row.get("sha256", "")) is not None, f"research digest: {name}")
        need(row.get("status") in {"historical", "superseded"}, f"research disposition: {name}")
    by_name = {row["name"]: row for row in files}
    by_digest = {}
    for row in files:
        by_digest.setdefault(row["sha256"], []).append(row)
        duplicate_of = row.get("duplicate_of")
        if duplicate_of is not None:
            need(duplicate_of in by_name and duplicate_of != row["name"], f"research duplicate target: {row['name']}")
            need(by_name[duplicate_of]["sha256"] == row["sha256"], f"research duplicate digest: {row['name']}")
    for digest, group in by_digest.items():
        canonical = [row for row in group if "duplicate_of" not in row]
        need(len(canonical) == 1, f"research digest ownership: {digest}")
        for row in group:
            if row is not canonical[0]:
                need(row.get("duplicate_of") == canonical[0]["name"], f"unmarked research duplicate: {row['name']}")
    p210 = by_name["Pass 2.10-DNIR reconciliation.txt"]
    p211 = by_name["Pass 2.11-Goals.txt"]
    need(p211.get("duplicate_of") == p210["name"] and p211["sha256"] == p210["sha256"], "Pass 2.11 duplicate")
    need(by_name["Pass 2.28-Idsem Naming Convergence.txt"].get("status") == "superseded", "Idsem disposition")

    projected_research = authority["research"]["pass_2"]
    need(projected_research.get("path") == "research/archive/pass-2", "authority research path")
    need(projected_research.get("archive_sha256") == research["archive_sha256"], "authority research digest")
    need(projected_research.get("files") == len(files), "authority research file count")
    need(projected_research.get("archive_integrity") == "corrupt; recovery requires the 25 original inputs", "authority research integrity")
except Exception as exc:
    print(f"authority manifest validation: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
then
    bad 'authority or research manifest is malformed, duplicated, incomplete, or inconsistent'
fi

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

AUTHORITY_MD="$ROOT/docs/spec/AUTHORITY.md"
if [ -r "$AUTHORITY_MD" ]; then
    examined=$((examined + 1))
    contains "$AUTHORITY_MD" 'docs/spec/law.md' 'AUTHORITY.md no longer names compact law'
    contains "$AUTHORITY_MD" 'supreme compact law' 'AUTHORITY.md no longer ranks compact law supreme'
    contains "$AUTHORITY_MD" 'compact law is the current owner ruling' 'AUTHORITY.md lost compact-law-wins ruling'
fi


README="$ROOT/docs/spec/README.md"
if [ -r "$README" ]; then
    examined=$((examined + 1))
    contains "$README" 'docs/spec/law.md' 'spec router no longer names compact law'
    contains "$README" 'supreme compact law' 'spec router no longer ranks compact law supreme'
    rejects "$README" 'Idol language law has one home:' 'spec router still claims constitution is the sole law home'
fi

AGENT_CANONICAL="$ROOT/.agents/AGENT_CANONICAL.md"
if [ -r "$AGENT_CANONICAL" ]; then
    examined=$((examined + 1))
    contains "$AGENT_CANONICAL" 'docs/spec/law.md' 'agent router no longer names compact law'
    contains "$AGENT_CANONICAL" 'Supreme compact law' 'agent router no longer ranks compact law supreme'
    rejects "$AGENT_CANONICAL" 'Sole semantic law | `docs/spec/constitution.md`' 'agent router still claims constitution is sole semantic law'
fi

AGENTS_SCOPE="$ROOT/.agents/AGENTS.md"
if [ -r "$AGENTS_SCOPE" ]; then
    examined=$((examined + 1))
    contains "$AGENTS_SCOPE" 'docs/spec/law.md' 'agent scope no longer names compact law'
    contains "$AGENTS_SCOPE" 'supreme compact law' 'agent scope no longer ranks compact law supreme'
    rejects "$AGENTS_SCOPE" 'is the sole semantic law' 'agent scope still claims constitution is sole semantic law'
fi

AGENT_COORD="$ROOT/.agents/AGENT_COORDINATION.md"
if [ -r "$AGENT_COORD" ]; then
    examined=$((examined + 1))
    contains "$AGENT_COORD" 'docs/spec/law.md' 'agent coordination no longer names compact law'
    rejects "$AGENT_COORD" 'Semantic law | `docs/spec/constitution.md` only' 'agent coordination still claims constitution is sole semantic law'
fi

ARCH_INJ="$ROOT/.agents/ARCHITECTURE_INJECTION.md"
if [ -r "$ARCH_INJ" ]; then
    examined=$((examined + 1))
    contains "$ARCH_INJ" 'observations → identities + facts → demand → lawful realization space → minimum physical work' 'architecture injection lost core pipeline model'
    contains "$ARCH_INJ" 'Preserve the strongest fact already known' 'architecture injection lost strongest-fact law'
    contains "$ARCH_INJ" 'Do not port the host compiler' 'architecture injection lost short-form mandate'
fi

if ! command -v git >/dev/null 2>&1; then
    bad 'git is required to bind declared authority blobs to exact bytes'
elif [ -r "$AUTHORITY_JSON" ]; then
    authority_fields=$(python3 - "$AUTHORITY_JSON" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
print(
    data["authority"]["compact_law"]["blob"],
    data["authority"]["long_form_law"]["blob"],
    data["authority"]["source_projection"]["blob"],
    data["source_law_edition"]["schema"],
    data["source_law_edition"]["sha256"],
)
PY
    ) || authority_fields=''
    # Every field is a whitespace-free identifier validated above.
    # shellcheck disable=SC2086
    set -- $authority_fields
    LAW_BLOB=${1:-}
    CON_BLOB=${2:-}
    SRC_BLOB=${3:-}
    EDITION_SCHEMA=${4:-}
    EDITION_SHA=${5:-}
    [ "$#" -eq 5 ] || bad 'authority manifest fields could not be extracted'
    if [ -n "$LAW_BLOB" ] && [ -r "$LAW" ]; then
        actual_law=$(git -C "$ROOT" hash-object "$LAW")
        [ "$actual_law" = "$LAW_BLOB" ] || bad "law.md blob drift (manifest $LAW_BLOB got $actual_law)"
    fi
    if [ -n "$CON_BLOB" ] && [ -r "$CONSTITUTION" ]; then
        actual_con=$(git -C "$ROOT" hash-object "$CONSTITUTION")
        [ "$actual_con" = "$CON_BLOB" ] || bad "constitution.md blob drift (manifest $CON_BLOB got $actual_con)"
    fi
    if [ -n "$SRC_BLOB" ] && [ -r "$SOURCE" ]; then
        actual_src=$(git -C "$ROOT" hash-object "$SOURCE")
        [ "$actual_src" = "$SRC_BLOB" ] || bad "source.md blob drift (manifest $SRC_BLOB got $actual_src)"
    fi

    derived_edition=''
    if command -v shasum >/dev/null 2>&1; then
        derived_edition=$(
            {
                printf '%s\000' "$EDITION_SCHEMA"
                cat "$LAW"
                printf '\000'
                cat "$CONSTITUTION"
            } | shasum -a 256 | awk '{print $1}'
        )
    elif command -v sha256sum >/dev/null 2>&1; then
        derived_edition=$(
            {
                printf '%s\000' "$EDITION_SCHEMA"
                cat "$LAW"
                printf '\000'
                cat "$CONSTITUTION"
            } | sha256sum | awk '{print $1}'
        )
    else
        bad 'no SHA-256 implementation available for source-law edition'
    fi
    [ -n "$EDITION_SCHEMA" ] || bad 'source-law edition schema missing'
    [ -n "$EDITION_SHA" ] || bad 'source-law edition digest missing'
    [ -n "$derived_edition" ] || bad 'source-law edition could not be derived'
    [ "$derived_edition" = "$EDITION_SHA" ] || bad "source-law edition drift (manifest $EDITION_SHA derived $derived_edition)"
fi

if [ -e "$ROOT/.agents/SESSION_STATE.md" ]; then
    bad '.agents/SESSION_STATE.md is ephemeral state masquerading as durable authority'
fi

if [ -r "$RESEARCH_ARCHIVE" ]; then
    archive_observation=$(python3 - "$RESEARCH_MANIFEST" "$RESEARCH_ARCHIVE" <<'PY'
import hashlib
import gzip
import json
import sys
import tarfile
import zlib

manifest = json.load(open(sys.argv[1]))

def classify(status, size, digest, gzip_complete, expected_size, expected_digest,
             observed_size=None, observed_digest=None):
    if status == "complete":
        if size != expected_size or digest != expected_digest or not gzip_complete:
            raise ValueError("declared-complete archive does not match complete identity")
        return "complete"
    if status == "corrupt":
        if observed_size is None or observed_digest is None:
            raise ValueError("declared-corrupt archive lacks exact observed identity")
        if size != observed_size or digest != observed_digest:
            raise ValueError("declared-corrupt archive moved from its preserved identity")
        if gzip_complete:
            raise ValueError("declared-corrupt archive unexpectedly became a complete gzip stream")
        return "preserved-corrupt"
    raise ValueError("unknown archive integrity status")

# Mandatory classifier damage controls. Exact corrupt provenance is distinct
# from complete admission, and neither moved bytes nor a false complete claim
# may enter either class.
if classify("complete", 8, "a", True, 8, "a") != "complete":
    raise SystemExit("complete archive classifier positive control failed")
if classify("corrupt", 3, "b", False, 8, "a", 3, "b") != "preserved-corrupt":
    raise SystemExit("corrupt archive classifier positive control failed")
for damaged in (
    ("corrupt", 4, "b", False, 8, "a", 3, "b"),
    ("corrupt", 3, "c", False, 8, "a", 3, "b"),
    ("corrupt", 3, "b", True, 8, "a", 3, "b"),
    ("complete", 3, "b", False, 8, "a", None, None),
    ("unknown", 8, "a", True, 8, "a", None, None),
):
    try:
        classify(*damaged)
    except ValueError:
        pass
    else:
        raise SystemExit("archive integrity classifier damage control failed")

archive_path = sys.argv[2]
raw = open(archive_path, "rb").read()
digest = hashlib.sha256(raw).hexdigest()
try:
    with gzip.open(archive_path, "rb") as stream:
        while stream.read(1024 * 1024):
            pass
    gzip_complete = True
except (EOFError, OSError, zlib.error):
    gzip_complete = False

integrity = manifest.get("archive_integrity", {})
try:
    state = classify(
        integrity.get("status"),
        len(raw),
        digest,
        gzip_complete,
        manifest.get("archive_bytes"),
        manifest.get("archive_sha256"),
        integrity.get("observed_bytes"),
        integrity.get("observed_sha256"),
    )
except ValueError as exc:
    print(exc)
    raise SystemExit(1)

if state == "preserved-corrupt":
    print(f"preserved corrupt archive {len(raw)} bytes sha256={digest}")
    raise SystemExit(2)

expected = {row["name"]: row for row in manifest["files"]}
try:
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        if len(members) != len(expected):
            raise ValueError("archive member count")
        seen = set()
        for member in members:
            if not member.isfile() or member.name not in expected or member.name in seen:
                raise ValueError(f"archive member identity: {member.name}")
            seen.add(member.name)
            row = expected[member.name]
            if member.size != row["bytes"]:
                raise ValueError(f"archive member bytes: {member.name}")
            stream = archive.extractfile(member)
            if stream is None or hashlib.sha256(stream.read()).hexdigest() != row["sha256"]:
                raise ValueError(f"archive member digest: {member.name}")
        if seen != set(expected):
            raise ValueError("archive member roster")
except (OSError, tarfile.TarError, ValueError) as exc:
    print(exc)
    raise SystemExit(1)

print(f"complete archive {len(raw)} bytes sha256={digest}")
PY
    )
    archive_rc=$?
    case "$archive_rc" in
        0) : ;;
        2) bad "Pass 2 archive is exact preserved corrupt provenance ($archive_observation); complete 88,492-byte archive is required for admission" ;;
        *) bad "Pass 2 archive identity, integrity, or member roster is invalid: ${archive_observation:-unclassified}" ;;
    esac
fi

# When a compiler subject is explicitly supplied, bind both its exact bytes and
# embedded projection. `IDOL_SHA256` is the caller's independently established
# candidate identity; observing plausible output is not artifact identity.
# Every execution is routed through the native evidence limiter so a hung or
# crashed compiler is infrastructure, never an authority answer.
if [ -n "${IDOL:-}" ]; then
    LIMITER=${AUTHORITY_LIMITER:-"$NATIVE/gate/run_limited.pl"}
    TMO=${AUTHORITY_TIMEOUT:-30}
    case "$IDOL" in
        /*) IDOL_PATH=$IDOL ;;
        *)
            idol_dir=$(dirname -- "$IDOL")
            idol_base=$(basename -- "$IDOL")
            IDOL_PATH=$(CDPATH='' cd -- "$idol_dir" 2>/dev/null && pwd)/$idol_base
            ;;
    esac
    if [ ! -x "$IDOL_PATH" ]; then
        bad "supplied compiler is unavailable: $IDOL"
    elif [ ! -r "$LIMITER" ]; then
        bad "structured compiler limiter is unavailable: $LIMITER"
    elif ! command -v perl >/dev/null 2>&1; then
        bad 'perl is required for structured compiler outcome evidence'
    elif ! printf '%s\n' "$TMO" | grep -Eq '^[1-9][0-9]*$'; then
        bad 'AUTHORITY_TIMEOUT must be one positive decimal duration in seconds'
    elif [ -z "${IDOL_SHA256:-}" ]; then
        bad 'IDOL_SHA256 is required to bind a supplied compiler artifact'
    elif ! printf '%s\n' "$IDOL_SHA256" | grep -Eq '^[0-9a-f]{64}$'; then
        bad 'IDOL_SHA256 is not one lowercase SHA-256 digest'
    elif [ -z "${AUTHORITY_LIMITER_SHA256:-}" ]; then
        bad 'AUTHORITY_LIMITER_SHA256 is required to bind the structured outcome limiter'
    elif ! printf '%s\n' "$AUTHORITY_LIMITER_SHA256" | grep -Eq '^[0-9a-f]{64}$'; then
        bad 'AUTHORITY_LIMITER_SHA256 is not one lowercase SHA-256 digest'
    elif [ -n "${EDITION_SHA:-}" ]; then
        compiler_sha_before=''
        if command -v shasum >/dev/null 2>&1; then
            compiler_sha_before=$(shasum -a 256 "$IDOL_PATH" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            compiler_sha_before=$(sha256sum "$IDOL_PATH" | awk '{print $1}')
        fi
        if [ -z "$compiler_sha_before" ]; then
            bad 'supplied compiler SHA-256 could not be recorded'
        elif [ "$compiler_sha_before" != "$IDOL_SHA256" ]; then
            bad "supplied compiler bytes differ from IDOL_SHA256 (expected $IDOL_SHA256 got $compiler_sha_before)"
        fi
        limiter_sha_before=''
        if command -v shasum >/dev/null 2>&1; then
            limiter_sha_before=$(shasum -a 256 "$LIMITER" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            limiter_sha_before=$(sha256sum "$LIMITER" | awk '{print $1}')
        fi
        if [ -z "$limiter_sha_before" ]; then
            bad 'structured compiler limiter SHA-256 could not be recorded'
        elif [ "$limiter_sha_before" != "$AUTHORITY_LIMITER_SHA256" ]; then
            bad "structured compiler limiter bytes differ from AUTHORITY_LIMITER_SHA256 (expected $AUTHORITY_LIMITER_SHA256 got $limiter_sha_before)"
        fi

        # Never execute either artifact unless both exact identities match the
        # independently supplied subjects. Recording a mismatch and continuing
        # would let untrusted replacement bytes participate in evidence.
        if [ "$compiler_sha_before" = "$IDOL_SHA256" ] && \
           [ "$limiter_sha_before" = "$AUTHORITY_LIMITER_SHA256" ]; then
            authority_probe_parent=$(mktemp -d "${TMPDIR:-/tmp}/idol-authority.XXXXXX") || authority_probe_parent=''
            if [ -z "$authority_probe_parent" ]; then
                bad 'could not create private compiler authority probe'
            else
            run_idol() {
                run_tag=$1
                shift
                RUN_EVENT_FILE="$authority_probe_parent/$run_tag.event"
                RUN_OUT="$authority_probe_parent/$run_tag.stdout"
                RUN_ERR="$authority_probe_parent/$run_tag.stderr"
                rm -f "$RUN_EVENT_FILE" "$RUN_OUT" "$RUN_ERR"
                perl "$LIMITER" "$TMO" "$RUN_EVENT_FILE" "$IDOL_PATH" "$@" \
                    </dev/null >"$RUN_OUT" 2>"$RUN_ERR"
                RUN_RC=$?
                RUN_EVENT=$(sed -n '1p' "$RUN_EVENT_FILE" 2>/dev/null)
                case "$RUN_EVENT" in
                    ok) return 0 ;;
                    timeout|signal:*|pipe|fork|group|wait|exec|armed|'')
                        bad "supplied compiler $run_tag infrastructure event: ${RUN_EVENT:-missing} (status $RUN_RC)"
                        return 1
                        ;;
                    *)
                        bad "supplied compiler $run_tag unknown outcome event: $RUN_EVENT"
                        return 1
                        ;;
                esac
            }

            if run_idol authority authority; then
                compiler_authority=$(cat "$RUN_OUT")
                if [ "$RUN_RC" -ne 0 ] || [ -z "$compiler_authority" ]; then
                    bad "supplied compiler does not report an authority projection (status $RUN_RC)"
                else
                    expected_compiler_authority="{\"schema\":\"idol.authority.projection.v1\",\"source_law\":{\"card\":\"one\",\"family\":\"idol\",\"schema\":\"$EDITION_SCHEMA\",\"sha256\":\"$EDITION_SHA\"}}"
                    [ "$compiler_authority" = "$expected_compiler_authority" ] \
                        || bad 'supplied compiler source-law projection is not the exact canonical authority object'
                fi
            fi

            if run_idol authority-option authority --backend=direct; then
                [ "$RUN_RC" -ne 0 ] || bad 'idol authority accepts compile options and is not an exact no-argument evidence query'
            fi
            if run_idol authority-forward authority -- ignored; then
                [ "$RUN_RC" -ne 0 ] || bad 'idol authority accepts forwarded program arguments'
            fi

            authority_probe="$authority_probe_parent/edition.id"
            printf 'edition_probe = 1\n' > "$authority_probe"
            if run_idol graph graph "$authority_probe"; then
                if [ "$RUN_RC" -ne 0 ] || ! python3 - "$EDITION_SCHEMA" "$EDITION_SHA" "$RUN_OUT" <<'PY'
import json, sys
schema, digest, path = sys.argv[1:]
try:
    graph = json.load(open(path))
    law = graph["root_source_law"]
    if graph["version"] != 11:
        raise ValueError("graph schema version")
    if law != {"card": "one", "family": "idol", "schema": schema, "sha256": digest}:
        raise ValueError("root source-law projection")
except Exception:
    raise SystemExit(1)
PY
                then
                    bad 'supplied executable does not carry its exact authority edition through real Idol ingress and graph export'
                fi
            fi

                find "$authority_probe_parent" -depth -delete
            fi
        fi

        compiler_sha_after=''
        if command -v shasum >/dev/null 2>&1; then
            compiler_sha_after=$(shasum -a 256 "$IDOL_PATH" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            compiler_sha_after=$(sha256sum "$IDOL_PATH" | awk '{print $1}')
        fi
        [ -n "$compiler_sha_after" ] || bad 'supplied compiler final SHA-256 could not be recorded'
        [ "$compiler_sha_after" = "$compiler_sha_before" ] \
            || bad "supplied compiler moved during authority probes ($compiler_sha_before -> $compiler_sha_after)"
        limiter_sha_after=''
        if command -v shasum >/dev/null 2>&1; then
            limiter_sha_after=$(shasum -a 256 "$LIMITER" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            limiter_sha_after=$(sha256sum "$LIMITER" | awk '{print $1}')
        fi
        [ -n "$limiter_sha_after" ] || bad 'structured compiler limiter final SHA-256 could not be recorded'
        [ "$limiter_sha_after" = "$limiter_sha_before" ] \
            || bad "structured compiler limiter moved during authority probes ($limiter_sha_before -> $limiter_sha_after)"
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

if [ -n "${compiler_sha_before:-}" ] || [ -n "${compiler_sha_after:-}" ]; then
    printf 'authority gate: compiler expected=%s before=%s after=%s\n' \
        "${IDOL_SHA256:-missing}" "${compiler_sha_before:-missing}" "${compiler_sha_after:-missing}"
fi
if [ -n "${limiter_sha_before:-}" ] || [ -n "${limiter_sha_after:-}" ]; then
    printf 'authority gate: limiter expected=%s before=%s after=%s\n' \
        "${AUTHORITY_LIMITER_SHA256:-missing}" "${limiter_sha_before:-missing}" "${limiter_sha_after:-missing}"
fi

if [ "$violations" -eq 0 ]; then
    printf 'authority gate: PASS (%s file(s)); authority convergence only\n' "$examined"
else
    printf 'authority gate: FAIL (%s violation(s), %s file(s))\n' "$violations" "$examined"
fi
exit "$violations"
