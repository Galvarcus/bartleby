vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# picker.vim - popup pickers built on inputpopup.vim's InputPopup (a
# single choice field - Enter on it submits immediately, same one-
# keypress feel as the buttonspopup.vim-based picker this replaced).
# Single job: given a list of option strings, get the user's pick back
# via a callback. No Binder/DocMeta knowledge lives here.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP

# Opens `options` as a single choice field titled `title`; calls `OnPick`
# with the chosen string. Not called at all if the popup is cancelled.
# `current` (optional) pre-selects/highlights whichever option matches
# it, so this doubles as a radio-button picker showing the active choice
# - omit it for a plain pick-one-of-N with no notion of a "current" value.
export def PickOne(title: string, options: list<string>, OnPick: func(string),
    current: string = ''): void
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'choice', options: options}]]
  var defaults: dict<any> = current ==# '' ? {} : {choice: current}
  var form: IP.InputPopup = IP.InputPopup.new(fields, defaults, {title: $' {title} ', buttons: []})
  form.OnSubmit((values: dict<any>) => {
    OnPick(values.choice)
  })
  form.Open()
enddef
