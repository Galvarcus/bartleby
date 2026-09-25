" Plugin_Name: Bartleby
" syntax/bartleby-compile-select.vim - highlighting for the compile
" content-selection pane (compile.vim's RedrawSelect()). Deliberately
" narrow, same as syntax/bartleby-binder.vim: only the fixed lines and
" marks the plugin itself renders are matched. A document's own title
" is arbitrary user text and is never pattern-matched.
" License: GNU GPL 3.0

if exists('b:current_syntax')
  finish
endif

" Line 1 is the '*** Compile ***' header, line 2 the project title.
syntax match bartlebyCompileSelectHeader /\%1l.*/
syntax match bartlebyCompileSelectTitle /\%2l.*/

" A document's inclusion checkbox - '[x]' (included) or '[ ]' (excluded).
" Folders get three plain spaces instead, so nothing here matches a
" folder row.
syntax match bartlebyCompileSelectChecked /\[x\]/
syntax match bartlebyCompileSelectUnchecked /\[ \]/

" The folder/document marker - '▸ ' (folder) or '· ' (document).
" Alternation, not a [...] character class - see
" syntax/bartleby-binder.vim for why.
syntax match bartlebyCompileSelectMarker /\%(▸\|·\)\ze /

" A folder's name: everything after the folder marker up to the '/' that
" RenderSelectLines() appends to folder titles only. Anchored on the
" folder marker, so a document title ending in '/' never matches.
syntax match bartlebyCompileSelectDirectory /\%(▸ \)\@<=.*\/$/

highlight default link bartlebyCompileSelectHeader Title
highlight default link bartlebyCompileSelectTitle Title
highlight default link bartlebyCompileSelectChecked DiffAdd
highlight default link bartlebyCompileSelectUnchecked Comment
highlight default link bartlebyCompileSelectMarker Comment
highlight default link bartlebyCompileSelectDirectory Directory

let b:current_syntax = 'bartleby-compile-select'
