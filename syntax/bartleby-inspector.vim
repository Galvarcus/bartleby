" Plugin_Name: Bartleby
" syntax/bartleby-inspector.vim - highlighting for the Inspector pane
" (inspector.vim). Same narrow scope as bartleby-binder/bartleby-
" compile-select: only the fixed vocabulary the plugin itself renders
" (the ::Inspector:: header, the field labels, the Synopsis header) is
" ever matched. A field's own value - title, label, status, target,
" keywords, synopsis text - is content the user wrote or picked and is
" never pattern-matched.
" License: GNU GPL 3.0

if exists('b:current_syntax')
  finish
endif

" Line 1 is always the '::Inspector::' header (see inspector.vim's
" RenderContent()).
syntax match bartlebyInspectorHeader /\%1l.*/

" 'Title: '/'Label: '/'Status: '/'Target: '/'Keywords: ', only at the
" very start of a line - the only place RenderContent() ever puts them.
syntax match bartlebyInspectorField /^\(Title\|Label\|Status\|Target\|Keywords\): /

" The 'Synopsis:' header line - unlike the fields above it has no
" trailing value on the same line, so it gets its own exact-match rule.
syntax match bartlebyInspectorSynopsisHeader /^Synopsis:$/

highlight default link bartlebyInspectorHeader Title
highlight default link bartlebyInspectorField Keyword
highlight default link bartlebyInspectorSynopsisHeader Keyword

let b:current_syntax = 'bartleby-inspector'
