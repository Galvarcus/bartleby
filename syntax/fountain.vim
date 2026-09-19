" Plugin_Name: Bartleby
" syntax/fountain.vim - highlighting for Fountain screenplay files,
" distinct from markdown's rules since Fountain's structure (scene
" headings, character cues, unquoted dialogue, transitions) has no
" markdown equivalent at all - see ftdetect/fountain.vim for why
" *.fountain needed its own real filetype rather than borrowing
" markdown's.
"
" Character-cue/dialogue detection and rule ordering follow the
" long-established vim-fountain plugin (Carson Fire) rather than a
" from-scratch design: \L ("not a lowercase letter") for a cue line is
" simpler and more robust than an explicit character class, and later
" :syntax rules correctly override earlier ones for the same line, so
" scene headings and transitions - which are also all-caps lines -
" just need to be declared after the character/dialogue region rather
" than excluded from its own pattern.
" License: GNU GPL 3.0

if exists('b:current_syntax')
  finish
endif
syntax sync minlines=200

" Title page: "Key: value" lines at the very start of the file, ended
" by the first blank line - only when the file actually starts with
" one (the first line must itself contain a colon), so a screenplay
" that opens directly on a scene heading isn't misread as a title page
" until its first blank line.
syntax region fountainTitlePage start=/\%^.*:/ end=/^\s*$/ contains=fountainTitleKey keepend
syntax match fountainTitleKey /^\a[A-Za-z0-9 ]*:/ contained contains=NONE

" Character cue + the dialogue block it introduces, as one region: the
" cue is any line with no lowercase letters at all (matchgroup), the
" dialogue is everything up to the next blank line. A region (not a
" line-by-line match) is what lets the dialogue body get its own
" highlight distinct from plain action/narration.
syntax region fountainDialogue matchgroup=fountainCharacter start=/^\L*$/ end=/^\s*$/
      \ contains=fountainParenthetical,fountainNote,fountainBoneyard,@fountainEmphasis

" Parenthetical: a whole line wrapped in (...), within a dialogue block.
syntax match fountainParenthetical /^\s*(.*)\s*$/ contained

" Scene headings: INT./EXT./EST./I-E./I\/E. prefix (period, slash, or a
" bare trailing space), or a leading '.' to force one (fountain's own
" escape for a scene heading that doesn't fit the standard prefixes).
" Declared after fountainDialogue so it correctly wins for these lines
" instead of being read as a character cue.
syntax region fountainSceneHeading start=/^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)/ end=/$/
      \ contains=fountainSceneNumber
syntax match fountainSceneHeading /^\.\a.*$/
syntax region fountainSceneNumber start=/#/ end=/#/ contained

" Transitions: conventionally end in "TO:", or are one of a small fixed
" set of standalone transition cues. Also declared after
" fountainDialogue for the same reason as scene headings.
syntax match fountainTransition /^\L* TO:$/
syntax match fountainTransition /^\c\(fade in\|fade out\|fade to black\)[.:]\s*$/

" Section headers (outline structure, unrelated to scene headings):
" one or more leading #, not immediately followed by another # (which
" would make it a scene-heading's own scene-number instead).
syntax match fountainSection /^#\{1,6}\s.*$/

" Synopsis: a single leading = (not the === page-break rule below).
syntax match fountainSynopsis /^=\([^=].*\)\?$/

" Page break: a line of three or more = characters and nothing else.
syntax match fountainPageBreak /^=\{3,}\s*$/

" Lyrics: a leading ~.
syntax match fountainLyric /^\s*\~.*$/

" Notes: [[double-bracketed]], and boneyard (comment) blocks: /* ... */,
" both droppable from the compiled output - conventionally styled like
" a comment.
syntax region fountainNote start=/\[\[/ end=/\]\]/
syntax region fountainBoneyard start=/\/\*/ end=/\*\//

" Centered text: >...<. A leading > with no closing < is still a
" (non-centered) forced transition instead.
syntax match fountainCenter /^\s*>.\{-}<\s*$/
syntax match fountainTransitionForced /^\s*>[^<]*$/

" Emphasis - fountain's own markdown-like inline styling. Longest/most
" specific first so e.g. *** isn't partly matched by the single-* rule.
syntax region fountainBoldItalic start=/\*\*\*/ end=/\*\*\*/ oneline
syntax region fountainBold start=/\*\*/ end=/\*\*/ oneline
syntax region fountainItalic start=/\*/ end=/\*/ oneline skip=/\\\*/
syntax region fountainUnderline start=/_/ end=/_/ oneline skip=/\\_/
syntax cluster fountainEmphasis contains=fountainBoldItalic,fountainBold,fountainItalic,fountainUnderline

highlight default link fountainTitlePage Comment
highlight default link fountainTitleKey Keyword
highlight default link fountainSceneHeading Statement
highlight default link fountainSceneNumber Number
highlight default link fountainTransition Statement
highlight default link fountainTransitionForced Statement
highlight default link fountainCharacter Type
highlight default link fountainDialogue String
highlight default link fountainParenthetical Comment
highlight default link fountainSection Title
highlight default link fountainSynopsis Comment
highlight default link fountainPageBreak Comment
highlight default link fountainLyric String
highlight default link fountainNote Todo
highlight default link fountainBoneyard Comment
highlight default link fountainCenter Statement
highlight default link fountainBoldItalic Special
highlight default link fountainBold Special
highlight default link fountainItalic Special
highlight default link fountainUnderline Underlined

let b:current_syntax = 'fountain'
