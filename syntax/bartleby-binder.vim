" Plugin_Name: Bartleby
" syntax/bartleby-binder.vim - highlighting for the Binder sidebar
" (binder.vim). Deliberately narrow: only the fixed, known vocabulary
" the plugin itself renders - the title line, tree markers, folder
" names, the Chapter:/Part: structural prefix, and the known label-color
" names - is ever matched. A document's own title is arbitrary user text
" and is never pattern-matched, so a title that happens to contain one of
" these words is never mis-highlighted: every rule below is anchored to
" a marker, a line position, or end of line.
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
" character.
syntax match bartlebyBinderMarker /^\s*\zs\%(▾\|▸\|·\)/

" A folder's name: everything after a folder marker (and after its
" optional 'Chapter: '/'Part: ' prefix) up to the '/' that binder.vim's
" RenderLines() appends to folder titles only. Anchored on the folder
" markers, so a document title ending in '/' never matches. Defined
" before bartlebyBinderRoleLabel: at the prefix's own start both rules
" match, and the later-defined rule wins there, so the prefix keeps its
" own highlight and this rule matches only the name after it.
syntax match bartlebyBinderDirectory /\%(\%(▾\|▸\) \%(\%(Chapter\|Part\): \)\=\)\@<=.*\/$/

" 'Chapter: '/'Part: ', only when it immediately follows the marker -
" binderitem.vim's DisplayLabel() is the only place that ever produces
" this exact text in this exact position. A lookbehind, not a shared
" prefix plus \zs: a second rule anchored on text another rule already
" claims would never match there.
syntax match bartlebyBinderRoleLabel /\%(\%(▾\|▸\|·\) \)\@<=\(Chapter\|Part\): /

" The label-color suffix binder.vim appends after a document's title,
" e.g. ' (Red)' - matched only against the fixed set of real label
" names (document.vim's LABELS, minus 'None' which is never shown) and
" only at end of line, where RenderLines() always puts it.
syntax match bartlebyBinderItemLabel / (\(Red\|Orange\|Yellow\|Green\|Blue\|Purple\))$/

highlight default link bartlebyBinderTitle Title
highlight default link bartlebyBinderMarker Comment
highlight default link bartlebyBinderDirectory Directory
highlight default link bartlebyBinderRoleLabel Keyword
highlight default link bartlebyBinderItemLabel Identifier

let b:current_syntax = 'bartleby-binder'
