#!/bin/sh
# gate/gap-145-consumer.sh — GAP-145: nothing may hold a second answer about
# what a token IS.
#
# Three classes of observer, one runner:
#
#   (1) QUOTE COLLAPSE.   A consumer that answers `.str` for every `.quoted`
#       has thrown away the producer's text/bytes distinction.
#   (2) DUPLICATE PRODUCER. A host module that classifies quotes, comments,
#       shebang or backtick beside `lib/compiler/lexer.id`.
#   (3) SECOND GRAMMAR AUTHORITY. The tree-sitter grammar is an independently
#       authored operator table. GAP-145's closure bullet allows it to be
#       "generated or mechanically verified from the same grammar/lexical
#       authority". Nothing verified it: the check inside the generator
#       compared against a hand-copied restatement of docs/spec/grammar.md 2 --
#       a file whose own first paragraph says it is not a grammar authority --
#       and compared only ADJACENT rows. Section 3 below compares EVERY PAIR
#       against `src/grammar_role_table.zig`, the generated projection of
#       `lib/compiler/token.id` (law.grammar.one).
#
# Every section positive-controls its own detector. A gate that cannot fail
# reports a number that proves nothing (law.gate.protocol).
set -u

ROOT=${GAP145_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TYPES="$ROOT/src/types.zig"
SEMA="$ROOT/src/sema.zig"
CODEGEN="$ROOT/src/codegen.zig"
AST="$ROOT/src/ast.zig"
DNIR="$ROOT/src/dnir_lower.zig"
PARSER="$ROOT/src/parser.zig"
DISPATCH="$ROOT/src/lexer_dispatch.zig"
LEXER_BRIDGE="$ROOT/src/lexer_bridge.zig"
TOKEN_VIEW="$ROOT/src/token_view.zig"
LEXER="$ROOT/src/lexer.zig"

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'gap-145 consumer gate: FAIL %s\n' "$*"
}

has() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if ! grep -Fq -- "$pattern" "$file"; then
        bad "$msg"
    fi
}

forbid() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if grep -Fq -- "$pattern" "$file"; then
        bad "$msg"
    fi
}

# ── 1. quote identity reaches the consumers ─────────────────────────────────

has "$AST" 'pub fn quotedLiteralIsByteSequence' \
    'ast.zig lost quotedLiteralIsByteSequence helper'
has "$TYPES" 'pub fn quotedLiteralType' \
    'types.zig lost quotedLiteralType helper'
has "$SEMA" 'types.quotedLiteralType(lit.quote)' \
    'sema.zig must type quoted literals via quotedLiteralType'
has "$CODEGEN" 'types.quotedLiteralType(lit.quote)' \
    'codegen.zig must recover quoted literal types via quotedLiteralType'
has "$DNIR" 'types.quotedLiteralType(lit.quote)' \
    'dnir_lower.zig must type quoted globals via quotedLiteralType'

forbid "$SEMA" '.quoted => .str,' \
    'sema.zig reintroduced bare `.quoted => .str` collapse'
forbid "$CODEGEN" '.quoted => .str,' \
    'codegen.zig reintroduced bare `.quoted => .str` collapse'
forbid "$DNIR" '.quoted => .str,' \
    'dnir_lower.zig reintroduced bare `.quoted => .str` collapse'

# ── 2. one producer of lexical identity ─────────────────────────────────────
#
# `src/lexical_identity.zig` called itself "canonical lexical token identities
# (production source of truth)" and had ZERO consumers, which is exactly why no
# call-graph census ever saw it. Its `classifyQuote` keyed on
# `facts.law` x `facts.provenance`; the producer's `classify_quote` keys on
# `family`. Two answers, and the divergence was invisible only because nothing
# asked. Deleted 2026-08-23. This is the ratchet that keeps it deleted.
examined=$((examined + 1))
if [ -e "$ROOT/src/lexical_identity.zig" ]; then
    bad 'src/lexical_identity.zig is back — one producer owns lexical identity (law.fact.producer.one); it is lib/compiler/lexer.id'
fi

# Token identity and source spelling have one owner too. `src/lexer.zig` used
# to author the enum and its `spelling()` method. Both now live in the generated
# projection of `lib/compiler/token.id`; the lexer holds only the temporary
# bridge alias.
has "$ROOT/src/lexer.zig" \
    'pub const TokenKind = @import("grammar_role_table.zig").TokenKind;' \
    'src/lexer.zig no longer aliases the owner-generated token identity'
forbid "$ROOT/src/lexer.zig" 'pub const TokenKind = enum' \
    'src/lexer.zig reintroduced a host-authored token identity enum'
has "$ROOT/src/grammar_role_table.zig" \
    'pub const TokenKind = enum(u8)' \
    'generated owner projection no longer carries token identity'
has "$ROOT/src/grammar_role_table.zig" \
    'return rows[@backingInt(self)].spell;' \
    'generated token identity no longer reads its owner-projected spelling row'

# ── 2b. the parser holds no raw-byte delimiter scan (GAP-145 O6) ─────────────
#
# `findMatchingParen` and `interpolationHoleEnd` answered "where does this
# delimiter close?" by walking QUOTED BYTES with a hand-rolled quote-state
# guesser — a second observation of literal structure the producer had already
# produced. Both were deleted 2026-08-26: delimiter extent is now observed over
# the producer pack through `matchingTokenClose` + `token_view.fromTokens`, which
# balances depth on the PRODUCER'S tokens and masks decoded braces the producer
# marked protected.
#
# That deletion was measured, reported, and then left with NOTHING enforcing
# it: this gate held the ceilings on the quote/text/byte surface and never
# refused a raw-byte scan coming back. Every assertion this project has ever
# written down without a runner has decayed; this one had not even the runner.
# A reintroduction in `src/parser.zig` must FAIL here, not merely become
# possible to notice.
#
# The remaining `findMatchingParen` sites (`src/c_frontend.zig`,
# `src/c_header_parse.zig`) are FOREIGN C HEADER INGRESS, upstream of any Idol
# token: there is no producer pack there to observe. They are out of this seam
# and are not counted.
forbid "$PARSER" 'findMatchingParen' \
    'parser.zig reacquired findMatchingParen — delimiter extent belongs to the producer pack (matchingTokenClose), not a raw-byte quote guesser'
forbid "$PARSER" 'interpolationHoleEnd' \
    'parser.zig reacquired interpolationHoleEnd — hole extent belongs to the producer pack, not a raw-byte scan'
has "$PARSER" 'fn matchingTokenClose(' \
    'parser.zig lost matchingTokenClose — the token-view delimiter-extent relation the O6 deletion replaced the raw scans with'
forbid "$TOKEN_VIEW" 'pub fn fromLexer(' \
    'token_view reacquired a lexer-owned producer-pack adapter'
forbid "$LEXER" 'duo_tokens: ?[]const Token' \
    'Lexer reacquired the duplicate producer-pack slice'
forbid "$LEXER" 'duo_index: usize' \
    'Lexer reacquired the duplicate producer-pack index'
forbid "$LEXER" 'fn duo_next(' \
    'Lexer reacquired the duplicate producer-pack cursor body'
forbid "$PARSER" 'self.lex.duo_tokens' \
    'Parser reacquired a producer-pack alias through Lexer'
forbid "$PARSER" 'self.lex.duo_index' \
    'Parser reacquired a producer index through Lexer'
forbid "$DISPATCH" 'lex.duo_tokens =' \
    'dispatch reacquired the duplicate producer-pack slice install'
forbid "$DISPATCH" 'lex.duo_index =' \
    'dispatch reacquired the duplicate producer-pack index install'
has "$PARSER" 'token_view.fromTokens' \
    'parser.zig stopped observing delimiter extent through its immutable pack'
has "$PARSER" 'const toks = self.pack_tokens orelse return try self.lex.peek();' \
    'Parser.pk no longer selects its immutable pack before the host oracle'
has "$PARSER" 'self.pack_index = self.producerStreamIndex();' \
    'Parser no longer owns producer-pack cursor advancement'

# Positive control for literal-zero lexer aliases. The old fields, cursor body,
# and token-view adapter must all be visible to the detector; the sole parser
# pack shape must not be mistaken for an alias.
cursorprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate cursor scratch' >&2; exit 2; }
{
    printf '%s\n' 'duo_tokens: ?[]const Token = null,'
    printf '%s\n' 'duo_index: usize = 0,'
    printf '%s\n' 'fn duo_next(self: *Lexer) Token {}'
    printf '%s\n' 'pub fn fromLexer(lex: *const Lexer) ?View {}'
} >"$cursorprobe/old.zig"
{
    printf '%s\n' 'pack_tokens: ?[]const Token = null,'
    printf '%s\n' 'pack_index: usize = 0,'
} >"$cursorprobe/new.zig"
cursor_old=$(grep -cE 'duo_tokens:|duo_index:|fn duo_next\(|pub fn fromLexer\(' "$cursorprobe/old.zig")
cursor_new=$(grep -cE 'duo_tokens:|duo_index:|fn duo_next\(|pub fn fromLexer\(' "$cursorprobe/new.zig" || true)
rm -rf -- "$cursorprobe"
examined=$((examined + 1))
if [ "$cursor_old" -ne 4 ] || [ "$cursor_new" -ne 0 ]; then
    bad "the duplicate-cursor detector is broken: old=$cursor_old new=$cursor_new"
fi

# POSITIVE CONTROL ON THE REFUSALS (law.gate.protocol). A `forbid` that cannot
# fail is the `tools/parity/grammar` defect: green for months while matching
# nothing. Plant both retired scans beside the live replacement in a scratch
# parser.zig — the detectors above must convict it, and must NOT convict a
# clean scratch that carries only the replacement.
o6probe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
{
    printf '%s\n' 'fn findMatchingParen(s: []const u8) ?usize { }'
    printf '%s\n' 'fn interpolationHoleEnd(s: []const u8) ?usize { }'
    printf '%s\n' 'fn matchingTokenClose(self: *Parser) ?usize { }'
} >"$o6probe/planted.zig"
: >"$o6probe/clean.zig"
o6_planted=$(grep -cE 'findMatchingParen|interpolationHoleEnd' "$o6probe/planted.zig")
o6_clean=$(grep -cE 'findMatchingParen|interpolationHoleEnd' "$o6probe/clean.zig")
o6_live=$(grep -cE 'fn matchingTokenClose\(' "$o6probe/planted.zig")
rm -rf -- "$o6probe"
examined=$((examined + 1))
if [ "$o6_planted" -ne 2 ] || [ "$o6_clean" -ne 0 ]; then
    bad "the raw-scan detector is broken: 2 planted scanned as $o6_planted, clean as $o6_clean"
elif [ "$o6_live" -ne 1 ]; then
    bad "the replacement detector is broken: matchingTokenClose planted once, counted $o6_live"
fi

# ── 2c. callable-header recognition executes from whole-pack lane two ────────
#
# Event derives previous visible identity and line-opener column, evaluates both
# admitted comma faces, and stores them in bits 4/5. Zig selects only the caller
# face; the standalone header-pack ABI is deleted.
forbid "$PARSER" 'fn headerSignal(' \
    'parser.zig retained the host header recognizer'
forbid "$PARSER" 'fn viewColonIsMethodCall(' \
    'parser.zig retained the host colon-role helper'
has "$PARSER" 'const decision = try self.currentParserDecision();' \
    'scan_func_header_signal no longer consumes lane two'
has "$PARSER" 'const shift: u6 = if (allow_untyped_comma) 5 else 4;' \
    'scan_func_header_signal lost its two admitted header faces'
forbid "$PARSER" 'idol_parser_header_pack(' \
    'parser.zig retained the standalone header-pack ABI'
has "$ROOT/lib/compiler/parser.id" 'header_signal_lx: bool = (fact: []i64' \
    'parser.id lost its event-internal header implementation'
has "$ROOT/lib/compiler/parser.id" '(headerplain << 4) | (headercomma << 5)' \
    'event lost lane-two header bits 4/5'
has "$ROOT/src/parser/projection.c" 'bool header_signal_lx(int64_t fact[]' \
    'tracked projection lost the event-internal header implementation'
forbid "$ROOT/build.zig" '-Dheader_signal_lx=idol_parser_header_pack' \
    'build.zig retained the standalone header ABI rename'
forbid "$ROOT/tools/node/dev/parser/artifact" 'idol_parser_header_pack(' \
    'parser artifact retained the standalone header differential after equivalence'
has "$ROOT/tools/node/dev/parser/artifact" 'bool from_event = ((events[count + 1] >> (allow ? 5 : 4)) & 1) != 0;' \
    'parser artifact no longer checks lane-two header bits'

transfer=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate parser-transfer scratch' >&2; exit 2; }
printf '%s\n' 'fn headerSignal() bool { return false; }' >"$transfer/planted.zig"
printf '%s\n' 'fn viewColonIsMethodCall() bool { return false; }' >>"$transfer/planted.zig"
printf '%s\n' 'return idol_parser_header_pack(facts, count, index);' >"$transfer/old.zig"
printf '%s\n' 'const decision = try self.currentParserDecision();' >"$transfer/new.zig"
host_count=$(grep -cE 'fn (headerSignal|viewColonIsMethodCall)\(' "$transfer/planted.zig")
header_old=$(grep -cF 'idol_parser_header_pack' "$transfer/old.zig")
header_new=$(grep -cF 'currentParserDecision' "$transfer/new.zig")
rm -rf -- "$transfer"
examined=$((examined + 1))
if [ "$host_count" -ne 2 ] || [ "$header_old" -ne 1 ] || [ "$header_new" -ne 1 ]; then
    bad "the header lane detector is broken: host=$host_count old=$header_old new=$header_new"
fi

# ── 2d. return-value decision executes from whole-pack lane two ──────────────
#
# The kind switch, cross-line gate, and idol-mode expression-start rule execute
# once into lane-two bits 2..3. Zig keeps only the selected diagnostic.
forbid "$PARSER" '.kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof, .semi => return false' \
    'parser.zig reintroduced a host kind switch beside the return face'
has "$PARSER" 'const verdict = ((try self.currentParserDecision()) >> 2) & 3;' \
    'returnStartsValue no longer consumes lane-two bits 2..3'
forbid "$PARSER" 'idol_parser_return_starts_value(' \
    'parser.zig retained the standalone return-value ABI'
has "$ROOT/lib/compiler/parser.id" 'return_starts_value_lx: i64 = (fact: []i64' \
    'parser.id lost its event-internal return implementation'
has "$ROOT/lib/compiler/parser.id" '(returnface << 2)' \
    'event lost lane-two return bits 2..3'
has "$ROOT/src/parser/projection.c" 'return_starts_value_lx(int64_t fact[]' \
    'tracked projection lost the event-internal return implementation'
forbid "$ROOT/build.zig" '-Dreturn_starts_value_lx=idol_parser_return_starts_value' \
    'build.zig retained the return-value ABI rename'
has "$ROOT/tools/node/dev/parser/artifact" 'int64_t found = (events[3] >> 2) & 3;' \
    'parser artifact no longer checks lane-two return bits'
forbid "$ROOT/tools/node/dev/parser/artifact" 'idol_parser_return_starts_value(' \
    'parser artifact retained the standalone return differential after equivalence'

returnprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate return-value scratch' >&2; exit 2; }
printf '%s\n' 'const verdict = idol_parser_return_starts_value(facts.ptr, count, index, line, self.idol_mode);' >"$returnprobe/old.zig"
printf '%s\n' 'const verdict = ((try self.currentParserDecision()) >> 2) & 3;' >"$returnprobe/new.zig"
printf '%s\n' 'switch (nxt.kind) { .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof, .semi => return false, else => {}, }' >"$returnprobe/plantswitch.zig"
return_old=$(grep -cF 'idol_parser_return_starts_value' "$returnprobe/old.zig")
return_new=$(grep -cF 'currentParserDecision' "$returnprobe/new.zig")
host_switch_count=$(grep -cE '\.kw_end, \.kw_else, \.kw_elseif, \.kw_until, \.kw_catch, \.eof, \.semi => return false' "$returnprobe/plantswitch.zig")
rm -rf -- "$returnprobe"
examined=$((examined + 1))
if [ "$return_old" -ne 1 ] || [ "$return_new" -ne 1 ] || [ "$host_switch_count" -ne 1 ]; then
    bad "the return lane detector is broken: old=$return_old new=$return_new host=$host_switch_count"
fi

# ── 2e. match-arm classification executes from whole-pack lane two ───────────
#
# Contextual `case` remains a name token, so the physical pack carries a short
# raw lexeme beside metadata. parser.id owns the word comparison, pattern role,
# same-line rule, delimiter depth and separator decision. Event lane two bits
# 0..1 carry the 0/1/2/3 face at the same producer coordinate.
forbid "$PARSER" 'std.mem.eql(u8, first.text, "case")' \
    'parser.zig reintroduced contextual case recognition beside parser.id clause'
forbid "$PARSER" 'if (!view.canStartPattern(start)) return false' \
    'parser.zig reintroduced the match pattern-role decision'
forbid "$PARSER" '.kw_then, .kw_do, .fat_arrow => return depth == 0' \
    'parser.zig reintroduced match separator/depth recognition'
has "$PARSER" 'const face = (try self.currentParserDecision()) & 3;' \
    'matchClause no longer consumes whole-pack lane-two bits 0..1'
forbid "$PARSER" 'idol_parser_match_clause(' \
    'parser.zig retained the standalone match-clause ABI'
has "$PARSER" 'facts[2 + index * 2] = @intCast(lexeme);' \
    'the parser pack lost its raw short-lexeme physical fact'
has "$ROOT/lib/compiler/parser.id" '_clause: i64 = (fact: []i64' \
    'parser.id lost its internal immutable-pack match implementation'
has "$ROOT/lib/compiler/parser.id" 'clauseface = _clause(fact, count, index)' \
    'event lost the lane-two match face producer'
has "$ROOT/lib/compiler/parser.id" 'out[count + index] = clauseface | (returnface << 2)' \
    'event lost the packed lane-two match/return word'
has "$ROOT/src/parser/projection.c" 'int64_t _clause(int64_t fact[]' \
    'tracked projection lost the event-internal match implementation'
forbid "$ROOT/build.zig" '-D_clause=idol_parser_match_clause' \
    'build.zig retained the match-clause ABI rename'
has "$ROOT/tools/node/dev/parser/artifact" 'int64_t found = events[count] & 3;' \
    'parser artifact no longer checks the lane-two match face'
forbid "$ROOT/tools/node/dev/parser/artifact" 'idol_parser_match_clause(' \
    'parser artifact retained the standalone match differential after equivalence'

matchprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate match-clause scratch' >&2; exit 2; }
printf '%s\n' 'const face = idol_parser_match_clause(facts.ptr, count, index);' >"$matchprobe/old.zig"
printf '%s\n' 'const face = (try self.currentParserDecision()) & 3;' >"$matchprobe/new.zig"
printf '%s\n' 'if (first.kind == .name and std.mem.eql(u8, first.text, "case")) return true;' >"$matchprobe/host.zig"
printf '%s\n' '.kw_then, .kw_do, .fat_arrow => return depth == 0,' >>"$matchprobe/host.zig"
match_old=$(grep -cF 'idol_parser_match_clause' "$matchprobe/old.zig")
match_new=$(grep -cF 'currentParserDecision' "$matchprobe/new.zig")
match_text=$(grep -cF 'std.mem.eql(u8, first.text, "case")' "$matchprobe/host.zig")
match_depth=$(grep -cF '.kw_then, .kw_do, .fat_arrow => return depth == 0' "$matchprobe/host.zig")
rm -rf -- "$matchprobe"
examined=$((examined + 1))
if [ "$match_old" -ne 1 ] || [ "$match_new" -ne 1 ] || [ "$match_text" -ne 1 ] || [ "$match_depth" -ne 1 ]; then
    bad "the match-clause lane detector is broken: old=$match_old new=$match_new text=$match_text depth=$match_depth"
fi

# ── 2e'. contextual type head executes from whole-pack lane two ──────────────
#
# `type` remains a contextual name because `type(x)` is an admitted call face.
# Event compares the producer's bounded raw word and following token once, then
# carries alias-head/not-alias in lane-two bit 6. Every Zig statement and
# attributed-declaration consumer selects that fact without text comparison or
# save/advance/restore lookahead.
type_text=$(grep -cE 'std\.mem\.eql\(u8, [[:alnum:]_]+\.text, "type"\)' "$PARSER" || true)
examined=$((examined + 1))
if [ "$type_text" -ne 0 ]; then
    bad "parser.zig retained $type_text contextual type text decision(s) beside event bit 6"
fi
type_lane=$(grep -cF 'currentParserDecision()) >> 6' "$PARSER" || true)
examined=$((examined + 1))
if [ "$type_lane" -ne 2 ]; then
    bad "the two remaining contextual type consumers must select lane-two bit 6 (calls=$type_lane)"
fi
has "$ROOT/lib/compiler/parser.id" 'fact[index * 2 + 2] == 435678704644' \
    'parser.id lost the exact contextual type source-word fact'
has "$ROOT/lib/compiler/parser.id" '(head << 6)' \
    'event lost lane-two contextual type bit 6'
has "$ROOT/src/parser/projection.c" 'fact[((index * 2) + 2)] == 435678704644' \
    'tracked projection lost contextual type recognition'
has "$ROOT/src/parser/projection.c" '((uint64_t)(head)) << ((uint64_t)(6)' \
    'tracked projection lost lane-two contextual type bit 6'
has "$ROOT/tools/node/dev/parser/artifact" 'int64_t found = (events[count] >> 6) & 1;' \
    'parser artifact no longer checks lane-two contextual type bit'
has "$ROOT/tools/node/dev/parser/artifact" 'type-lane-cases=5' \
    'parser artifact lost the exact contextual type control count'

typeprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate contextual-type scratch' >&2; exit 2; }
{
    printf '%s\n' 'if (std.mem.eql(u8, tok.text, "type")) return true;'
    printf '%s\n' 'if (std.mem.eql(u8, nxt.text, "type")) return true;'
    printf '%s\n' 'if (std.mem.eql(u8, next.text, "type")) return true;'
    printf '%s\n' 'if (std.mem.eql(u8, head.text, "type")) return true;'
} >"$typeprobe/old.zig"
{
    printf '%s\n' 'if (((try self.currentParserDecision()) >> 6) & 1 == 1) return true;'
    printf '%s\n' 'if (((try self.currentParserDecision()) >> 6) & 1 == 1) return true;'
    printf '%s\n' 'if (((try self.currentParserDecision()) >> 6) & 1 == 1) return true;'
    printf '%s\n' 'if (((try self.currentParserDecision()) >> 6) & 1 == 1) return true;'
} >"$typeprobe/new.zig"
: >"$typeprobe/clean.zig"
type_old=$(grep -cE 'std\.mem\.eql\(u8, [[:alnum:]_]+\.text, "type"\)' "$typeprobe/old.zig")
type_new=$(grep -cF 'currentParserDecision()) >> 6' "$typeprobe/new.zig")
type_clean=$(grep -cE 'std\.mem\.eql\(u8, [[:alnum:]_]+\.text, "type"\)|currentParserDecision\(\).*>> 6' "$typeprobe/clean.zig" || true)
rm -rf -- "$typeprobe"
examined=$((examined + 1))
if [ "$type_old" -ne 4 ] || [ "$type_new" -ne 4 ] || [ "$type_clean" -ne 0 ]; then
    bad "the contextual-type detector is broken: old=$type_old new=$type_new clean=$type_clean"
fi

# ── 2e''. bare declaration path executes from whole-pack lane two ────────────
#
# Header bit 4 is settled at `(`. Event walks backward over the exact admitted
# name (`.` name)* (`:` name)? path and writes bit 7 at the starting name. Zig
# statement and attribute consumers select that coordinate without a second
# save/scan/restore path recognizer.
forbid "$PARSER" 'fn starts_bare_func_decl(' \
    'parser.zig retained the host bare-declaration path recognizer'
bare_calls=$(grep -cF 'starts_bare_func_decl()' "$PARSER" || true)
examined=$((examined + 1))
if [ "$bare_calls" -ne 0 ]; then
    bad "parser.zig retained $bare_calls bare-declaration scanner call(s)"
fi
bare_lane=$(grep -cF 'currentParserDecision()) >> 7' "$PARSER" || true)
examined=$((examined + 1))
if [ "$bare_lane" -ne 2 ]; then
    bad "the two remaining bare-declaration consumers must select lane-two bit 7 (calls=$bare_lane)"
fi
has "$ROOT/lib/compiler/parser.id" 'out[count + start] = out[count + start] | (1 << 7)' \
    'event lost the propagated bare-declaration head bit'
has "$ROOT/lib/compiler/parser.id" '== token.kindcolon' \
    'event lost subject-specialized declaration path recognition'
has "$ROOT/lib/compiler/parser.id" '== token.kinddot' \
    'event lost static declaration path recognition'
has "$ROOT/src/parser/projection.c" 'out[(count + start)] = ((int64_t)((out[(count + start)]) | (128)))' \
    'tracked projection lost lane-two bare-declaration bit 7'
has "$ROOT/tools/node/dev/parser/artifact" 'from_event = ((events[count] >> 7) & 1) != 0;' \
    'parser artifact lost the direct cursor/event bare-head differential'
has "$ROOT/tools/node/dev/parser/artifact" 'bare-lane-cases=5' \
    'parser artifact lost the exact bare-head case count'

bareprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate bare-head scratch' >&2; exit 2; }
{
    printf '%s\n' 'fn starts_bare_func_decl(self: *Parser) bool { return false; }'
    printf '%s\n' 'if (try self.starts_bare_func_decl()) return true;'
    printf '%s\n' 'if (try self.starts_bare_func_decl()) return true;'
    printf '%s\n' 'if (try self.starts_bare_func_decl()) return true;'
    printf '%s\n' 'if (try self.starts_bare_func_decl()) return true;'
} >"$bareprobe/old.zig"
{
    printf '%s\n' 'if ((((try self.currentParserDecision()) >> 7) & 1) != 0) return true;'
    printf '%s\n' 'if ((((try self.currentParserDecision()) >> 7) & 1) != 0) return true;'
    printf '%s\n' 'if ((((try self.currentParserDecision()) >> 7) & 1) != 0) return true;'
    printf '%s\n' 'if ((((try self.currentParserDecision()) >> 7) & 1) != 0) return true;'
} >"$bareprobe/new.zig"
: >"$bareprobe/clean.zig"
bare_old=$(grep -cE 'starts_bare_func_decl' "$bareprobe/old.zig")
bare_new=$(grep -cF 'currentParserDecision()) >> 7' "$bareprobe/new.zig")
bare_clean=$(grep -cE 'starts_bare_func_decl|currentParserDecision\(\).*>> 7' "$bareprobe/clean.zig" || true)
rm -rf -- "$bareprobe"
examined=$((examined + 1))
if [ "$bare_old" -ne 5 ] || [ "$bare_new" -ne 4 ] || [ "$bare_clean" -ne 0 ]; then
    bad "the bare-head detector is broken: old=$bare_old new=$bare_new clean=$bare_clean"
fi

# ── 2f. line-head identity comes from whole-pack visible-token history ────────
#
# Event bit 22 combines the owner lead row with the previous parser-visible line
# while skipping shebang/comment identities. The standalone lead ABI is deleted.
forbid "$PARSER" 'fn opensLineAndExpression(' \
    'parser.zig retained the host line-head recognizer'
forbid "$PARSER" 'grammar_roles.lookup(tok.kind).opens_line' \
    'parser.zig retained the host opens_line role decision'
has "$PARSER" 'fn currentParserLead(self: *Parser) ParseError!bool {' \
    'Parser lost its event-backed line-head observer'
lead_consumers=$(grep -cF 'if (try self.currentParserLead()) break;' "$PARSER" || true)
examined=$((examined + 1))
if [ "$lead_consumers" -ne 2 ]; then
    bad "both Pratt consumers must use event line-head bit 22 (calls=$lead_consumers)"
fi
forbid "$PARSER" 'idol_parser_lead(' \
    'parser.zig retained the standalone line-head ABI'
forbid "$ROOT/lib/compiler/parser.id" 'lead: bool = (kind: i64, line: i64, before: i64)' \
    'parser.id retained the standalone line-head relation'
has "$ROOT/lib/compiler/parser.id" 'leads: str = token.grammarrole.lead()' \
    'event lost the owner lead row'
has "$ROOT/lib/compiler/parser.id" '(leadface << 22)' \
    'event lost line-head bit 22'
forbid "$ROOT/src/parser/projection.c" 'bool lead(int64_t kind, int64_t line, int64_t before)' \
    'tracked projection retained the line-head function'
forbid "$ROOT/build.zig" '-Dlead=idol_parser_lead' \
    'build.zig retained the line-head ABI rename'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_lead(void)' \
    'parser artifact retained the standalone lead differential'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_event_lead_trivia(void)' \
    'parser artifact lost the trivia-aware line-head differential'
has "$ROOT/tools/node/dev/parser/artifact" 'event-lead-cases=2' \
    'parser artifact lost the exact line-head case count'

leadprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate line-head scratch' >&2; exit 2; }
printf '%s\n' 'fn opensLineAndExpression() bool { return grammar_roles.lookup(tok.kind).opens_line; }' >"$leadprobe/old.zig"
printf '%s\n' 'return ((try self.currentParserEvent()) >> 22) & 1 != 0;' >"$leadprobe/new.zig"
: >"$leadprobe/clean.zig"
lead_old=$(grep -cE 'opensLineAndExpression|lookup\(tok.kind\)\.opens_line' "$leadprobe/old.zig")
lead_new=$(grep -cE 'currentParserEvent.*>> 22' "$leadprobe/new.zig")
lead_clean=$(grep -cE 'opensLineAndExpression|idol_parser_lead|currentParserEvent.*>> 22' "$leadprobe/clean.zig" || true)
rm -rf -- "$leadprobe"
examined=$((examined + 1))
if [ "$lead_old" -ne 1 ] || [ "$lead_new" -ne 1 ] || [ "$lead_clean" -ne 0 ]; then
    bad "the event-line-head detector is broken: old=$lead_old new=$lead_new clean=$lead_clean"
fi

# ── 2f'. prefix identity comes from whole-pack event ─────────────────────────
#
# The owner row remains `prefix()`, but event bit 20 now carries its answer at
# each producer coordinate. The standalone relation/ABI is deleted.
forbid "$PARSER" 'grammar_roles.lookup(first_tok.kind).prefix' \
    'parser.zig retained the host prefix role decision'
forbid "$PARSER" 'grammar_roles.lookup(.+)\.prefix' \
    'parser.zig retained any host prefix role decision'
has "$PARSER" 'fn currentParserPrefix(self: *Parser) ParseError!bool {' \
    'Parser lost its event-backed prefix observer'
has "$PARSER" 'const is_unary = try self.currentParserPrefix();' \
    'parse_expr_stmt no longer consumes event prefix bit 20'
forbid "$PARSER" 'idol_parser_prefix(' \
    'parser.zig retained the standalone prefix ABI'
forbid "$ROOT/lib/compiler/parser.id" 'prefix: bool = (kind: i64)' \
    'parser.id retained the standalone prefix relation'
has "$ROOT/lib/compiler/parser.id" 'prefixes: str = token.grammarrole.prefix()' \
    'event lost the owner prefix row'
has "$ROOT/lib/compiler/parser.id" '(prefixface << 20)' \
    'event lost prefix bit 20'
forbid "$ROOT/src/parser/projection.c" 'bool prefix(int64_t kind)' \
    'tracked projection retained the standalone prefix function'
forbid "$ROOT/build.zig" '-Dprefix=idol_parser_prefix' \
    'build.zig retained the prefix ABI rename'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_prefix(void)' \
    'parser artifact retained the standalone prefix differential'
has "$ROOT/tools/node/dev/parser/artifact" '(prefix << 20)' \
    'whole-pack event oracle lost prefix bit 20'

prefixprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate prefix scratch' >&2; exit 2; }
printf '%s\n' 'const is_unary = grammar_roles.lookup(first_tok.kind).prefix;' >"$prefixprobe/old.zig"
printf '%s\n' 'const is_unary = ((try self.currentParserEvent()) >> 20) & 1 != 0;' >"$prefixprobe/new.zig"
: >"$prefixprobe/clean.zig"
prefix_old=$(grep -cE 'lookup\(.*\)\.prefix' "$prefixprobe/old.zig")
prefix_new=$(grep -cE 'currentParserEvent.*>> 20' "$prefixprobe/new.zig")
prefix_clean=$(grep -cE 'lookup\(.*\)\.prefix|idol_parser_prefix|currentParserEvent.*>> 20' "$prefixprobe/clean.zig" || true)
rm -rf -- "$prefixprobe"
examined=$((examined + 1))
if [ "$prefix_old" -ne 1 ] || [ "$prefix_new" -ne 1 ] || [ "$prefix_clean" -ne 0 ]; then
    bad "the event-prefix detector is broken: old=$prefix_old new=$prefix_new clean=$prefix_clean"
fi

# ── 2f''. operand demand comes from the consumed event coordinate ────────────
#
# `advRaw` captures event bit 21 before advancing the sole pack cursor. The
# standalone relation/ABI is deleted, so a consumed token cannot be reclassified
# from spelling or from the next token's coordinate.
forbid "$PARSER" 'grammar_roles.lookup\(.+\)\.demands_operand' \
    'parser.zig retained the host demands_operand role decision'
forbid "$PARSER" 'fn demandsOperand(' \
    'parser.zig retained the host demandsOperand helper'
has "$PARSER" 'demand = ((events[index] >> 21) & 1) != 0;' \
    'advRaw no longer captures demand from the consumed event coordinate'
has "$PARSER" 'if (demand) try self.denyRetiredLengthHash(tok);' \
    'advRaw no longer consumes the settled demand face'
forbid "$PARSER" 'idol_parser_demands_operand(' \
    'parser.zig retained the standalone demands_operand ABI'
forbid "$ROOT/lib/compiler/parser.id" 'demands_operand: bool = (kind: i64)' \
    'parser.id retained the standalone demands_operand relation'
has "$ROOT/lib/compiler/parser.id" 'demands: str = token.grammarrole.demand()' \
    'event lost the owner demand row'
has "$ROOT/lib/compiler/parser.id" '(demandface << 21)' \
    'event lost operand-demand bit 21'
forbid "$ROOT/src/parser/projection.c" 'bool demands_operand(int64_t kind)' \
    'tracked projection retained the standalone demands_operand function'
forbid "$ROOT/build.zig" '-Ddemands_operand=idol_parser_demands_operand' \
    'build.zig retained the demands_operand ABI rename'
has "$ROOT/tools/node/dev/parser/artifact" '(demand << 21)' \
    'whole-pack event oracle lost demand bit 21'

demandprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate demands_operand scratch' >&2; exit 2; }
printf '%s\n' 'fn demandsOperand(kind: u8) bool { return grammar_roles.lookup(kind).demands_operand; }' >"$demandprobe/old.zig"
printf '%s\n' 'const demand = ((events[index] >> 21) & 1) != 0;' >"$demandprobe/new.zig"
: >"$demandprobe/clean.zig"
demand_old=$(grep -cE 'demandsOperand|lookup\(.+\)\.demands_operand' "$demandprobe/old.zig")
demand_new=$(grep -cE 'events\[index\].*>> 21' "$demandprobe/new.zig")
demand_clean=$(grep -cE 'demandsOperand|demands_operand|events\[index\].*>> 21' "$demandprobe/clean.zig" || true)
rm -rf -- "$demandprobe"
examined=$((examined + 1))
if [ "$demand_old" -ne 1 ] || [ "$demand_new" -ne 1 ] || [ "$demand_clean" -ne 0 ]; then
    bad "the event-demand detector is broken: old=$demand_old new=$demand_new clean=$demand_clean"
fi

# ── 2f'''. Pratt triple comes from event bits 23..46 ─────────────────────────
forbid "$PARSER" 'grammar_roles.lookup\(.+\)\.precedence' \
    'parser.zig retained the host precedence role decision'
forbid "$PARSER" 'grammar_roles.lookup\(.+\)\.assoc' \
    'parser.zig retained the host assoc role decision'
forbid "$PARSER" 'fn infixBinOp(' \
    'parser.zig retained the host infixBinOp helper'
forbid "$PARSER" 'idol_parser_infix_prec(' \
    'parser.zig retained the standalone infix ABI'
has "$PARSER" 'const triple = ((try self.currentParserEvent()) >> 23) & 0xFFFFFF;' \
    'Pratt no longer consumes event bits 23..46'
forbid "$ROOT/lib/compiler/parser.id" 'infix_prec: i64 = (kind: i64)' \
    'parser.id retained the standalone infix relation'
has "$ROOT/lib/compiler/parser.id" '(infix << 23)' \
    'event lost the packed Pratt triple'
forbid "$ROOT/src/parser/projection.c" 'int64_t infix_prec(int64_t kind)' \
    'tracked projection retained the standalone infix function'
forbid "$ROOT/build.zig" '-Dinfix_prec=idol_parser_infix_prec' \
    'build.zig retained the infix ABI rename'
has "$ROOT/tools/node/dev/parser/artifact" '(infix << 23)' \
    'event oracle lost the Pratt triple'

infixprecprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate infix scratch' >&2; exit 2; }
printf '%s\n' 'fn infixBinOp(kind: u8) ?Relation { return grammar_roles.infixRelation(kind); }' >"$infixprecprobe/old.zig"
printf '%s\n' 'const triple = (event >> 23) & 0xffffff;' >"$infixprecprobe/new.zig"
: >"$infixprecprobe/clean.zig"
infixprec_old=$(grep -cE 'infixBinOp|infixRelation' "$infixprecprobe/old.zig")
infixprec_new=$(grep -cE 'event >> 23' "$infixprecprobe/new.zig")
infixprec_clean=$(grep -cE 'infixBinOp|infixRelation|idol_parser_infix_prec|event >> 23' "$infixprecprobe/clean.zig" || true)
rm -rf -- "$infixprecprobe"
examined=$((examined + 1))
if [ "$infixprec_old" -ne 1 ] || [ "$infixprec_new" -ne 1 ] || [ "$infixprec_clean" -ne 0 ]; then
    bad "the event-infix detector is broken: old=$infixprec_old new=$infixprec_new clean=$infixprec_clean"
fi

# ── 2f''''. primitive, literal, and quoted identities come from event ───────
#
# Event bits 17..19 carry the three owner facts at the exact current coordinate.
# Saved quoted tokens retain the bit captured before speculative advance.
forbid "$PARSER" 'grammar_roles\.isDescriptor(' \
    'parser.zig retained the host primitive-descriptor role decision'
forbid "$PARSER" 'grammar_roles\.isLiteralKind(' \
    'parser.zig retained the host literal-kind role decision'
forbid "$PARSER" 'grammar_roles\.isQuotedKind(' \
    'parser.zig retained the host quoted-kind role decision'
has "$PARSER" 'fn currentParserPrimitive(self: *Parser) ParseError!bool {' \
    'Parser lost primitive event bit 17'
has "$PARSER" 'fn currentParserLiteral(self: *Parser) ParseError!bool {' \
    'Parser lost literal event bit 18'
has "$PARSER" 'fn currentParserQuoted(self: *Parser) ParseError!bool {' \
    'Parser lost quoted event bit 19'
has "$PARSER" 'const quoted = try self.currentParserQuoted();' \
    'parse_pack no longer preserves quoted identity before advancing'
forbid "$PARSER" 'idol_parser_is_primitive_descriptor_kind(' \
    'parser.zig retained the primitive ABI'
forbid "$PARSER" 'idol_parser_is_literal_kind(' \
    'parser.zig retained the literal ABI'
forbid "$PARSER" 'idol_parser_is_quoted_kind(' \
    'parser.zig retained the quoted ABI'
forbid "$ROOT/lib/compiler/parser.id" 'is_primitive_descriptor_kind: bool = (k: i64)' \
    'parser.id retained the primitive relation'
forbid "$ROOT/lib/compiler/parser.id" 'is_literal_kind: bool = (kind: i64)' \
    'parser.id retained the literal relation'
forbid "$ROOT/lib/compiler/parser.id" 'is_quoted_kind: bool = (kind: i64)' \
    'parser.id retained the quoted relation'
has "$ROOT/lib/compiler/parser.id" '(primitive << 17)' \
    'event lost primitive bit 17'
has "$ROOT/lib/compiler/parser.id" '(literal << 18)' \
    'event lost literal bit 18'
has "$ROOT/lib/compiler/parser.id" '(quoted << 19)' \
    'event lost quoted bit 19'
forbid "$ROOT/src/parser/projection.c" 'bool is_primitive_descriptor_kind(int64_t k)' \
    'tracked projection retained the primitive function'
forbid "$ROOT/src/parser/projection.c" 'bool is_literal_kind(int64_t kind)' \
    'tracked projection retained the literal function'
forbid "$ROOT/src/parser/projection.c" 'bool is_quoted_kind(int64_t kind)' \
    'tracked projection retained the quoted function'
forbid "$ROOT/build.zig" '-Dis_primitive_descriptor_kind=idol_parser_is_primitive_descriptor_kind' \
    'build.zig retained the primitive ABI rename'
forbid "$ROOT/build.zig" '-Dis_literal_kind=idol_parser_is_literal_kind' \
    'build.zig retained the literal ABI rename'
forbid "$ROOT/build.zig" '-Dis_quoted_kind=idol_parser_is_quoted_kind' \
    'build.zig retained the quoted ABI rename'
has "$ROOT/lib/compiler/token.id" 'literal(): str' \
    'token.id lost the literal owner row'
has "$ROOT/lib/compiler/token.id" 'quoted(): str' \
    'token.id lost the quoted owner row'
has "$ROOT/tools/node/dev/parser/artifact" '(primitive << 17)' \
    'event oracle lost primitive bit 17'
has "$ROOT/tools/node/dev/parser/artifact" '(literal << 18)' \
    'event oracle lost literal bit 18'
has "$ROOT/tools/node/dev/parser/artifact" '(quoted << 19)' \
    'event oracle lost quoted bit 19'

identityprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate identity scratch' >&2; exit 2; }
printf '%s\n' \
    'grammar_roles.isDescriptor(tok.kind);' \
    'grammar_roles.isLiteralKind(tok.kind);' \
    'grammar_roles.isQuotedKind(tok.kind);' >"$identityprobe/old.zig"
printf '%s\n' \
    'const primitive = ((event >> 17) & 1) != 0;' \
    'const literal = ((event >> 18) & 1) != 0;' \
    'const quoted = ((event >> 19) & 1) != 0;' >"$identityprobe/new.zig"
: >"$identityprobe/clean.zig"
identity_old=$(grep -cE 'isDescriptor|isLiteralKind|isQuotedKind' "$identityprobe/old.zig")
identity_new=$(grep -cE 'event >> (17|18|19)' "$identityprobe/new.zig")
identity_clean=$(grep -cE 'isDescriptor|isLiteralKind|isQuotedKind|idol_parser_is_(primitive_descriptor|literal|quoted)_kind|event >> (17|18|19)' "$identityprobe/clean.zig" || true)
rm -rf -- "$identityprobe"
examined=$((examined + 1))
if [ "$identity_old" -ne 3 ] || [ "$identity_new" -ne 3 ] || [ "$identity_clean" -ne 0 ]; then
    bad "the event identity detector is broken: old=$identity_old new=$identity_new clean=$identity_clean"
fi

# ── 2f'''''''. unary, glue, and update ordinals come from event ───────────────
examined=$((examined + 1))
if grep -Eq '^[[:space:]]*(const[[:space:]]+[^=]+=[[:space:]]*)?grammar_roles\.(unaryRelation|gluedRelation|updateRelation)\(' "$PARSER"; then
    bad 'parser.zig retained an executable host unary/glue/update relation decision'
fi
forbid "$PARSER" 'idol_parser_unary(' \
    'parser.zig retained the unary ABI'
forbid "$PARSER" 'idol_parser_glue(' \
    'parser.zig retained the glue ABI'
forbid "$PARSER" 'idol_parser_update(' \
    'parser.zig retained the update ABI'
has "$PARSER" '((try self.currentParserEvent()) >> 47) & 0x1F' \
    'unary no longer consumes event bits 47..51'
has "$PARSER" '((try self.currentParserEvent()) >> 52) & 0x1F' \
    'glue no longer consumes event bits 52..56'
has "$PARSER" '((try self.currentParserEvent()) >> 57) & 0x1F' \
    'update no longer consumes event bits 57..61'
forbid "$ROOT/lib/compiler/parser.id" '_unary: i64 = (kind: i64)' \
    'parser.id retained the unary relation'
forbid "$ROOT/lib/compiler/parser.id" '_glue: i64 = (kind: i64)' \
    'parser.id retained the glue relation'
forbid "$ROOT/lib/compiler/parser.id" '_update: i64 = (kind: i64)' \
    'parser.id retained the update relation'
has "$ROOT/lib/compiler/parser.id" '(unaryface << 47)' \
    'event lost unary bits 47..51'
has "$ROOT/lib/compiler/parser.id" '(glueface << 52)' \
    'event lost glue bits 52..56'
has "$ROOT/lib/compiler/parser.id" '(updateface << 57)' \
    'event lost update bits 57..61'
forbid "$ROOT/lib/compiler/parser.id" 'relationordinal:' \
    'parser.id restored a second relation-order scanner'
forbid "$ROOT/lib/compiler/parser.id" 'prefixordinal:' \
    'parser.id restored a second prefix-order scanner'
has "$ROOT/lib/compiler/token.id" '_encode: str = (which: i64)' \
    'token.id lost the compact owner ordinal projection'
has "$ROOT/lib/token/grammarrole.id" 'relation(): str' \
    'grammarrole.id lost the generated relation ordinal row'
has "$ROOT/lib/token/grammarrole.id" 'unary(): str' \
    'grammarrole.id lost the generated unary ordinal row'
forbid "$ROOT/src/parser/projection.c" 'int64_t _unary(int64_t kind)' \
    'tracked projection retained the unary function'
forbid "$ROOT/src/parser/projection.c" 'int64_t _glue(int64_t kind)' \
    'tracked projection retained the glue function'
forbid "$ROOT/src/parser/projection.c" 'int64_t _update(int64_t kind)' \
    'tracked projection retained the update function'
forbid "$ROOT/build.zig" '-D_unary=idol_parser_unary' \
    'build.zig retained the unary ABI rename'
forbid "$ROOT/build.zig" '-D_glue=idol_parser_glue' \
    'build.zig retained the glue ABI rename'
forbid "$ROOT/build.zig" '-D_update=idol_parser_update' \
    'build.zig retained the update ABI rename'
for name in infixRelation unaryRelation gluedRelation updateRelation; do
    forbid "$ROOT/src/grammar_roles.zig" "pub fn $name(" \
        "grammar_roles.zig restored dead host facade $name"
done
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_relation_faces(void)' \
    'parser artifact retained standalone relation-face differentials'
has "$ROOT/tools/node/dev/parser/artifact" '(unary << 47)' \
    'event oracle lost unary bits'
has "$ROOT/tools/node/dev/parser/artifact" '(glue << 52)' \
    'event oracle lost glue bits'
has "$ROOT/tools/node/dev/parser/artifact" '(update << 57)' \
    'event oracle lost update bits'

relationprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate relation-face scratch' >&2; exit 2; }
printf '%s\n' \
    'const a = grammar_roles.unaryRelation(kind);' \
    'const b = grammar_roles.gluedRelation(kind);' \
    'const c = grammar_roles.updateRelation(kind);' >"$relationprobe/old.zig"
printf '%s\n' \
    'const a = ((event >> 47) & 31) - 1;' \
    'const b = ((event >> 52) & 31) - 1;' \
    'const c = ((event >> 57) & 31) - 1;' >"$relationprobe/new.zig"
printf '%s\n' \
    'orders = "add sub mul div idiv mod pow band bor bxor lshift rshift concat eq neq lt gt leq geq and or contains matmul pipeline "' \
    'orders = "neg not len bnot compile "' >"$relationprobe/mirror.id"
: >"$relationprobe/clean.id"
relation_old=$(grep -cE 'grammar_roles\.(unaryRelation|gluedRelation|updateRelation)' "$relationprobe/old.zig")
relation_new=$(grep -cE 'event >> (47|52|57)' "$relationprobe/new.zig")
relation_mirror=$(grep -cE 'add sub mul div idiv|neg not len bnot compile' "$relationprobe/mirror.id")
relation_clean=$(grep -cE 'add sub mul div idiv|neg not len bnot compile' "$relationprobe/clean.id" || true)

# Positive control: mutate token.id's `_prefixorder` in a stage copy to swap
# `neg` and `compile`, regenerate lib/token/grammarrole.id, and verify the
# `unary(): str` row at every affected slot shifts. This is the "owner order
# drives the ABI result" claim made provable end-to-end. The mutation inverts
# `_unaryname` for `kind` whose prefix is `neg` or `compile`, so the encoded
# row byte at those slots must differ from the tracked row.
relation_owner=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap145-relation-owner.XXXXXX") || {
    echo 'gap-145 consumer gate: cannot allocate relation-owner scratch' >&2
    rm -rf -- "$relationprobe"
    exit 2
}
cp -R lib "$relation_owner/lib"
mkdir -p "$relation_owner/tools/node/dev/grammar"
cp tools/node/dev/grammar/emit "$relation_owner/tools/node/dev/grammar/emit"
cp tools/node/dev/grammar/idol_c_runtime_shim.c "$relation_owner/tools/node/dev/grammar/idol_c_runtime_shim.c"
chmod +x "$relation_owner/tools/node/dev/grammar/emit"
# emit requires the existing projections to be staged too, otherwise the
# preflight bails before the owner even runs.
cp -R src "$relation_owner/src"
# Swap `neg` and `compile` in the staged `_prefixorder`. The token.id uses
# space-separated names; the swap mutates the order so `_encode(1)` produces
# a different row byte at every slot whose prefix is `neg` or `compile`.
sed -i 's|_prefixorder = "neg not len bnot compile "|_prefixorder = "compile not len bnot neg "|' \
    "$relation_owner/lib/compiler/token.id"
relation_unary_tracked=$(grep -A1 '^unary(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *"//; s/"$//')
# The emit script resolves IDOL relative to its working directory, so the
# relative `./zig-out/bin/idol` would resolve into the stage tree where it
# does not exist. Pass an absolute path.
if (cd "$relation_owner" && IDOL="$ROOT/zig-out/bin/idol" sh tools/node/dev/grammar/emit --write) >/dev/null 2>&1; then
    relation_unary_swapped=$(grep -A1 '^unary(): str$' "$relation_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *"//; s/"$//')
else
    relation_unary_swapped=''
fi
rm -rf -- "$relationprobe"

examined=$((examined + 1))
if [ "$relation_old" -ne 3 ] || [ "$relation_new" -ne 3 ] || [ "$relation_mirror" -ne 2 ] || [ "$relation_clean" -ne 0 ]; then
    bad "the relation-face transfer detector is broken: old=$relation_old new=$relation_new mirror=$relation_mirror clean=$relation_clean"
fi
if [ -z "$relation_unary_tracked" ] || [ -z "$relation_unary_swapped" ] || [ "$relation_unary_tracked" = "$relation_unary_swapped" ]; then
    bad "the owner-order-shift probe is broken: tracked and swapped unary rows agree (tracked_len=${#relation_unary_tracked} swapped_len=${#relation_unary_swapped})"
fi

# ── 2f''''''''. offside layout consumes whole-pack event facts ───────────────
#
# The owner rows still distinguish six layout terminators from the five
# written empty-body closers. Public `event` emits those as bits 15 and 16.
# The opening face and every edge consume the event word through public
# `boundary`; dynamic column decisions stay private in `_layout_verdict`. Four
# standalone seams are deleted: opening, layout terminator, empty-body terminator,
# and direct layout verdict.
examined=$((examined + 1))
if grep -Eq '\.(kw_end|kw_else|kw_elseif|kw_until|kw_catch)\b.*=>\s*(\.close|return f\b)' "$PARSER"; then
    bad 'parser.zig retained an executable host layout-terminator switch arm'
fi
forbid "$ROOT/lib/compiler/parser.id" '_opening: i64 = (' \
    'parser.id retained the standalone opening relation'
has "$ROOT/lib/compiler/parser.id" '_layout_verdict: i64 = (offside: bool, open_col: i64, body_col: i64, terminator: bool, line: i64, col: i64)' \
    'parser.id lost the private dynamic _layout_verdict relation'
forbid "$ROOT/lib/compiler/parser.id" '_layout_terminator: bool = (kind: i64)' \
    'parser.id retained the standalone layout-terminator relation'
forbid "$ROOT/lib/compiler/parser.id" '_empty_body_terminator: bool = (kind: i64)' \
    'parser.id retained the standalone empty-body relation'
has "$ROOT/lib/compiler/parser.id" 'terminators: str = token.grammarrole.layoutterminator()' \
    'event lost the owner layout-terminator row'
has "$ROOT/lib/compiler/parser.id" 'empties: str = token.grammarrole.emptybodyterminator()' \
    'event lost the owner empty-body row'
has "$ROOT/lib/compiler/token.id" 'layoutterminator(): str' \
    'token.id lost the layoutterminator owner row'
has "$ROOT/lib/compiler/token.id" 'emptybodyterminator(): str' \
    'token.id lost the emptybodyterminator owner row'
has "$ROOT/lib/token/grammarrole.id" 'layoutterminator(): str' \
    'grammarrole.id lost the layoutterminator row'
has "$ROOT/lib/token/grammarrole.id" 'emptybodyterminator(): str' \
    'grammarrole.id lost the emptybodyterminator row'
forbid "$ROOT/src/parser/projection.c" 'int64_t _opening(bool idol_mode' \
    'tracked parser projection retained the opening ABI'
has "$ROOT/src/parser/projection.c" 'int64_t _layout_verdict(bool offside' \
    'tracked parser projection lost boundary-internal layout verdict'
forbid "$ROOT/src/parser/projection.c" 'bool _layout_terminator(int64_t kind)' \
    'tracked parser projection retained the standalone layout-terminator function'
forbid "$ROOT/src/parser/projection.c" 'bool _empty_body_terminator(int64_t kind)' \
    'tracked parser projection retained the standalone empty-body function'
forbid "$ROOT/build.zig" '-D_opening=idol_parser_opening' \
    'build.zig retained the opening ABI rename'
forbid "$ROOT/build.zig" '-D_layout_verdict=idol_parser_layout_verdict' \
    'build.zig retained the direct layout-verdict ABI rename'
forbid "$ROOT/build.zig" '-D_layout_terminator=idol_parser_layout_terminator' \
    'build.zig retained the layout-terminator ABI rename'
forbid "$ROOT/build.zig" '-D_empty_body_terminator=idol_parser_empty_body_terminator' \
    'build.zig retained the empty-body ABI rename'
has "$PARSER" 'const first_event = try self.currentParserEvent();' \
    'open_layout/empty-body no longer read the whole-pack event'
has "$PARSER" 'if (((first_event >> 16) & 1) != 0) break :empty;' \
    'empty-body handling no longer consumes event bit 16'
forbid "$PARSER" 'idol_parser_layout_verdict' \
    'parser.zig retained the direct layout-verdict ABI'
forbid "$PARSER" 'idol_parser_layout_terminator' \
    'parser.zig retained the standalone layout-terminator ABI'
forbid "$PARSER" 'idol_parser_empty_body_terminator' \
    'parser.zig retained the standalone empty-body ABI'
forbid "$PARSER" 'idol_parser_opening' \
    'parser.zig retained the standalone opening ABI'

# Detector probes — planted old/new/clean. Old carries the six-token host list;
# new carries the one event read plus opening and boundary consumers.
layoutprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate layout scratch' >&2; exit 2; }
printf '%s\n' \
    'fn open_layout(self: *Parser) LayoutFrame {' \
    '    switch (first.kind) {' \
    '        .kw_end =>,' \
    '        .kw_else =>,' \
    '        .kw_elseif =>,' \
    '        .kw_until =>,' \
    '        .kw_catch =>,' \
    '        .eof => return f,' \
    '    }' \
    '}' >"$layoutprobe/old.zig"
printf '%s\n' \
    'const first_event = try self.currentParserEvent();' \
    'idol_parser_boundary(true, count, offside, open_line, open, body, first_event, line, before, col, idol);' \
    'idol_parser_boundary(false, count, offside, open_line, open, body, first_event, line, before, col, idol);' >"$layoutprobe/new.zig"
: >"$layoutprobe/clean.zig"
layout_old=$(grep -cE '\.(kw_end|kw_else|kw_elseif|kw_until|kw_catch|eof)\b' "$layoutprobe/old.zig")
layout_new=$(grep -cE 'currentParserEvent|idol_parser_(opening|boundary)' "$layoutprobe/new.zig")
layout_clean=$(grep -cE 'currentParserEvent|idol_parser_(opening|boundary)|kw_end.*kw_else.*kw_catch' "$layoutprobe/clean.zig" || true)
examined=$((examined + 1))
if [ "$layout_old" -lt 6 ] || [ "$layout_new" -ne 3 ] || [ "$layout_clean" -ne 0 ]; then
    bad "the layout event detector is broken: old=$layout_old new=$layout_new clean=$layout_clean"
fi
rm -rf -- "$layoutprobe"

# Owner-driven positive control: mutate `layoutterminator()` in a stage copy
# of token.id to swap which slot carries `1`, regenerate grammarrole.id via
# the same emit recipe the parent uses, and verify the tracked row byte
# moves. The mutation must break at least one byte — at the swapped kind
# slot — and the gate verdict must rest on the byte being different, not
# on the source text.
layout_owner=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap145-layout-owner.XXXXXX") || {
    echo 'gap-145 consumer gate: cannot allocate layout-owner scratch' >&2
    exit 2
}
cp -R lib "$layout_owner/lib"
mkdir -p "$layout_owner/tools/node/dev/grammar"
cp tools/node/dev/grammar/emit "$layout_owner/tools/node/dev/grammar/emit"
cp tools/node/dev/grammar/idol_c_runtime_shim.c "$layout_owner/tools/node/dev/grammar/idol_c_runtime_shim.c"
chmod +x "$layout_owner/tools/node/dev/grammar/emit"
cp -R src "$layout_owner/src"
# The `layoutterminator()` predicate currently reads:
#     if kind == kindend or kind == kindelse or kind == kindelseif
#       bit = "1"
#     if kind == kinduntil or kind == kindcatch or kind == kindeof
#       bit = "1"
# Replace `kindend` with `kindreturn` in the staged token.id — `kindreturn`
# is not in the original six. The bit at `kindend` flips '1' to '0', and
# the bit at `kindreturn` flips '0' to '1'. The row bytes at those two
# slots MUST shift; the row MUST differ from the tracked row.
sed -i 's|kind == kindend or kind == kindelse|kind == kindreturn or kind == kindelse|' \
    "$layout_owner/lib/compiler/token.id"
layout_row_tracked=$(grep -A1 '^layoutterminator(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
if (cd "$layout_owner" && IDOL="$ROOT/zig-out/bin/idol" sh tools/node/dev/grammar/emit --write) >/dev/null 2>&1; then
    layout_row_swapped=$(grep -A1 '^layoutterminator(): str$' "$layout_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
else
    layout_row_swapped=''
fi
rm -rf -- "$layout_owner"

examined=$((examined + 1))
if [ -z "$layout_row_tracked" ] || [ -z "$layout_row_swapped" ] || [ "$layout_row_tracked" = "$layout_row_swapped" ]; then
    bad "the layout owner-order-shift probe is broken: tracked and swapped rows agree (tracked_len=${#layout_row_tracked} swapped_len=${#layout_row_swapped})"
fi

# ── 2f'''''''''. static member identity comes from whole-pack event ────────────
#
# Once `.` / `:` / `@` fixes member position, ordinary name and keyword
# identities are member faces. The owner row now crosses only in event bit 9;
# the standalone member relation/ABI is deleted.
forbid "$PARSER" 'fn is_name_like_kind(' \
    'parser.zig retained the host spelling-based member recognizer'
forbid "$PARSER" 'const s = k.spelling();' \
    'parser.zig still reconstructs member identity from display spelling'
forbid "$PARSER" 'std.ascii.isAlphabetic(s[0])' \
    'parser.zig still decides member identity from an ASCII display byte'
forbid "$PARSER" 'const text = tok.kind.spelling();' \
    'parse_at_path_segment still reconstructs a static segment from display spelling'
forbid "$PARSER" 'std.ascii.isAlphabetic(text[0])' \
    'parse_at_path_segment still classifies static segments from display bytes'
has "$PARSER" 'fn currentParserMember(self: *Parser) ParseError!bool {' \
    'Parser lost its whole-pack member observer'
member_calls=$(grep -cF 'self.currentParserMember()' "$PARSER" || true)
examined=$((examined + 1))
if [ "$member_calls" -ne 3 ]; then
    bad "all three production member consumers must index event bit 9 (calls=$member_calls)"
fi
forbid "$PARSER" 'idol_parser_member(' \
    'parser.zig retained the standalone member ABI'
has "$ROOT/lib/compiler/token.id" 'member(): str' \
    'token.id lost the owner-projected member row'
has "$ROOT/lib/token/grammarrole.id" 'member(): str' \
    'grammarrole.id lost the generated member row'
has "$ROOT/lib/compiler/parser.id" 'members: str = token.grammarrole.member()' \
    'whole-pack event no longer consumes the owner member row'
forbid "$ROOT/lib/compiler/parser.id" 'member: bool = (kind: i64)' \
    'parser.id retained the standalone member relation'
forbid "$ROOT/src/parser/projection.c" 'bool member(int64_t kind)' \
    'tracked parser projection retained the standalone member ABI'
forbid "$ROOT/build.zig" '-Dmember(kind)=idol_parser_member(kind)' \
    'build.zig retained the member ABI rename'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_member(void)' \
    'parser artifact retained the standalone member differential'
has "$ROOT/tools/node/dev/parser/artifact" '(member << 9)' \
    'whole-pack event differential lost the member bit'

memberprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate member scratch' >&2; exit 2; }
printf '%s\n' \
    'fn is_name_like_kind(k: TK) bool {' \
    '    const s = k.spelling();' \
    '    return std.ascii.isAlphabetic(s[0]);' \
    '}' >"$memberprobe/old.zig"
printf '%s\n' 'if (((static_event >> 9) & 1) == 0) return null;' >"$memberprobe/new.zig"
: >"$memberprobe/clean.zig"
member_old=$(grep -cE 'is_name_like_kind|k\.spelling|isAlphabetic' "$memberprobe/old.zig")
member_new=$(grep -cE 'static_event >> 9' "$memberprobe/new.zig")
member_clean=$(grep -cE 'is_name_like_kind|idol_parser_member|isAlphabetic|static_event >> 9' "$memberprobe/clean.zig" || true)
rm -rf -- "$memberprobe"
examined=$((examined + 1))
if [ "$member_old" -ne 3 ] || [ "$member_new" -ne 1 ] || [ "$member_clean" -ne 0 ]; then
    bad "the member transfer detector is broken: old=$member_old new=$member_new clean=$member_clean"
fi

# Owner-damage control: move the ordinary-name bit to the integer-literal slot
# in a private stage tree, regenerate through the canonical grammar emitter, and
# require the generated member row to change. This proves the verdict follows
# token.id rather than the host test or the tracked projection text.
member_owner=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap145-member-owner.XXXXXX") || {
    echo 'gap-145 consumer gate: cannot allocate member-owner scratch' >&2
    exit 2
}
cp -R lib "$member_owner/lib"
mkdir -p "$member_owner/tools/node/dev/grammar"
cp tools/node/dev/grammar/emit "$member_owner/tools/node/dev/grammar/emit"
cp tools/node/dev/grammar/idol_c_runtime_shim.c "$member_owner/tools/node/dev/grammar/idol_c_runtime_shim.c"
chmod +x "$member_owner/tools/node/dev/grammar/emit"
cp -R src "$member_owner/src"
python3 - "$member_owner/lib/compiler/token.id" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'if kind == kindname or (kind >= kindand and kind <= kindlet)'
new = 'if kind == kindintlit or (kind >= kindand and kind <= kindlet)'
if s.count(old) != 1:
    raise SystemExit(1)
p.write_text(s.replace(old, new))
PY
member_row_tracked=$(grep -A1 '^member(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
if (cd "$member_owner" && IDOL="$ROOT/zig-out/bin/idol" sh tools/node/dev/grammar/emit --write) >/dev/null 2>&1; then
    member_row_shifted=$(grep -A1 '^member(): str$' "$member_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
else
    member_row_shifted=''
fi
rm -rf -- "$member_owner"
examined=$((examined + 1))
if [ -z "$member_row_tracked" ] || [ -z "$member_row_shifted" ] || [ "$member_row_tracked" = "$member_row_shifted" ]; then
    bad "the member owner-shift probe is broken: tracked and shifted rows agree (tracked_len=${#member_row_tracked} shifted_len=${#member_row_shifted})"
fi

# ── 2f''''''''''. complete block boundary action comes from parser.id ─────────
#
# The production loop no longer combines a host LayoutVerdict wrapper with a
# second TokenKind switch. One graph-proven relation returns continue, close,
# misindent, or return-and-close plus the updated body column. The token owner
# supplies unconditional closers and conditional else/elseif identities.
forbid "$PARSER" 'const LayoutVerdict = enum' \
    'parser.zig retained the host layout verdict enum'
forbid "$PARSER" 'fn layout_verdict(' \
    'parser.zig retained the host layout verdict wrapper'
forbid "$PARSER" '.kw_end, .kw_until, .eof => break' \
    'parse_block_open retained the host unconditional boundary list'
forbid "$PARSER" '.rparen, .rbrace, .rbracket => break' \
    'parse_block_open retained the host bracket-boundary list'
has "$PARSER" 'idol_parser_boundary(' \
    'parse_block_open no longer delegates the complete boundary action'
boundary_calls=$(grep -cF 'idol_parser_boundary(' "$PARSER" || true)
examined=$((examined + 1))
if [ "$boundary_calls" -lt 2 ]; then
    bad "the production boundary ABI is not declared and consumed (calls=$boundary_calls)"
fi
has "$ROOT/lib/compiler/token.id" 'boundary(): str' \
    'token.id lost the unconditional block-boundary row'
has "$ROOT/lib/compiler/token.id" 'branch(): str' \
    'token.id lost the conditional branch row'
has "$ROOT/lib/token/grammarrole.id" 'boundary(): str' \
    'grammarrole.id lost the generated block-boundary row'
has "$ROOT/lib/token/grammarrole.id" 'branch(): str' \
    'grammarrole.id lost the generated branch row'
has "$ROOT/lib/compiler/parser.id" 'boundary: i64 = (opening: bool, count: i64, offside: bool, open_line: i64, open: i64, body: i64, edge: i64, line: i64, before: i64, col: i64, idol: bool)' \
    'parser.id lost the complete block-boundary relation'
has "$ROOT/src/parser/projection.c" 'int64_t boundary(bool opening, int64_t count, bool offside' \
    'tracked parser projection lost the block-boundary ABI'
has "$ROOT/build.zig" '-Dboundary(...)=idol_parser_boundary(__VA_ARGS__)' \
    'build.zig no longer renames the block-boundary ABI symbol'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_boundary(void)' \
    'parser artifact lost the exhaustive boundary behavior probe'

boundaryprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate boundary scratch' >&2; exit 2; }
printf '%s\n' \
    'switch (tok.kind) {' \
    '    .kw_end, .kw_until, .eof => break,' \
    '    .rparen, .rbrace, .rbracket => break,' \
    '}' >"$boundaryprobe/old.zig"
printf '%s\n' 'const action = idol_parser_boundary(false, count, offside, open_line, open, body, event, line, before, col, idol);' >"$boundaryprobe/new.zig"
: >"$boundaryprobe/clean.zig"
boundary_old=$(grep -cE 'kw_end.*kw_until.*eof|rparen.*rbrace.*rbracket' "$boundaryprobe/old.zig")
boundary_new=$(grep -cF 'idol_parser_boundary' "$boundaryprobe/new.zig")
boundary_clean=$(grep -cE 'kw_end.*kw_until.*eof|rparen.*rbrace.*rbracket|idol_parser_boundary' "$boundaryprobe/clean.zig" || true)
rm -rf -- "$boundaryprobe"
examined=$((examined + 1))
if [ "$boundary_old" -ne 2 ] || [ "$boundary_new" -ne 1 ] || [ "$boundary_clean" -ne 0 ]; then
    bad "the boundary transfer detector is broken: old=$boundary_old new=$boundary_new clean=$boundary_clean"
fi

# Owner-damage control: change one unconditional closer, one branch identity,
# one direct statement face, and one admission face
# in a private stage, regenerate both projections, and require both exact rows to
# move. A copied parser list or tracked-text oracle cannot satisfy this control.
boundary_owner=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap145-boundary-owner.XXXXXX") || {
    echo 'gap-145 consumer gate: cannot allocate boundary-owner scratch' >&2
    exit 2
}
cp -R lib "$boundary_owner/lib"
mkdir -p "$boundary_owner/tools/node/dev/grammar"
cp tools/node/dev/grammar/emit "$boundary_owner/tools/node/dev/grammar/emit"
cp tools/node/dev/grammar/idol_c_runtime_shim.c "$boundary_owner/tools/node/dev/grammar/idol_c_runtime_shim.c"
chmod +x "$boundary_owner/tools/node/dev/grammar/emit"
cp -R src "$boundary_owner/src"
python3 - "$boundary_owner/lib/compiler/token.id" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
changes = (
    ('if kind == kindend or kind == kinduntil or kind == kindeof',
     'if kind == kindbreak or kind == kinduntil or kind == kindeof'),
    ('if kind == kindelse or kind == kindelseif',
     'if kind == kinddo or kind == kindelseif'),
    ('if kind == kindwhile\n      face = 11',
     'if kind == kindwhile\n      face = 10'),
    ('if kind == kindlet\n      face = 8',
     'if kind == kindlet\n      face = 7'),
)
for old, new in changes:
    if s.count(old) != 1:
        raise SystemExit(1)
    s = s.replace(old, new)
p.write_text(s)
PY
boundary_row_tracked=$(grep -A1 '^boundary(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
branch_row_tracked=$(grep -A1 '^branch(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
statement_row_tracked=$(grep -A1 '^statement(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
admission_row_tracked=$(grep -A1 '^admission(): str$' lib/token/grammarrole.id | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
if (cd "$boundary_owner" && IDOL="$ROOT/zig-out/bin/idol" sh tools/node/dev/grammar/emit --write) >/dev/null 2>&1; then
    boundary_row_shifted=$(grep -A1 '^boundary(): str$' "$boundary_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
    branch_row_shifted=$(grep -A1 '^branch(): str$' "$boundary_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
    statement_row_shifted=$(grep -A1 '^statement(): str$' "$boundary_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
    admission_row_shifted=$(grep -A1 '^admission(): str$' "$boundary_owner/lib/token/grammarrole.id" | tail -1 | sed 's/^ *//;s/^"//;s/"$//')
else
    boundary_row_shifted=''
    branch_row_shifted=''
    statement_row_shifted=''
    admission_row_shifted=''
fi
rm -rf -- "$boundary_owner"
examined=$((examined + 1))
if [ -z "$boundary_row_tracked" ] || [ -z "$boundary_row_shifted" ] || [ "$boundary_row_tracked" = "$boundary_row_shifted" ]; then
    bad "the block-boundary owner-shift probe is broken (tracked_len=${#boundary_row_tracked} shifted_len=${#boundary_row_shifted})"
fi
examined=$((examined + 1))
if [ -z "$branch_row_tracked" ] || [ -z "$branch_row_shifted" ] || [ "$branch_row_tracked" = "$branch_row_shifted" ]; then
    bad "the branch owner-shift probe is broken (tracked_len=${#branch_row_tracked} shifted_len=${#branch_row_shifted})"
fi
examined=$((examined + 1))
if [ -z "$statement_row_tracked" ] || [ -z "$statement_row_shifted" ] || [ "$statement_row_tracked" = "$statement_row_shifted" ]; then
    bad "the statement owner-shift probe is broken (tracked_len=${#statement_row_tracked} shifted_len=${#statement_row_shifted})"
fi
examined=$((examined + 1))
if [ -z "$admission_row_tracked" ] || [ -z "$admission_row_shifted" ] || [ "$admission_row_tracked" = "$admission_row_shifted" ]; then
    bad "the admission owner-shift probe is broken (tracked_len=${#admission_row_tracked} shifted_len=${#admission_row_shifted})"
fi

# ── 2f'''''''''''. one complete block-edge answer from parser.id ─────────────
#
# The one boundary result owns loop action, clause face, written closure, and
# body-column establishment. Zig retains diagnostics, token consumption, and
# physical frame storage; no clause or closure recognizer survives beside it.
forbid "$PARSER" 'if (tok.kind == .kw_end) {' \
    'close_block retained the host written-end recognizer'
forbid "$PARSER" 'if (offside and tok.loc.line != self.prev_line and tok.loc.col > open.col)' \
    'close_block retained the host deep-end column decision'
forbid "$PARSER" 'return tok.loc.col >= open.col;' \
    'clause binding retained the host opener-column decision'
forbid "$PARSER" 'fn clause_binds(' \
    'parser.zig retained the two-call clause boolean wrapper'
forbid "$PARSER" 'fn clause_face(' \
    'parser.zig retained the standalone clause-face wrapper'
forbid "$PARSER" 'idol_parser_clause(' \
    'parser.zig retained the standalone clause ABI'
forbid "$PARSER" 'idol_parser_closure(' \
    'parser.zig retained the standalone closure ABI'
has "$PARSER" 'const decision = idol_parser_boundary(' \
    'close_block no longer consumes the complete boundary answer'
has "$PARSER" 'const action = (decision >> 4) & 0x7;' \
    'close_block no longer consumes boundary closure bits'
has "$PARSER" 'self.layout.clause_face = @intCast((decision >> 2) & 0x3);' \
    'parse_block_open no longer preserves the boundary clause face'
has "$PARSER" 'var face = self.last_layout.clause_face;' \
    'parse_if_clauses no longer consumes the completed block face'
has "$PARSER" 'Only the settled clause face remains observable.' \
    'return-edge observation lost the closed-frame invariant'
forbid "$PARSER" 'self.layout.body_col = @intCast((edge_decision >> 8)' \
    'return-edge observation mutates a block that action 3 already closed'
boundary_calls=$(grep -cF 'idol_parser_boundary(' "$PARSER" || true)
examined=$((examined + 1))
if [ "$boundary_calls" -lt 4 ]; then
    bad "complete boundary ABI is not declared and consumed at every edge (calls=$boundary_calls)"
fi
has "$ROOT/lib/compiler/parser.id" '# 1 close, 2 misindent, 3 parse return and close); bits 2..3 carry the clause face;' \
    'parser.id boundary lost the packed clause/closure contract'
has "$ROOT/lib/compiler/parser.id" 'sealed = closing << 4' \
    'parser.id boundary no longer packs written closure'
forbid "$ROOT/lib/compiler/parser.id" 'clause: i64 = (kind: i64, offside: bool, open: i64, col: i64)' \
    'parser.id retained the standalone clause relation'
forbid "$ROOT/lib/compiler/parser.id" 'closure: i64 = (offside: bool, idol: bool, kind: i64, line: i64, before: i64, col: i64, open: i64)' \
    'parser.id retained the standalone closure relation'
has "$ROOT/src/parser/projection.c" 'int64_t boundary(bool opening, int64_t count, bool offside' \
    'tracked parser projection lost the packed boundary ABI'
forbid "$ROOT/src/parser/projection.c" 'int64_t clause(int64_t kind, bool offside' \
    'tracked parser projection retained the standalone clause ABI'
forbid "$ROOT/src/parser/projection.c" 'int64_t closure(bool offside, bool idol' \
    'tracked parser projection retained the standalone closure ABI'
has "$ROOT/build.zig" '-Dboundary(...)=idol_parser_boundary(__VA_ARGS__)' \
    'build.zig no longer renames the packed boundary ABI symbol'
forbid "$ROOT/build.zig" '-Dclause(...)=idol_parser_clause(__VA_ARGS__)' \
    'build.zig retained the standalone clause ABI rename'
forbid "$ROOT/build.zig" '-Dclosure(...)=idol_parser_closure(__VA_ARGS__)' \
    'build.zig retained the standalone closure ABI rename'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_boundary_closure(void)' \
    'parser artifact lost the 48-case packed closure differential'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_boundary_clause(void)' \
    'parser artifact lost the exhaustive packed clause differential'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_boundary_opening(void)' \
    'parser artifact lost the boundary-opening differential'
has "$ROOT/tools/node/dev/parser/artifact" 'boundary-opening-cases=7' \
    'parser artifact lost the exact boundary-opening case count'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_opening(void)' \
    'parser artifact retained the standalone opening differential'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_closure(void)' \
    'parser artifact retained the standalone closure differential'
forbid "$ROOT/tools/node/dev/parser/artifact" 'static int verify_branch_clause(void)' \
    'parser artifact retained the standalone clause differential'

# One whole-pack static event producer now carries the token facts that used to
# be recomputed in every boundary call. Parser owns one fact pack, one event
# array, and one cursor coordinate across both.
has "$ROOT/lib/compiler/parser.id" 'event: i64 = (fact: []i64, count: i64, out: []i64, capacity: i64, idol: bool)' \
    'parser.id lost the whole-pack event producer'
has "$ROOT/build.zig" '"-Devent(...)=idol_parser_event(__VA_ARGS__)",' \
    'build lost the whole-pack event ABI rename'
has "$ROOT/src/parser/projection.c" 'int64_t event(int64_t fact[], int64_t count, int64_t out[], int64_t capacity, bool idol)' \
    'generated parser projection lost the event buffer ABI'
has "$PARSER" 'extern fn idol_parser_event(' \
    'parser.zig lost the generated whole-pack event ABI'
has "$PARSER" 'parser_events: ?[]i64 = null,' \
    'Parser lost its one cached event array'
has "$PARSER" 'fn ensureParserEvents(self: *Parser) ParseError![]const i64 {' \
    'Parser no longer derives events once from parser_facts'
has "$PARSER" 'const static_event = try self.currentParserEvent();' \
    'production statement dispatch no longer indexes the whole-pack event array'
has "$PARSER" 'self.alloc.free(events);' \
    'Parser no longer releases its event array with the owned pack'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_event(void)' \
    'parser artifact lost the whole-pack event differential'
has "$ROOT/tools/node/dev/parser/artifact" 'event-cases=228' \
    'parser artifact lost its exact whole-pack event count'
has "$ROOT/tools/node/dev/parser/artifact" 'event-boundary-slots=114' \
    'parser artifact lost exhaustive event-to-boundary coverage'
has "$ROOT/tools/node/dev/parser/artifact" 'short_out[i] != 777' \
    'whole-pack short-capacity control no longer proves non-mutation'
has "$ROOT/lib/compiler/parser.id" '(returns << 13) | (ending << 14) | (terminator << 15) | (empty << 16)' \
    'event lost return/end/layout/empty static facts'
has "$PARSER" 'const edge = try self.currentParserEvent();' \
    'close_block no longer supplies the whole-pack event to boundary'
has "$ROOT/lib/compiler/parser.id" '(layouttype << 62)' \
    'whole-pack event lost layout type-start recognition'
has "$PARSER" 'fn currentParserLayoutType(self: *Parser) ParseError!bool {' \
    'parser no longer consumes the settled layout type-start fact'
has "$PARSER" 'if (!try self.currentParserLayoutType()) return null;' \
    'layout type argument path bypasses the settled fact'
forbid "$PARSER" 'fn layout_arg_can_start_type(' \
    'parser.zig retained the host layout type-start recognizer'
has "$ROOT/lib/compiler/parser.id" '(assignment << 8)' \
    'whole-pack decision lost assignment-body recognition'
has "$PARSER" 'if (try self.currentParserBodyAssignment()) {' \
    'single-line function body bypasses the settled assignment fact'
forbid "$PARSER" 'fn func_body_should_use_expr_stmt(' \
    'parser.zig retained the host assignment-body recognizer'
has "$ROOT/lib/compiler/parser.id" '(declaration << 9)' \
    'whole-pack decision lost attributed-declaration dispatch recognition'
has "$PARSER" 'switch (try self.currentParserAttributeDispatch()) {' \
    'attributed declaration bypasses the settled dispatch face'
has "$PARSER" 'return self.currentParserAttributeDeclaration();' \
    'attribute attachment bypasses the settled declaration fact'
forbid "$PARSER" 'return switch (nxt.kind) {' \
    'parser.zig retained the host attribute declaration switch'
attributed_switch=$(sed -n '/fn parse_attributed_decl/,/fn strip_quotes/p' "$PARSER" | grep -cF 'switch (tok.kind) {' || true)
examined=$((examined + 1))
if [ "$attributed_switch" -ne 0 ]; then
    bad 'parser.zig retained the host attributed-declaration dispatch switch'
fi
has "$ROOT/tools/node/dev/parser/artifact" 'declaration-lane-cases=12' \
    'parser artifact lost the exact attribute declaration control count'
has "$ROOT/lib/compiler/parser.id" '(delimiter << 13)' \
    'whole-pack decision lost attribute delimiter extent'
has "$PARSER" 'currentParserAttributeBoundary() orelse return false' \
    'attribute lookahead bypasses the immutable-pack delimiter boundary'
attribute_switch=$(sed -n '/fn parse_at_starts_attribute_decl/,/fn is_known_attribute/p' "$PARSER" | grep -cF 'switch (tok.kind) {' || true)
examined=$((examined + 1))
if [ "$attribute_switch" -ne 0 ]; then
    bad 'parser.zig retained the host attribute-parenthesis delimiter switch'
fi
has "$ROOT/tools/node/dev/parser/artifact" 'delimiter-lane-cases=5' \
    'parser artifact lost the exact delimiter-boundary control count'
forbid "$PARSER" '(decision >> 36)' \
    'statement dispatch returned to the per-token boundary payload'
forbid "$PARSER" '(decision >> 41)' \
    'statement admission returned to the per-token boundary payload'
event_calls=$(grep -cF 'idol_parser_event(' "$PARSER" || true)
examined=$((examined + 1))
if [ "$event_calls" -ne 3 ]; then
    bad "whole-pack event ABI must have one declaration, one production call, and one direct test call: calls=$event_calls"
fi
examined=$((examined + 1))
if ! python3 - "$ROOT/lib/compiler/parser.id" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
start = s.index('boundary: i64 = (')
end = s.index('\n# Cursor on `(`', start)
body = s[start:end]
bad = (
    'token.grammarrole.statement()', 'token.grammarrole.admission()',
    'token.grammarrole.member()', 'token.grammarrole.boundary()',
    'token.grammarrole.branch()', 'token.grammarrole.layoutterminator()',
    'token.grammarrole.emptybodyterminator()', 'routed', 'denied',
)
raise SystemExit(any(item in body for item in bad))
PY
then
    bad 'dynamic boundary restored static token facts beside the whole-pack event producer'
fi

eventprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate event scratch' >&2; exit 2; }
printf '%s\n' \
    'for (tokens) |tok| {' \
    '    const decision = idol_parser_boundary(0, false, 0, 0, tok.kind, 0, 0, 0, idol);' \
    '    consume((decision >> 36) & 31);' \
    '}' >"$eventprobe/old.zig"
printf '%s\n' \
    'const written = idol_parser_event(facts.ptr, count, events.ptr, count, idol);' \
    'consume(events[index] & 31);' >"$eventprobe/new.zig"
: >"$eventprobe/clean.zig"
event_old=$(grep -cE 'idol_parser_boundary|decision >> 36' "$eventprobe/old.zig")
event_new=$(grep -cE 'idol_parser_event|events\[index\]' "$eventprobe/new.zig")
event_clean=$(grep -cE 'idol_parser_boundary|decision >> 36|idol_parser_event|events\[index\]' "$eventprobe/clean.zig" || true)
rm -rf -- "$eventprobe"
examined=$((examined + 1))
if [ "$event_old" -ne 2 ] || [ "$event_new" -ne 2 ] || [ "$event_clean" -ne 0 ]; then
    bad "the whole-pack event detector is broken: old=$event_old new=$event_new clean=$event_clean"
fi

# Direct statement dispatch rides on whole-pack event bits 0..4. The owner row maps
# every token identity; Zig switches only on the settled face. Contextual name
# and @ lookahead remain explicit follow-on work rather than being guessed here.
has "$ROOT/lib/compiler/token.id" 'statement(): str' \
    'token.id lost the direct statement owner row'
has "$ROOT/lib/token/grammarrole.id" 'statement(): str' \
    'grammarrole.id lost the generated statement row'
has "$ROOT/lib/compiler/parser.id" 'statements: str = token.grammarrole.statement()' \
    'whole-pack event no longer consumes the statement owner row'
has "$PARSER" 'const dispatch_face: u8 = @intCast(static_event & 0x1F);' \
    'parse_block_open no longer consumes whole-pack statement dispatch'
has "$PARSER" 'fn parse_stmt_face(self: *Parser, tok: Token, face: u8, admission: u8)' \
    'parser lost the face-driven statement materializer'
has "$PARSER" 'return switch (face) {' \
    'statement materializer no longer switches on the owner face'
forbid "$PARSER" '.kw_local => self.parse_local(),' \
    'parse_stmt retained the host local-statement kind branch'
forbid "$PARSER" '.kw_if => self.parse_if(),' \
    'parse_stmt retained the host if-statement kind branch'
forbid "$PARSER" '.kw_break => blk: {' \
    'parse_stmt retained the host break-statement kind branch'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_statement_face(void)' \
    'parser artifact lost the exhaustive statement-face differential'

# Source-family statement admission rides on whole-pack event bits 5..8. Macro is
# denied in every family; the remaining faces are denied only in canonical Idol.
has "$ROOT/lib/compiler/token.id" 'admission(): str' \
    'token.id lost the statement-admission owner row'
has "$ROOT/lib/token/grammarrole.id" 'admission(): str' \
    'grammarrole.id lost the generated admission row'
has "$ROOT/lib/compiler/parser.id" 'admissions: str = token.grammarrole.admission()' \
    'whole-pack event no longer consumes the admission owner row'
has "$PARSER" 'const admission_face: u8 = @intCast((static_event >> 5) & 0xF);' \
    'parse_block_open no longer consumes whole-pack statement admission'
has "$PARSER" 'fn denyRetiredStmtKeyword(_: *Parser, tok: Token, admission: u8)' \
    'retired-keyword diagnostics no longer materialize the owner admission face'
forbid "$PARSER" 'if (tok.kind == .kw_macro) {' \
    'retired statement admission restored the host macro identity branch'
forbid "$PARSER" '.kw_try, .kw_catch =>' \
    'retired statement admission restored the host try/catch identity switch'
has "$ROOT/tools/node/dev/parser/artifact" 'static int verify_admission(void)' \
    'parser artifact lost the 114-by-two admission differential'
has "$ROOT/tools/node/dev/parser/artifact" 'admission-cases=228' \
    'parser artifact lost its exact admission case count'
admission_calls=$(grep -cF 'self.statement_admission(' "$PARSER" || true)
examined=$((examined + 1))
if [ "$admission_calls" -lt 5 ]; then
    bad "non-block retired-keyword paths bypass the owner admission face: calls=$admission_calls"
fi

admissionprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate admission scratch' >&2; exit 2; }
printf '%s\n' \
    'if (tok.kind == .kw_macro) deny();' \
    'switch (tok.kind) { .kw_try, .kw_catch => deny(), else => {} }' >"$admissionprobe/old.zig"
printf '%s\n' \
    'const admission = (event >> 5) & 15;' \
    'switch (admission) { 1 => deny_macro(), 2 => deny_route(), else => {} }' >"$admissionprobe/new.zig"
: >"$admissionprobe/clean.zig"
admission_old=$(grep -cE 'tok\.kind|kw_macro|kw_try|kw_catch' "$admissionprobe/old.zig")
admission_new=$(grep -cE 'event >> 5|switch \(admission\)' "$admissionprobe/new.zig")
admission_clean=$(grep -cE 'tok\.kind|kw_macro|kw_try|kw_catch|event >> 5|switch \(admission\)' "$admissionprobe/clean.zig" || true)
rm -rf -- "$admissionprobe"
examined=$((examined + 1))
if [ "$admission_old" -ne 2 ] || [ "$admission_new" -ne 2 ] || [ "$admission_clean" -ne 0 ]; then
    bad "the admission transfer detector is broken: old=$admission_old new=$admission_new clean=$admission_clean"
fi

statementprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate statement scratch' >&2; exit 2; }
printf '%s\n' \
    'return switch (tok.kind) {' \
    '    .kw_if => parse_if(),' \
    '    .kw_break => parse_break(),' \
    '};' >"$statementprobe/old.zig"
printf '%s\n' \
    'const face = event & 31;' \
    'return switch (face) { 10 => parse_if(), 19 => parse_break(), else => parse_expr() };' >"$statementprobe/new.zig"
: >"$statementprobe/clean.zig"
statement_old=$(grep -cE 'switch \(tok\.kind\)|\.kw_if|\.kw_break' "$statementprobe/old.zig")
statement_new=$(grep -cE 'event & 31|switch \(face\)' "$statementprobe/new.zig")
statement_clean=$(grep -cE 'tok\.kind|kw_if|kw_break|event & 31|switch \(face\)' "$statementprobe/clean.zig" || true)
rm -rf -- "$statementprobe"
examined=$((examined + 1))
if [ "$statement_old" -ne 3 ] || [ "$statement_new" -ne 2 ] || [ "$statement_clean" -ne 0 ]; then
    bad "the statement transfer detector is broken: old=$statement_old new=$statement_new clean=$statement_clean"
fi

closingprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate closing scratch' >&2; exit 2; }
printf '%s\n' \
    'if (tok.kind == .kw_end) {' \
    '    if (offside and tok.loc.line != self.prev_line and tok.loc.col > open.col) return error.Bad;' \
    '}' \
    'return tok.loc.col >= open.col;' >"$closingprobe/old.zig"
printf '%s\n' \
    'const edge = idol_parser_boundary(false, count, offside, open_line, open, body, event, line, before, col, idol);' \
    'const action = (edge >> 4) & 7;' \
    'const face = (edge >> 2) & 3;' >"$closingprobe/new.zig"
: >"$closingprobe/clean.zig"
closing_old=$(grep -cE 'tok\.kind == \.kw_end|tok\.loc\.line != self\.prev_line|tok\.loc\.col >= open\.col' "$closingprobe/old.zig")
closing_new=$(grep -cF 'idol_parser_boundary' "$closingprobe/new.zig")
closing_clean=$(grep -cE 'kw_end|prev_line|open\.col|idol_parser_closure|idol_parser_boundary|idol_parser_clause' "$closingprobe/clean.zig" || true)
rm -rf -- "$closingprobe"
examined=$((examined + 1))
if [ "$closing_old" -ne 3 ] || [ "$closing_new" -ne 1 ] || [ "$closing_clean" -ne 0 ]; then
    bad "the complete boundary detector is broken: old=$closing_old new=$closing_new clean=$closing_clean"
fi

# ── 2g. raw producer kind validates through the owner-generated enum ─────────
#
# `kindFromRecord` selected `grammar_role_table.rows[ordinal].kind`, retaining a
# second runtime identity projection after token.id had already generated the
# sparse TokenKind enum. Decode now validates against that enum's generated
# field values and performs one physical backing conversion. No row lookup or
# host-authored kind table may return.
forbid "$DISPATCH" 'fn kindFromRecord(' \
    'lexer dispatch retained the ordinal-to-row kind bridge'
forbid "$DISPATCH" 'const grammar_role_table = @import("grammar_role_table.zig")' \
    'lexer dispatch retained the grammar-row runtime identity import'
has "$DISPATCH" 'for (@typeInfo(lexer.TokenKind).@"enum".field_values)' \
    'record decode no longer validates through the owner-generated enum values'
has "$DISPATCH" '@as(lexer.TokenKind, @fromBackingInt(raw_kind))' \
    'record decode no longer performs the checked physical enum conversion'

kindprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate record-kind scratch' >&2; exit 2; }
printf '%s\n' 'fn kindFromRecord(raw: i64) void {}' >"$kindprobe/old.zig"
printf '%s\n' 'const grammar_role_table = @import("grammar_role_table.zig");' >>"$kindprobe/old.zig"
printf '%s\n' 'for (@typeInfo(lexer.TokenKind).@"enum".field_values) |_| {}' >"$kindprobe/new.zig"
kind_old=$(grep -cE 'kindFromRecord|grammar_role_table' "$kindprobe/old.zig")
kind_new=$(grep -cF 'field_values' "$kindprobe/new.zig")
rm -rf -- "$kindprobe"
examined=$((examined + 1))
if [ "$kind_old" -ne 2 ] || [ "$kind_new" -ne 1 ]; then
    bad "the record-kind detector is broken: old=$kind_old new=$kind_new"
fi

# The constant host/generated selector always answered generated_native after
# production routing became unconditional. Keeping the enum and query preserved
# a fallback-shaped API with no lawful alternate answer.
forbid "$LEXER_BRIDGE" 'pub const TokenizeAuthority' \
    'lexer bridge reacquired the obsolete host/generated authority enum'
forbid "$LEXER_BRIDGE" 'pub fn tokenizeAuthority(' \
    'lexer bridge reacquired the constant authority selector'
selectorprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate selector scratch' >&2; exit 2; }
printf '%s\n' 'pub const TokenizeAuthority = enum { host_zig, generated_native };' >"$selectorprobe/old.zig"
printf '%s\n' 'pub fn tokenizeAuthority() TokenizeAuthority { return .generated_native; }' >>"$selectorprobe/old.zig"
selector_old=$(grep -cE 'TokenizeAuthority|tokenizeAuthority' "$selectorprobe/old.zig")
rm -rf -- "$selectorprobe"
examined=$((examined + 1))
if [ "$selector_old" -ne 2 ]; then
    bad "the authority-selector detector is broken: old=$selector_old"
fi

# The explicit ProductionPack wrapper, tokenizePack constructor and fromPack
# view only tested one another; production routes directly into Lexer. Keeping
# that closed loop preserved a second pack API with no consumer.
forbid "$DISPATCH" 'pub const ProductionPack' \
    'lexer dispatch reacquired the dead ProductionPack wrapper'
forbid "$DISPATCH" 'pub fn tokenizePack(' \
    'lexer dispatch reacquired the dead tokenizePack constructor'
forbid "$TOKEN_VIEW" 'pub fn fromPack(' \
    'token view reacquired the dead ProductionPack adapter'
packprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate dead-pack scratch' >&2; exit 2; }
printf '%s\n' 'pub const ProductionPack = struct {};' >"$packprobe/old.zig"
printf '%s\n' 'pub fn tokenizePack() void {}' >>"$packprobe/old.zig"
printf '%s\n' 'pub fn fromPack() void {}' >>"$packprobe/old.zig"
pack_old=$(grep -cE 'ProductionPack|tokenizePack|fromPack' "$packprobe/old.zig")
rm -rf -- "$packprobe"
examined=$((examined + 1))
if [ "$pack_old" -ne 3 ]; then
    bad "the dead-pack detector is broken: old=$pack_old"
fi

# `useDuoTokens` was the mutable installer after record decode. Production now
# returns one proven EOF-terminated slice to Parser; Lexer retains only cursor
# parking plus shebang/hint observations for its host-oracle boundary.
forbid "$LEXER" 'pub fn useDuoTokens(' \
    'lexer reacquired the mutable useDuoTokens installer'
forbid "$LEXER" 'pub const TokenStreamError' \
    'lexer retained the orphaned token-stream installer error type'
forbid "$LEXER" 'pub fn installProducerPack(' \
    'lexer reacquired the one-consumer producer-pack wrapper'
has "$DISPATCH" 'lex.cursor.index = lex.cursor.bytes.len;' \
    'production route no longer parks the host oracle after producer success'
has "$DISPATCH" 'lex.harvestCommentHints(toks);' \
    'production route no longer publishes producer comment hints'
has "$PARSER" 'self.pack_tokens = toks;' \
    'Parser no longer owns the returned immutable producer pack'
has "$PARSER" 'self.pack_index = 0;' \
    'Parser no longer seats the sole producer cursor'
useprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate installer scratch' >&2; exit 2; }
printf '%s\n' 'pub fn useDuoTokens() void {}' >"$useprobe/old.zig"
printf '%s\n' 'pub const TokenStreamError = error{};' >>"$useprobe/old.zig"
printf '%s\n' 'pub fn installProducerPack() void {}' >>"$useprobe/old.zig"
printf '%s\n' 'lex.cursor.index = lex.cursor.bytes.len;' >"$useprobe/new.zig"
printf '%s\n' 'lex.harvestCommentHints(toks);' >>"$useprobe/new.zig"
printf '%s\n' 'self.pack_tokens = toks;' >>"$useprobe/new.zig"
printf '%s\n' 'self.pack_index = 0;' >>"$useprobe/new.zig"
use_old=$(grep -cE 'useDuoTokens|TokenStreamError|installProducerPack' "$useprobe/old.zig")
use_new=$(grep -cE 'cursor.index = .*cursor.bytes.len|harvestCommentHints\(toks\)|pack_tokens = toks|pack_index = 0' "$useprobe/new.zig")
rm -rf -- "$useprobe"
examined=$((examined + 1))
if [ "$use_old" -ne 3 ] || [ "$use_new" -ne 4 ]; then
    bad "the token-installer detector is broken: old=$use_old new=$use_new"
fi

# ── 3. tree-sitter agrees with the one grammar-fact owner ───────────────────

python3 - "$ROOT" <<'PY'
import re, sys, os

root = sys.argv[1]

# `~=` and `!=` are ONE producer identity (`neq`, slot 89) with two source
# spellings. `kindspell` carries one field per slot, so the compat spelling has
# no row of its own. Declared here, printed on every run, rather than silently
# skipped -- an unresolved operator must be visible, not absent.
ALIAS = {'~=': '!='}

# Owner infix identities that tree-sitter does NOT render as a
# `binary_expression` row, each with the rule that owns it instead. This is a
# PROJECTION BOUNDARY, not a precedence fact: the owner says these have binding
# power, and the editor grammar spends it somewhere else.
#
# It exists so the check can demand SET EQUALITY. Requiring the tree-sitter set
# to be merely nonempty passed when an operator was DELETED -- drop `^` from
# grammar.js and its generator and the remaining 23 rows still agree with each
# other, so the editor grammar loses exponentiation and the gate says PASS.
# Every owner infix identity must now be in the table or in this list.
EXCLUDED = {
    '=':  'assignment statement, not an expression operator',
    '+=': 'compound assignment statement',
    '-=': 'compound assignment statement',
    '*=': 'compound assignment statement',
    '/=': 'compound assignment statement',
    '%=': 'compound assignment statement',
    '^=': 'compound assignment statement',
    '.':  'field_projection / field_expression',
    '@':  'attribute and world-access rules',
    'not': 'unary_expression',
    '!':  'unary_expression',
}

def owner_rows(path):
    src = open(path).read()
    body = re.search(r'pub const rows = \[slot_count\]RoleRow\{(.*)\n\};', src, re.S).group(1)
    by_spell = {}
    for line in (l for l in body.splitlines() if l.strip().startswith('.{')):
        if '.kind = null' in line:
            continue
        sp = re.search(r'\.spell = "((?:[^"\\]|\\.)*)"', line)
        if not sp or not sp.group(1):
            continue
        prec = re.search(r'\.precedence = (-?\d+)', line)
        asc = re.search(r'\.assoc = \.([a-z]+)', line)
        by_spell[sp.group(1)] = (
            int(prec.group(1)) if prec else 0,
            asc.group(1) if asc else 'none',
        )
    return by_spell

def ts_rows(path):
    src = open(path).read()
    body = re.search(r'binary_expression: \$ => choice\((.*?)\n    \),', src, re.S).group(1)
    out = []
    for m in re.finditer(r"prec\.(left|right)\((\d+), seq\(\$\.expression, '((?:[^'\\]|\\.)*)', \$\.expression\)\)", body):
        out.append((m.group(3), int(m.group(2)), m.group(1)))
    return out

def compare(owner, ts):
    """Returns (problems, pairs, resolved-count). Set equality first, then order."""
    problems = []
    resolved = []
    covered = set()
    for spell, level, side in ts:
        key = ALIAS.get(spell, spell)
        if key not in owner:
            problems.append('tree-sitter operator %r has no identity in the owner projection' % spell)
            continue
        if owner[key][0] == 0:
            problems.append('tree-sitter renders %r as an infix operator; the owner gives it no binding power' % spell)
            continue
        covered.add(key)
        resolved.append((spell, level, side, owner[key][0], owner[key][1]))

    # SET EQUALITY, the half that a nonempty check cannot see.
    infix = {sp for sp, (prec, _) in owner.items() if prec != 0}
    for sp in sorted(infix - covered - set(EXCLUDED)):
        problems.append(
            'owner infix identity %r is MISSING from tree-sitter binary_expression '
            'and is not a declared projection exclusion' % sp)
    for sp in sorted(set(EXCLUDED) - infix):
        problems.append(
            'declared exclusion %r is not an owner infix identity — the exclusion '
            'list has drifted from the owner' % sp)

    pairs = 0
    for i in range(len(resolved)):
        for j in range(i + 1, len(resolved)):
            a, b = resolved[i], resolved[j]
            pairs += 1
            ts_ord = (a[1] > b[1]) - (a[1] < b[1])
            au_ord = (a[3] > b[3]) - (a[3] < b[3])
            if ts_ord != au_ord:
                problems.append(
                    'binding order: %r (ts %d / owner %d) vs %r (ts %d / owner %d)'
                    % (a[0], a[1], a[3], b[0], b[1], b[3]))
    for spell, level, side, prec, asc in resolved:
        # tree-sitter has no nonassoc; `prec.left` is its only rendering of one.
        want = {'left': 'left', 'right': 'right', 'nonassoc': 'left', 'none': 'left'}[asc]
        if side != want:
            problems.append('associativity: %r is prec.%s, owner says %s' % (spell, side, asc))
    return problems, pairs, len(resolved)

owner_path = os.path.join(root, 'src/grammar_role_table.zig')
ts_path = os.path.join(root, 'ext/tree-sitter-idol/grammar.js')
owner = owner_rows(owner_path)
ts = ts_rows(ts_path)
if not ts:
    print('gap-145 consumer gate: FAIL tree-sitter binary_expression yielded 0 operators — '
          'the reader is broken, and a broken reader reports agreement')
    sys.exit(1)

infix_total = len([1 for _, (prec, _) in owner.items() if prec != 0])
problems, pairs, resolved = compare(owner, ts)
print('  owner infix identities: %d = %d rendered + %d declared exclusions'
      % (infix_total, infix_total - len(EXCLUDED), len(EXCLUDED)))
print('  tree-sitter operators: %d, resolved against the owner: %d, pairs compared: %d'
      % (len(ts), resolved, pairs))
print('  declared compat spellings sharing one identity: %s'
      % ', '.join('%s->%s' % kv for kv in sorted(ALIAS.items())))

# POSITIVE CONTROLS. Two, because the two failure modes are independent: a row
# that MOVED and a row that VANISHED. The second one is here because the first
# version of this check had only the nonempty guard, and a deleted operator
# passed it.
planted_move = [(sp, (99 if sp == '..' else lv), a) for (sp, lv, a) in ts]
ctl_move, _, _ = compare(owner, planted_move)
if not any(p.startswith('binding order') for p in ctl_move):
    print('gap-145 consumer gate: FAIL the comparator did not see a planted inversion — '
          'it cannot fail, so its pass means nothing')
    sys.exit(1)

planted_drop = [(sp, lv, a) for (sp, lv, a) in ts if sp != '^']
ctl_drop, _, _ = compare(owner, planted_drop)
if not any(p.startswith('owner infix identity') for p in ctl_drop):
    print("gap-145 consumer gate: FAIL the comparator did not see a planted DELETION of "
          "'^' — an editor grammar can lose an operator and still report agreement")
    sys.exit(1)
print('  positive controls: planted inversion detected (%d finding(s)); '
      'planted deletion of %r detected (%d finding(s))'
      % (len(ctl_move), '^', len(ctl_drop)))

if problems:
    for p in problems:
        print('gap-145 consumer gate: FAIL tree-sitter vs lib/compiler/token.id — %s' % p)
    sys.exit(1)
print('  tree-sitter operator table agrees with lib/compiler/token.id on every pair, '
      'and covers every owner infix identity')
sys.exit(0)
PY
ts_status=$?
examined=$((examined + 1))
if [ "$ts_status" -ne 0 ]; then
    bad 'tree-sitter is a second grammar authority that disagrees with lib/compiler/token.id'
fi

# ── 3b. the quote-blind arm count is a CEILING that falls ───────────────────
#
# 34 `.quoted =>` arms; 12 read the producer quote. The other 22 are mostly
# span, truthiness and emit-side realization and carry no text/byte claim, so
# this is not a demand for zero today. It is a demand that the number not GROW
# while GAP-145 is open, and it is COUNTED on every run rather than asserted in
# a comment, because every count this project wrote down as prose has decayed.
#
# Lower the ceiling as arms are converted. The pattern is
# `src/dnir_lower.zig` `graphTextConst`, which reads `sourceQuoteValue` off the
# graph instead of assuming text. Raising it is the edit that must be argued
# for.
#
# A DISCARD IS NOT AN OBSERVATION. This section was defeated once, measured
# 2026-08-26: 21 blind arms were rewritten as `blk: { _ = s.quote; ... }` — a
# Zig DISCARD that observes nothing — and the observing regex below counted
# every one of them, taking blind from 10 to 0 with zero semantic change. The
# planted control here is that exact shape. An arm observes the producer quote
# only by a route that can answer differently for the two faces.
QUOTE_BLIND_CEILING=13

# 2026-08-27 O5 (second wave): two name-kingdom folds in src/macro_expand.zig
# stopped guessing the face from AST shape and now observe the producer quote
# via `ast.quotedLiteralIsByteSequence(lit.quote)` — cloneCapture (~455, a
# byte-sequence literal is not an identifier, capture refuses) and
# typeArgFromExpr (~815, a byte-sequence literal is not a type name, the arm
# refuses) — taking blind 15 → 13. The first wave (six codegen folds, blind
# 21 → 15) landed via #189. Same route law: graph routes are unreachable in
# macro_expand (no graph handle); the producer-quote observation is canonical
# for this consumer. Lower the ceiling as the remaining face-neutral arms
# (span, truthy, emit, inert, carrier, test) are adjudicated away.

# 2026-08-27 O5: six text claims in src/codegen.zig stopped guessing the face
# from AST shape and now observe the producer quote via
# `ast.quotedLiteralIsByteSequence(lit.quote)` — fold_meta_string_expr (≈19817),
# metaStringFromExpr (≈20979, ≈20989), deriveNameValueFromExpr (≈21005),
# __comptimefixpoint (≈21253), and the generic emit_expr arm (≈17113, byte face
# now emits an honest commented placeholder instead of a text literal) — taking
# blind 21 → 15. The graph routes (`graphTextConst`/`sourceQuoteValue`) are
# unreachable in codegen: codegen has no graph handle (zero `semantic_graph`
# imports; the deletion witness is the `graphTextConst` prologue at
# src/dnir_lower.zig:2054). The producer-quote observation route was already
# canonical in codegen at 11155/16593/22546 and the fail-closed byte refusal
# follows comptime.zig:451. Lower the ceiling as the remaining face-neutral
# arms (span, truthy, emit, inert, carrier, test, name) are adjudicated away.

armregex='^[[:space:]]*(\.[a-z_, .]*)?\.quoted =>'
arms=$(grep -hE "$armregex" "$ROOT"/src/*.zig | wc -l | tr -d ' ')
# `.quoted` CONTAINS `.quote`, so a naive `grep -c '\.quote'` matches every arm
# and reports 0 blind ones. It did, on the first run of this check. `[^d]` is
# what separates reading the fact from naming the node. Discards `_ = x.quote`
# are STRIPPED before this count — see the block comment above.
observing=$(grep -hE "$armregex" "$ROOT"/src/*.zig \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -cE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst')
blind=$((arms - observing))
examined=$((examined + 1))
if [ "$arms" -eq 0 ]; then
    bad 'the quoted-arm census matched nothing — a reader that examines zero subjects reports agreement'
else
    printf '  quoted arms: %s, observing the producer quote: %s, blind: %s (ceiling %s)\n' \
        "$arms" "$observing" "$blind" "$QUOTE_BLIND_CEILING"
    if [ "$blind" -gt "$QUOTE_BLIND_CEILING" ]; then
        bad "quote-blind .quoted arms ROSE to $blind, ceiling $QUOTE_BLIND_CEILING"
    fi
fi

# POSITIVE CONTROL ON THE CLASSIFIER (law.gate.protocol). The planted defect is
# the shape that defeated this section, verbatim: a discard that the old
# observing regex counted. Two planted arms, no real observation between them,
# must classify as two BLIND arms — or this census again reports a zero it was
# never given.
ctl=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
{
    printf '%s\n' '        .quoted => |s| blk: { _ = s.quote; break :blk .{ .str = s.val }; },'
    printf '%s\n' '        .quoted => |lit| blk: { _ = lit.quote; break :blk true; },'
    printf '%s\n' '        .quoted => |s| graphTextConst(ctx.graph, expr),'
} >"$ctl/planted.zig"
: >"$ctl/clean.zig"
planted_arms=$(grep -hE "$armregex" "$ctl/planted.zig" | wc -l | tr -d ' ')
planted_obs=$(grep -hE "$armregex" "$ctl/planted.zig" \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -cE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst')
rm -rf -- "$ctl"
planted_blind=$((planted_arms - planted_obs))
if [ "$planted_arms" -ne 3 ] || [ "$planted_blind" -ne 2 ]; then
    bad "the arm classifier is broken: 3 planted arms counted as $planted_arms, the 2 discard baits as $planted_blind blind — a discard must never count as observing"
elif [ "$planted_obs" -ne 1 ]; then
    bad "the arm classifier no longer recognises the graph route: 1 observing arm counted as $planted_obs"
fi

# A DISCARD OF THE QUOTE FIELD IS BAIT, OUTRIGHT. Stripping discards from the
# observing count (above) closes the ADD-an-arm hole, but rewriting one of the
# 21 existing blind arms as a discard would still pass both §3b (blind stays at
# ceiling) and §3d (the line is stripped). There is no legitimate reason to
# write `_ = x.quote;` inside a `.quoted` arm: the field is either OBSERVED by
# a route that can answer differently for the two faces, or the arm is
# face-neutral and should not mention the field at all. The only use of the
# shape ever measured in this tree was census bait. Zero tolerance, positive
# control below.
baits=$(grep -hE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' "$ROOT"/src/*.zig | wc -l | tr -d ' ')
examined=$((examined + 1))
if [ "$baits" -ne 0 ]; then
    bad "$baits .quoted arm(s) DISCARD the quote field ('_ = x.quote;') — a discard observes nothing; read the face or drop the mention"
fi

# ── 3d. DIVERGENT QUOTE ARMS: the zero GAP-145 actually demands ─────────────
#
# §3b counts a SURFACE (blind arms) and §3c counts a FORM (tag tests); neither
# judges a member. The task seam is sharper than both: an arm is DIVERGENT when
# it can answer differently for the text face and the byte face of one quoted
# literal — the class GAP-207 measured printing a pointer at exit 0. Those are
# the arms that must be ZERO while the surface census may stay a ratchet.
#
# A grep cannot judge divergence line-locally, so the judgement lives in an
# allowlist ledger: an arm is divergent unless its line is classified here as
# one of the face-neutral kinds the gap enumerates ("span, truthiness, or
# emit-side realization and carry no text/byte claim"). The ledger is derived
# from the live tree, so a re-classification is a diff you can read, not a
# number you have to trust.
#
# Kinds:
#   observe     the arm asks the producer face (graph/descriptor route)
#   span        the answer is a location; no value law is touched
#   truthy      presence/non-nil law; identical for both faces
#   emit        emit-side realization; the physical carrier is shared by design
#   name        the literal is used as a NAME (identifier), not as a value
#   inert       the arm claims no effect and no value shape
#   carrier     the one deliberate `.str` carrier, adjudicated in GAP-145
#              "What this section does NOT claim"
#   test        inside a unit test, not a consumer decision
DIVERGENT_QUOTE_ARMS=0

divergent=$(grep -hE "$armregex" "$ROOT"/src/*.zig \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -vE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst' \
    | grep -vE '=> \|(\*?x\| x\.loc,|s\| s\.val,|x\| x\.val,|lit\| lit\.val,)|=> return true,|=> true,|=> \{\},|=> null,|\.str = s\.val \}, // both faces share this carrier|=> \|lit\| \.\{ \.named = lit\.val \},|=> non_numeric_out\.\* = true,|=> \|v\| \{$|=> \{$|=> \|s\| \.\{ \.string = s\.val \},|=> try self\.emit_c_string_literal\(expr\.quoted\.val\),|=> \|\*x\| if \(d\.kind == \.text\) \{$')
examined=$((examined + 1))
divcount=$(printf '%s' "$divergent" | grep -c . )
if [ "$divcount" -ne "$DIVERGENT_QUOTE_ARMS" ]; then
    bad "DIVERGENT quote arms ROSE to $divcount, must be $DIVERGENT_QUOTE_ARMS — classify the new arm in this ledger or convert it to a producer route"
fi
printf '  divergent quote arms: %s (must be %s)\n' "$divcount" "$DIVERGENT_QUOTE_ARMS"

# ── 3c. THE FORM THE ARM CENSUS CANNOT SEE ──────────────────────────────────
#
# Section 3b greps for a SWITCH ARM, `.quoted =>`. A consumer can reach the
# same node through a TAG TEST -- `p.* == .quoted`, `args[0].* == .quoted` --
# and every one of those was invisible to the census that has been reported as
# GAP-145's O5 number since it was first taken.
#
# This is not a hypothetical blind spot. `planConcat` in `src/dnir_lower.zig`
# is written in that form, and it folded the bytes of EVERY quoted part
# straight into a printf format string without asking which face it had:
#
#     print('abc' .. "Z")            answered abcZ   (folded, tag-test site)
#     x = 'abc' .. "Z" ; print(x)    refused         (switch-arm site)
#
# One fact with two answers, and the census that was supposed to be counting
# exactly this class could not see the site that carried it.
#
# WHAT THIS SECTION DOES AND DOES NOT CLAIM. It counts the surface; it does not
# judge each member. Most of these sites read a literal as a NAME -- a concept
# name, a `__emit` template, a field spelling -- where no text/byte law is
# observable, and deciding that line-locally is not something a grep can do
# honestly. So the number is a CEILING on the surface, not a blind count: it
# makes the form visible, which it was not, and refuses growth while GAP-145 is
# open. A site added here has to be argued for by raising the number.
QUOTE_TAGTEST_CEILING=88

tagtests=$(grep -h '== \.quoted\b' "$ROOT"/src/*.zig | wc -l | tr -d ' ')
examined=$((examined + 1))

# POSITIVE CONTROL ON THE COUNTER. The counter is the instrument; a ceiling
# reported by a pattern that matches nothing is the exact defect this whole
# file exists for (`tools/parity/grammar` grepped `ROLEIDENTITYCOUNT` at a file
# that writes `roleidentitycount` and was green for months). Two planted sites
# in a scratch file must be counted as two, and a file with none as none.
tagprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
cat > "$tagprobe/planted.zig" <<'PLANT'
    if (p.* == .quoted) return null;
    const v = if (args[0].* == .quoted) args[0].quoted.val else null;
    if (p.* == .int_lit) return null;
PLANT
: > "$tagprobe/clean.zig"
planted=$(grep -h '== \.quoted\b' "$tagprobe/planted.zig" | wc -l | tr -d ' ')
cleaned=$(grep -h '== \.quoted\b' "$tagprobe/clean.zig" | wc -l | tr -d ' ')
rm -rf -- "$tagprobe"
if [ "$planted" -ne 2 ] || [ "$cleaned" -ne 0 ]; then
    bad "the tag-test counter is broken: planted 2 counted as $planted, empty counted as $cleaned"
elif [ "$tagtests" -eq 0 ]; then
    bad 'the tag-test census matched nothing while its own control counted 2 -- it is reading the wrong tree'
else
    printf '  .quoted tag-test sites: %s (ceiling %s); counter control: 2 planted, 0 in empty\n' \
        "$tagtests" "$QUOTE_TAGTEST_CEILING"
    if [ "$tagtests" -gt "$QUOTE_TAGTEST_CEILING" ]; then
        bad "the .quoted tag-test surface ROSE to $tagtests, ceiling $QUOTE_TAGTEST_CEILING"
    fi
fi

# ── 3e. comment rules are EMITTED, not authored (GAP-145 O1 comments) ───────
#
# §3 closed the operator half of the second-grammar-authority seam. The comment
# half stood open until this section: `tail()` in scripts/treesitter_emit.id
# emitted ONE collapsed Lua `--` comment rule while the tracked grammar.js
# carried three hand-authored GAP-145 identities. The generator disclaimed
# authorship of rules that existed only as hand edits, and nothing compared
# them — the exact shape §3's header describes, one registry later.
#
# Three demands, in order of strength:
#
#   BYTE IDENTITY. The comment rules in the tracked artifact must be the exact
#   rendering of `tail()`'s Comments registry — same lines, same bytes. A hand
#   edit to grammar.js's comment rules, or a generator edit that does not
#   reproduce them, fails here.
#
#   OWNER RESOLUTION. Every comment identity the emission carries must resolve
#   against src/grammar_role_table.zig — the generated projection of
#   lib/compiler/token.id, the one grammar-fact owner (law.grammar.one):
#
#       hash_comment         -> .comment             spell "#",    canonical
#       compat_comment       -> .compat_comment      spell "--",   compat_only
#       compat_long_comment  -> .compat_long_comment spell "--[[", compat_only
#
#   SET EQUALITY both ways: an owner comment identity missing from the emission
#   fails (deleted rule), and an emitted rule with no owner identity fails
#   (invented grammar). The rule-name -> kind mapping is a declared projection
#   boundary, printed on every run, exactly like ALIAS in §3.
#
#   NO COLLAPSE. The emitted union must reference each identity by its own rule
#   name. Re-collapsing to one `token(choice(seq('--', ...)))` rule — the old
#   shape, which folded all three identities into one Lua comment — fails the
#   byte comparison, and this comment says why it must.
#
# Positive controls, both failure modes §3 learned separately: a rule whose
# TEXT moves, and a rule that VANISHES from the tracked artifact.
python3 - "$ROOT" <<'PY'
import re, sys, os

root = sys.argv[1]

# Declared projection boundary: tree-sitter rule name -> owner kind.
COMMENT_ALIAS = {
    'hash_comment': 'comment',
    'compat_comment': 'compat_comment',
    'compat_long_comment': 'compat_long_comment',
}

def unescape(s):
    # .id double-quoted escapes, left to right: \\ -> \, \n -> newline,
    # \' -> ', \" -> ".
    out, i = [], 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s) and s[i+1] in ('\\', 'n', "'", '"'):
            out.append({'\\': '\\', 'n': '\n', "'": "'", '"': '"'}[s[i+1]])
            i += 2
            continue
        out.append(s[i]); i += 1
    return ''.join(out)

def emitted_comment_rules(path):
    """Render tail()'s Comments registry: the b-accumulated lines after the
    'Comments {cbar}' banner line, up to (not including) the '  },' closer."""
    src = open(path).read().split('\n')
    anchors = [n for n, l in enumerate(src) if 'Comments {cbar}' in l]
    if len(anchors) != 1:
        return None, 'found %d "Comments" banner anchors, expected exactly 1' % len(anchors)
    rendered = []
    for l in src[anchors[0]+1:]:
        m = re.match(r'^\s*b = "\{b\}(.*)\\n"$', l)
        if not m:
            break
        rendered.append(unescape(m.group(1)))
    # drop the leading blank line of the section, stop before the closer
    body = [r for r in rendered]
    if body and body[0] == '':
        body = body[1:]
    if '  },' in body:
        body = body[:body.index('  },')]
    return body, None

def tracked_comment_rules(path):
    """The comment rules in grammar.js: from 'comment: $ =>' through the
    terminating \"']')),\" line, byte-exact, comments and all."""
    js = open(path).read().split('\n')
    starts = [n for n, l in enumerate(js) if l.strip().startswith('comment: $ =>')]
    if not starts:
        return None, 'no comment rule in the tracked grammar'
    i = starts[-1]
    ends = [n for n, l in enumerate(js) if n > i and "']'))," in l]
    if not ends:
        return None, 'comment rule in the tracked grammar does not terminate'
    return js[i:ends[0]+1], None

def owner_comment_rows(path):
    src = open(path).read()
    rows = {}
    for m in re.finditer(
            r'\.\{ \.kind = \.([a-z_]*comment[a-z_]*), \.spell = "([^"]*)"(.*?)\},',
            src, re.S):
        kind, spell, rest = m.group(1), m.group(2), m.group(3)
        rows[kind] = (spell, '.compat_only = true' in rest)
    return rows

def compare(gen, tracked, owner):
    problems = []
    if gen != tracked:
        for n in range(max(len(gen), len(tracked))):
            g = gen[n] if n < len(gen) else '<missing>'
            t = tracked[n] if n < len(tracked) else '<missing>'
            if g != t:
                problems.append(
                    'comment rule line %d differs — generator emits %r, '
                    'tracked grammar has %r' % (n, g, t))
                break
        if not problems:
            problems.append('comment rule blocks differ in length: generator %d '
                            'lines, tracked %d' % (len(gen), len(tracked)))
    # identity extraction from the EMITTED block. The union head `comment:` is
    # the query-compatible projection face, not a member identity; members are
    # the $.name references in its choice arms, and DEFINED identities are the
    # 4-space-indented rules that are union members.
    names = set(re.findall(r'\$\.([a-z_]*comment[a-z_]*),', '\n'.join(gen)))
    defined = set(re.findall(r'^\s{4}([a-z_]*comment[a-z_]*): \$ =>', '\n'.join(gen), re.M)) - {'comment'}
    if names != defined:
        problems.append('the comment union references %s but defines %s — a '
                        'referenced identity has no rule, or a rule is unreferenced'
                        % (sorted(names), sorted(defined)))
    owner_family = {k for k in owner if 'comment' in k}
    emitted_kinds = {COMMENT_ALIAS.get(n) for n in defined}
    for n in sorted(defined - set(COMMENT_ALIAS)):
        problems.append('emitted comment rule %r has no declared owner mapping — '
                        'invented grammar or a drifted projection boundary' % n)
    for k in sorted(owner_family - emitted_kinds):
        problems.append('owner comment identity %r is MISSING from the emitted '
                        'comment rules' % k)
    for k in sorted(emitted_kinds - owner_family):
        problems.append('emitted comment rule maps to %r, which the owner '
                        'projection does not carry' % k)
    # spelling and compat facts flow from the owner. compat_long_comment's
    # opener is spelled as three JS literals ('--', '[', '['), so the
    # spell-occurrence needle is the owner spell's first two characters for
    # spells three characters or longer.
    for n, k in sorted(COMMENT_ALIAS.items()):
        if k not in owner:
            continue
        spell, compat = owner[k]
        needle = spell if len(spell) < 3 else spell[:2]
        if needle not in '\n'.join(gen):
            problems.append('owner spell %r for %s does not occur in the emitted '
                            'rules' % (spell, k))
        want_compat = 'compat' in k
        if want_compat and not compat:
            problems.append('owner marks %s canonical, the emission treats it as '
                            'compat' % k)
        if not want_compat and compat:
            problems.append('owner marks %s compat_only, the emission treats it '
                            'as canonical' % k)
    return problems

gen_path = os.path.join(root, 'scripts/treesitter_emit.id')
js_path = os.path.join(root, 'ext/tree-sitter-idol/grammar.js')
owner_path = os.path.join(root, 'src/grammar_role_table.zig')

gen, err = emitted_comment_rules(gen_path)
if err:
    print('gap-145 consumer gate: FAIL comment-emission reader: %s' % err)
    sys.exit(1)
tracked, err = tracked_comment_rules(js_path)
if err:
    print('gap-145 consumer gate: FAIL tracked-comment reader: %s' % err)
    sys.exit(1)
if not gen or not tracked:
    print('gap-145 consumer gate: FAIL a comment reader yielded zero rules — '
          'a broken reader reports agreement')
    sys.exit(1)
owner = owner_comment_rows(owner_path)
if not owner:
    print('gap-145 consumer gate: FAIL owner projection carries no comment rows — '
          'reading the wrong tree')
    sys.exit(1)

problems = compare(gen, tracked, owner)

# POSITIVE CONTROLS. Two, because §3 proved the failure modes are independent:
# text that MOVES and rules that VANISH.
ctl_move = list(gen)
if len(ctl_move) > 6:
    ctl_move[6] = ctl_move[6].replace('prec(-1,', 'prec(-2,')
ctl_move_p = compare(ctl_move, tracked, owner)
if not any(p.startswith('comment rule line') for p in ctl_move_p):
    print('gap-145 consumer gate: FAIL the comment comparator did not see a '
          'planted text move — it cannot fail, so its pass means nothing')
    sys.exit(1)

ctl_drop = [l for l in gen if 'hash_comment' not in l]
ctl_drop_p = compare(ctl_drop, tracked, owner)
if not any('MISSING' in p or 'union references' in p or 'differ' in p for p in ctl_drop_p):
    print("gap-145 consumer gate: FAIL the comment comparator did not see the "
          "planted DELETION of 'hash_comment' — an editor grammar can lose a "
          "comment identity and still report agreement")
    sys.exit(1)

print('  comment rules: generator emission is byte-identical to the tracked '
      'grammar (%d lines)' % len(gen))
print('  comment identities: %s' % ', '.join(
    '%s->%s(%r)' % (n, k, owner[k][0] if k in owner else '?')
    for n, k in sorted(COMMENT_ALIAS.items())))
print('  positive controls: planted text move detected (%d finding(s)); planted '
      'deletion of hash_comment detected (%d finding(s))'
      % (len(ctl_move_p), len(ctl_drop_p)))

if problems:
    for p in problems:
        print('gap-145 consumer gate: FAIL comment authorship — %s' % p)
    sys.exit(1)
sys.exit(0)
PY
cmt_status=$?
examined=$((examined + 1))
if [ "$cmt_status" -ne 0 ]; then
    bad 'tree-sitter comment rules are authored or drifted, not emitted from the lexical owner'
fi

# ── 4. the identity-count parity probe must be able to run ──────────────────

if [ -x "$ROOT/tools/parity/grammar" ] || [ -r "$ROOT/tools/parity/grammar" ]; then
    examined=$((examined + 1))
    if ! sh "$ROOT/tools/parity/grammar" >/dev/null 2>&1; then
        bad 'tools/parity/grammar reports drift between host TokenKind identity and the generated projection'
    fi
fi

if [ "$violations" -eq 0 ]; then
    printf 'gap-145 consumer gate: PASS (%d check(s))\n' "$examined"
    exit 0
fi

printf 'gap-145 consumer gate: FAIL (%d violation(s), %d check(s))\n' "$violations" "$examined"
exit 1
