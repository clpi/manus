#!/bin/sh
# Rebuild research/archive/pass-2/pass-2-source.tar.gz from a source directory.
#
# The committed archive at e4d45bed is corrupt (truncated gzip). manifest.json
# records the expected SHA-256 (e66fe6cd…) for a complete 25-file corpus.
# Supply a directory containing every manifest file at its original name.
#
# Usage:
#   ./tools/node/dev/rebuild-pass2-archive.sh /path/to/pass-2/sources
#
# On success, writes pass-2-source.tar.gz and prints the digest for gate check.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MANIFEST="$ROOT/research/archive/pass-2/manifest.json"
OUT="$ROOT/research/archive/pass-2/pass-2-source.tar.gz"
SRC=${1:-}

if [ -z "$SRC" ]; then
  printf 'usage: %s <source-directory>\n' "$0" >&2
  printf '  directory must contain all files listed in %s\n' "$MANIFEST" >&2
  exit 64
fi

if [ ! -d "$SRC" ]; then
  printf 'rebuild-pass2-archive: source directory missing: %s\n' "$SRC" >&2
  exit 1
fi

if [ ! -r "$MANIFEST" ]; then
  printf 'rebuild-pass2-archive: manifest missing: %s\n' "$MANIFEST" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'rebuild-pass2-archive: python3 required\n' >&2
  exit 1
fi

python3 - "$SRC" "$MANIFEST" "$OUT" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text())
expected = manifest.get("archive_sha256")
files = manifest.get("files", [])
if not files:
    raise SystemExit("manifest has no files[]")

missing = []
bad = []
names = []
for entry in files:
    name = entry["name"]
    want = entry["sha256"]
    path = src / name
    if not path.is_file():
        missing.append(name)
        continue
    data = path.read_bytes()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((name, want, got))
    names.append(name)

if missing:
    print("rebuild-pass2-archive: missing files:", file=sys.stderr)
    for name in missing:
        print(f"  {name}", file=sys.stderr)
    raise SystemExit(1)
if bad:
    print("rebuild-pass2-archive: digest mismatch:", file=sys.stderr)
    for name, want, got in bad:
        print(f"  {name}: want {want}, got {got}", file=sys.stderr)
    raise SystemExit(1)

names.sort()
cmd = ["tar", "-czf", str(out_path), "-C", str(src)] + names
subprocess.run(cmd, check=True)

digest = hashlib.sha256(out_path.read_bytes()).hexdigest()
size = out_path.stat().st_size
print(f"rebuild-pass2-archive: wrote {out_path} ({size} bytes)")
print(f"rebuild-pass2-archive: sha256 {digest}")
if expected and digest != expected:
    print(
        f"rebuild-pass2-archive: WARN digest != manifest archive_sha256 ({expected})",
        file=sys.stderr,
    )
    raise SystemExit(2)
print("rebuild-pass2-archive: digest matches manifest")
PY
