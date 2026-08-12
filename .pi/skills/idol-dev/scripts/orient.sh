#!/bin/sh
# Idol orient — current observed state. Output is orientation evidence, not
# replacement status authority. Read the exact gap files and live claims.
set -eu
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
exec "$repo/tools/devnode/orient"
