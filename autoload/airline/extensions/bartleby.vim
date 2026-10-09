" Plugin_Name: Bartleby
" autoload/airline/extensions/bartleby.vim: the writing progress of
" Bartleby in vim-airline, which loads this file by itself. It is legacy
" Vim script, because airline calls these functions by lowercase names,
" which a Vim9 script cannot export. See autoload/bartleby/progress.vim.
" License: GNU GPL 3.0

function! airline#extensions#bartleby#init(ext) abort
  call airline#parts#define_function('bartleby', 'bartleby#progress#Status')
  call a:ext.add_statusline_func('airline#extensions#bartleby#apply')
endfunction

" Add the progress to the section that g:bartleby_airline_section names,
" only in the windows where it has text, so that no empty separator shows.
" The separator before it is as in the example extension of airline.
function! airline#extensions#bartleby#apply(...) abort
  if bartleby#progress#Status(a:2.bufnr) !=# ''
    let l:space = g:airline_symbols.space
    call airline#extensions#append_to_section(get(g:, 'bartleby_airline_section', 'y'),
          \ l:space . g:airline_right_alt_sep . l:space . airline#section#create_right(['bartleby']))
  endif
endfunction
