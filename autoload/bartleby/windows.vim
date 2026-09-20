vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# windows.vim - locates Bartleby's own "chrome" windows (Binder,
# Inspector) by buffer name, so document-opening code can reliably jump
# to whichever window is the plain editor rather than guessing via
# :wincmd p - which only tracks the single most-recently-used window, and
# breaks as soon as there's more than one non-editor window open (once
# Inspector is open alongside Binder, "previous window" can just as easily
# resolve to Inspector as to the editor, depending on click/focus order).
# Outliner used to be a third chrome window here (a real buffer taking
# over the editor slot); it's a popup now (see outliner.vim), so it
# never occupies a window at all and has nothing to list here.
# License: GNU GPL 3.0
##############################################################################

const CHROME_BUFFER_NAMES: list<string> = [
  'Bartleby-Binder',
  'Bartleby-Inspector',
]

# Permanent side-panels that document-opening code must never overwrite.
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

# Switches to the first window in the current tab that isn't protected
# chrome (Binder/Inspector), creating one if every window in the tab is
# protected. A window showing Outliner is fair game for takeover - see
# PROTECTED_BUFFER_NAMES above. Always succeeds; always leaves the
# current window safe to overwrite.
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
