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

for root in $corpus; do
  [ -d "$root" ] || continue
  find "$root" -name '*.id' -type f 2>/dev/null
done | sort > "$work/corpus"

: > "$work/exports"
lifted=0; refused=0; n=0
while IFS= read -r src; do
  n=$((n + 1))
  out="$work/$n.json"
  if "$idol" graph "$src" > "$out" 2>/dev/null && [ -s "$out" ]; then
    printf '%s\t%s\n' "$src" "$out" >> "$work/exports"
    lifted=$((lifted + 1))
  else
    rm -f "$out"
    refused=$((refused + 1))
  fi
done < "$work/corpus"

printf 'gate/application.sh: corpus %s file(s) under [%s]; %s lifted, %s refused\n' \
  "$n" "$corpus" "$lifted" "$refused"

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

for row in open(exports):
    f, path = row.rstrip("\n").split("\t")
    try:
        d = json.load(open(path))
    except Exception:
        continue
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
        if node is None:
            continue
        outcome = "blocking" if cid in blocking else "bootstrap"
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
            elif assign_target(text, node["col"]):
                cause, note = "projection-with-application-parens", head
            elif head == '<computed>':
                cause, note = "callee-is-a-value", "<computed>"
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
