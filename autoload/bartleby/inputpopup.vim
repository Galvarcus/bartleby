vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inputpopup.vim: a modal popup form with one Tab order and Submit and
# Cancel buttons. Field types: text, choice, filter, and multiline.
# picker.vim's PickOne uses one choice field. buttonspopup.vim's
# PopupButtonMenu is separate, for the Corkboard card grid, which is not
# a form.
#
# fields is a list of rows, and each row is a list of field specs:
#
#   var fields = [
#     [{name: 'title', type: 'text'}],
#     [{name: 'kind', type: 'choice', options: ['Manuscript', 'Book']}],
#     [{name: 'city', type: 'text'}, {name: 'zip', type: 'text'}],
#   ]
#
# Shown as:
#
#   title:  __________________
#   kind:   [ Manuscript ]  [ Book ]
#   city: ______  zip: _____
#
#   [ Submit ]  [ Cancel ]
#
# A choice field always takes a whole row: the width of a row of options
# does not combine with text boxes. A filter field, a text line above a
# fuzzy-matched list, and a multiline field, a text area, are each the
# only field of their popup, see PromptFilter and PromptMultiline.
#
# The caller gives starting values in a dict keyed by field name. For a
# choice field, the value is the option to select. OnSubmit receives a
# dict of the values: typed text for a text field, and the selected
# option for a choice or filter field.
#
# opts keys are a data contract, not Vim identifiers, so they keep
# snake_case:
#   field_width   number        Width of a text field. Default 20.
#   widths        dict<number>  Width per text field, by field name.
#   maxlengths    dict<number>  Maximum characters per text field, by
#                               field name. Typing stops there. A longer
#                               starting value is kept. The field is at
#                               least one column wider, for the cursor.
#   labels        dict<string>  Label per field, by field name. Default:
#                               the field name.
#   submit_label  string        Text of the Submit button.
#   cancel_label  string        Text of the Cancel button.
#   buttons       list          An empty list shows no buttons.
#   min_width     number        Minimum width of the popup.
#   title, line, col, zindex    Passed to popup_create unchanged.
#
# Keys: Tab and S-Tab, or C-n and C-p, move between the fields and the
# buttons. In a text field, Left, Right, Home, and End move the cursor,
# C-u clears it, and Enter moves to the next field. In a choice field,
# Left and Right change the option, without wrapping, and Enter moves
# on. C-s submits and Esc or C-c cancels from anywhere. The mouse can
# click buttons, text fields, and options.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/log.vim' as L

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Convert rows of field names, a list of lists of strings, to
# field specs of type text. Saves writing each spec for a form of only
# text fields.
def Noop(): void
enddef

export def TextFields(rows: list<list<string>>): list<list<dict<any>>>
  return rows->mapnew((_, row) => row->mapnew((_, name) => ({name: name, type: 'text'})))
enddef

# FUNCTION: Show one text field, titled title and filled with default.
# Call OnSubmit with the text, or OnCancel, which does nothing by
# default, on cancel. One Enter submits, like input in a box.
export def PromptText(title: string, default: string, OnSubmit: func(string),
    OnCancel: func() = Noop): void
  var fields: list<list<dict<any>>> = [[{name: 'value', type: 'text'}]]
  var form: InputPopup = InputPopup.new(fields, {value: default}, {title: $' {title} '})
  form.OnSubmit((values: dict<any>) => {
    OnSubmit(values.value)
  })
  form.OnCancel(OnCancel)
  form.Open()
enddef

# FUNCTION: Show options as a list, titled title, that narrows as you
# type, with matchfuzzy. Call OnSubmit with the selected option. Nothing
# is called on cancel, or on Enter with no match. Up, Down, C-k, C-j,
# PageUp, PageDown, and the mouse wheel move the selection, and the list
# scrolls with it. One Enter submits, as in PickOne. names, optional, maps
# an option to the text shown and matched for it, as in PickOne, and
# OnSubmit still receives the option.
export def PromptFilter(title: string, options: list<string>, OnSubmit: func(string),
    maxVisible: number = 10, minWidth: number = 0, names: dict<string> = {}): void
  var shown: list<string> = options->mapnew((_, o) => get(names, o, o))
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'filter',
    options: shown, maxVisible: maxVisible}]]
  var form: InputPopup = InputPopup.new(fields, {},
    {title: $' {title} ', buttons: [], min_width: minWidth})
  form.OnSubmit((values: dict<any>) => {
    if values.choice !=# ''
      OnSubmit(options[index(shown, values.choice)])
    endif
  })
  form.Open()
enddef

# FUNCTION: Show a multiline text field, titled title and filled with
# default, a string with line breaks. Enter adds a line, unlike every
# other one-field prompt, so C-s or the Submit button submits. Call
# OnSubmit with the text joined by line breaks. Nothing is called on
# cancel.
export def PromptMultiline(title: string, default: string, OnSubmit: func(string),
    rows: number = 5, width: number = 50): void
  var fields: list<list<dict<any>>> = [[{name: 'text', type: 'multiline',
    rows: rows}]]
  var form: InputPopup = InputPopup.new(fields, {text: default},
    {title: printf(IN.T(" %s (C-s to save) "), title), widths: {text: width}, buttons: []})
  form.OnSubmit((values: dict<any>) => {
    OnSubmit(values.text)
  })
  form.Open()
enddef

# FUNCTION: Add text to row, the line that Render builds: its text, and
# its length in characters.
def AppendTo(row: dict<any>, text: string): void
  row.text ..= text
  row.chars += strchars(text)
enddef

# What a key handler of InputPopup did: the key was not one of its keys,
# it was handled, it changed the text of the field, or it closed the
# popup, which must then not be drawn again.
const KEY_UNHANDLED: string = ''
const KEY_HANDLED: string = 'handled'
const KEY_CHANGED: string = 'changed'
const KEY_CLOSED: string = 'closed'

export class InputPopup
  var fieldRows: list<list<dict<any>>>
  var defaults: dict<any>
  var opts: dict<any>

  var fields: list<dict<any>> = []
  var buttons: list<dict<any>> = []
  var bufnr: number = -1
  var winid: number = -1
  var currentIdx: number = 0

  var _onSubmit: any = v:null
  var _onCancel: any = v:null

  var _fieldHit: list<dict<any>> = []
  var _optionHit: list<dict<any>> = []
  var _buttonHit: list<dict<any>> = []

  def new(this.fieldRows, defaults: dict<any> = {}, opts: dict<any> = {})
    this.defaults = defaults
    this.opts = opts
    this.BuildFields()
    this.BuildButtons()
  enddef

  ############################################################################
  # SECTION: Setup.
  ############################################################################

  def BuildFields(): void
    this.fields = []
    var widths: dict<any> = get(this.opts, 'widths', {})
    var labels: dict<any> = get(this.opts, 'labels', {})
    var defaultWidth: number = get(this.opts, 'field_width', 20)
    for rowIdx in range(len(this.fieldRows))
      for spec in this.fieldRows[rowIdx]
        var name: string = spec.name
        var fieldType: string = get(spec, 'type', 'text')
        var field: dict<any> = {
          name: name,
          label: get(labels, name, name),
          type: fieldType,
          row: rowIdx,
        }
        if fieldType ==# 'choice'
          var options: list<string> = get(spec, 'options', [])
          var startValue: string = get(this.defaults, name, '')
          var selectedIdx: number = max([0, index(options, startValue)])
          field.options = options
          field.selectedIdx = selectedIdx
        elseif fieldType ==# 'filter'
          field.value = ''
          field.cursor = 0
          field.offset = 0
          field.options = get(spec, 'options', [])
          field.maxVisible = get(spec, 'maxVisible', 10)
          field.filtered = copy(field.options)
          field.selectedIdx = 0
          field.scrollTop = 0
        elseif fieldType ==# 'multiline'
          var startText: string = get(this.defaults, name, '')
          field.lines = split(startText, "\n", true)
          if empty(field.lines)
            field.lines = ['']
          endif
          field.rows = get(spec, 'rows', 5)
          field.width = get(widths, name, defaultWidth)
          field.cursorLine = 0
          field.cursorCol = strchars(field.lines[0])
          field.scrollOffset = 0
        else
          var raw: any = get(this.defaults, name, '')
          var isComplex: bool = type(raw) != v:t_string
          var text: string = isComplex ? string(raw) : raw
          field.value = text
          field.cursor = strchars(text)
          field.offset = 0
          field.isComplex = isComplex
          field.maxLength = get(get(this.opts, 'maxlengths', {}), name, 0)
          # One column more than the maximum, for the cursor after the last
          # character. Without it the field scrolls and hides the text.
          field.width = max([get(widths, name, defaultWidth), field.maxLength + 1])
        endif
        add(this.fields, field)
      endfor
    endfor
  enddef

  def BuildButtons(): void
    if has_key(this.opts, 'buttons')
      this.buttons = get(this.opts, 'buttons', [])
      return
    endif
    this.buttons = [
      {label: get(this.opts, 'submit_label', IN.T("Submit")), action: 'submit'},
      {label: get(this.opts, 'cancel_label', IN.T("Cancel")), action: 'cancel'},
    ]
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('InputPopupLabel'))
      prop_type_add('InputPopupLabel', {highlight: 'Title'})
    endif
    if empty(prop_type_get('InputPopupCursor'))
      prop_type_add('InputPopupCursor', {highlight: 'IncSearch'})
    endif
    if empty(prop_type_get('InputPopupButton'))
      prop_type_add('InputPopupButton', {highlight: 'Pmenu'})
    endif
    if empty(prop_type_get('InputPopupButtonActive'))
      prop_type_add('InputPopupButtonActive', {highlight: 'PmenuSel'})
    endif
    if empty(prop_type_get('InputPopupOption'))
      prop_type_add('InputPopupOption', {highlight: 'Pmenu'})
    endif
    if empty(prop_type_get('InputPopupScrollbar'))
      prop_type_add('InputPopupScrollbar', {highlight: 'PmenuSbar'})
    endif
    if empty(prop_type_get('InputPopupThumb'))
      prop_type_add('InputPopupThumb', {highlight: 'PmenuThumb'})
    endif
    if empty(prop_type_get('InputPopupOptionSelected'))
      prop_type_add('InputPopupOptionSelected', {highlight: 'PmenuSel'})
    endif
  enddef

  def ButtonLineText(): string
    var parts: list<string> = []
    for b in this.buttons
      add(parts, '[ ' .. b.label .. ' ]')
    endfor
    return join(parts, '  ')
  enddef

  def FieldLineText(f: dict<any>): string
    var label: string = f.label .. ': '
    if f.type ==# 'choice'
      var parts: list<string> = []
      for opt in f.options
        add(parts, '[ ' .. opt .. ' ]')
      endfor
      return label .. join(parts, '  ')
    endif
    return label .. repeat('_', f.width)
  enddef

  def ComputeSize(): list<number>
    if len(this.fields) == 1 && this.fields[0].type ==# 'filter'
      var f: dict<any> = this.fields[0]
      var w: number = 20
      for opt in f.options
        w = max([w, strchars(opt)])
      endfor
      var visibleRows: number = min([max([len(f.options), 1]), f.maxVisible])
      # One more column for the scrollbar when the list can scroll.
      var scrollbar: number = len(f.options) > f.maxVisible ? 2 : 0
      return [this.FitTitle(max([w + scrollbar, 10])), 1 + visibleRows]
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# 'multiline'
      var f: dict<any> = this.fields[0]
      return [max([f.width, 10]), f.rows + (empty(this.buttons) ? 0 : 1)]
    endif

    var rowWidths: dict<number> = {}
    var rowCount: number = 0
    for f in this.fields
      var w: number = strchars(this.FieldLineText(f))
      if f.type !=# 'choice'
        w = get(rowWidths, string(f.row), 0) + strchars(f.label) + 2 + f.width + 2
      endif
      rowWidths[string(f.row)] = w
      rowCount = max([rowCount, f.row + 1])
    endfor
    var maxWidth: number = strchars(this.ButtonLineText())
    for w in values(rowWidths)
      maxWidth = max([maxWidth, w])
    endfor
    return [this.FitTitle(max([maxWidth, 10])), max([rowCount, 1]) + (empty(this.buttons) ? 0 : 1)]
  enddef

  # METHOD: Return width, widened so that the title shows in full with 2
  # columns to spare, and to the min_width option.
  def FitTitle(width: number): number
    var title: string = trim(get(this.opts, 'title', ''))
    return max([width, strdisplaywidth(title) + 2, get(this.opts, 'min_width', 0)])
  enddef

  ############################################################################
  # SECTION: Public API.
  ############################################################################

  # METHOD: Set the function called with the field values on submit.
  def OnSubmit(Cb: any): void
    this._onSubmit = Cb
  enddef

  # METHOD: Set the function called on cancel.
  def OnCancel(Cb: any): void
    this._onCancel = Cb
  enddef

  def Open(): void
    if empty(this.fields)
      log.Error(IN.T("InputPopup: fieldRows produced no fields"))
      return
    endif

    this.currentIdx = 0
    this.EnsurePropTypes()

    var [width, height] = this.ComputeSize()

    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    this.winid = popup_create(this.bufnr, {
      line: get(this.opts, 'line', 0),
      col: get(this.opts, 'col', 0),
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      title: get(this.opts, 'title', ' Input '),
      zindex: get(this.opts, 'zindex', 300),
      mapping: false,
      mousemoveevent: false,
      filter: (winid, key) => this.Filter(winid, key),
      callback: (winid, result) => this.OnClose(winid, result),
    })

    setwinvar(this.winid, '&wrap', 0)
    setwinvar(this.winid, '&number', 0)
    setwinvar(this.winid, '&relativenumber', 0)

    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid, 0)
    endif
  enddef

  ############################################################################
  # SECTION: Focus helpers.
  ############################################################################

  def TotalControls(): number
    return len(this.fields) + len(this.buttons)
  enddef

  def IsButtonIdx(idx: number): bool
    return idx >= len(this.fields)
  enddef

  def ButtonAt(idx: number): dict<any>
    return this.buttons[idx - len(this.fields)]
  enddef

  def Focus(idx: number): void
    this.currentIdx = idx
    if idx < len(this.fields) && this.fields[idx].type !=# 'choice'
      this.fields[idx].cursor = strchars(this.fields[idx].value)
    endif
  enddef

  def ActivateButton(idx: number): void
    var btn: dict<any> = this.ButtonAt(idx)
    popup_close(this.winid, btn.action == 'submit' ? 1 : 0)
  enddef

  ############################################################################
  # SECTION: Input handling.
  ############################################################################

  def HandleMultilineKey(key: string): bool
    var f: dict<any> = this.fields[this.currentIdx]
    if key ==# "\<CR>"
      var line: string = f.lines[f.cursorLine]
      var before: string = strcharpart(line, 0, f.cursorCol)
      var after: string = strcharpart(line, f.cursorCol)
      f.lines[f.cursorLine] = before
      insert(f.lines, after, f.cursorLine + 1)
      f.cursorLine += 1
      f.cursorCol = 0
    elseif key ==# "\<Up>"
      if f.cursorLine > 0
        f.cursorLine -= 1
        f.cursorCol = min([f.cursorCol, strchars(f.lines[f.cursorLine])])
      endif
    elseif key ==# "\<Down>"
      if f.cursorLine < len(f.lines) - 1
        f.cursorLine += 1
        f.cursorCol = min([f.cursorCol, strchars(f.lines[f.cursorLine])])
      endif
    elseif key ==# "\<Left>"
      if f.cursorCol > 0
        f.cursorCol -= 1
      elseif f.cursorLine > 0
        f.cursorLine -= 1
        f.cursorCol = strchars(f.lines[f.cursorLine])
      endif
    elseif key ==# "\<Right>"
      if f.cursorCol < strchars(f.lines[f.cursorLine])
        f.cursorCol += 1
      elseif f.cursorLine < len(f.lines) - 1
        f.cursorLine += 1
        f.cursorCol = 0
      endif
    elseif key ==# "\<BS>" || key ==# "\<C-h>"
      if f.cursorCol > 0
        var chars: list<string> = split(f.lines[f.cursorLine], '\zs')
        remove(chars, f.cursorCol - 1)
        f.lines[f.cursorLine] = join(chars, '')
        f.cursorCol -= 1
      elseif f.cursorLine > 0
        var prevLen: number = strchars(f.lines[f.cursorLine - 1])
        f.lines[f.cursorLine - 1] ..= f.lines[f.cursorLine]
        remove(f.lines, f.cursorLine)
        f.cursorLine -= 1
        f.cursorCol = prevLen
      endif
    elseif key ==# "\<Del>"
      var line: string = f.lines[f.cursorLine]
      if f.cursorCol < strchars(line)
        var chars: list<string> = split(line, '\zs')
        remove(chars, f.cursorCol)
        f.lines[f.cursorLine] = join(chars, '')
      elseif f.cursorLine < len(f.lines) - 1
        f.lines[f.cursorLine] ..= f.lines[f.cursorLine + 1]
        remove(f.lines, f.cursorLine + 1)
      endif
    elseif key ==# "\<Home>" || key ==# "\<C-a>"
      f.cursorCol = 0
    elseif key ==# "\<End>" || key ==# "\<C-e>"
      f.cursorCol = strchars(f.lines[f.cursorLine])
    elseif strchars(key) == 1 && char2nr(key) >= 32
      var chars: list<string> = split(f.lines[f.cursorLine], '\zs')
      insert(chars, key, f.cursorCol)
      f.lines[f.cursorLine] = join(chars, '')
      f.cursorCol += 1
    else
      return false
    endif
    return true
  enddef

  # METHOD: The popup filter. It sends key to the handler of the control
  # that has focus, after the keys that every control shares, and redraws
  # unless the key closed the popup.
  def Filter(winid: number, key: string): bool
    var isButton: bool = this.IsButtonIdx(this.currentIdx)
    var type: string = isButton ? 'button' : this.fields[this.currentIdx].type
    if type ==# 'multiline'
      if this.MultilineKey(winid, key) !=# KEY_CLOSED
        this.Render()
      endif
      return true
    endif
    var result: string = this.CommonKey(winid, key)
    if result ==# KEY_UNHANDLED
      if type ==# 'button'
        result = this.ButtonKey(winid, key)
      elseif type ==# 'filter'
        result = this.FilterFieldKey(winid, key)
      elseif type ==# 'choice'
        result = this.ChoiceKey(winid, key)
      else
        result = this.TextKey(winid, key)
      endif
    endif
    if result !=# KEY_CLOSED
      this.Render()
    endif
    return true
  enddef

  # METHOD: Keys of a multiline field. Ctrl-S submits and Esc cancels, and
  # every other key edits the text.
  def MultilineKey(winid: number, key: string): string
    if key == "\<C-s>"
      popup_close(winid, 1)
      return KEY_CLOSED
    elseif key == "\<Esc>" || key == "\<C-c>"
      popup_close(winid, 0)
      return KEY_CLOSED
    endif
    this.HandleMultilineKey(key)
    return KEY_HANDLED
  enddef

  # METHOD: Keys that every control shares: move to the next or previous
  # control, submit, cancel, and click.
  def CommonKey(winid: number, key: string): string
    if key == "\<Tab>" || key == "\<C-n>"
      this.Focus((this.currentIdx + 1) % this.TotalControls())
    elseif key == "\<S-Tab>" || key == "\<C-p>"
      this.Focus((this.currentIdx - 1 + this.TotalControls()) % this.TotalControls())
    elseif key == "\<C-s>"
      popup_close(winid, 1)
      return KEY_CLOSED
    elseif key == "\<Esc>" || key == "\<C-c>"
      popup_close(winid, 0)
      return KEY_CLOSED
    elseif key == "\<LeftMouse>"
      this.HandleMouseClick()
    else
      return KEY_UNHANDLED
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a button. A button holds no text, so other keys do
  # nothing.
  def ButtonKey(winid: number, key: string): string
    if key == "\<CR>" || key == ' '
      this.ActivateButton(this.currentIdx)
      return KEY_CLOSED
    elseif key == "\<Left>"
      this.Focus(max([len(this.fields), this.currentIdx - 1]))
    elseif key == "\<Right>"
      this.Focus(min([this.TotalControls() - 1, this.currentIdx + 1]))
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a filter field: move in the list, or pick with Enter.
  # Other keys edit the text, and a changed text filters the list again.
  def FilterFieldKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == "\<Down>" || key == "\<C-j>" || key == "\<ScrollWheelDown>"
      this.MoveFilterSelection(f, 1)
    elseif key == "\<Up>" || key == "\<C-k>" || key == "\<ScrollWheelUp>"
      this.MoveFilterSelection(f, -1)
    elseif key == "\<PageDown>"
      this.MoveFilterSelection(f, f.maxVisible)
    elseif key == "\<PageUp>"
      this.MoveFilterSelection(f, -f.maxVisible)
    elseif key == "\<CR>"
      if !empty(f.filtered)
        popup_close(winid, 1)
      endif
      return KEY_CLOSED
    else
      var result: string = this.TextKey(winid, key)
      if result ==# KEY_CHANGED
        f.filtered = f.value ==# '' ? copy(f.options) : matchfuzzy(f.options, f.value)
        f.selectedIdx = 0
        f.scrollTop = 0
      endif
      return result
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a choice field. It holds no text, so other keys do
  # nothing.
  def ChoiceKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == "\<Left>"
      f.selectedIdx = max([0, f.selectedIdx - 1])
    elseif key == "\<Right>"
      f.selectedIdx = min([len(f.options) - 1, f.selectedIdx + 1])
    elseif key == "\<CR>"
      if len(this.fields) == 1
        popup_close(winid, 1)
        return KEY_CLOSED
      endif
      this.Focus(this.currentIdx < len(this.fields) - 1 ? this.currentIdx + 1 : len(this.fields))
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a text field. Enter submits a popup of one field, or
  # else moves on, to the Submit button after the last field. Returns
  # KEY_CHANGED when the text changed.
  def TextKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == "\<CR>"
      if len(this.fields) == 1
        popup_close(winid, 1)
        return KEY_CLOSED
      endif
      this.Focus(this.currentIdx < len(this.fields) - 1 ? this.currentIdx + 1 : len(this.fields))
    elseif key == "\<BS>" || key == "\<C-h>"
      if f.cursor == 0
        return KEY_HANDLED
      endif
      var chars: list<string> = split(f.value, '\zs')
      remove(chars, f.cursor - 1)
      f.value = join(chars, '')
      f.cursor -= 1
      return KEY_CHANGED
    elseif key == "\<Del>"
      if f.cursor >= strchars(f.value)
        return KEY_HANDLED
      endif
      var chars: list<string> = split(f.value, '\zs')
      remove(chars, f.cursor)
      f.value = join(chars, '')
      return KEY_CHANGED
    elseif key == "\<C-u>"
      f.value = ''
      f.cursor = 0
      return KEY_CHANGED
    elseif key == "\<Left>"
      f.cursor = max([0, f.cursor - 1])
    elseif key == "\<Right>"
      f.cursor = min([strchars(f.value), f.cursor + 1])
    elseif key == "\<Home>" || key == "\<C-a>"
      f.cursor = 0
    elseif key == "\<End>" || key == "\<C-e>"
      f.cursor = strchars(f.value)
    elseif strchars(key) == 1 && char2nr(key) >= 32 && !this.AtMaxLength(f)
      var chars: list<string> = split(f.value, '\zs')
      insert(chars, key, f.cursor)
      f.value = join(chars, '')
      f.cursor += 1
      return KEY_CHANGED
    endif
    return KEY_HANDLED
  enddef

  def HandleMouseClick(): void
    var pos: dict<any> = getmousepos()
    if pos.winid != this.winid
      return
    endif

    for hit in this._buttonHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(len(this.fields) + hit.idx)
        this.ActivateButton(this.currentIdx)
        return
      endif
    endfor

    for hit in this._optionHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(hit.idx)
        this.fields[hit.idx].selectedIdx = hit.optionIdx
        return
      endif
    endfor

    for hit in this._fieldHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(hit.idx)
        # Place the cursor at the click. Assumes one byte per character in the
        # field, which is true for ASCII text.
        var clickChar: number = pos.column - hit.startCol
        var f: dict<any> = this.fields[hit.idx]
        f.cursor = max([0, min([strchars(f.value), f.offset + clickChar])])
        return
      endif
    endfor
  enddef

  def OnClose(winid: number, result: number): void
    if result == 1
      if type(this._onSubmit) == v:t_func
        call(this._onSubmit, [this.Values()])
      endif
    else
      if type(this._onCancel) == v:t_func
        call(this._onCancel, [])
      endif
    endif
    this.bufnr = -1
    this.winid = -1
  enddef

  ############################################################################
  # SECTION: Values.
  ############################################################################

  # METHOD: Return the field values in a dict keyed by field name, never by
  # label. A text field whose default was not a string, such as a list or
  # a number, is converted back with eval. Text that no longer parses stays
  # a string. A choice field returns its selected option.
  def Values(): dict<any>
    var result: dict<any> = {}
    for f in this.fields
      if f.type ==# 'choice'
        result[f.name] = empty(f.options) ? '' : f.options[f.selectedIdx]
        continue
      endif
      if f.type ==# 'filter'
        result[f.name] = empty(f.filtered) ? '' : f.filtered[f.selectedIdx]
        continue
      endif
      if f.type ==# 'multiline'
        result[f.name] = join(f.lines, "\n")
        continue
      endif
      var val: any = trim(f.value)
      if f.isComplex
        try
          val = eval(val)
        catch
          # Keep the text as a string if it no longer parses as Vim data.
        endtry
      endif
      result[f.name] = val
    endfor
    return result
  enddef

  ############################################################################
  # SECTION: Rendering.
  ############################################################################

  # METHOD: Return true when a text field with a maximum length is full.
  def AtMaxLength(f: dict<any>): bool
    return get(f, 'maxLength', 0) > 0 && strchars(f.value) >= f.maxLength
  enddef

  # METHOD: Move the selection of a filter list by step rows, and scroll so
  # that the selection stays visible.
  def MoveFilterSelection(f: dict<any>, step: number): void
    f.selectedIdx = max([0, min([len(f.filtered) - 1, f.selectedIdx + step])])
    if f.selectedIdx < f.scrollTop
      f.scrollTop = f.selectedIdx
    elseif f.selectedIdx >= f.scrollTop + f.maxVisible
      f.scrollTop = f.selectedIdx - f.maxVisible + 1
    endif
  enddef

  def RenderFilter(): void
    var f: dict<any> = this.fields[0]
    # The trailing space is for the cursor at the end of the text, as in
    # RenderMultiline.
    # REFERENCE: https://github.com/Galvarcus/bartleby/issues/3
    var lines: list<string> = ['> ' .. f.value .. ' ']
    for i in range(f.maxVisible)
      var idx: number = f.scrollTop + i
      add(lines, idx < len(f.filtered) ? '  ' .. f.filtered[idx] : '')
    endfor
    # With a scrollbar, each list row is padded so that its last column
    # holds the scrollbar, see DrawFilterScrollbar.
    if this.FilterScrolls(f)
      var width: number = popup_getoptions(this.winid).minwidth
      for i in range(1, f.maxVisible)
        lines[i] ..= repeat(' ', max([0, width - 1 - strdisplaywidth(lines[i])])) .. ' '
      endfor
    endif
    if empty(f.filtered)
      lines[1] = '  ' .. IN.T("(no matches)")
    endif

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    this.ApplyFilterHighlights(lines, f)
  enddef

  def ApplyFilterHighlights(lines: list<string>, f: dict<any>): void
    prop_remove({type: 'InputPopupLabel', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupCursor', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupOption', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupOptionSelected', bufnr: this.bufnr}, 1, len(lines))

    var inputText: string = lines[0]
    # Skip the prompt mark and space before the typed text: 2 characters.
    var cursorCharIdx: number = 2 + f.cursor
    var cursorByteCol: number = byteidx(inputText, cursorCharIdx) + 1
    var nextByteCol: number = byteidx(inputText, cursorCharIdx + 1)
    var cursorLen: number = (nextByteCol == -1 ? strlen(inputText) : nextByteCol) - (cursorByteCol - 1)
    prop_add(1, cursorByteCol, {
      type: 'InputPopupCursor', bufnr: this.bufnr, length: max([cursorLen, 1]),
    })

    this._fieldHit = []
    this._optionHit = []
    for i in range(min([len(f.filtered) - f.scrollTop, f.maxVisible]))
      var idx: number = f.scrollTop + i
      var lnum: number = i + 2
      var text: string = lines[lnum - 1]
      var propType: string = idx == f.selectedIdx ? 'InputPopupOptionSelected' : 'InputPopupOption'
      # Stop before the scrollbar column, which has its own highlight.
      var length: number = this.FilterScrolls(f) ? strlen(text) - 1 : strlen(text)
      prop_add(lnum, 1, {
        type: propType, bufnr: this.bufnr, length: max([length, 1]),
      })
      add(this._optionHit, {idx: 0, optionIdx: idx, lnum: lnum, startCol: 1, endCol: strlen(text)})
    endfor
    this.DrawFilterScrollbar(f)
  enddef

  # METHOD: Return true while a filter list is longer than its rows.
  def FilterScrolls(f: dict<any>): bool
    return len(f.filtered) > f.maxVisible
  enddef

  # METHOD: Draw a scrollbar in the last column of the list rows, only
  # while the list is longer than its rows. PmenuSbar colors the track and
  # PmenuThumb the thumb, as in Vim's completion menu. The size and place
  # of the thumb show which part of the list is visible. RenderFilter has
  # already padded the rows, so the last column is free.
  def DrawFilterScrollbar(f: dict<any>): void
    prop_remove({type: 'InputPopupScrollbar', bufnr: this.bufnr, all: true})
    prop_remove({type: 'InputPopupThumb', bufnr: this.bufnr, all: true})
    if !this.FilterScrolls(f)
      return
    endif
    var total: number = len(f.filtered)
    var rows: number = f.maxVisible
    var thumbSize: number = max([1, rows * rows / total])
    var thumbTop: number = (f.scrollTop * (rows - thumbSize) + (total - rows) / 2) / (total - rows)
    for i in range(rows)
      var lnum: number = i + 2
      prop_add(lnum, strlen(getbufline(this.bufnr, lnum)[0]), {
        type: i >= thumbTop && i < thumbTop + thumbSize ? 'InputPopupThumb' : 'InputPopupScrollbar',
        bufnr: this.bufnr, length: 1,
      })
    endfor
  enddef

  def RenderMultiline(): void
    var f: dict<any> = this.fields[0]
    if f.cursorLine < f.scrollOffset
      f.scrollOffset = f.cursorLine
    elseif f.cursorLine >= f.scrollOffset + f.rows
      f.scrollOffset = f.cursorLine - f.rows + 1
    endif

    var lines: list<string> = []
    for i in range(f.rows)
      var lineIdx: number = f.scrollOffset + i
      add(lines, lineIdx < len(f.lines) ? f.lines[lineIdx] : '')
    endfor
    # The cursor is a highlighted character, so at the end of its line it
    # needs a space to show on, as text fields have their padding. Only the
    # drawing gets the space, not the text. See issue 3.
    var cursorIdx: number = f.cursorLine - f.scrollOffset
    if cursorIdx >= 0 && cursorIdx < len(lines) && f.cursorCol >= strchars(lines[cursorIdx])
      lines[cursorIdx] ..= ' '
    endif

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    this.ApplyMultilineHighlights(lines, f)
  enddef

  def ApplyMultilineHighlights(lines: list<string>, f: dict<any>): void
    prop_remove({type: 'InputPopupCursor', bufnr: this.bufnr}, 1, len(lines))

    var cursorScreenLine: number = f.cursorLine - f.scrollOffset + 1
    if cursorScreenLine >= 1 && cursorScreenLine <= len(lines)
      var text: string = lines[cursorScreenLine - 1]
      var cursorByteCol: number = byteidx(text, f.cursorCol) + 1
      var nextByteCol: number = byteidx(text, f.cursorCol + 1)
      var cursorLen: number = (nextByteCol == -1 ? strlen(text) : nextByteCol) - (cursorByteCol - 1)
      prop_add(cursorScreenLine, cursorByteCol, {
        type: 'InputPopupCursor', bufnr: this.bufnr, length: max([cursorLen, 1]),
      })
    endif
  enddef

  # METHOD: Draw the popup: the fields, row by row, then the buttons, with
  # their highlights. A popup of one filter or multiline field has a
  # drawing of its own.
  def Render(): void
    if this.bufnr == -1
      return
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# 'filter'
      this.RenderFilter()
      return
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# 'multiline'
      this.RenderMultiline()
      return
    endif
    var layout: dict<any> = this.LayoutFields()
    var lines: list<string> = layout.lines
    var btnLnum: number = -1
    var btnMeta: list<dict<any>> = []
    if !empty(this.buttons)
      var buttons: dict<any> = this.LayoutButtons()
      lines->add(buttons.line)
      btnLnum = len(lines)
      btnMeta = buttons.meta
    endif
    this.WriteLines(lines)
    this.ApplyHighlights(lines, layout.meta, btnLnum, btnMeta)
  enddef

  # METHOD: Lay out the fields: the fields of a row on one line, and a
  # choice field on a line of its own. Returns the lines, and for each
  # field where its parts are, for ApplyHighlights.
  def LayoutFields(): dict<any>
    var lines: list<string> = []
    var meta: list<dict<any>> = []
    # The line being built: its row, its text, and its length in characters.
    var row: dict<any> = {num: -1, text: '', chars: 0}
    for idx in range(len(this.fields))
      var f: dict<any> = this.fields[idx]
      if f.row != row.num
        if row.num != -1
          add(lines, row.text)
        endif
        row = {num: f.row, text: '', chars: 0}
      endif
      var label: string = f.label .. ': '
      var labelStartChar: number = row.chars
      AppendTo(row, label)
      if f.type ==# 'choice'
        add(meta, this.LayoutChoice(idx, f, row, labelStartChar, strchars(label)))
        add(lines, row.text)
        row = {num: -1, text: '', chars: 0}
      else
        add(meta, this.LayoutText(idx, f, row, labelStartChar, strchars(label)))
      endif
    endfor
    if row.num != -1
      add(lines, row.text)
    endif
    return {lines: lines, meta: meta}
  enddef

  # METHOD: Add the options of the choice field f to row. Returns where its
  # label and options are.
  def LayoutChoice(idx: number, f: dict<any>, row: dict<any>, labelStartChar: number,
      labelChars: number): dict<any>
    var optChars: list<dict<any>> = []
    for i in range(len(f.options))
      var startChar: number = row.chars
      AppendTo(row, '[ ' .. f.options[i] .. ' ]')
      add(optChars, {optionIdx: i, startChar: startChar, endChar: row.chars})
      if i < len(f.options) - 1
        AppendTo(row, '  ')
      endif
    endfor
    return {
      idx: idx, field: f, lnum: row.num + 1, isChoice: true,
      labelStartChar: labelStartChar, labelChars: labelChars,
      optChars: optChars,
    }
  enddef

  # METHOD: Add the visible part of the text field f to row, scrolled so
  # that the cursor of the focused field shows. Returns where its label and
  # value are.
  def LayoutText(idx: number, f: dict<any>, row: dict<any>, labelStartChar: number,
      labelChars: number): dict<any>
    if idx == this.currentIdx
      if f.cursor < f.offset
        f.offset = f.cursor
      elseif f.cursor > f.offset + f.width - 1
        f.offset = f.cursor - f.width + 1
      endif
    else
      f.offset = 0
    endif
    var visible: string = strcharpart(f.value, f.offset, f.width)
    var valueStartChar: number = row.chars
    AppendTo(row, visible .. repeat(' ', max([f.width - strchars(visible), 0])) .. '  ')
    return {
      idx: idx, field: f, lnum: row.num + 1, isChoice: false,
      labelStartChar: labelStartChar, labelChars: labelChars,
      valueStartChar: valueStartChar, valueChars: f.width,
    }
  enddef

  # METHOD: Lay out the buttons on one line. Returns the line, and where
  # each button is.
  def LayoutButtons(): dict<any>
    var line: string = ''
    var meta: list<dict<any>> = []
    for i in range(len(this.buttons))
      var startChar: number = strchars(line)
      line ..= '[ ' .. this.buttons[i].label .. ' ]'
      add(meta, {idx: i, startChar: startChar, endChar: strchars(line)})
      if i < len(this.buttons) - 1
        line ..= '  '
      endif
    endfor
    return {line: line, meta: meta}
  enddef

  # METHOD: Put lines in the popup buffer, and remove the lines after them.
  def WriteLines(lines: list<string>): void
    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif
  enddef

  def ApplyHighlights(lines: list<string>, meta: list<dict<any>>,
      btnLnum: number, btnCharMeta: list<dict<any>>): void
    prop_remove({type: 'InputPopupLabel', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupCursor', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupButton', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupButtonActive', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupOption', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'InputPopupOptionSelected', bufnr: this.bufnr}, 1, len(lines))

    this._fieldHit = []
    this._optionHit = []
    for m in meta
      var text: string = lines[m.lnum - 1]
      var labelStartCol: number = byteidx(text, m.labelStartChar) + 1
      var labelEndByte: number = byteidx(text, m.labelStartChar + m.labelChars)
      var labelLen: number = (labelEndByte == -1 ? strlen(text) : labelEndByte) - (labelStartCol - 1)
      prop_add(m.lnum, labelStartCol, {
        type: 'InputPopupLabel', bufnr: this.bufnr, length: max([labelLen, 1]),
      })

      if m.isChoice
        for oc in m.optChars
          var optStartCol: number = byteidx(text, oc.startChar) + 1
          var optEndByte: number = byteidx(text, oc.endChar)
          var optEndCol: number = (optEndByte == -1 ? strlen(text) : optEndByte)
          var propType: string = oc.optionIdx == m.field.selectedIdx
            ? 'InputPopupOptionSelected' : 'InputPopupOption'
          prop_add(m.lnum, optStartCol, {
            type: propType, bufnr: this.bufnr, length: max([optEndCol - (optStartCol - 1), 1]),
          })
          add(this._optionHit, {idx: m.idx, optionIdx: oc.optionIdx, lnum: m.lnum,
            startCol: optStartCol, endCol: optEndCol})
        endfor
        continue
      endif

      var valueStartCol: number = byteidx(text, m.valueStartChar) + 1
      var valueEndByte: number = byteidx(text, m.valueStartChar + m.valueChars)
      var valueEndCol: number = (valueEndByte == -1 ? strlen(text) : valueEndByte)
      add(this._fieldHit, {idx: m.idx, lnum: m.lnum, startCol: valueStartCol, endCol: valueEndCol})
    endfor

    if this.currentIdx < len(this.fields) && this.fields[this.currentIdx].type !=# 'choice'
      var activeMeta: dict<any> = meta[this.currentIdx]
      var f: dict<any> = activeMeta.field
      var cursorCharIdx: number = activeMeta.valueStartChar + (f.cursor - f.offset)
      var text: string = lines[activeMeta.lnum - 1]
      var cursorByteCol: number = byteidx(text, cursorCharIdx) + 1
      var nextByteCol: number = byteidx(text, cursorCharIdx + 1)
      var cursorLen: number = (nextByteCol == -1 ? strlen(text) : nextByteCol) - (cursorByteCol - 1)
      prop_add(activeMeta.lnum, cursorByteCol, {
        type: 'InputPopupCursor', bufnr: this.bufnr, length: max([cursorLen, 1]),
      })
    endif

    this._buttonHit = []
    if btnLnum == -1
      return
    endif
    var btnText: string = lines[btnLnum - 1]
    var activeBtnIdx: number = this.currentIdx - len(this.fields)
    for bm in btnCharMeta
      var startCol: number = byteidx(btnText, bm.startChar) + 1
      var endByte: number = byteidx(btnText, bm.endChar)
      var endCol: number = (endByte == -1 ? strlen(btnText) : endByte)
      var propType: string = bm.idx == activeBtnIdx ? 'InputPopupButtonActive' : 'InputPopupButton'
      prop_add(btnLnum, startCol, {
        type: propType, bufnr: this.bufnr, length: max([endCol - (startCol - 1), 1]),
      })
      add(this._buttonHit, {idx: bm.idx, lnum: btnLnum, startCol: startCol, endCol: endCol})
    endfor
  enddef
endclass
