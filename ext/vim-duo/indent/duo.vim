if exists('b:did_indent')
  finish
endif
let b:did_indent = 1

setlocal autoindent
setlocal indentexpr=GetDuoIndent()
setlocal indentkeys=0{,0},0),0],!^F,o,O,e,0=end,0=else,0=elseif,0=then,0=until,0=catch

if exists('*GetDuoIndent')
  finish
endif

function GetDuoIndent()
  let l:line = getline(v:lnum)
  let l:prev = getline(v:lnum - 1)
  let l:ind = indent(v:lnum - 1)

  " Increase indent after block-opening keywords
  if l:prev =~# '\v^\s*(if|elseif|else|for|while|repeat|do|fun%ction|enum|concept|alias|match|try|catch|defer)>'
    let l:ind += shiftwidth()
  endif

  " Increase indent after `then` at end of line
  if l:prev =~# '\v\sthen$'
    let l:ind += shiftwidth()
  endif

  " Decrease indent on block-closing keywords
  if l:line =~# '\v^\s*(end|else|elseif|until|catch)>'
    let l:ind -= shiftwidth()
  endif

  if l:ind < 0
    let l:ind = 0
  endif

  return l:ind
endfunction
