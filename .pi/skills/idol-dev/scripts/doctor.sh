#!/bin/sh
# Idol doctor — pre-agent admission check. Rejects stale artifacts, wrong tool
# versions, missing generated projections, missing credentials, dead MCP
# servers, and broken gates. Run before any substantive agent work.
set -eu
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
exec "$repo/tools/devnode/doctor"
