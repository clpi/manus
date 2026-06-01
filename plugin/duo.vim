" Duo plugin for Neovim/Vim
" This file is automatically loaded when the plugin is installed

if exists("g:loaded_duo_plugin")
  finish
endif
let g:loaded_duo_plugin = 1

" Runtime path configuration
augroup duo_plugin
  autocmd!
  autocmd FileType duo setlocal syntax=duo
  autocmd FileType duo setlocal commentstring=--%s
  autocmd FileType duo setlocal tabstop=4
  autocmd FileType duo setlocal shiftwidth=4
  autocmd FileType duo setlocal expandtab
augroup END