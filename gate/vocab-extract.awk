# gate/vocab-extract.awk — conservative source-declaration freeze classifier.
#
# This is not a semantic vocabulary producer and does not decide public reach.
# It recognizes added column-one declaration shapes only so admission can fail
# closed while the graph lacks an authoritative public-vocabulary delta. Every
# hit is therefore "unknown; blocked", never "this is a relation because AWK
# said so". Delete this classifier when the graph projection exists.

function idol_decl(L,   nm, rest) {
    if (L ~ /^enum[ \t]+[A-Za-z_]/) {
        nm = L; sub(/^enum[ \t]+/, "", nm); sub(/[^A-Za-z0-9_].*$/, "", nm)
        return nm == "" ? "" : "case\t" nm
    }
    if (L !~ /^[A-Za-z_]/) return ""
    nm = L; sub(/[^A-Za-z0-9_].*$/, "", nm)
    if (nm == "") return ""
    # Column-1 keywords and top-level statement heads. Not declarations.
    if (nm ~ /^(if|for|while|else|elseif|elif|return|break|continue|end|enum|global|fun|function|local|let|const|match|case|try|catch|defer|do|then|in|not|and|or|print|error|assert|import|require|use)$/) return ""
    rest = substr(L, length(nm) + 1)
    # relation forms, in corpus-frequency order (see lib/strings.id:11,
    # lib/cmp.id:4, benchmarks/wasm_rt/conform/run_spec.id:36,
    # lib/compiler/lexer.id:287, examples/compile_fail/barecase_mixed.id:32)
    if (rest ~ /^:[^=]*=[ \t]*\(/)        return "relation\t" nm
    if (rest ~ /^[ \t]*=[ \t]*\(/)        return "relation\t" nm
    if (rest ~ /^\([^)]*:[^)]*\)[ \t]*:/) return "relation\t" nm
    if (rest ~ /^\([^)]*:[^)]*\)[ \t]*$/) return "relation\t" nm
    # a brace set of BARE names is a case set; a brace set of `name: type` is
    # a descriptor; either way it must carry no `=` or it is a value binding
    # (lib/process.id:11 `work: { line: str } = (line: str)` is a RELATION).
    if (rest ~ /^:[ \t]*\{[ \t]*[a-z_][a-z0-9_]*([ \t]*,[ \t]*[a-z_][a-z0-9_]*)*[ \t]*\}[ \t]*$/ && rest !~ /:[^{]*:/) return "case\t" nm
    if (rest ~ /^:[ \t]*\{/ && rest !~ /=/) return "descriptor\t" nm
    if (rest ~ /^[ \t]*=/ || rest ~ /^:[^={]*=/) return "binding\t" nm
    return ""
}

# MODE=file : every input line is a source line.
# MODE=diff : only `+` added lines count, and only when the source byte that
#             follows the `+` is in column 1 (i.e. not a space) -- an indented
#             added line is not a module-scope declaration.
{
    if (MODE == "diff") {
        if ($0 ~ /^\+\+\+ /) { f = $2; sub(/^b\//, "", f); FNAMEX = f; next }
        if ($0 !~ /^\+/) next
        L = substr($0, 2)
        if (L ~ /^[ \t]/) next
    } else {
        L = $0
        FNAMEX = FILENAME
    }
    r = idol_decl(L)
    if (r == "") next
    split(r, p, "\t")
    if (p[2] ~ /^_/) next
    print p[1] "\t" p[2] "\t" FNAMEX
}
