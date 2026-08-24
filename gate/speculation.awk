# gate/speculation.awk -- enumerate the relations that ASSIGN a module-scope
# `global`, one `<relation>\t<global>` row each, from Idol source.
#
# THE SOURCE IS THE SUBJECT AND NOT THE GRAPH, deliberately. The graph is the
# thing under test: it mints a FRESH scope-local entity for `_pos = _pos + 1`
# inside a relation rather than an edge to the module binding, so asking the
# graph "does this relation write a global" returns the same answer as "does
# this relation have a local", which is no answer. The source still has the
# `global` keyword the graph dropped.
#
# CONSERVATIVE IN THE DIRECTION THAT MATTERS. It reports only DIRECT writes to
# a name declared `global` in the SAME file. A relation that mutates through a
# callee is not reported, and neither is a genuine shadowing local of the same
# spelling -- which the graph cannot distinguish either, and which is the
# indistinguishability this measurement exists to exhibit.
/^global[ \t]+/ {
    n = $2
    sub(/[:=].*$/, "", n)
    gsub(/[ \t]/, "", n)
    if (n != "") glob[n] = 1
    next
}
# A module-scope relation head: `name = (`, `name: ty = (`.
/^[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[^=]*)?=[ \t]*\(/ {
    rel = $0
    sub(/[ \t]*[:=].*$/, "", rel)
    gsub(/[ \t]/, "", rel)
    cur = rel
    next
}
# Any other column-1 line ends the relation body.
/^[A-Za-z_]/ { cur = ""; next }
cur != "" && /^[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=]/ {
    t = $0
    sub(/^[ \t]+/, "", t)
    sub(/[ \t]*=.*$/, "", t)
    if (t in glob && !((cur SUBSEP t) in seen)) {
        seen[cur SUBSEP t] = 1
        print cur "\t" t
    }
}
