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
# The two lifecycle states a required frontier may publish. The gate does not
# choose between them — the gap's own status field does, and the block is
# required to AGREE. Requiring OPEN here made closing a gap a repository-wide
# commit block.
LIFECYCLE = ("OPEN", "CLOSED")
BOOTSTRAP = "docs/bootstrap.md"
CONTRACT = "docs/spec/convergence-contract.md"
REQUIRED = (
    "GAP-134",
    "GAP-137",
    "GAP-144",
    "GAP-145",
    "GAP-149",
    "GAP-202",
    "GAP-205",
    "GAP-207",
    "GAP-221",
)
PROJECTION = "gaps/ROOT-PROGRAM.md"
# The projection roster is a structural machine-marker block, not Markdown
# headings: the old `## The two chokepoints` / `## Findings that outrank the
# classification` boundaries were heading syntax and are gone.
ROSTER_BEGIN = "<!-- idol-projection-roster:v1:begin -->"
ROSTER_END = "<!-- idol-projection-roster:v1:end -->"
RECLASSIFIED_ROW = re.compile(r"^\|\s*`(GAP-\d{3})`\s*\|")
GAP_REF = re.compile(r"(GAP-\d{3})`?[ \t]*(\(not P0\))?")
NOT_P0 = "(not P0)"
# The status words that mean WORK IS STILL LIVE. `IN_PROGRESS` was missing, so a
# P0 subject that had been picked up became invisible to the census while the
# roster still dispatched at it — the projection was blamed for naming a gap the
# census had silently dropped. Being worked on is the least retired a gap can be.
# `OWNER-BLOCKED` is the same ruling one step further out: `00c0473d` marked
# GAP-146 blocked on GAP-119 and the census dropped it the same afternoon,
# blocking every lane's commit. Waiting on another owner is not retirement — it
# is live P0 work with a named dependency, which is MORE dispatchable, not less.
# The shape rather than the one word is admitted, so the next `*-BLOCKED`
# spelling (`IMPLEMENTATION-BLOCKED` is already written in this tree) cannot
# repeat the outage. Retirement is CLOSED, SUPERSEDED or REFUTED, and being
# blocked is none of them.
# The status and priority now live in the gap's leading `| field | value |`
# metadata table, not in `**Status:**` / `**Priority:**` header lines.
ACTIVE_STATUS = re.compile(
    r"^[ \t]*"
    r"(OPEN|REOPENED|IN_PROGRESS|(?!(?:CLOSED|SUPERSEDED|REFUTED)-)[A-Z_][A-Z_-]*-BLOCKED)"
    r"([ \t\u00b7(:\u2014]|$)",
    re.IGNORECASE,
)
P0_MARK = re.compile(r"P0", re.IGNORECASE)
ROOT_EDGES = {
    "GAP-134": ("lib/compiler/token.id", "src/parser.zig"),
    "GAP-145": ("lib/compiler/lexer.id", "src/parser.zig"),
}
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


def split_row(line):
    """Split a Markdown table row on unescaped pipes; unescape `\\|`."""
    cells = [
        cell.replace("\x00", "|").strip()
        for cell in line.replace("\\|", "\x00").split("|")
    ]
    if cells and cells[0] == "":
        cells = cells[1:]
    if cells and cells[-1] == "":
        cells = cells[:-1]
    return cells


def is_separator(cells):
    return bool(cells) and all(re.fullmatch(r"-+", cell) for cell in cells)


def field_table(lines):
    """The leading `| field | value |` metadata table as (field, value) pairs.

    Fields are lowercased; only the file's first metadata table is read, so a
    `| field | value |` table buried in the body cannot shadow the header.
    """
    pairs = []
    header_seen = False
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if header_seen:
                break
            continue
        if not stripped.startswith("|"):
            break
        if not header_seen:
            if not re.match(r"^\|\s*field\s*\|", line):
                return []
            header_seen = True
            continue
        cells = split_row(line)
        if len(cells) >= 2 and not is_separator(cells):
            pairs.append((cells[0].strip().lower(), cells[1].strip()))
    return pairs


def section_names(lines):
    """Section names from every `| section |` marker table, in order."""
    names = []
    for i, line in enumerate(lines):
        if re.match(r"^\|\s*section\s*\|", line):
            for row in lines[i + 1:]:
                if not row.strip().startswith("|"):
                    break
                cells = split_row(row)
                if cells and not is_separator(cells):
                    names.append(cells[0].strip())
    return names


def section_anchor(name):
    """The anchor a `| section |` marker table row publishes.

    Same slug rules the old Markdown headings used, so existing
    `superseded_observations` anchors keep resolving.
    """
    slug = name.lower().replace("`", "")
    slug = re.sub(r"[^\w\- ]", "", slug, flags=re.UNICODE)
    return re.sub(r"[ \t]+", "-", slug).strip("-")


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
    first_section = next(
        (i for i, line in enumerate(lines) if re.match(r"^\|\s*section\s*\|", line)),
        len(lines),
    )
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
    # THE METADATA TABLE DECIDES, THE BLOCK AGREES. This asserted OPEN on both
    # faces, so closing a required gap failed the gate and blocked every commit
    # in the repository until someone edited this file — which is the copied-
    # census decay the gate exists to refuse, reproduced by the gate itself.
    # `fe41f1d6` closed GAP-221 and left it on the REQUIRED roster; main was
    # commit-blocked for every lane. The lifecycle is now derived from the one
    # metadata table that states it, and only the AGREEMENT is enforced.
    pairs = field_table(lines[:begin])
    statuses = [value for field, value in pairs if field == "status"]
    if len(statuses) != 1 or not re.match(r"(OPEN|CLOSED)(?![A-Z])", statuses[0]):
        raise FrontierError(
            "metadata must carry exactly one status field naming "
            f"{' or '.join(sorted(LIFECYCLE))}"
        )
    status = "OPEN" if statuses[0].startswith("OPEN") else "CLOSED"
    if frontier["status"] != status:
        raise FrontierError(
            f"frontier status is {frontier['status']} but the metadata "
            f"states {status}; they must agree"
        )

    require_string(frontier["root_program"], "root_program")
    require_string_list(frontier["superseded_observations"], "superseded_observations")
    # A blocker list is the one field the lifecycle inverts. An OPEN frontier
    # with no blocker states nothing; a CLOSED one that still lists a blocker
    # is not closed, and that half-edit is exactly how a closure goes stale.
    if status == "OPEN":
        require_string_list(frontier["current_blockers"], "current_blockers")
    else:
        if frontier["current_blockers"] != []:
            raise FrontierError(
                "a CLOSED frontier must carry no current_blockers"
            )

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

    # Section anchors are published by `| section |` marker tables, not by
    # Markdown headings; the slug rules are unchanged so existing
    # `superseded_observations` anchors keep resolving.
    anchors = {section_anchor(name) for name in section_names(lines)}
    for link in frontier["superseded_observations"]:
        if not link.startswith("#") or link[1:] not in anchors:
            raise FrontierError(f"superseded observation is not a local section link: {link}")


def is_active_p0(meta):
    """meta: dict from the gap's leading `| field | value |` metadata table."""
    status = meta.get("status", "")
    priority = meta.get("priority", "")
    live = bool(ACTIVE_STATUS.match(status))
    p0 = bool(P0_MARK.search(status) or P0_MARK.search(priority))
    return live and p0


def active_p0_set(gaps_dir):
    """The active-P0 census, recomputed here from the gap metadata on disk."""
    active = set()
    seen = 0
    for path in sorted(gaps_dir.glob("GAP-*.md")):
        seen += 1
        lines = path.read_text(encoding="utf-8").splitlines()
        if is_active_p0(dict(field_table(lines))):
            active.add(path.stem)
    if seen == 0:
        raise FrontierError("no GAP-*.md subjects found; census cannot be computed")
    return active


def split_projection(text):
    lines = text.splitlines()
    try:
        begin = next(i for i, line in enumerate(lines) if line.strip() == ROSTER_BEGIN)
        end = next(i for i, line in enumerate(lines) if line.strip() == ROSTER_END)
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
    # while GAP-145 is OPEN, GAP-134 blockers must name it — but only while
    # GAP-134 is itself OPEN. A CLOSED frontier carries no blockers by rule
    # above, so demanding one here would make closing GAP-134 a commit block,
    # which is the same defect this gate just stopped reproducing.
    if (
        frontiers.get("GAP-145", {}).get("status") == "OPEN"
        and frontiers.get("GAP-134", {}).get("status") == "OPEN"
    ):
        if not any(
            "GAP-145" in blocker
            for blocker in frontiers["GAP-134"]["current_blockers"]
        ):
            raise FrontierError(
                "GAP-145 is OPEN, so a GAP-134 blocker must name it"
            )


def assert_no_markdown_structure(text, label):
    """The controls prove the gate no longer reads Markdown structure: no
    sample may carry a heading or list marker outside fenced code."""
    in_fence = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"#{1,6} ", line):
            raise FrontierError(f"{label}: heading marker survived: {line!r}")
        if re.match(r"[ \t]*(?:-|\*|\d+\.) ", line):
            raise FrontierError(f"{label}: list marker survived: {line!r}")


def sample(frontier=None, header="OPEN"):
    value = frontier or {
        "schema": SCHEMA,
        "gap": "GAP-000",
        "status": "OPEN",
        "root_program": "owner -> consumer",
        "current_blockers": ["One current blocker."],
        "superseded_observations": ["#historical-observation"],
    }
    text = "\n".join((
        "| field | value |",
        "|---|---|",
        "| title | GAP-000 — control |",
        f"| status | {header} |",
        "",
        BEGIN,
        "```json",
        json.dumps(value),
        "```",
        END,
        "",
        "| section |",
        "|---|---|",
        "| Historical observation |",
        "",
    ))
    # The positive control is heading-free and list-free: the gate must pass
    # it on structural tables and machine markers alone.
    assert_no_markdown_structure(text, "frontier sample")
    return text


def closed(blockers=None):
    """A CLOSED frontier: the header states it, the block agrees, no blockers."""
    return {
        "schema": SCHEMA,
        "gap": "GAP-000",
        "status": "CLOSED",
        "root_program": "owner -> consumer",
        "current_blockers": [] if blockers is None else blockers,
        "superseded_observations": ["#historical-observation"],
    }


def controls():
    validate_text(sample(), "GAP-000")
    # A CLOSED frontier is ADMITTED, and that is the whole repair: requiring
    # OPEN made a closure fail the gate, so closing a required gap blocked every
    # commit in the repository. The header decides and the block agrees.
    validate_text(sample(closed(), header="CLOSED"), "GAP-000")
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
    # Every HALF-EDIT of a closure is refused, in both directions, because a
    # half-edited closure is how the roster went stale in the first place.
    damaged.append(sample(closed(), header="OPEN"))
    damaged.append(sample(header="CLOSED"))
    damaged.append(sample(closed(["A blocker a closed gap cannot have."]), header="CLOSED"))
    damaged.append(sample(closed(), header="REOPENED"))
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

    return (
        len(damaged)
        + 1
        + projection_controls()
        + order_controls()
        + blocker_controls()
        + census_controls()
    )


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


def census_controls():
    """The census VOCABULARY is pinned here, not just asserted in a comment.

    `IN_PROGRESS` was absent from `ACTIVE_STATUS`, so the one P0 subject carrying
    it (`GAP-146`) dropped out of the active set while `gaps/ROOT-PROGRAM.md`
    still dispatched at it — and the gate blamed the projection for naming a gap
    the census had silently retired. Being worked on is the least retired a gap
    can be. These controls fail closed if that word is ever dropped again.

    The controls run the REAL pipeline — metadata table text through
    field_table into is_active_p0 — on heading-free, list-free samples, so
    they prove the census no longer reads Markdown headers or list markers.
    """
    def meta(status, priority, extra=()):
        rows = []
        if status is not None:
            rows.append(f"| status | {status} |")
        if priority is not None:
            rows.append(f"| priority | {priority} |")
        rows.extend(f"| {field} | {value} |" for field, value in extra)
        text = "\n".join(["| field | value |", "|---|---|"] + rows + [""])
        assert_no_markdown_structure(text, "census control")
        return dict(field_table(text.splitlines()))

    selected = (
        meta("OPEN", "P0"),
        meta("REOPENED", "P0"),
        meta("IN_PROGRESS", "P0"),
        # the exact metadata shape carried by GAP-146 on disk
        meta("IN_PROGRESS", "P0",
             (("filed", "!2026-08-10T12:08:03Z"), ("kind", "regression"))),
        # BLOCKED IS NOT RETIRED. `00c0473d` marked GAP-146 OWNER-BLOCKED on
        # GAP-119 and the census dropped it, so the roster dispatched at a gap
        # the census refused and every lane's commit was blocked. The shape is
        # admitted, not the one word.
        meta("OWNER-BLOCKED", "P0",
             (("filed", "!2026-08-10T12:08:03Z"), ("kind", "regression"))),
        meta("IMPLEMENTATION-BLOCKED", "P0"),
        meta("SEMANTIC-VOCABULARY-BLOCKED", "P0"),
    )
    for index, parsed in enumerate(selected, 1):
        if not is_active_p0(parsed):
            raise FrontierError(
                f"census positive control {index} was not selected"
            )

    rejected = (
        # retired lifecycles are not active, whatever their priority says
        meta("CLOSED", "P0"),
        meta("SUPERSEDED", "P0"),
        meta("REFUTED", "P0"),
        # active lifecycles that are not P0 are not in the active-P0 census
        meta("OPEN", "P1"),
        meta("IN_PROGRESS", "P2"),
        # a longer word that merely STARTS with an active one is not that word
        meta("OPENED", "P0"),
        meta("IN_PROGRESSING", "P0"),
        # a retired lifecycle is retired however it is qualified, and a blocked
        # spelling is only live because BLOCKED is what it says
        meta("CLOSED-BLOCKED", "P0"),
        meta("OWNER-PENDING", "P0"),
        # a subject with no status field at all is not active
        meta(None, "P0"),
    )
    for index, parsed in enumerate(rejected, 1):
        if is_active_p0(parsed):
            raise FrontierError(
                f"census damage control {index} was not rejected"
            )

    return len(selected) + len(rejected)


def projection_sample(roster="`GAP-001`, `GAP-002`", table="| `GAP-003` | CLOSED | x |"):
    text = "\n".join((
        "| field | value |",
        "|---|---|",
        "| title | ROOT-PROGRAM — control |",
        "",
        ROSTER_BEGIN,
        "",
        "| # | directive |",
        "|---|---|",
        "| 1 | Program — " + roster + ". |",
        "",
        ROSTER_END,
        "",
        "| section |",
        "|---|---|",
        "| Reclassified |",
        "",
        table,
        "",
    ))
    # The projection control is heading-free and list-free: the roster
    # boundaries are machine markers, not `##` headings.
    assert_no_markdown_structure(text, "projection sample")
    return text


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
        # the roster boundaries are gone: a Markdown heading is not a boundary
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
