" Plugin_Name: Bartleby
" syntax/bartleby-compile-select.vim - highlighting for the compile
" content-selection screen (compile.vim's RenderSelectLines()).
" Deliberately narrow, same reasoning as bartleby-binder's own syntax
" file: only the checkbox and tree marker are fixed, known vocabulary
" the plugin itself renders - an item's own title is arbitrary user
" text and is never pattern-matched.
" License: GNU GPL 3.0

if exists('b:current_syntax')
  finish
endif

" A document's inclusion checkbox - '[x]' (included) or '[ ]' (excluded).
" Folders get three plain spaces instead (no checkbox of their own),
" so nothing here ever matches a folder row.
syntax match bartlebyCompileSelectChecked /\[x\]/
syntax match bartlebyCompileSelectUnchecked /\[ \]/

" The folder/document marker - '▸ ' (folder) or '· ' (document).
" Alternation, not a [...] character class - see bartleby-binder.vim's
" own syntax file for why.
syntax match bartlebyCompileSelectMarker /\%(▸\|·\)\ze /

highlight default link bartlebyCompileSelectChecked DiffAdd
highlight default link bartlebyCompileSelectUnchecked Comment
highlight default link bartlebyCompileSelectMarker Comment

let b:current_syntax = 'bartleby-compile-select'
