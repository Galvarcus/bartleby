" Plugin_Name: Bartleby
" syntax/bartleby-binder.vim - highlighting for the Binder sidebar
" (binder.vim). Deliberately narrow: only the fixed, known vocabulary
" the plugin itself renders - the title line, tree markers, the
" Chapter:/Part: structural prefix, and the known label-color names -
" is ever matched. An item's own title is arbitrary user text and is
" never pattern-matched, so a title that happens to contain one of
" these words is never mis-highlighted as anything but plain text: the
" role-label and item-label patterns below are anchored immediately
" after the marker or at end of line specifically so they can't reach
" into the title itself.
" License: GNU GPL 3.0

if exists('b:current_syntax')
  finish
endif

" Line 1 is always the project name (see binder.vim's Render()).
syntax match bartlebyBinderTitle /\%1l.*/

" The expand/collapse/document marker - '▾ ' (expanded folder),
" '▸ ' (collapsed folder), '· ' (document). Alternation, not a [...]
" character class: multi-byte characters inside a bracket expression
" don't reliably advance Vim's regex match position to the next real
" character, which silently broke the role-label pattern below (it
" never matched at all) until this was found and fixed here too.
syntax match bartlebyBinderMarker /^\s*\zs\%(▾\|▸\|·\)/

" 'Chapter: '/'Part: ', only when it immediately follows the marker -
" binderitem.vim's DisplayLabel() is the only place that ever produces
" this exact text in this exact position.
syntax match bartlebyBinderRoleLabel /\%(\%(▾\|▸\|·\) \)\@<=\(Chapter\|Part\): /

" The label-color suffix binder.vim appends after a document's title,
" e.g. ' (Red)' - matched only against the fixed set of real label
" names (document.vim's LABELS, minus 'None' which is never shown) and
" only at end of line, where RenderLines() always puts it.
syntax match bartlebyBinderItemLabel / (\(Red\|Orange\|Yellow\|Green\|Blue\|Purple\))$/

highlight default link bartlebyBinderTitle Title
highlight default link bartlebyBinderMarker Comment
highlight default link bartlebyBinderRoleLabel Keyword
highlight default link bartlebyBinderItemLabel Identifier

let b:current_syntax = 'bartleby-binder'
