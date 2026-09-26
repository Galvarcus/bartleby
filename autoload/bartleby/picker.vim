vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# picker.vim: pickers built on InputPopup from inputpopup.vim, with one
# choice field, where one Enter picks. It takes a list of options and
# returns the pick through a callback. It knows nothing of the Binder or
# of document metadata.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP

# FUNCTION: Show options as one choice field titled title, and call OnPick
# with the chosen option. Nothing is called on cancel. current, optional,
# selects the matching option first, so the picker also shows the active
# choice. Without it, no option is marked as current.
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
