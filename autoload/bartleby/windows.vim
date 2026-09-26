vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# windows.vim: finds Bartleby's own pane windows, the Binder and the
# Inspector, by buffer name, so that code that opens documents always
# finds the editor window. :wincmd p is not enough: it remembers only the
# last window, which can be the Inspector instead of the editor.
# The Outliner is a popup, see outliner.vim, so it takes no window.
# License: GNU GPL 3.0
##############################################################################

const CHROME_BUFFER_NAMES: list<string> = [
  'Bartleby-Binder',
  'Bartleby-Inspector',
]

# Side panes that code opening documents must never replace.
const PROTECTED_BUFFER_NAMES: list<string> = [
  'Bartleby-Binder',
  'Bartleby-Inspector',
]

def MatchesAny(bufNr: number, names: list<string>): bool
  var name: string = bufname(bufNr)
  for bufferName in names
    if name =~# '\V' .. bufferName .. '\$'
      return true
    endif
  endfor
  return false
enddef

export def IsChromeBuffer(bufNr: number): bool
  return MatchesAny(bufNr, CHROME_BUFFER_NAMES)
enddef

def IsProtectedBuffer(bufNr: number): bool
  return MatchesAny(bufNr, PROTECTED_BUFFER_NAMES)
enddef

# FUNCTION: Go to the first window of the current tab that is not a
# protected pane, the Binder or the Inspector, and create one when every
# window is protected. Always succeeds, and always leaves a window that
# can be replaced.
export def GoToEditorWindow(): bool
  for winNr in range(1, winnr('$'))
    if !IsProtectedBuffer(winbufnr(winNr))
      execute ':' .. winNr .. 'wincmd w'
      return true
    endif
  endfor
  execute 'rightbelow vnew'
  return true
enddef
