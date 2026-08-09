# duon 0.1 — Formal Grammar (Pass 108)

**The first credibility artifact** (Pass 106 §1). The surface as EBNF over an
offside lexer, with the precedence table and the five ambiguity resolutions
stated as rules. The parser is generated from this file — the grammar is data —
and this document is **normative** until the graph service hosts it.

## 1. Lexical layer

```
input      → utf8 text, normalized: tabs→4sp; trailing ws stripped
tokens     → NEWLINE, INDENT, DEDENT emitted à la offside:
             NEWLINE at each physical line end NOT inside open ( [ { ;
             INDENT/DEDENT on column change against the indent stack;
             a dedent to a column not on the stack ⇒ LAYOUT ERROR
             (never an alternate parse — ceilings keep the stack ≤ 4)
comment    → "--" to end of line (dropped; doc blocks are checks)
name       → [a-z][a-z0-9]*            -- single word; acronyms lowercase
number     → digit [digit _]* ["." digit+] | "0x" hex+ | "0b" bin+
             ("_" legal only between digits)
byte       → "'" char "'"
string     → '"' (text | "{" expr "}")* '"'      -- holes are full exprs
rawstring  → "[[" text "]]"
END        → "end" (accepted, DELETED by the reader — resync only)
```

## 2. Precedence (tightest → loosest); all left-assoc unless noted

```
1  postfix:  .name   :name(args)   [expr…]   (args)   @rel|@Proto   {…}-call
             "str"-call                       -- the two parenless operands
2  prefix:   not  -  ~  #  .name(leading)  :name(leading)  @(bare)
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
while      → "while" cond ( inline [ ";" stmt ] | block )
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
           | tableliteral | string             -- brace-call, string-call
primary    → name | number | byte | string | rawstring
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

**R3 — parenless calls.** Only postfix positions accept a `string` or
`tableliteral` as an argument-forming token; they bind at level 1; at most one
per spine (enforced post-parse); and they are **forbidden in `cond` and in
`for`-iterable position** (self-delimitation). So `while sh "x" …` is a layout
error, never a surprise parse.

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
is the self-hosted one. Two known points of contact with reality:

- **R5 is enforced as of afad6f3.** Infix `@` folded to `.matmul` used to
  type-check clean in `.duo` — a green check on a construct with no meaning. It
  is now an error in `.duo` with the `.lua` dialect untouched, which is exactly
  what "the grammar cannot express a directive" requires of the implementation.
- **The offside layer is real.** Blocks close by dedent (`4b5d2d8`), with
  `examples/spec100/offside.duo` and two `examples/compile_fail/offside_*.duo`
  fixtures asserting that a dedent matching no legal shape is a DIAGNOSTIC and
  never an alternate parse.

The gap between this file and `src/parser.zig` is the work; naming the gap is
what makes it measurable.
