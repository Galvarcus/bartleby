vim9script

##############################################################################
# Plugin_Name: Bartleby
# syntax/bartleby-binder.vim: highlighting for the Binder sidebar of
# binder.vim. It matches only the fixed text that Bartleby writes: the
# title line, the tree markers, folder names, the Chapter and Part
# prefixes, and the label color names. A document title is the user's own
# text and is never matched, so a title that contains one of these words
# is not highlighted by mistake: every rule is anchored to a marker, a
# line number, or the end of a line.
#
# No s:is_loaded guard: a syntax file runs once for every buffer, and the
# b:current_syntax guard is the right one.
# License: GNU GPL 3.0
##############################################################################

if exists('b:current_syntax')
  finish
endif

# Line 1 is always the project name, see Render in binder.vim.
syntax match bartlebyBinderTitle /\%1l.*/

# The marker: an expanded folder, a collapsed folder, or a document. An
# alternation, not a bracket expression: a multibyte character in a
# bracket expression does not reliably move the regex position to the
# next character.
syntax match bartlebyBinderMarker /^\s*\zs\%(▾\|▸\|·\)/

# A folder name: everything after a folder marker, and after its optional
# Chapter or Part prefix, up to the slash that RenderLines in binder.vim
# adds only to folder titles. Anchored on the folder markers, so a
# document title that ends in a slash never matches. Defined before
# bartlebyBinderRoleLabel: where the prefix starts, both rules match and
# the later rule wins, so the prefix keeps its own highlight and this
# rule matches only the name after it.
syntax match bartlebyBinderDirectory /\%(\%(▾\|▸\) \%(\%(Chapter\|Part\): \)\=\)\@<=.*\/$/

# The Chapter or Part prefix, only right after the marker, the only place
# where DisplayLabel in binderitem.vim writes it. A lookbehind, not a
# shared start with \zs: a second rule anchored on text that another rule
# already matched never matches there.
syntax match bartlebyBinderRoleLabel /\%(\%(▾\|▸\|·\) \)\@<=\(Chapter\|Part\): /

# The label color that binder.vim adds after a document title, such as
# Red. Only the real label names match, the LABELS of document.vim
# without None, which is never shown, and only at the end of the line,
# where RenderLines puts it.
syntax match bartlebyBinderItemLabel / (\(Red\|Orange\|Yellow\|Green\|Blue\|Purple\))$/

highlight default link bartlebyBinderTitle Title
highlight default link bartlebyBinderMarker Comment
highlight default link bartlebyBinderDirectory Directory
highlight default link bartlebyBinderRoleLabel Keyword
highlight default link bartlebyBinderItemLabel Identifier

b:current_syntax = 'bartleby-binder'
