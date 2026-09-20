vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# wrap.vim - greedy word-wrap of a string to a given display width. Single
# job: text in, wrapped lines out. No card/UI knowledge lives here.
# License: GNU GPL 3.0
##############################################################################

export def Wrap(text: string, width: number): list<string>
  if text ==# ''
    return []
  endif

  var words: list<string> = split(text)
  var lines: list<string> = []
  var current: string = ''
  for word in words
    var candidate: string = current ==# '' ? word : current .. ' ' .. word
    if strdisplaywidth(candidate) > width && current !=# ''
      lines->add(current)
      current = word
    else
      current = candidate
    endif
  endfor
  if current !=# ''
    lines->add(current)
  endif
  return lines
enddef
