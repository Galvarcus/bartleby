vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# formpopup.vim - a reusable, modal text-entry popup whose layout is driven
# License: GNU GPL 3.0
# entirely by the `inputVars` structure passed in - a list of rows, each
# row a list of field names:
#
#   var vars = [
#     ['name'],
#     ['address', 'city', 'state', 'zip'],
#     ['email'],
#     ['phonenumber'],
#   ]
#
# renders as:
#
#   name:  __________________
#   address: ______  city: ____  state: __  zip: _____
#   email: __________________
#   phonenumber: __________________
#
#   [ Submit ]  [ Cancel ]
#
# FormPopup knows nothing about where values come from or go to. The
# caller supplies starting values (a plain dict<any>, e.g. read from a
# config file, a database, or just {}) and gets a dict<any> back via an
# OnSubmit callback when the user submits. What happens with that dict -
# save it to a `.config` file, send it somewhere, stash it in a
# variable - is entirely up to the caller.
#
# opts: NOTE - these are a data contract, not Vim identifiers, so they're
# left as originally documented (snake_case) rather than renamed to
# camelCase, so any other caller of this widget doesn't break.
#   field_width   number            default value-box width (default 20)
#   widths        dict<number>      per-field width override, keyed by
#                                    the field name as it appears in
#                                    inputVars
#   labels        dict<string>      per-field display label, keyed by
#                                    the field name as it appears in
#                                    inputVars. Falls back to the field
#                                    name itself when a field has no
#                                    entry here - the value used to look
#                                    up/store defaults is always the
#                                    inputVars name, only the on-screen
#                                    text changes.
#   submit_label   string           text on the submit button (default
#                                    'Submit')
#   cancel_label   string           text on the cancel button (default
#                                    'Cancel')
#   title, line, col, zindex        passed straight through to popup_create()
#
# Keys: Tab/S-Tab or C-n/C-p move between fields AND the two buttons,
# Left/Right/Home/End move the cursor within a field (or hop between
# buttons when a button has focus), C-u clears a field, Enter advances
# to the next field/button and activates a focused button, C-s submits
# from anywhere, Esc/C-c cancels from anywhere. The buttons can also be
# clicked with the mouse, as can a field (which focuses it and places
# the cursor at the click, on a byte-column best-effort basis).
#
# Usage:
#   import autoload 'bartleby/formpopup.vim' as FP
#   import autoload 'bartleby/config.vim' as ConfigLib     " or any storage you like
#
#   def OpenContactForm(): void
#     var cfg = ConfigLib.Config.new(getcwd())
#     var vars = [['name'], ['address', 'city', 'state', 'zip'],
#                 ['email'], ['phonenumber']]
#     var form = FP.FormPopup.new(vars, cfg.All(), {
#       title: ' Contact Info ',
#       labels: {phonenumber: 'Phone Number', zip: 'Zip Code'},
#     })
#     form.OnSubmit((values) => {
#       for [key, val] in items(values)
#         cfg.Set(key, val)
#       endfor
#       cfg.Save()
#     })
#     form.Open()
#   enddef
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

export class FormPopup
  var inputVars: list<list<string>>
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
  var _buttonHit: list<dict<any>> = []

  def new(this.inputVars, defaults: dict<any> = {}, opts: dict<any> = {})
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
    for rowIdx in range(len(this.inputVars))
      for name in this.inputVars[rowIdx]
        var raw: any = get(this.defaults, name, '')
        var isComplex: bool = type(raw) != v:t_string
        var text: string = isComplex ? string(raw) : raw
        add(this.fields, {
          name: name,
          label: get(labels, name, name),
          row: rowIdx,
          value: text,
          cursor: strchars(text),
          offset: 0,
          isComplex: isComplex,
          width: get(widths, name, defaultWidth),
        })
      endfor
    endfor
  enddef

  def BuildButtons(): void
    this.buttons = [
      {label: get(this.opts, 'submit_label', 'Submit'), action: 'submit'},
      {label: get(this.opts, 'cancel_label', 'Cancel'), action: 'cancel'},
    ]
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('FormPopupLabel'))
      prop_type_add('FormPopupLabel', {highlight: 'Title'})
    endif
    if empty(prop_type_get('FormPopupCursor'))
      prop_type_add('FormPopupCursor', {highlight: 'IncSearch'})
    endif
    if empty(prop_type_get('FormPopupButton'))
      prop_type_add('FormPopupButton', {highlight: 'Pmenu'})
    endif
    if empty(prop_type_get('FormPopupButtonActive'))
      prop_type_add('FormPopupButtonActive', {highlight: 'PmenuSel'})
    endif
  enddef

  def ButtonLineText(): string
    var parts: list<string> = []
    for b in this.buttons
      add(parts, '[ ' .. b.label .. ' ]')
    endfor
    return join(parts, '  ')
  enddef

  def ComputeSize(): list<number>
    var rowWidths: dict<number> = {}
    var rowCount: number = 0
    for f in this.fields
      var key: string = string(f.row)
      var w: number = get(rowWidths, key, 0) + strchars(f.label) + 2 + f.width + 2
      rowWidths[key] = w
      rowCount = max([rowCount, f.row + 1])
    endfor
    var maxWidth: number = strchars(this.ButtonLineText())
    for w in values(rowWidths)
      maxWidth = max([maxWidth, w])
    endfor
    # +1 row for the Submit/Cancel button line
    return [max([maxWidth, 10]), max([rowCount, 1]) + 1]
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
      log.Error('FormPopup: inputVars produced no fields')
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
      title: get(this.opts, 'title', ' Form '),
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
    if idx < len(this.fields)
      this.fields[idx].cursor = strchars(this.fields[idx].value)
    endif
  enddef

  def ActivateButton(idx: number): void
    var btn: dict<any> = this.ButtonAt(idx)
    popup_close(this.winid, btn.action == 'submit' ? 1 : 0)
  enddef

  # --- input handling -------------------------------------------------

  def Filter(winid: number, key: string): bool
    var isButton: bool = this.IsButtonIdx(this.currentIdx)

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
    elseif key == "\<CR>"
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
      endif
    elseif key == "\<Del>"
      var f: dict<any> = this.fields[this.currentIdx]
      if f.cursor < strchars(f.value)
        var chars: list<string> = split(f.value, '\zs')
        remove(chars, f.cursor)
        f.value = join(chars, '')
      endif
    elseif key == "\<C-u>"
      this.fields[this.currentIdx].value = ''
      this.fields[this.currentIdx].cursor = 0
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

  # Returns the current field values as a plain dict<any>, keyed by the
  # field's inputVars name (never its display label). Fields whose
  # starting default was a non-string type (list, dict, number, ...) are
  # eval()'d back into that type; a value that no longer parses is left
  # as the typed-in string instead.
  def Values(): dict<any>
    var result: dict<any> = {}
    for f in this.fields
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

  def Render(): void
    if this.bufnr == -1
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
        idx: idx,
        field: f,
        lnum: curRow + 1,
        labelStartChar: labelStartChar,
        labelChars: strchars(label),
        valueStartChar: valueStartChar,
        valueChars: f.width,
      })
    endfor
    if curRow != -1
      add(lines, line)
    endif

    var btnLnum: number = len(lines) + 1
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
  enddef

  def ApplyHighlights(lines: list<string>, meta: list<dict<any>>,
      btnLnum: number, btnCharMeta: list<dict<any>>): void
    prop_remove({type: 'FormPopupLabel', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'FormPopupCursor', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'FormPopupButton', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'FormPopupButtonActive', bufnr: this.bufnr}, 1, len(lines))

    this._fieldHit = []
    for m in meta
      var text: string = lines[m.lnum - 1]
      var labelStartCol: number = byteidx(text, m.labelStartChar) + 1
      var labelEndByte: number = byteidx(text, m.labelStartChar + m.labelChars)
      var labelLen: number = (labelEndByte == -1 ? strlen(text) : labelEndByte) - (labelStartCol - 1)
      prop_add(m.lnum, labelStartCol, {
        type: 'FormPopupLabel', bufnr: this.bufnr, length: max([labelLen, 1]),
      })

      var valueStartCol: number = byteidx(text, m.valueStartChar) + 1
      var valueEndByte: number = byteidx(text, m.valueStartChar + m.valueChars)
      var valueEndCol: number = (valueEndByte == -1 ? strlen(text) : valueEndByte)
      add(this._fieldHit, {idx: m.idx, lnum: m.lnum, startCol: valueStartCol, endCol: valueEndCol})
    endfor

    if this.currentIdx < len(this.fields)
      var activeMeta: dict<any> = meta[this.currentIdx]
      var f: dict<any> = activeMeta.field
      var cursorCharIdx: number = activeMeta.valueStartChar + (f.cursor - f.offset)
      var text: string = lines[activeMeta.lnum - 1]
      var cursorByteCol: number = byteidx(text, cursorCharIdx) + 1
      var nextByteCol: number = byteidx(text, cursorCharIdx + 1)
      var cursorLen: number = (nextByteCol == -1 ? strlen(text) : nextByteCol) - (cursorByteCol - 1)
      prop_add(activeMeta.lnum, cursorByteCol, {
        type: 'FormPopupCursor', bufnr: this.bufnr, length: max([cursorLen, 1]),
      })
    endif

    this._buttonHit = []
    var btnText: string = lines[btnLnum - 1]
    var activeBtnIdx: number = this.currentIdx - len(this.fields)
    for bm in btnCharMeta
      var startCol: number = byteidx(btnText, bm.startChar) + 1
      var endByte: number = byteidx(btnText, bm.endChar)
      var endCol: number = (endByte == -1 ? strlen(btnText) : endByte)
      var propType: string = bm.idx == activeBtnIdx ? 'FormPopupButtonActive' : 'FormPopupButton'
      prop_add(btnLnum, startCol, {
        type: propType, bufnr: this.bufnr, length: max([endCol - (startCol - 1), 1]),
      })
      add(this._buttonHit, {idx: bm.idx, lnum: btnLnum, startCol: startCol, endCol: endCol})
    endfor
  enddef
endclass
