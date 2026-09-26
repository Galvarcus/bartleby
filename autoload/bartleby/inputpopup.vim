vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inputpopup.vim - a reusable, modal popup mixing free-text fields and
# choice-of-N fields in one form, one Tab-navigation flow, one Submit/
# Cancel. Supersedes formpopup.vim (text-only) - its layout/navigation/
# hit-testing architecture is carried forward here, extended with a
# `type: 'choice'` field. picker.vim's PickOne() and buttonspopup.vim's
# PopupButtonMenu remain separate: PickOne is refactored to call this
# widget with a single choice field (see picker.vim); PopupButtonMenu
# stays a standalone primitive for Corkboard's card grid, which isn't a
# form and doesn't fit this shape.
#
# `fields` is a list of rows, each row a list of field specs:
#
#   var fields = [
#     [{name: 'title', type: 'text'}],
#     [{name: 'kind', type: 'choice', options: ['Manuscript', 'Book']}],
#     [{name: 'city', type: 'text'}, {name: 'zip', type: 'text'}],
#   ]
#
# A choice field always takes its own full row regardless of grouping -
# mixing it with other fields on one row isn't supported, since the
# width math for a row of options doesn't compose cleanly with text
# boxes. renders as:
#
#   title:  __________________
#   kind:   [ Manuscript ]  [ Book ]
#   city: ______  zip: _____
#
#   [ Submit ]  [ Cancel ]
#
# The caller supplies starting values (a plain dict<any>, keyed by field
# name - a choice field's default is the option string to preselect) and
# gets a dict<any> back via OnSubmit when the user submits: a text
# field's value as typed, a choice field's currently-selected option
# string.
#
# opts (a data contract, not Vim identifiers - left as originally
# documented on formpopup.vim, snake_case, so callers don't break):
#   field_width   number            default text-field value-box width
#                                    (default 20)
#   widths        dict<number>      per-field width override (text
#                                    fields only), keyed by field name
#   labels        dict<string>      per-field display label, keyed by
#                                    field name. Falls back to the field
#                                    name itself.
#   submit_label   string           text on the submit button (default
#                                    'Submit')
#   cancel_label   string           text on the cancel button (default
#                                    'Cancel')
#   title, line, col, zindex        passed straight through to popup_create()
#
# Keys: Tab/S-Tab or C-n/C-p move between fields AND the two buttons.
# Within a text field: Left/Right/Home/End move the cursor, C-u clears
# it, Enter advances. Within a choice field: Left/Right move which
# option is selected (clamped, not wrapped), Enter advances. C-s submits
# from anywhere, Esc/C-c cancels from anywhere. Buttons, text fields, and
# individual choice options can all be clicked with the mouse.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

# Converts formpopup.vim's old row-of-names format (list<list<string>>)
# into InputPopup's field-spec format, for the common case of a form
# that's entirely text fields - saves writing out {name: x, type: 'text'}
# at every call site migrating off FormPopup.
def Noop(): void
enddef

export def TextFields(rows: list<list<string>>): list<list<dict<any>>>
  return rows->mapnew((_, row) => row->mapnew((_, name) => ({name: name, type: 'text'})))
enddef

# Opens a single text field titled `title`, pre-filled with `default`;
# calls `OnSubmit` with the entered string, or `OnCancel` (a no-op by
# default) if the popup is cancelled instead. The single-field-submits-
# on-one-Enter behavior applies, so this feels like input() with a
# nicer box, not an extra form to fill out.
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

# Opens `options` as a type-to-filter list titled `title` (fuzzy-matched
# via Vim's own matchfuzzy() as the user types); calls `OnSubmit` with
# the selected string. Not called at all if cancelled or if Enter is
# pressed with no matches. Up/Down (or Ctrl-K/Ctrl-J) move the
# selection within the filtered results; Enter submits directly, same
# one-keypress feel as PickOne.
export def PromptFilter(title: string, options: list<string>, OnSubmit: func(string),
    maxVisible: number = 10, minWidth: number = 0): void
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'filter',
    options: options, maxVisible: maxVisible}]]
  var form: InputPopup = InputPopup.new(fields, {},
    {title: $' {title} ', buttons: [], min_width: minWidth})
  form.OnSubmit((values: dict<any>) => {
    if values.choice !=# ''
      OnSubmit(values.choice)
    endif
  })
  form.Open()
enddef

# Opens a multi-line text field titled `title`, pre-filled with
# `default` (newline-separated). Enter inserts a newline rather than
# submitting (unlike every other single-field prompt) - use Ctrl-S or
# the Submit button. Calls OnSubmit with the edited text, newline-
# joined; not called at all if cancelled.
export def PromptMultiline(title: string, default: string, OnSubmit: func(string),
    rows: number = 5, width: number = 50): void
  var fields: list<list<dict<any>>> = [[{name: 'text', type: 'multiline',
    rows: rows}]]
  var form: InputPopup = InputPopup.new(fields, {text: default},
    {title: $' {title} (<C-s> to save) ', widths: {text: width}, buttons: []})
  form.OnSubmit((values: dict<any>) => {
    OnSubmit(values.text)
  })
  form.Open()
enddef

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

  # --- setup ------------------------------------------------------------

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
          field.width = get(widths, name, defaultWidth)
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
      {label: get(this.opts, 'submit_label', 'Submit'), action: 'submit'},
      {label: get(this.opts, 'cancel_label', 'Cancel'), action: 'cancel'},
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

  # `width`, widened so the popup's title shows in full with 2 columns
  # to spare, and to the caller's min_width option.
  def FitTitle(width: number): number
    var title: string = trim(get(this.opts, 'title', ''))
    return max([width, strdisplaywidth(title) + 2, get(this.opts, 'min_width', 0)])
  enddef

  # --- public API ---------------------------------------------------------

  # Cb: func(dict<any>) — called with the submitted field values.
  def OnSubmit(Cb: any): void
    this._onSubmit = Cb
  enddef

  # Cb: func() — called if the user cancels instead of submitting.
  def OnCancel(Cb: any): void
    this._onCancel = Cb
  enddef

  def Open(): void
    if empty(this.fields)
      log.Error('InputPopup: fieldRows produced no fields')
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

  # --- focus helpers ------------------------------------------------------

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

  # --- input handling -------------------------------------------------

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

  def Filter(winid: number, key: string): bool
    var isButton: bool = this.IsButtonIdx(this.currentIdx)
    var isMultiline: bool = !isButton && this.fields[this.currentIdx].type ==# 'multiline'

    if isMultiline
      if key == "\<C-s>"
        popup_close(winid, 1)
        return true
      elseif key == "\<Esc>" || key == "\<C-c>"
        popup_close(winid, 0)
        return true
      else
        this.HandleMultilineKey(key)
      endif
      this.Render()
      return true
    endif

    var isChoice: bool = !isButton && this.fields[this.currentIdx].type ==# 'choice'
    var isFilter: bool = !isButton && this.fields[this.currentIdx].type ==# 'filter'
    var valueChanged: bool = false

    if key == "\<Tab>" || key == "\<C-n>"
      this.Focus((this.currentIdx + 1) % this.TotalControls())
    elseif key == "\<S-Tab>" || key == "\<C-p>"
      this.Focus((this.currentIdx - 1 + this.TotalControls()) % this.TotalControls())
    elseif key == "\<C-s>"
      popup_close(winid, 1)
      return true
    elseif key == "\<Esc>" || key == "\<C-c>"
      popup_close(winid, 0)
      return true
    elseif key == "\<LeftMouse>"
      this.HandleMouseClick()
    elseif isButton && (key == "\<CR>" || key == ' ')
      this.ActivateButton(this.currentIdx)
      return true
    elseif isButton && key == "\<Left>"
      this.Focus(max([len(this.fields), this.currentIdx - 1]))
    elseif isButton && key == "\<Right>"
      this.Focus(min([this.TotalControls() - 1, this.currentIdx + 1]))
    elseif isButton
      # buttons hold no text; ignore any other key while one has focus
    elseif isFilter && (key == "\<Down>" || key == "\<C-j>" || key == "\<ScrollWheelDown>")
      this.MoveFilterSelection(this.fields[this.currentIdx], 1)
    elseif isFilter && (key == "\<Up>" || key == "\<C-k>" || key == "\<ScrollWheelUp>")
      this.MoveFilterSelection(this.fields[this.currentIdx], -1)
    elseif isFilter && key == "\<PageDown>"
      this.MoveFilterSelection(this.fields[this.currentIdx], this.fields[this.currentIdx].maxVisible)
    elseif isFilter && key == "\<PageUp>"
      this.MoveFilterSelection(this.fields[this.currentIdx], -this.fields[this.currentIdx].maxVisible)
    elseif isFilter && key == "\<CR>"
      if !empty(this.fields[this.currentIdx].filtered)
        popup_close(winid, 1)
      endif
      return true
    elseif isChoice && key == "\<Left>"
      var f: dict<any> = this.fields[this.currentIdx]
      f.selectedIdx = max([0, f.selectedIdx - 1])
    elseif isChoice && key == "\<Right>"
      var f: dict<any> = this.fields[this.currentIdx]
      f.selectedIdx = min([len(f.options) - 1, f.selectedIdx + 1])
    elseif isChoice && key == "\<CR>"
      if len(this.fields) == 1
        popup_close(winid, 1)
        return true
      endif
      this.Focus(this.currentIdx < len(this.fields) - 1 ? this.currentIdx + 1 : len(this.fields))
    elseif isChoice
      # choice fields hold no text; ignore any other key
    elseif key == "\<CR>"
      if len(this.fields) == 1
        popup_close(winid, 1)
        return true
      endif
      if this.currentIdx < len(this.fields) - 1
        this.Focus(this.currentIdx + 1)
      else
        this.Focus(len(this.fields))    # hop to the Submit button
      endif
    elseif key == "\<BS>" || key == "\<C-h>"
      var f: dict<any> = this.fields[this.currentIdx]
      if f.cursor > 0
        var chars: list<string> = split(f.value, '\zs')
        remove(chars, f.cursor - 1)
        f.value = join(chars, '')
        f.cursor -= 1
        valueChanged = true
      endif
    elseif key == "\<Del>"
      var f: dict<any> = this.fields[this.currentIdx]
      if f.cursor < strchars(f.value)
        var chars: list<string> = split(f.value, '\zs')
        remove(chars, f.cursor)
        f.value = join(chars, '')
        valueChanged = true
      endif
    elseif key == "\<C-u>"
      this.fields[this.currentIdx].value = ''
      this.fields[this.currentIdx].cursor = 0
      valueChanged = true
    elseif key == "\<Left>"
      var f: dict<any> = this.fields[this.currentIdx]
      f.cursor = max([0, f.cursor - 1])
    elseif key == "\<Right>"
      var f: dict<any> = this.fields[this.currentIdx]
      f.cursor = min([strchars(f.value), f.cursor + 1])
    elseif key == "\<Home>" || key == "\<C-a>"
      this.fields[this.currentIdx].cursor = 0
    elseif key == "\<End>" || key == "\<C-e>"
      var f: dict<any> = this.fields[this.currentIdx]
      f.cursor = strchars(f.value)
    elseif strchars(key) == 1 && char2nr(key) >= 32
      var f: dict<any> = this.fields[this.currentIdx]
      var chars: list<string> = split(f.value, '\zs')
      insert(chars, key, f.cursor)
      f.value = join(chars, '')
      f.cursor += 1
      valueChanged = true
    endif

    if valueChanged && isFilter
      var f: dict<any> = this.fields[this.currentIdx]
      f.filtered = f.value ==# '' ? copy(f.options) : matchfuzzy(f.options, f.value)
      f.selectedIdx = 0
      f.scrollTop = 0
    endif

    this.Render()
    return true
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
        # best-effort click-to-cursor placement; assumes ~1 byte per
        # character within the value box (fine for ASCII input)
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

  # --- values -----------------------------------------------------------

  # Returns the current field values as a plain dict<any>, keyed by each
  # field's own name (never its display label). A text field whose
  # starting default was a non-string type (list, dict, number, ...) is
  # eval()'d back into that type; a value that no longer parses is left
  # as the typed-in string instead. A choice field's value is whichever
  # option string is currently selected.
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
          # left as a plain string if it no longer parses as vim data
        endtry
      endif
      result[f.name] = val
    endfor
    return result
  enddef

  # --- rendering ----------------------------------------------------------

  # Moves a filter list's selection by `step` rows, and scrolls so that
  # the selection stays visible.
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
    var lines: list<string> = ['> ' .. f.value]
    for i in range(f.maxVisible)
      var idx: number = f.scrollTop + i
      add(lines, idx < len(f.filtered) ? '  ' .. f.filtered[idx] : '')
    endfor
    # With a scrollbar, every list row is padded so that its last column
    # holds the scrollbar (see DrawFilterScrollbar()).
    if this.FilterScrolls(f)
      var width: number = popup_getoptions(this.winid).minwidth
      for i in range(1, f.maxVisible)
        lines[i] ..= repeat(' ', max([0, width - 1 - strdisplaywidth(lines[i])])) .. ' '
      endfor
    endif
    if empty(f.filtered)
      lines[1] = '  (no matches)'
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
    var cursorCharIdx: number = 2 + f.cursor    # "> " prefix is 2 chars
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

  # True while a filter list is longer than its visible rows.
  def FilterScrolls(f: dict<any>): bool
    return len(f.filtered) > f.maxVisible
  enddef

  # A scrollbar in the last column of the list rows, only while the list
  # is longer than its visible rows: PmenuSbar for the track, PmenuThumb
  # for the thumb, as in Vim's own completion menu. The thumb's size and
  # place show which part of the list is visible. RenderFilter() has
  # already padded the rows so that the last column is free.
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

    var lines: list<string> = []
    var meta: list<dict<any>> = []
    var curRow: number = -1
    var line: string = ''
    var lineChars: number = 0

    for idx in range(len(this.fields))
      var f: dict<any> = this.fields[idx]

      if f.row != curRow
        if curRow != -1
          add(lines, line)
        endif
        curRow = f.row
        line = ''
        lineChars = 0
      endif

      var label: string = f.label .. ': '
      var labelStartChar: number = lineChars
      line ..= label
      lineChars += strchars(label)

      if f.type ==# 'choice'
        var optChars: list<dict<any>> = []
        for i in range(len(f.options))
          var text: string = '[ ' .. f.options[i] .. ' ]'
          var startChar: number = lineChars
          line ..= text
          lineChars += strchars(text)
          add(optChars, {optionIdx: i, startChar: startChar, endChar: lineChars})
          if i < len(f.options) - 1
            line ..= '  '
            lineChars += 2
          endif
        endfor
        add(meta, {
          idx: idx, field: f, lnum: curRow + 1, isChoice: true,
          labelStartChar: labelStartChar, labelChars: strchars(label),
          optChars: optChars,
        })
        add(lines, line)
        curRow = -1
        line = ''
        lineChars = 0
        continue
      endif

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
      var pad: number = f.width - strchars(visible)
      var display: string = visible .. repeat(' ', max([pad, 0]))
      var valueStartChar: number = lineChars
      line ..= display .. '  '
      lineChars += strchars(display) + 2

      add(meta, {
        idx: idx, field: f, lnum: curRow + 1, isChoice: false,
        labelStartChar: labelStartChar, labelChars: strchars(label),
        valueStartChar: valueStartChar, valueChars: f.width,
      })
    endfor
    if curRow != -1
      add(lines, line)
    endif

    var btnLnum: number = -1
    if !empty(this.buttons)
      btnLnum = len(lines) + 1
      var btnLine: string = ''
      var btnCharMeta: list<dict<any>> = []
      for i in range(len(this.buttons))
        var text: string = '[ ' .. this.buttons[i].label .. ' ]'
        var startChar: number = strchars(btnLine)
        btnLine ..= text
        add(btnCharMeta, {idx: i, startChar: startChar, endChar: strchars(btnLine)})
        if i < len(this.buttons) - 1
          btnLine ..= '  '
        endif
      endfor
      add(lines, btnLine)

      setbufline(this.bufnr, 1, lines)
      if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
        deletebufline(this.bufnr, len(lines) + 1, '$')
      endif
      this.ApplyHighlights(lines, meta, btnLnum, btnCharMeta)
    else
      setbufline(this.bufnr, 1, lines)
      if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
        deletebufline(this.bufnr, len(lines) + 1, '$')
      endif
      this.ApplyHighlights(lines, meta, -1, [])
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
