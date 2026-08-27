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
BOOTSTRAP = "docs/bootstrap.md"
CONTRACT = "docs/spec/convergence-contract.md"
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
ROOT_EDGES = {
    "GAP-134": ("lib/compiler/token.id", "src/parser.zig"),
    "GAP-145": ("lib/compiler/lexer.id", "src/parser.zig"),
}
STATUS_HEADER = re.compile(r"^\*\*Status:\*\*[ \t]+([A-Z]+)", re.MULTILINE)
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

    if expected_gap in ROOT_EDGES:
        first, last = ROOT_EDGES[expected_gap]
        if not frontier["root_program"].startswith(first):
            raise FrontierError(
                f"root_program must start at the grammar owner {first}"
            )
        if not frontier["root_program"].endswith(last):
            raise FrontierError(
                f"root_program must end at the parser consumer {last}"
            )

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


def validate_order(text, source, steps):
    flat = re.sub(r"\s+", " ", text)
    chain = " -> ".join(steps)
    pattern = r".*?".join(re.escape(step) for step in steps)
    if re.search(pattern, flat):
        return
    raise FrontierError(f"{source} is missing critical-path order: {chain}")


def validate_blockers(frontiers):
    """No blocker may reference a gap whose frontier is no longer OPEN."""
    for gap, frontier in sorted(frontiers.items()):
        for blocker in frontier["current_blockers"]:
            for ref in re.findall(r"GAP-\d{3}", blocker):
                if ref == gap:
                    continue
                other = frontiers.get(ref)
                if other is not None and other["status"] != "OPEN":
                    raise FrontierError(
                        f"{gap} blocker cites {ref} as blocking, but its "
                        f"frontier status is {other['status']}"
                    )
    # while GAP-145 is OPEN, GAP-134 blockers must name it
    if (
        frontiers.get("GAP-145", {}).get("status") == "OPEN"
        and frontiers.get("GAP-134") is not None
    ):
        if not any(
            "GAP-145" in blocker
            for blocker in frontiers["GAP-134"]["current_blockers"]
        ):
            raise FrontierError(
                "GAP-145 is OPEN, so a GAP-134 blocker must name it"
            )


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

    # root-edge discipline: GAP-134 must start at lib/compiler/token.id
    # and end at src/parser.zig; damage each edge independently
    edge_sample = {
        "schema": SCHEMA,
        "gap": "GAP-134",
        "status": "OPEN",
        "root_program": "lib/compiler/token.id -> src/parser.zig",
        "current_blockers": ["One current blocker."],
        "superseded_observations": ["#historical-observation"],
    }

    for index, text in enumerate(damaged, 1):
        try:
            validate_text(text, "GAP-000")
        except FrontierError:
            continue
        raise FrontierError(f"damage control {index} was not rejected")

    # root-edge controls carry their own gap identity, so they are validated
    # with the expected gap they name and one intact positive control
    validate_text(sample(edge_sample), "GAP-134")
    edge_damaged = [
        sample(edge_sample).replace("lib/compiler/token.id", "src/dump.c"),
        sample(edge_sample).replace("src/parser.zig", "src/pretty.zig"),
    ]
    for index, text in enumerate(edge_damaged, 1):
        try:
            validate_text(text, "GAP-134")
        except FrontierError:
            continue
        raise FrontierError(f"root edge damage control {index} was not rejected")

    return len(damaged) + 1 + projection_controls() + order_controls() + blocker_controls()


def blocker_sample(gap="GAP-000", status="OPEN", blockers=None):
    return {
        "schema": SCHEMA,
        "gap": gap,
        "status": status,
        "root_program": "owner -> consumer",
        "current_blockers": blockers or ["One current blocker."],
        "superseded_observations": ["#historical-observation"],
    }


def blocker_controls():
    # intact: GAP-134 cites the still-open GAP-145
    validate_blockers({
        "GAP-134": blocker_sample(
            "GAP-134", blockers=["GAP-145 remains OPEN."]
        ),
        "GAP-145": blocker_sample("GAP-145"),
    })

    # damaged: GAP-134 cites a gap whose frontier is CLOSED
    try:
        validate_blockers({
            "GAP-134": blocker_sample(
                "GAP-134", blockers=["GAP-145 remains OPEN."]
            ),
            "GAP-145": blocker_sample("GAP-145", status="CLOSED"),
        })
    except FrontierError:
        pass
    else:
        raise FrontierError("blocker damage control 1 was not rejected")

    # damaged: GAP-145 is OPEN but no GAP-134 blocker names it
    try:
        validate_blockers({
            "GAP-134": blocker_sample("GAP-134"),
            "GAP-145": blocker_sample("GAP-145"),
        })
    except FrontierError:
        pass
    else:
        raise FrontierError("blocker discipline damage control was not rejected")

    return 3


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


def order_controls():
    # bootstrap chain: GAP-145 -> GAP-134 -> parser
    validate_order(
        "source-family -> GAP-145 -> GAP-134 -> parser",
        "control",
        ("GAP-145", "GAP-134", "parser"),
    )
    damaged = [
        "source-family -> GAP-134 -> GAP-145 -> parser",
        "source-family -> GAP-145 -> parser",
    ]
    for index, text in enumerate(damaged, 1):
        try:
            validate_order(text, "control", ("GAP-145", "GAP-134", "parser"))
        except FrontierError:
            continue
        raise FrontierError(f"order damage control {index} was not rejected")

    # contract chain: all four stages, each absent step is one damage
    contract_steps = (
        "GAP-145 lexical",
        "GAP-134 grammar roles",
        "parser recognition",
        "graph",
    )
    intact = (
        "GAP-145 lexical identity -> GAP-134 grammar roles -> "
        "parser recognition -> graph facts"
    )
    validate_order(intact, "control", contract_steps)
    contract_damaged = []
    for drop in contract_steps:
        keep = [step for step in contract_steps if step != drop]
        flat = " -> ".join(keep)
        contract_damaged.append(flat)
    for index, text in enumerate(contract_damaged, 1):
        try:
            validate_order(text, "control", contract_steps)
        except FrontierError:
            continue
        raise FrontierError(f"contract order damage control {index} was not rejected")
    return len(damaged) + len(contract_damaged) + 2


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
    frontiers = {}
    for gap in REQUIRED:
        path = root / "gaps" / f"{gap}.md"
        if not path.is_file():
            raise FrontierError(f"required subject is absent: {path.relative_to(root)}")
        text = path.read_text(encoding="utf-8")
        validate_text(text, gap)
        block = text.split(BEGIN, 1)[1].split(END, 1)[0]
        frontiers[gap] = json.loads(
            re.search(r"```json\s*(.*?)\s*```", block, re.S).group(1)
        )
        checked += 1
    if checked != len(REQUIRED) or checked == 0:
        raise FrontierError("required frontier subject set was not examined")
    validate_blockers(frontiers)

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

    bootstrap_path = root / BOOTSTRAP
    if not bootstrap_path.is_file():
        raise FrontierError(f"required subject is absent: {BOOTSTRAP}")
    validate_order(
        bootstrap_path.read_text(encoding="utf-8"),
        BOOTSTRAP,
        ("GAP-145", "GAP-134", "parser"),
    )

    contract_path = root / CONTRACT
    if not contract_path.is_file():
        raise FrontierError(f"required subject is absent: {CONTRACT}")
    validate_order(
        contract_path.read_text(encoding="utf-8"),
        CONTRACT,
        ("GAP-145 lexical", "GAP-134 grammar roles", "parser recognition", "graph"),
    )

    print(
        f"frontier gate: PASS ({checked} gap(s), "
        f"{rows} projection row(s) against {len(active)} active-P0 gap(s), "
        f"critical path order checked in {BOOTSTRAP} and {CONTRACT}, "
        f"blocker discipline over {len(frontiers)} frontier block(s))"
    )


try:
    main()
except FrontierError as error:
    print(f"frontier gate: BLOCKED — {error}", file=sys.stderr)
    sys.exit(1)
PY
