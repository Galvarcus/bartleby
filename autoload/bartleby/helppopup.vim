vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# helppopup.vim - a static "press ? for help" popup listing a buffer's own
# hotkeys, NERDTree-style. Shared by binder.vim/outliner.vim/compile.vim's
# selection pane rather than each rolling its own - it's plain text, <Esc>
# to close, everything else swallowed while it's open.
# License: GNU GPL 3.0
##############################################################################

# entries: list of [key, description] pairs, in whatever order the caller
# wants them shown. title becomes the popup's own border title; falls
# back to ' Help ' when empty.
export def Show(title: string, entries: list<list<string>>): void
  var popupTitle: string = title ==# '' ? ' Help ' : $' {title} '

  var keyWidth: number = 0
  for entry in entries
    keyWidth = max([keyWidth, strchars(entry[0])])
  endfor

  var lines: list<string> = ['']
  for entry in entries
    lines->add(printf('  %-' .. keyWidth .. 's   %s', entry[0], entry[1]))
  endfor
  lines->add('')
  lines->add('  Press <Esc> to close')

  popup_create(lines, {
    title: popupTitle,
    border: [1, 1, 1, 1],
    padding: [0, 1, 0, 1],
    zindex: 300,
    minwidth: 40,
    filter: (id: number, key: string): bool => {
      if key ==# "\<Esc>"
        popup_close(id)
      endif
      return true
    },
  })
enddef
