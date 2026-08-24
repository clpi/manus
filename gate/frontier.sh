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
REQUIRED = (
    "GAP-134",
    "GAP-137",
    "GAP-144",
    "GAP-145",
    "GAP-202",
    "GAP-205",
    "GAP-207",
    "GAP-221",
)
PROJECTION = "gaps/ROOT-PROGRAM.md"
ROSTER_BEGIN = "## The two chokepoints"
ROSTER_END = "## Findings that outrank the classification"
RECLASSIFIED_ROW = re.compile(r"^\|\s*`(GAP-\d{3})`\s*\|")
GAP_REF = re.compile(r"(GAP-\d{3})`?[ \t]*(\(not P0\))?")
NOT_P0 = "(not P0)"
ACTIVE_STATUS = re.compile(
    r"^\*\*Status:\*\*[ \t]*(OPEN|REOPENED)([ \t\u00b7(:\u2014-]|$)", re.IGNORECASE
)
ACTIVE_P0 = re.compile(r"^\*\*(Status|Priority):\*\*.*P0", re.IGNORECASE)
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


def is_active_p0(header):
    lines = header.splitlines()
    status = any(ACTIVE_STATUS.match(line) for line in lines)
    p0 = any(ACTIVE_P0.match(line) for line in lines)
    return status and p0


def active_p0_set(gaps_dir):
    """The active-P0 census, recomputed here from the gap headers on disk."""
    active = set()
    seen = 0
    for path in sorted(gaps_dir.glob("GAP-*.md")):
        seen += 1
        header = "\n".join(path.read_text(encoding="utf-8").splitlines()[:8])
        if is_active_p0(header):
            active.add(path.stem)
    if seen == 0:
        raise FrontierError("no GAP-*.md subjects found; census cannot be computed")
    return active


def split_projection(text):
    lines = text.splitlines()
    try:
        begin = next(i for i, line in enumerate(lines) if line.startswith(ROSTER_BEGIN))
        end = next(i for i, line in enumerate(lines) if line.startswith(ROSTER_END))
    except StopIteration:
        raise FrontierError(
            f"projection is missing its roster boundaries "
            f"({ROSTER_BEGIN!r} .. {ROSTER_END!r})"
        ) from None
    if begin >= end:
        raise FrontierError("projection roster boundaries are reversed")
    return lines[begin:end], lines


def validate_projection(text, active, present):
    """The projection may not dispatch at work the gap headers no longer select."""
    roster_lines, lines = split_projection(text)

    roster = {}
    for line in roster_lines:
        for ref, exempt in GAP_REF.findall(line):
            roster[ref] = roster.get(ref, False) or bool(exempt)
    if not roster:
        raise FrontierError("projection roster names no gap; it examines nothing")

    reclassified = []
    for line in lines:
        match = RECLASSIFIED_ROW.match(line)
        if match:
            reclassified.append(match.group(1))
    if not reclassified:
        raise FrontierError("projection reclassification table has no rows")

    for ref in sorted(set(roster) | set(reclassified)):
        if ref not in present:
            raise FrontierError(f"projection names a gap with no file: {ref}")

    for ref, exempt in sorted(roster.items()):
        if exempt:
            if ref in active:
                raise FrontierError(
                    f"projection marks {ref} '{NOT_P0}' but the census still selects it"
                )
            continue
        if ref not in active:
            raise FrontierError(
                f"projection dispatches at {ref}, which the active-P0 census no "
                f"longer selects"
            )

    for ref in sorted(set(reclassified)):
        if ref in active:
            raise FrontierError(
                f"projection reports {ref} reclassified while the census still "
                f"selects it"
            )

    return len(roster) + len(set(reclassified))


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

    return len(damaged) + 1 + projection_controls()


def projection_sample(roster="`GAP-001`, `GAP-002`", table="| `GAP-003` | CLOSED | x |"):
    return "\n".join((
        "# ROOT-PROGRAM — control",
        "",
        ROSTER_BEGIN,
        "",
        "**1 Program** — " + roster + ".",
        "",
        ROSTER_END,
        "",
        "## Reclassified",
        "",
        table,
        "",
    ))


def projection_controls():
    active = {"GAP-001", "GAP-002"}
    present = {"GAP-001", "GAP-002", "GAP-003"}
    validate_projection(projection_sample(), active, present)
    validate_projection(
        projection_sample(roster="`GAP-001`, `GAP-004` (not P0)"),
        active,
        present | {"GAP-004"},
    )

    damaged = [
        # a roster entry the census no longer selects
        (projection_sample(roster="`GAP-001`, `GAP-003`"), active, present),
        # a roster entry with no file at all
        (projection_sample(roster="`GAP-001`, `GAP-999`"), active, present),
        # a reclassified gap the census still selects
        (projection_sample(table="| `GAP-002` | CLOSED | x |"), active, present),
        # a roster entry marked (not P0) that the census does select
        (projection_sample(roster="`GAP-001` (not P0)"), active, present),
        # an empty roster examines nothing
        (projection_sample(roster="nothing"), active, present),
        # an empty reclassification table examines nothing
        (projection_sample(table="no rows here"), active, present),
        # the roster boundaries are gone
        (projection_sample().replace(ROSTER_BEGIN, "## renamed"), active, present),
    ]
    for index, (text, act, pres) in enumerate(damaged, 1):
        try:
            validate_projection(text, act, pres)
        except FrontierError:
            continue
        raise FrontierError(f"projection damage control {index} was not rejected")
    return len(damaged) + 2


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

    gaps_dir = root / "gaps"
    active = active_p0_set(gaps_dir)
    present = {path.stem for path in gaps_dir.glob("GAP-*.md")}
    projection_path = root / PROJECTION
    if not projection_path.is_file():
        raise FrontierError(f"required subject is absent: {PROJECTION}")
    rows = validate_projection(
        projection_path.read_text(encoding="utf-8"), active, present
    )
    if rows == 0:
        raise FrontierError("projection was not examined")

    print(
        f"frontier gate: PASS ({checked} gap(s), "
        f"{rows} projection row(s) against {len(active)} active-P0 gap(s))"
    )


try:
    main()
except FrontierError as error:
    print(f"frontier gate: BLOCKED — {error}", file=sys.stderr)
    sys.exit(1)
PY
