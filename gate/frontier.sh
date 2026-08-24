#!/bin/sh
# gate/frontier.sh — fail closed on missing or ambiguous current gap frontiers.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

exec python3 - "$root" "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

SCHEMA = "idol.gap.frontier.v1"
BEGIN = "<!-- idol-gap-frontier:v1:begin -->"
END = "<!-- idol-gap-frontier:v1:end -->"
REQUIRED = ("GAP-134", "GAP-137", "GAP-145", "GAP-202", "GAP-205")
KEYS = {
    "schema",
    "gap",
    "status",
    "root_program",
    "current_blockers",
    "superseded_observations",
}


class FrontierError(ValueError):
    pass


def heading_anchor(line):
    heading = re.sub(r"^#{1,6}[ \t]+", "", line.rstrip())
    heading = heading.lower().replace("`", "")
    heading = re.sub(r"[^\w\- ]", "", heading, flags=re.UNICODE)
    return re.sub(r"[ \t]+", "-", heading).strip("-")


def require_string(value, field):
    if not isinstance(value, str) or not value.strip():
        raise FrontierError(f"{field} must be a non-empty string")


def require_string_list(value, field):
    if not isinstance(value, list) or not value:
        raise FrontierError(f"{field} must be a non-empty array")
    for entry in value:
        require_string(entry, field)
    if len(value) != len(set(value)):
        raise FrontierError(f"{field} contains duplicate entries")


def validate_text(text, expected_gap):
    lines = text.splitlines()
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise FrontierError("frontier markers must occur exactly once")

    begin = lines.index(BEGIN)
    end = lines.index(END)
    if begin >= end:
        raise FrontierError("frontier markers are reversed")
    if begin >= 12:
        raise FrontierError("frontier block must begin within the top 12 lines")
    first_section = next((i for i, line in enumerate(lines) if line.startswith("## ")), len(lines))
    if begin >= first_section:
        raise FrontierError("frontier block must precede the first section")

    body = lines[begin + 1:end]
    if len(body) < 3 or body[0] != "```json" or body[-1] != "```":
        raise FrontierError("frontier markers must contain one fenced JSON object")
    try:
        frontier = json.loads("\n".join(body[1:-1]))
    except json.JSONDecodeError as error:
        raise FrontierError(f"frontier JSON is invalid: {error.msg}") from error

    if not isinstance(frontier, dict) or set(frontier) != KEYS:
        raise FrontierError("frontier JSON must contain exactly the v1 fields")
    if frontier["schema"] != SCHEMA:
        raise FrontierError(f"schema must be {SCHEMA}")
    if frontier["gap"] != expected_gap:
        raise FrontierError(f"gap must be {expected_gap}")
    if frontier["status"] != "OPEN":
        raise FrontierError("status must be OPEN")
    status_headers = re.findall(
        r"^\*\*Status:\*\*[ \t]+([A-Z]+)",
        "\n".join(lines[:begin]),
        flags=re.MULTILINE,
    )
    if status_headers != ["OPEN"]:
        raise FrontierError("frontier status disagrees with an unambiguous OPEN prose header")

    require_string(frontier["root_program"], "root_program")
    require_string_list(frontier["current_blockers"], "current_blockers")
    require_string_list(frontier["superseded_observations"], "superseded_observations")

    anchors = {
        heading_anchor(line)
        for line in lines
        if re.match(r"^#{1,6}[ \t]+", line)
    }
    for link in frontier["superseded_observations"]:
        if not link.startswith("#") or link[1:] not in anchors:
            raise FrontierError(f"superseded observation is not a local heading link: {link}")


def sample(frontier=None):
    value = frontier or {
        "schema": SCHEMA,
        "gap": "GAP-000",
        "status": "OPEN",
        "root_program": "owner -> consumer",
        "current_blockers": ["One current blocker."],
        "superseded_observations": ["#historical-observation"],
    }
    return "\n".join((
        "# GAP-000 — control",
        "",
        "**Status:** OPEN",
        "",
        BEGIN,
        "```json",
        json.dumps(value),
        "```",
        END,
        "",
        "## Historical observation",
        "",
    ))


def controls():
    validate_text(sample(), "GAP-000")
    damaged = []
    damaged.append(sample().replace(BEGIN, ""))
    damaged.append(sample().replace(BEGIN, BEGIN + "\n" + BEGIN))

    empty = json.loads(json.dumps({
        "schema": SCHEMA,
        "gap": "GAP-000",
        "status": "OPEN",
        "root_program": "owner -> consumer",
        "current_blockers": [],
        "superseded_observations": ["#historical-observation"],
    }))
    damaged.append(sample(empty))
    damaged.append(sample().replace("#historical-observation", "#absent-observation"))
    damaged.append(sample().replace('"status": "OPEN"', '"status": "CLOSED"'))

    for index, text in enumerate(damaged, 1):
        try:
            validate_text(text, "GAP-000")
        except FrontierError:
            continue
        raise FrontierError(f"damage control {index} was not rejected")
    return len(damaged) + 1


def main():
    root = Path(sys.argv[1])
    args = sys.argv[2:]
    if args == ["--selftest"]:
        count = controls()
        print(f"frontier controls: PASS ({count} control(s))")
        return
    if args:
        raise FrontierError(f"unknown argument: {' '.join(args)}")

    checked = 0
    for gap in REQUIRED:
        path = root / "gaps" / f"{gap}.md"
        if not path.is_file():
            raise FrontierError(f"required subject is absent: {path.relative_to(root)}")
        validate_text(path.read_text(encoding="utf-8"), gap)
        checked += 1
    if checked != len(REQUIRED) or checked == 0:
        raise FrontierError("required frontier subject set was not examined")
    print(f"frontier gate: PASS ({checked} gap(s))")


try:
    main()
except FrontierError as error:
    print(f"frontier gate: BLOCKED — {error}", file=sys.stderr)
    sys.exit(1)
PY
