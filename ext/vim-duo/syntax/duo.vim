" Vim syntax file for Duo programming language
" Language: Duo (https://github.com/duo-lang/duo)
" Maintainer: Duo Contributors
" Last Change: 2026-06-11

if exists('b:current_syntax')
  finish
endif

" Duo is case-sensitive
syntax case match

" ---------------------------------------------------------------------------
" Keywords
" ---------------------------------------------------------------------------

" Lua core keywords
syntax keyword duoKeyword and break do else elseif end false for function fun
syntax keyword duoKeyword global goto if in local nil not or repeat return
syntax keyword duoKeyword then true until while

" Duo type keywords
syntax keyword duoType i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool void str

" Duo contextual keywords
syntax keyword duoContextual match try catch defer async await concept alias
syntax keyword duoContextual private extends

" Access / declaration modifiers
syntax keyword duoStorage const enum

" ---------------------------------------------------------------------------
" Operators
" ---------------------------------------------------------------------------

syntax match duoOperator "+\|-\|\*\|/\|//\|%\|\^\|#"
syntax match duoOperator "&\|~\||\|<<\|>>"
syntax match duoOperator "\.\.\.\?\|==\|~=\|<=\|>=\|<\|>"
syntax match duoOperator "=\|::\|->\|=>\|@\|?\|!"

" ---------------------------------------------------------------------------
" Comments
" ---------------------------------------------------------------------------

" Long block comments: --[[ ... ]]  with = levels  --[==[ ... ]==]
syntax region duoComment matchgroup=duoCommentDelim start="--\[\z(=*\)\[" end="\]\z1\]" contains=duoTodo,@Spell

" Line comments
syntax match duoComment "--\[\z(=*\)\[" contains=duoCommentDelim " partial — real block handled above
syntax match duoComment "--[^[\].].*$" contains=duoTodo,@Spell
syntax match duoComment "--$" contains=duoTodo

" TODO markers
syntax keyword duoTodo contained TODO FIXME HACK XXX BUG NOTE OPTIMIZE

" ---------------------------------------------------------------------------
" Strings
" ---------------------------------------------------------------------------

" Long strings: [[ ... ]]  with = levels  [==[ ... ]==]
syntax region duoLongString matchgroup=duoStringDelim start="\[\z(=*\)\[" end="\]\z1\]" contains=@Spell

" Double-quoted strings
syntax region duoString matchgroup=duoStringDelim start='"' skip='\\.' end='"' contains=duoStringEscape,@Spell

" Single-quoted strings
syntax region duoString matchgroup=duoStringDelim start="'" skip='\\.' end="'" contains=duoStringEscape,@Spell

" Escape sequences inside strings
syntax match duoStringEscape "\\[abfnrtv\\\"']" contained
syntax match duoStringEscape "\\\d\{1,3}" contained
syntax match duoStringEscape "\\x\x\x" contained
syntax match duoStringEscape "\\u{\x\{1,6}}" contained
syntax match duoStringEscape "\\z" contained

" ---------------------------------------------------------------------------
" Numbers
" ---------------------------------------------------------------------------

" Hex integers: 0xABC 0Xabc
syntax match duoNumber "\<0[xX]\x\+\>"

" Binary integers: 0b1010 0B1010
syntax match duoNumber "\<0[bB][01]\+\>"

" Floats: 3.14  .5  1.0e10  1.e-3  3e+7
syntax match duoNumber "\<\d\+\.\d*\%([eE][+-]\?\d\+\)\?\>"
syntax match duoNumber "\.\d\+\%([eE][+-]\?\d\+\)\?\>"
syntax match duoNumber "\<\d\+[eE][+-]\?\d\+\>"

" Plain integers: 0  42  1000 (must come after float/hex/binary patterns)
syntax match duoNumber "\<\d\+\>"

" Integer type suffixes: 42i32  1.0f64
syntax match duoNumber "\<\d\+[iu]\d\+\>"
syntax match duoNumber "\<\d\+\.\d*[fd]\d\+\>"
syntax match duoNumber "\<\d\+[fd]\d\+\>"

" ---------------------------------------------------------------------------
" Attributes:  @export  @inline  @deprecated("msg")  @implements(Concept)
" ---------------------------------------------------------------------------

syntax match duoAttribute "@\h\w*" contains=duoAttributeName nextgroup=duoAttributeArgs
syntax match duoAttributeName "@\h\w*" contained
syntax region duoAttributeArgs matchgroup=duoAttributeDelim start="(" end=")" contained contains=duoString,duoNumber,duoType,duoKeyword

" ---------------------------------------------------------------------------
" Type annotations (heuristic: identifiers followed by type-looking things)
" ---------------------------------------------------------------------------

" Composite type markers:  ?T  *T  [N]T
syntax match duoTypeOp "[?*\[\]]" containedin=ALL

" ---------------------------------------------------------------------------
" Highlighting groups
" ---------------------------------------------------------------------------

highlight default link duoKeyword      Keyword
highlight default link duoType         Type
highlight default link duoContextual   Keyword
highlight default link duoStorage      StorageClass

highlight default link duoOperator     Operator

highlight default link duoComment      Comment
highlight default link duoCommentDelim Comment
highlight default link duoTodo         Todo

highlight default link duoString       String
highlight default link duoLongString   String
highlight default link duoStringDelim  String
highlight default link duoStringEscape SpecialChar

highlight default link duoNumber       Number

highlight default link duoAttribute    PreProc
highlight default link duoAttributeName PreProc
highlight default link duoAttributeArgs PreProc
highlight default link duoAttributeDelim PreProc

highlight default link duoTypeOp       Operator

let b:current_syntax = 'duo'
