#!/bin/sh
# gate/application.sh — WHY each unpublished application candidate is
# unpublished, by CAUSE, over the same corpus `gate/coverage.sh` measures.
#
# WHAT THIS ANSWERS THAT `gate/coverage.sh` DOES NOT. Coverage reports one
# ratio — published / candidates — and a three-way split of the remainder into
# `published`, `bootstrap` and `blocking`. Those three are OUTCOMES, not
# causes. `bootstrap` and `blocking` are the SAME missing fact wearing two
# downstream faces: whether some spelling roster happens to lower the site
# anyway. Ranking work off that split ranks the roster, not the gap.
#
# WHAT A CAUSE IS HERE. One repair. Two rows share a cause when one change
# closes both, and they get different rows when they do not — which is why
# `s:len()` and `x:floor()` are ONE row (neither names a declared relation)
# while `t:concat(sep)` is a DIFFERENT row (`lib/table.id` declares `concat`;
# the roster answers first and the declaration is never reached).
#
# `host-relation-name-declared-in-home` IS AN UPPER BOUND AND NOT A WORK ITEM.
# It says a relation OF THAT NAME is declared in a home `subjectFirstForeignRelation`
# searches, and that `methodCallResolved` answered before the search could run.
# It does NOT say the declaration is the right one for the subject: `lib/table.id`
# declares `len`, and 1883 of this row's sites are `s:len()` on TEXT. Whether a
# site is reorder-reachable needs subject conformance, which this classifier does
# not compute and must not pretend to.
#
# IT AGREES WITH `gate/coverage.sh` BY CONSTRUCTION. The totals line reprints
# `fact_coverage` summed over the same lift, so a drift between the two
# instruments is visible in this gate's own output rather than inferred.
#
# THE CLASSIFIER IS NOT THE COMPILER, and says so. It reads the graph export's
# `unresolved_applications` / `blocking_applications` — exact node ids the
# compiler minted — and then attributes each site by reading the SOURCE at the
# node's own line/column. That second half is a spelling reading, and a
# spelling reading is exactly what this project distrusts. It is admissible
# HERE and nowhere downstream for one reason: nothing consumes this output but
# a human ranking work. No compiler phase may read it, and no fact it prints
# is published anywhere. The `unattributed` row is the honesty column: a site
# the reader cannot parse is counted as its own cause, never folded into a
# neighbouring one.
#
# ═══ WHY THIS FILE REFUSES INSTEAD OF PRINTING AN EMPTY TABLE ══════════════
#
# THIS GATE SHIPPED VACUOUS AND `gate/vacuity.sh` CONVICTED IT. Under the
# HOLLOW plant — a compiler that runs, exits 0 and answers nothing, beside
# empty `examples/` and `lib/` homes — every step below succeeded and the gate
# exited 0 on the line `reporting only (… measured 0)`. Nothing had been
# measured. `find` matched no file, the lift loop ran zero times, the
# classifier read an empty export list, and a histogram over no sites printed
# as a histogram with no findings. That is this repository's one recurring
# defect: ABSENCE OF A SUBJECT INDISTINGUISHABLE FROM ABSENCE OF A VIOLATION.
#
# It matters more here than in a lexical firewall, because this gate is the
# instrument behind a published coverage claim and a published cause ranking.
# A vacuous run does not merely fail to find work; it certifies a wall it never
# looked at.
#
# So four SUBJECT FLOORS are asserted, each naming a distinct thing that must
# exist before any number below it means anything:
#
#   1. every named corpus root RESOLVES        (a skipped root is a smaller corpus
#                                               reported under the same name)
#   2. the corpus enumerates at least one `.id`
#   3. at least one file LIFTS to a graph export
#   4. the lifted exports PARSE, and `fact_coverage` reports at least one
#      application CANDIDATE — the denominator of the ratio this gate prints
#
# WHAT IS DELIBERATELY NOT A FLOOR: the size of the histogram. Requiring
# unpublished sites to exist would be a control that needs the defect to
# survive, and it would turn red the day the wall closes — the gate would be
# unturnable-green and then permanently unturnable-red, which is the same lie
# with the sign flipped. Zero unpublished candidates over a real corpus with a
# real denominator is a legitimate clean answer, and this gate reports it.
# What may never be legitimate is zero SUBJECTS.
set -u
repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64
idol=${IDOL:-$repo/zig-out/bin/idol}
corpus=${COVERAGE_CORPUS:-examples lib}
budget=${APPLICATION_BUDGET:-}
[ -x "$idol" ] || { echo "application: no compiler at $idol (set IDOL=)" >&2; exit 64; }
command -v python3 >/dev/null 2>&1 || { echo "application: python3 absent" >&2; exit 64; }
work=$(mktemp -d -t idolapplication) || exit 64
trap 'rm -rf "$work"' EXIT INT TERM

# FLOOR 1. A named root that does not resolve is not an empty root — it is a
# census silently taken over a different corpus than the one it names, and the
# totals line claims agreement with `gate/coverage.sh` over exactly this list.
#
# NO `2>/dev/null` ON THE ENUMERATION. Item 1 on `gate/vacuity.sh`'s list of
# convicted instruments is a swept-away `find` error read downstream as a count
# of zero. `find` returns non-zero when any path errored, so the status is the
# answer and the diagnostic stays on stderr where a reader can see it.
: > "$work/corpus.raw"
for root in $corpus; do
  [ -d "$root" ] || {
    printf 'application: corpus root %s does not resolve — a census that skips a named root reports a smaller corpus under the same name\n' "$root" >&2
    exit 64
  }
  find "$root" -name '*.id' -type f >> "$work/corpus.raw" || {
    printf 'application: enumeration under %s errored — an enumeration that failed is not an empty corpus\n' "$root" >&2
    exit 64
  }
done
# AND THE SORT IS GUARDED TOO. `sort` can emit part of its input and then fail
# — a full temp volume is the ordinary way — and its status is the last one in
# this pipeline, so an unguarded `sort` hands the loop below a TRUNCATED corpus
# with `n` and `lifted` both comfortably positive. No floor below can see that,
# because a smaller corpus is exactly what a smaller corpus looks like.
sort < "$work/corpus.raw" > "$work/corpus" || {
  printf 'application: ordering the corpus failed — a partial list is not the corpus, and every count below it would be taken over the part that survived
' >&2
  exit 64
}

: > "$work/exports"
lifted=0; refused=0; n=0; firstrefused=''; firstsay=''
while IFS= read -r src; do
  n=$((n + 1))
  out="$work/$n.json"
  if "$idol" graph "$src" > "$out" 2>"$work/say" && [ -s "$out" ]; then
    printf '%s\t%s\n' "$src" "$out" >> "$work/exports"
    lifted=$((lifted + 1))
  else
    # THE FIRST REFUSAL IS QUOTED. A systemic refusal — a compiler that
    # answers nothing for every input — and a corpus with a few known-hard
    # files produce the same counter, and only the diagnostic separates them.
    # Kept to one line, because the count it sits beside is whatever
    # `sh gate/application.sh` reports today and is not written down here.
    if [ -z "$firstrefused" ]; then
      firstrefused=$src
      firstsay=$(tr -d '\r' < "$work/say" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-96)
    fi
    rm -f "$out"
    refused=$((refused + 1))
  fi
done < "$work/corpus"

printf 'gate/application.sh: corpus %s file(s) under [%s]; %s lifted, %s refused\n' \
  "$n" "$corpus" "$lifted" "$refused"
[ -z "$firstrefused" ] || printf 'gate/application.sh: first refusal %s: %s\n' \
  "$firstrefused" "${firstsay:-(silent)}"

# FLOOR 2 and FLOOR 3, before a single number is printed. A table computed over
# no file is not a clean table.
if [ "$n" -eq 0 ]; then
  printf 'application: enumerated ZERO .id file(s) under [%s] — a scan with no subject is not a clean sweep\n' "$corpus" >&2
  exit 64
fi
if [ "$lifted" -eq 0 ]; then
  printf 'application: %s corpus file(s) and NOT ONE lifted to a graph export — the classifier would attribute nothing and call it agreement\n' "$n" >&2
  exit 64
fi

APPLICATION_HOMES="c iter math meta os result string table testing io" \
APPLICATION_RATCHET="$work/ratchet" \
APPLICATION_SITES="${APPLICATION_SITES:-}" \
python3 - "$work/exports" "$repo" <<'PY'
import json, os, re, sys, collections

exports, repo = sys.argv[1], sys.argv[2]

# The homes `Sema.foreign_module_homes` searches for a subject-first relation
# whose subject names no home of its own. Read from the environment so the
# roster this gate compares against is a visible input, not a second copy of a
# list that lives in `src/sema.zig`.
HOMES = os.environ["APPLICATION_HOMES"].split()

# `native_bootstrap.methodApplication`'s subject-first faces, plus the stream
# roster. Membership changes nothing about the CAUSE — every name here is a
# relation with no declaration — it only separates "already lowered by a
# spelling" from "not lowered at all", which is the outcome column.
DECL = re.compile(r'^([a-z][a-z0-9_]*)\s*(?::[^=]*?)?=\s*\(')
IDENT = re.compile(r'[A-Za-z0-9_.]')

declared = collections.defaultdict(set)
for h in HOMES:
    p = os.path.join(repo, "lib", h + ".id")
    if not os.path.exists(p):
        continue
    for line in open(p, encoding="utf-8", errors="replace"):
        m = DECL.match(line)
        if m:
            declared[m.group(1)].add(h)

src_cache = {}
def source(f):
    if f not in src_cache:
        src_cache[f] = open(os.path.join(repo, f), encoding="utf-8",
                            errors="replace").read().split("\n")
    return src_cache[f]

def home_file(f, home):
    """`home_resolve.resolve`'s search order, for the question `is there a
    module behind this spelling`. Sibling of the referring file, project root,
    `lib/`. A miss here is the same miss the compiler makes."""
    p = home.replace(".", "/")
    d = os.path.dirname(os.path.join(repo, f))
    for base in (d, repo, os.path.join(repo, "lib")):
        for cand in (os.path.join(base, p + ".id"), os.path.join(base, p, "init.id")):
            if os.path.exists(cand):
                return True
    return False

def assign_target(text, col):
    """True when the `(` at `col` closes onto a single `=`. `x(i) = v` cannot be
    an application in any reading — nothing assigns to an application result —
    so the parentheses are projection, which `docs/spec/law.md` §5 gives to
    `[]`: "`()` is ordinary application. It never means table indexing."."""
    i = col - 1
    if i >= len(text) or text[i] != '(':
        return False
    depth = 0
    while i < len(text):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                r = text[i + 1:].lstrip()
                while r[:1] in ('.', '['):
                    m = re.match(r'^(\.[A-Za-z0-9_]+|\[[^\]]*\])', r)
                    if not m:
                        break
                    r = r[m.end():].lstrip()
                return r.startswith('=') and not r.startswith('==')
        i += 1
    return False

def read_site(f, line, col):
    L = source(f)
    if not line or line - 1 >= len(L):
        return None
    s = L[line - 1]
    i = col - 1
    if i < 0 or i >= len(s):
        return None
    anchor = s[i]
    meth = None
    if anchor == ':':
        e = i + 1
        while e < len(s) and IDENT.match(s[e]):
            e += 1
        meth = s[i + 1:e]
    j = i - 1
    while j >= 0 and s[j] in ' \t':
        j -= 1
    if j >= 0 and s[j] in ')]}':
        head = '<computed>'
    else:
        e = j + 1
        while j >= 0 and IDENT.match(s[j]):
            j -= 1
        head = s[j + 1:e] or None
    return anchor, head, meth, s

tot = collections.Counter()
hist = collections.Counter()
faces = collections.Counter()
homes_seen = collections.Counter()
names = collections.defaultdict(collections.Counter)
sites = open(os.environ["APPLICATION_SITES"], "w") if os.environ.get("APPLICATION_SITES") else None

parsed = 0
unparsed = []
for row in open(exports):
    f, path = row.rstrip("\n").split("\t")
    try:
        d = json.load(open(path))
    except Exception as e:
        # AN EXPORT THAT LIFTED AND THEN DID NOT PARSE IS NOT A FILE WITH NO
        # FINDINGS. The shell counted it as `lifted`, so dropping it here makes
        # the reported denominator larger than the set actually classified.
        unparsed.append((f, "%s: %s" % (type(e).__name__, e)))
        continue
    parsed += 1
    for k, v in d.get("fact_coverage", {}).items():
        tot[k] += v
    nodes = {x["id"]: x for x in d["nodes"]}
    blocking = set(d.get("blocking_applications", []))
    funcs = set(x.get("name") for x in d["nodes"]
                if x["kind"] == "func" and x.get("name"))
    binds = set(x.get("name") for x in d["nodes"]
                if x["kind"] in ("local", "param") and x.get("name"))
    for cid in d.get("unresolved_applications", []):
        node = nodes.get(cid)
        outcome = "blocking" if cid in blocking else "bootstrap"
        if node is None:
            # A NODE ID THE COMPILER MINTED AND THE EXPORT DID NOT CARRY. The
            # site exists — `unresolved_applications` named it — so dropping it
            # would shrink this table below the count the compiler published,
            # silently. It goes to the honesty column with its own note.
            hist["unattributed"] += 1
            faces[("unattributed", outcome)] += 1
            names["unattributed"]["<no-node>"] += 1
            if sites is not None:
                sites.write("%s\t-\t-\tunattributed\t%s\n" % (f, outcome))
            continue
        site = read_site(f, node.get("line"), node.get("col"))
        note = ""
        if site is None:
            cause = "unattributed"
        else:
            anchor, head, meth, text = site
            if anchor == '@':
                cause, note = "comptime-directive", "@"
            elif anchor == ':':
                note = meth
                if meth in funcs:
                    cause = "local-relation-unpublished"
                elif meth in declared:
                    cause = "host-relation-name-declared-in-home"
                else:
                    cause = "host-relation-no-entity"
            elif head is None:
                cause = "unattributed"
            elif head == '<computed>':
                # A COMPUTED CALLEE FOLLOWED BY `=` IS A CURRIED DECLARATION,
                # not a projection. `to(micron)(inch) = stretch@exact` and
                # `eq(i64)(f64) = eq_f64_i64@lossless` are conversion-edge
                # DECLARATIONS whose second curry level is the assignment's
                # left side, and rewriting their parentheses to brackets makes
                # `examples/compile_fail/relation_lossy_compose.id` — a fixture
                # that exists to be refused — compile clean. Measured: 26 sites,
                # every one of them a declaration. The projection row therefore
                # admits a NAME or a dotted name and nothing else.
                cause, note = "callee-is-a-value", "<computed>"
            elif assign_target(text, node["col"]) and \
                    head.split('.')[0] in binds:
                # `x(i) = v` WHERE `x` IS A VALUE BINDING. Nothing assigns to an
                # application result, so the parentheses here are projection,
                # and `docs/spec/law.md` §5 gives projection to `[]`:
                # "`()` is ordinary application. It never means table indexing."
                # `examples/call_index_assign.id` is the negative probe for
                # exactly this shape and requires it to refuse.
                #
                # THE BINDING TEST IS LOAD-BEARING AND WAS ADDED AFTER A WRONG
                # REPAIR. `env(k) = v` is the CANONICAL write face of the
                # injected `os` world's environment PLACE — `examples/projection/place.id`
                # names all four faces and puts `os.env[k] = v` on the LEGACY
                # side — and `env` is a world projection, not a binding, so it
                # is not in `binds` and never reaches this row. A relation with
                # a place has a lawful write face through `()`; a local holding
                # a table does not.
                cause, note = "projection-with-application-parens", head
            elif '.' in head:
                root = head.split('.')[0]
                home = '.'.join(head.split('.')[:-1])
                note = home
                if root in binds or root in funcs:
                    cause = "callee-is-a-value"
                elif home_file(f, home):
                    cause = "cross-home-application"
                    homes_seen[home] += 1
                else:
                    cause = "home-unresolved"
            else:
                note = head
                if head in funcs:
                    cause = "local-relation-unpublished"
                elif head in binds:
                    cause = "callee-is-a-value"
                elif head in declared:
                    cause = "host-relation-name-declared-in-home"
                else:
                    cause = "host-relation-no-entity"
        hist[cause] += 1
        faces[(cause, outcome)] += 1
        names[cause][note] += 1
        if sites is not None:
            sites.write("%s\t%s\t%s\t%s\t%s\n"
                        % (f, node.get("line"), node.get("col"), cause, outcome))

cand = tot["candidates"]
unpub = tot["bootstrap"] + tot["blocking"]

# ── FLOOR 4: the denominator is a subject, and it has to exist ─────────────
# Everything below prints a share of `unpub` and a ratio over `cand`. Both
# guards already read `if cand else 0`, which turns a missing denominator into
# a printed `0.0%` — a number the reader cannot distinguish from a measured
# one. So the absence is raised here instead of being formatted away.
#
# `parsed` and `unparsed` are separate from the shell's `lifted`: the shell
# counted a non-empty file, this counts a file that was actually read. A gap
# between them means the table was computed over fewer modules than the header
# line reports, which is the same class of lie one level down.
floor = []
if parsed == 0:
    floor.append("not one graph export parsed; the classifier read nothing")
if unparsed:
    floor.append("%d lifted export(s) did not parse, first %s (%s)"
                 % (len(unparsed), unparsed[0][0], unparsed[0][1]))
if cand == 0:
    floor.append("fact_coverage reports ZERO application candidates; the "
                 "coverage ratio and every share below would divide by a "
                 "denominator that was never measured")
if floor:
    sys.stderr.write("application: SUBJECT FLOOR — a table over no subject is "
                     "not a clean table\n")
    for line in floor:
        sys.stderr.write("application:   %s\n" % line)
    raise SystemExit(64)

print()
print("== TOTALS (must match gate/coverage.sh over the same corpus) ==")
print("candidates %d  published %d (%.1f%%)  bootstrap %d  blocking %d"
      % (cand, tot["published"], 100.0 * tot["published"] / cand if cand else 0,
         tot["bootstrap"], tot["blocking"]))
print()
print("== UNPUBLISHED APPLICATION CANDIDATES BY CAUSE ==")
print("%-38s %8s %8s %8s %7s" % ("cause", "total", "blocking", "bootstrap", "share"))
for cause, v in hist.most_common():
    print("%-38s %8d %8d %8d %6.1f%%"
          % (cause, v, faces[(cause, "blocking")], faces[(cause, "bootstrap")],
             100.0 * v / unpub if unpub else 0))
print("%-38s %8d %8d %8d %6.1f%%"
      % ("TOTAL", sum(hist.values()),
         sum(v for (c, o), v in faces.items() if o == "blocking"),
         sum(v for (c, o), v in faces.items() if o == "bootstrap"), 100.0))
print()
print("== THE NAMES BEHIND EACH CAUSE (top 8) ==")
for cause, _ in hist.most_common():
    top = ", ".join("%s %d" % (k or "-", v) for k, v in names[cause].most_common(8))
    print("%-38s %s" % (cause, top))
print()
print("== CROSS-HOME REACH, by home ==")
print("cross-home-application resolves to a module file for %d site(s); a call "
      "whose target is never\ncompiled cannot publish complete application "
      "facts, so this row is cross-module reachability\nand belongs to that "
      "concern, not to application publication." % sum(homes_seen.values()))
for k, v in homes_seen.most_common(12):
    print("   %6d %s" % (v, k))
# THE RATCHETED CAUSE, written out for the shell. `x(i) = v` is the one cause
# in this table that is a SOURCE defect rather than a producer gap: the
# parentheses are projection, `docs/spec/law.md` §5 gives projection to `[]`,
# and the direct backend already refuses the site (`DNB001 assign-target`). It
# is ratcheted because it is the only row that can be driven to zero without
# publishing a fact, and because every site of it inflates the coverage
# DENOMINATOR with a candidate that is not an application.
if sites is not None:
    sites.close()
open(os.environ["APPLICATION_RATCHET"], "w").write(
    str(hist.get("projection-with-application-parens", 0)))
PY
status=$?
[ "$status" -eq 0 ] || exit "$status"
measured=$(cat "$work/ratchet" 2>/dev/null || echo "")
[ -n "$measured" ] || { echo "application: the classifier wrote no ratchet count" >&2; exit 64; }
echo
if [ -n "$budget" ]; then
  printf 'gate/application.sh: projection-with-application-parens budget %s, measured %s\n' \
    "$budget" "$measured"
  if [ "$measured" -gt "$budget" ]; then
    printf 'gate/application.sh: OVER BUDGET\n'
    exit 1
  fi
  exit 0
fi
printf 'gate/application.sh: reporting only (set APPLICATION_BUDGET to ratchet projection-with-application-parens, measured %s)\n' "$measured"
exit 0
