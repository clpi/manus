#!/bin/sh
# Restore the exact historical container from manifest-verified original inputs.
# This is a foreign archive boundary, not semantic law or a compiler producer.
# --check verifies reproducibility without replacing the repository archive.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MANIFEST="$ROOT/research/archive/pass-2/manifest.json"
OUT="$ROOT/research/archive/pass-2/pass-2-source.tar.gz"
CHECK=false
if [ "$#" -gt 0 ] && [ "$1" = "--check" ]; then
    CHECK=true
    shift
fi
if [ "$#" -ne 1 ]; then
    printf 'usage: %s [--check] <source-directory>\n' "$0" >&2
    exit 64
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf 'rebuild-pass2-archive: python3 required\n' >&2
    exit 1
fi

python3 - "$1" "$MANIFEST" "$OUT" "$CHECK" <<'PY'
import gzip
import hashlib
import io
import json
import os
import sys
import tarfile
import tempfile
from pathlib import Path


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate manifest key: {key}")
        result[key] = value
    return result


src = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
try:
    manifest = json.loads(manifest_path.read_text(), object_pairs_hook=unique)
    rows = manifest["files"]
    if not rows or not src.is_dir():
        raise ValueError("source directory or manifest files are missing")
    contents = {}
    for row in rows:
        name = row["name"]
        if (not isinstance(name, str) or name in {"", ".", ".."}
                or "/" in name or "\\" in name or name in contents):
            raise ValueError(f"unsafe or duplicate source filename: {name}")
        data = (src / name).read_bytes()
        if len(data) != row["bytes"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
            raise ValueError(f"source bytes differ from manifest: {name}")
        contents[name] = data

    # Neither input timestamps/permissions nor host tar/gzip defaults own the
    # archived bytes. Keep both names of duplicate inputs, in stable order.
    packed = io.BytesIO()
    with tarfile.open(fileobj=packed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, data in sorted(contents.items()):
            member = tarfile.TarInfo(name)
            member.size = len(data)
            member.mode = 0o644
            member.uid = member.gid = member.mtime = 0
            member.uname = member.gname = ""
            archive.addfile(member, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed,
                       compresslevel=9, mtime=0) as stream:
        stream.write(packed.getvalue())
    candidate = compressed.getvalue()
    digest = hashlib.sha256(candidate).hexdigest()
    if len(candidate) != manifest["archive_bytes"] or digest != manifest["archive_sha256"]:
        raise ValueError("rebuilt container differs from the exact manifest identity")

    if sys.argv[4] != "true":
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".pass2-", dir=out_path.parent,
                                             delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(candidate)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), 0o644)
            os.replace(temporary, out_path)
            temporary = None
        finally:
            if temporary is not None:
                temporary.unlink()
    action = "verified" if sys.argv[4] == "true" else "restored"
    print(f"rebuild-pass2-archive: {action} exact archive ({len(candidate)} bytes) sha256={digest}")
except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
    print(f"rebuild-pass2-archive: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
