# Idsem 0.1 - Formal Grammar

This is the normative human projection of C0's grammar until the graph service
hosts it. The parser is not yet generated from this file. `GAP-134` owns that
missing grammar projection; `GAP-145` owns the lexical identity migration. The
implementation accepting a form does not make it canonical.

## 1. Lexical layer

```
input      → utf8 text, normalized: tabs→4sp; trailing ws stripped
tokens     → NEWLINE, INDENT, DEDENT emitted à la offside:
             NEWLINE at each physical line end NOT inside open ( [ { ;
             INDENT/DEDENT on column change against the indent stack;
             a dedent to a column not on the stack ⇒ LAYOUT ERROR
             (never an alternate parse — ceilings keep the stack ≤ 4)
shebang    → "#!" text NEWLINE, only at byte zero; source provenance
comment    → "#" text NEWLINE; trivia with zero semantic authority
name       → [a-z][a-z0-9]*            -- single word; acronyms lowercase
number     → digit [digit _]* ["." digit+] | "0x" hex+ | "0b" bin+
             ("_" legal only between digits)
bytes      → "'" byteitem* "'"         -- byte sequence, never text/char
text       → '"' (textitem | "{" expr "}")* '"'
backtick   → RESERVED
END        → "end" (accepted, DELETED by the reader — resync only)
```

`text` may span physical lines without becoming another literal kind. When the
opening quote is followed immediately by a newline, that newline and the final
newline before a closing quote on its own line are omitted. The whitespace
prefix before the closing quote is removed exactly from every nonblank content
line; a nonblank line with less indentation is an error. Blank lines normalize
to empty lines. This rule is deterministic and formatter-stable.

`bytes` accepts byte-oriented escapes such as `\xNN`, `\n`, `\\`, and `\'`.
Ordinary source characters contribute their UTF-8 bytes. Unicode escape syntax
inside a byte literal is rejected until separately admitted; it never produces
a host-language character integer. Byte literals do not interpolate.

The compatibility projection separately recognizes Lua `--` comments, Lua long
comments, Lua long strings, and historical Lua single-quoted text. These carry
compatibility provenance and never share canonical token identity. A historical
single-quoted text literal canonicalizes to double-quoted text before it can be
read as native Idsem. Backtick remains tokenizable but has no canonical grammar
role and never implies process execution.

Delimiter roles are closed. `()` is ordinary callable application and grouping;
`{}` is structured pack, descriptor home, and descriptor application; `[]` is
computed/indexed projection; `.` is statically named projection; and `:` carries
its admitted descriptor, subject, and home roles. These syntax facts disappear
after resolution except as provenance. No delimiter implies allocation, place,
boxing, dispatch, or another semantic relation identity.

## 2. Precedence (tightest → loosest); all left-assoc unless noted

```
1  postfix:  .name   :name(args)   [expr…]   (args)   @rel|@Proto
             {…} descriptor-application
2  prefix:   not  -  ~  .name(leading)  :name(leading)  @(bare)
3  ^                                          (right)
4  * / %
5  + -
6  << >>
7  & (band | refine — operand space selects)
8  ~ (bxor)   | (bor | union)
9  ..
10 == != < <= > >=
11 and         -- in binding conditions: the guard-chain link
12 or
13 = += -= *= /= (binding / update; also the binding-condition form)
14 , (pack / group)
```

## 3. Grammar (EBNF; `{}`=repeat, `[]`=optional, `|`=alt)

```
module     → { stmt } EOF
block      → NEWLINE INDENT { stmt } DEDENT
stmt       → binding | shapedecl | expr | ifstmt | while | for | return
           | "break" | "continue" | check
binding    → target { "," target } assignop expr { "," expr }
target     → name | destructure | place
destructure→ "{" name { "," name } "}"
place      → postfixexpr                       -- a.b, a[k], .b (anchored)
shapedecl  → name ":" shape [ "=" expr ]       -- IS [+ HOLDS]

ifstmt     → "if" cond ( inline [ "else" inline ] | block [ "else" (ifstmt|block) ] )
while      → "while" cond ( inline | block )    -- P119: no ";" tail
for        → "for" name { "," name } "in" postfixexpr ( inline | block )
inline     → stmt                              -- exactly one; self-delimited
cond       → chain
chain      → link { "and" link }               -- guard chain (Pass 101)
link       → [ target { "," target } "=" ] orexpr
return     → "return" [ expr { "," expr } ]
check      → "check" "(" expr ")"

expr       → orexpr | fn
fn         → "(" [ params ] ")" [ ":" shape ] ( expr | block )
params     → param { "," param } | ".." name
param      → name [ ":" shape ] [ "=" expr ]
orexpr     → andexpr { "or" andexpr }
andexpr    → cmpexpr { "and" cmpexpr }
cmpexpr    → catexpr { cmpop catexpr }
…                                              -- per the precedence table
unary      → { prefixop } postfixexpr
postfixexpr→ primary { postfix }
postfix    → "." name | ":" name callargs | "[" expr { "," expr } "]"
           | "(" [ args ] ")" | "@" ( name | postfixexpr )
           | tableliteral                      -- descriptor application only
primary    → name | number | bytes | text
           | "(" expr ")" | tableliteral | "@" [ tableliteral ]
           | "." name | ":" name callargs      -- leading lens / sibling call
tableliteral → "{" [ field { fieldsep field } ] "}"
field      → name | name "=" expr | name ":" shape | "[" expr "]" "=" expr
           | ".." expr | fn-slot…
shape      → postfixexpr { ("|" | "&") postfixexpr }    -- descriptor space
```

## 4. The five ambiguity resolutions (rules, not luck)

**R1 — `:` (IS vs INVOKE).** After a *name in statement/field position* with no
call group ⇒ shapedecl (IS). Anywhere a left operand value exists and a call
group follows ⇒ INVOKE. Leading `:name(` with no left operand ⇒ sibling invoke.
The forms cannot coincide: **IS never takes an argument group; INVOKE always
does.**

**R2 — leading `.name` (lens vs case).** Argument position ⇒ lens over each
element, *always* (Pass 98). Descriptor-expected position — RHS of `==` against
a known case-set, constructor field, dispatch key, contract, `return` under a
case contract — ⇒ the case. Neither context ⇒ diagnostic ("state the shape or
qualify"). The parser produces ONE node (`anchorref`); *resolution* is semantic,
so the grammar is unambiguous because the spelling is one production.

**R3 — descriptor application.** A postfix `tableliteral` records descriptor
application syntax. Resolution requires the subject to supply a descriptor;
an ordinary callable in the same position is rejected rather than reinterpreted
as a brace call. Ordinary callable application always uses `callargs`.

**R4 — binding conditions and guard chains.** Inside `cond`, `=` binds a
`link`'s targets to its `orexpr`, and `and` sequences links. Therefore
`while b = :peek() and p(b)` parses as `(b = :peek()) and (p(b))` **by the chain
production**, not by a precedence exception — and outside `cond`, `=` is a
statement and cannot appear in expressions at all.

**R5 — `@` (bare vs postfix vs constructor).** Postfix `@` requires a left
operand (level 1). Bare `@` is a primary; immediately followed by `{` it is the
enclosing-descriptor constructor — one production, `"@" [tableliteral]`. **No
prefix-`@`-expression production exists: the grammar cannot express a
directive.**

## 5. Notes

The grammar is **LL(2) modulo the offside layer**: one token of lookahead past
`name` decides shapedecl vs binding vs call, and `cond` needs the second token
to separate `target =` from `orexpr`.

X8, TMP-1, chain-collapse and the one-liner limits are **canonicalizer laws, not
grammar** — the grammar accepts more than the canon emits, by design (repair
over rejection).

The generated parser plus a fuzz corpus against these productions ships with the
evaluator (G-D1's sibling fixture).

## 6. Status in this repository

This document is normative and the parser is **not yet generated from it**.
`src/parser.zig` is hand-written and predates this grammar; `lib/std/compiler/parser.duo`
is the self-hosted target. Three known points of contact with reality:

- **R5 is enforced as of afad6f3.** Infix `@` folded to `.matmul` used to
  type-check clean in `.duo` — a green check on a construct with no meaning. It
  is now an error in `.duo` with the `.lua` dialect untouched, which is exactly
  what "the grammar cannot express a directive" requires of the implementation.
- **The offside layer is real.** Blocks close by dedent (`4b5d2d8`), with
  `examples/spec100/offside.duo` and two `examples/compile_fail/offside_*.duo`
  fixtures asserting that a dedent matching no legal shape is a DIAGNOSTIC and
  never an alternate parse.
- **Lexical closure is not implemented.** Both live lexers currently emit one
  string token for single quotes, double quotes, and Lua long strings. They
  still tokenize `#` as length, and parser/tooling paths reconstruct delimiters
  from source. `GAP-145` requires distinct token identities and generated roles
  before parser or corpus migration.

The gap between this file and `src/parser.zig` is the work; naming the gap is
what makes it measurable.
