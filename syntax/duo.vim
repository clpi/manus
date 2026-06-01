" Duo syntax highlighting
" Based on Lua syntax with Duo-specific extensions

if exists("b:current_syntax")
  finish
endif

" Keywords
syn keyword duoKeyword fun function req global local const struct
syn keyword duoConditional if then elseif else end
syn keyword duoRepeat while repeat until for in do break
syn keyword duoKeyword return goto
syn keyword duoBoolean true false nil
syn keyword duoOperator and or not

" Type annotations
syn match duoType ":\s*i64"
syn match duoType ":\s*f64"
syn match duoType ":\s*str"
syn match duoType ":\s*bool"
syn match duoType ":\s*void"
syn match duoType "<[A-Za-z]>"

" Strings
syn region duoString start=+'+ end=+'+ skip=+\\\\\|\\'+
syn region duoString start=+"+ end=+"+ skip=+\\\\\|\\"+
syn region duoString start='\[\[' end='\]\]'

" Numbers
syn match duoNumber "\<\d\+\>"
syn match duoNumber "\<\d\+\.\d\+\>"
syn match duoNumber "\<\d\+[eE][+-]\?\d\+\>"
syn match duoNumber "\<0x\x\+\>"

" Comments
syn match duoComment "--.*$"

" Metaprogramming operator
syn match duoSpecial "##"

" Generics
syn match duoSpecial "<"
syn match duoSpecial ">"

" Operators
syn match duoOperator "+"
syn match duoOperator "-"
syn match duoOperator "*"
syn match duoOperator "/"
syn match duoOperator "%"
syn match duoOperator "^"
syn match duoOperator "#"
syn match duoOperator "=="
syn match duoOperator "~="
syn match duoOperator "<"
syn match duoOperator ">"
syn match duoOperator "<="
syn match duoOperator ">="
syn match duoOperator "\.\."

" Function calls
syn match duoFunction "[a-zA-Z_][a-zA-Z0-9_]*("me=e-1

" Standard library functions
syn keyword duoFunction print assert error type tostring tonumber
syn keyword duoFunction ipairs pairs next
syn keyword duoFunction math string table io os
syn keyword duoFunction require load loadfile dofile

" Highlighting
hi def link duoKeyword Keyword
hi def link duoConditional Conditional
hi def link duoRepeat Repeat
hi def link duoBoolean Boolean
hi def link duoOperator Operator
hi def link duoType Type
hi def link duoString String
hi def link duoNumber Number
hi def link duoComment Comment
hi def link duoFunction Function
hi def link duoSpecial Special

let b:current_syntax = "duo"