vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# helppopup.vim: a popup that lists the keys of a pane, shown with ?, as
# in NERDTree. Shared by the Binder, Outliner, Corkboard, scrive list,
# lookup popup, and compile selection pane. Plain text. Esc closes it,
# and it takes every other key while it is open.
# License: GNU GPL 3.0
##############################################################################

# FUNCTION: Show entries, a list of key and description pairs in the
# caller's order. title is the border title, or Help when it is empty.
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
