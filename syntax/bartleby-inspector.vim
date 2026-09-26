vim9script

##############################################################################
# Plugin_Name: Bartleby
# syntax/bartleby-inspector.vim: highlighting for the Inspector pane of
# inspector.vim. As in the Binder and compile selection syntax files, it
# matches only the fixed text that Bartleby writes: the Inspector header,
# the field labels, and the Synopsis header. A field value, such as a
# title, keywords, or synopsis text, is the user's own and is never
# matched.
#
# No s:is_loaded guard: a syntax file runs once for every buffer.
# License: GNU GPL 3.0
##############################################################################

if exists('b:current_syntax')
  finish
endif

# Line 1 is always the Inspector header, see RenderContent in
# inspector.vim.
syntax match bartlebyInspectorHeader /\%1l.*/

# A field label, only at the start of a line, the only place where
# RenderContent writes one.
syntax match bartlebyInspectorField /^\(Title\|Label\|Status\|Target\|Keywords\): /

# The Synopsis header. Unlike the fields above, it has no value on its own
# line, so it has its own exact rule.
syntax match bartlebyInspectorSynopsisHeader /^Synopsis:$/

highlight default link bartlebyInspectorHeader Title
highlight default link bartlebyInspectorField Keyword
highlight default link bartlebyInspectorSynopsisHeader Keyword

b:current_syntax = 'bartleby-inspector'
