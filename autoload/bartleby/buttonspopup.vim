vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# buttonspopup.vim - generic reusable popup of clickable buttons.
# License: GNU GPL 3.0
#
# USAGE
# -----
#   import autoload 'bartleby/buttonspopup.vim' as BP
#
#   var buttons = [
#     BP.Button.new('Yes',    MyYesFunc),
#     BP.Button.new('No',     MyNoFunc),
#     BP.Button.new('Cancel', MyCancelFunc),
#   ]
#
#   var menu = BP.PopupButtonMenu.new(buttons, {
#     button: {columns: 3},
#     popup:  {title: ' Confirm ', border: []},
#     callback: (selected: any) => {
#       if selected != null
#         # the caller decides whether/how to invoke it - the popup class
#         # itself never calls a button's Action.
#         call(selected.Action, [])
#       endif
#     },
#   })
#   menu.Show()
#
# Button.new(label, Action, data = v:none)
#   label   string   - text shown on the button. A plain string renders as
#                       the original single-line '[ label ]' bracket style.
#                       A label containing "\n" instead renders as a
#                       bordered multi-line card - the first line reads as
#                       a title, with no special styling of its own; how
#                       you split further lines (e.g. word-wrapping a
#                       longer synopsis) is entirely up to the caller (see
#                       bartleby/wrap.vim for a small helper).
#   Action  funcref  - associated function; returned untouched to the
#                       callback (never invoked by this class)
#   data    any      - optional caller-defined payload carried alongside
#                       the button (e.g. an id, a record, ...); defaults
#                       to v:none when omitted
#
# PopupButtonMenu.new(buttons: list<Button>, opts: dict<any> = {})
#   opts is a dict<any> with three (all optional except callback) sections.
#   NOTE: opts' own keys (button/popup/callback and their sub-keys below)
#   are a data contract, not Vim identifiers - left as originally
#   documented (snake_case) rather than renamed to camelCase, so any other
#   caller of this widget doesn't break.
#
#     opts.popup     any popup_create() option: title, border, pos, line,
#                     col, minwidth, zindex, highlight, etc. Passed straight
#                     through. 'filter' and 'callback' are reserved and
#                     overwritten by this class.
#
#     opts.button     columns      number  grid column count
#                                          (default: len(buttons), i.e. 1 row)
#                     spacing      number  blank cols between buttons within
#                                          a row (default: 2)
#                     row_spacing  number  blank lines between button rows
#                                          (default: 1)
#                     width        number  force a minimum width for every
#                                          button (default: 0, meaning each
#                                          button is sized independently to
#                                          fit its own content - single-line
#                                          text, or the longest line of a
#                                          multi-line card)
#                     normal_hl    string  highlight group, unselected
#                                          button (default 'Pmenu')
#                     select_hl    string  highlight group, selected
#                                          button (default 'PmenuSel')
#                     selected     number  initially-highlighted button
#                                          index (default 0)
#
#     opts.on_key     optional func(id: number, selected: number,
#                     key: string): bool, tried before this popup's own
#                     key handling on every keypress. Return true to mean
#                     "handled, stop here"; false falls through to the
#                     built-in navigation/activation keys as normal. Lets
#                     a caller layer its own keys onto an otherwise-
#                     unmodified popup (see bartleby/corkboard.vim for an
#                     example: 'e' to edit, J/K to reorder).
#
#     opts.callback   REQUIRED. func(any). Called once, when the popup
#                     closes, with the activated Button object, or `null`
#                     if the popup was cancelled (<Esc>, or a click outside
#                     the popup).
#
# menu.Show(): number   -- opens the popup, returns its winid.
#
# NAVIGATION
# ----------
#   <Left>/<Right>/<Tab>/<S-Tab> / h / l   move selection (wraps)
#   <Up>/<Down> / k / j                    move by one grid row (wraps per
#                                           column)
#   <CR> / <Space>                         activate the selected button
#   <LeftMouse>                            click a button to activate it
#                                           directly; clicking outside the
#                                           popup cancels it
#   <ScrollWheelUp>/<ScrollWheelDown>      scroll when content exceeds
#                                           opts.popup.maxheight (default:
#                                           terminal height minus a small
#                                           margin) - selection also
#                                           auto-scrolls into view as it
#                                           moves past the visible area
#   <Esc> / <C-c>                          cancel (callback receives null)
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

# [topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical].
# Plain ASCII, deliberately - Unicode box-drawing characters are in
# Unicode's "ambiguous width" category, and a mismatch between what a
# terminal/font actually renders them as and what strdisplaywidth()
# assumes throws off every highlight span computed from it. Gating on
# 'ambiwidth' wasn't sufficient to avoid this in practice, since that
# reflects Vim's own assumption rather than the terminal's actual
# rendering - so ASCII stays unconditional for now.
def BoxChars(): list<string>
  return ['+', '+', '+', '+', '-', '|']
enddef

export class Button
  public var label: string
  public var Action: func
  public var data: any = v:none

  def new(this.label, this.Action, this.data = v:none)
  enddef
endclass

export class PopupButtonMenu
  # ---- configuration (set from opts in the constructor) ----
  var buttons: list<Button>
  var callback: func(any)
  var columns: number = 1
  var spacing: number = 2
  var rowSpacing: number = 1
  var buttonWidth: number = 0
  var normalHl: string = 'Pmenu'
  var selectHl: string = 'PmenuSel'
  var popupOpts: dict<any> = {}
  # Optional func(id: number, selected: number, key: string): bool, tried
  # before this popup's own key handling. Returning true means "handled,
  # stop here"; false falls through to the built-in navigation/activation
  # keys as normal. Lets a caller (e.g. corkboard.vim) add its own keys to
  # an otherwise-unmodified PopupButtonMenu. null (the default) means no
  # hook - behavior is identical to before this option existed.
  var OnKey: any = null

  # ---- runtime state ----
  var id: number = -1
  var lines: list<string> = []
  var positions: list<dict<any>> = []
  var matchIds: list<number> = []
  var selected: number = 0

  def new(this.buttons, opts: dict<any> = {})
    if empty(this.buttons)
      log.Error('PopupButtonMenu: buttons list must not be empty')
      throw 'PopupButtonMenu: buttons list must not be empty'
    endif

    var buttonOpts: dict<any> = get(opts, 'button', {})
    this.popupOpts = copy(get(opts, 'popup', {}))
    this.callback = get(opts, 'callback', null)
    if this.callback == null
      log.Error('PopupButtonMenu: opts.callback is required')
      throw 'PopupButtonMenu: opts.callback is required'
    endif

    this.columns = max([1, get(buttonOpts, 'columns', len(this.buttons))])
    this.spacing = get(buttonOpts, 'spacing', 2)
    this.rowSpacing = max([0, get(buttonOpts, 'row_spacing', 1)])
    this.buttonWidth = get(buttonOpts, 'width', 0)
    this.normalHl = get(buttonOpts, 'normal_hl', 'Pmenu')
    this.selectHl = get(buttonOpts, 'select_hl', 'PmenuSel')
    this.OnKey = get(opts, 'on_key', null)
    this.selected = max([0, min([len(this.buttons) - 1, get(buttonOpts, 'selected', 0)])])
  enddef

  # -------------------------- public API --------------------------------

  def Show(): number
    this.BuildLayout()

    if !has_key(this.popupOpts, 'line') && !has_key(this.popupOpts, 'pos')
      this.popupOpts.line = (&lines - len(this.lines)) / 2
    endif
    if !has_key(this.popupOpts, 'col') && !has_key(this.popupOpts, 'pos')
      var maxWidth: number = 0
      for l in this.lines
        maxWidth = max([maxWidth, strdisplaywidth(l)])
      endfor
      this.popupOpts.col = (&columns - maxWidth) / 2
    endif
    if !has_key(this.popupOpts, 'border')
      this.popupOpts.border = []
    endif
    if !has_key(this.popupOpts, 'padding')
      this.popupOpts.padding = [0, 1, 0, 1]
    endif
    if !has_key(this.popupOpts, 'maxheight')
      # Leaves room for the tabline/statusline/command line - Vim shows a
      # scrollbar automatically once content exceeds this (it renders in
      # the right-hand padding column reserved above, so it doesn't eat
      # into card text). Reaching it while a button is selected still
      # needs explicit handling below, though - see EnsureVisible().
      this.popupOpts.maxheight = max([3, &lines - 6])
    endif
    if !has_key(this.popupOpts, 'mapping')
      # Default 'mapping' is TRUE, meaning keys typed while this popup has
      # focus are first run through the user's own :map'd bindings before
      # ever reaching our filter. Two problems follow from that: (1) a
      # personal mapping on <Left> (very common - e.g. disabling arrow
      # keys, or binding <Left>/<Right> to window/buffer navigation)
      # intercepts the key outright, so our filter never sees it at all;
      # and (2) even when nothing is mapped, Vim still has to wait up to
      # 'timeoutlen' (1000ms by default) to see whether a longer mapped
      # sequence is coming, which is the real source of the sluggishness.
      # Since this popup implements its own complete key handling, we
      # don't want any of that: take the keys raw.
      this.popupOpts.mapping = false
    endif

    # bound-method funcrefs: Vim resolves `this` when these are invoked
    # later by the popup, so Filter/HandleClose keep full access to the
    # object's state.
    this.popupOpts.filter = this.Filter
    this.popupOpts.callback = this.HandleClose

    this.id = popup_create(this.lines, this.popupOpts)

    # Each button gets its own always-on highlight match (normalHl, or
    # selectHl for the initially-selected one). See AddMatch() for why
    # matchaddpos() is used here instead of text properties.
    this.matchIds = []
    for pos in this.positions
      var hl: string = pos.idx == this.selected ? this.selectHl : this.normalHl
      this.matchIds->add(this.AddMatch(pos, hl))
    endfor

    return this.id
  enddef

  # -------------------------- internals ---------------------------------

  # A label with no "\n" renders exactly as before: single line, sized to
  # its own '[ label ]' text (or opts.button.width, whichever is wider).
  # A label containing "\n" renders as a bordered box instead - each line
  # left-aligned and padded to the widest line (or opts.button.width).
  # Returns {lines: list<string>, width: number} - every line in `lines`
  # has the same display width, so callers never need to pad further.
  def RenderButton(button: Button): dict<any>
    var cellLines: list<string> = split(button.label, "\n", true)

    if len(cellLines) == 1
      var text: string = '[ ' .. cellLines[0] .. ' ]'
      var natural: number = strdisplaywidth(text)
      var width: number = this.buttonWidth > 0 ? max([this.buttonWidth, natural]) : natural
      var padTotal: number = width - natural
      var padLeft: number = padTotal / 2
      var padRight: number = padTotal - padLeft
      return {lines: [repeat(' ', padLeft) .. text .. repeat(' ', padRight)], width: width}
    endif

    var contentWidth: number = this.buttonWidth
    for l in cellLines
      contentWidth = max([contentWidth, strdisplaywidth(l)])
    endfor

    var chars: list<string> = BoxChars()
    var boxLines: list<string> = [chars[0] .. repeat(chars[4], contentWidth + 2) .. chars[1]]
    for l in cellLines
      boxLines->add(chars[5] .. ' ' .. l .. repeat(' ', contentWidth - strdisplaywidth(l))
        .. ' ' .. chars[5])
    endfor
    boxLines->add(chars[2] .. repeat(chars[4], contentWidth + 2) .. chars[3])

    return {lines: boxLines, width: contentWidth + 4}
  enddef

  def BuildLayout(): void
    var newLines: list<string> = []
    var newPositions: list<dict<any>> = []
    var idx: number = 0
    var buttonCount: number = len(this.buttons)
    var rowCount: number = (buttonCount + this.columns - 1) / this.columns
    var curLine: number = 1

    for r in range(rowCount)
      # Render every button in this row first, so rowHeight (the tallest
      # of them) is known before any of their lines are assembled -
      # shorter buttons in the same row get blank-padded to match.
      var rendered: list<dict<any>> = []
      for c in range(this.columns)
        if idx + c >= buttonCount
          break
        endif
        rendered->add(this.RenderButton(this.buttons[idx + c]))
      endfor
      var rowHeight: number = 1
      for rb in rendered
        rowHeight = max([rowHeight, len(rb.lines)])
      endfor

      var colCursor: number = 1
      for i in range(len(rendered))
        var rb: dict<any> = rendered[i]
        var spans: list<list<number>> = []
        for subLine in range(len(rb.lines))
          spans->add([curLine + subLine, colCursor, rb.width])
        endfor
        newPositions->add({idx: idx + i, spans: spans})
        colCursor += rb.width + this.spacing
      endfor

      for subLine in range(rowHeight)
        var parts: list<string> = []
        for rb in rendered
          parts->add(subLine < len(rb.lines) ? rb.lines[subLine] : repeat(' ', rb.width))
        endfor
        newLines->add(join(parts, repeat(' ', this.spacing)))
      endfor
      curLine += rowHeight
      idx += len(rendered)

      if r < rowCount - 1
        for i in range(this.rowSpacing)
          newLines->add('')
          curLine += 1
        endfor
      endif
    endfor

    this.lines = newLines
    this.positions = newPositions
  enddef

  # Adds a highlight match for one button inside the popup window and
  # returns its match-id, so it can be individually removed later.
  #
  # This uses matchaddpos() (via win_execute(), since matchaddpos() always
  # targets the *current* window and a popup can't be made current without
  # closing it) rather than text properties (prop_add()). Text properties
  # turned out to be unreliable for this: with several separate highlighted
  # spans sharing one popup screen line, only the first span's colors were
  # actually composited into the popup's rendered surface - every span
  # after it fell back to a generic "this is a difference" attribute
  # (bold) instead of applying normalHl/selectHl. matchaddpos() has none
  # of that limitation: each match is composited independently regardless
  # of how many others share the line, and (unlike the prop_add() version)
  # its highlight is picked up by the very next `redraw` reliably, with no
  # stale-by-one-keystroke lag. matchaddpos() also accepts several [line,
  # col, length] triples in one call, which is what lets a multi-line
  # card's whole box - border and all - be one single match/one match-id,
  # the same as a single-line button's one span always was.
  def AddMatch(pos: dict<any>, hlGroup: string): number
    var output: string = win_execute(this.id,
      $'echo matchaddpos("{hlGroup}", {string(pos.spans)})')
    return str2nr(trim(output))
  enddef

  # Scrolls the popup, if needed, so `targetLine` (the top line of a
  # button's own spans) is visible - needed because this class's own key
  # handling means Vim's usual "moving the cursor scrolls the view"
  # popup behavior never gets a chance to run for keyboard navigation.
  def EnsureVisible(targetLine: number): void
    var topLine: number = str2nr(trim(win_execute(this.id, 'echo line("w0")')))
    var botLine: number = str2nr(trim(win_execute(this.id, 'echo line("w$")')))
    if targetLine < topLine
      win_execute(this.id, $'normal! {targetLine}Gzt')
    elseif targetLine > botLine
      win_execute(this.id, $'normal! {targetLine}Gzb')
    endif
  enddef

  def SetSelected(newIdx: number): void
    if newIdx == this.selected
      return
    endif

    matchdelete(this.matchIds[this.selected], this.id)
    this.matchIds[this.selected] =
      this.AddMatch(this.positions[this.selected], this.normalHl)

    matchdelete(this.matchIds[newIdx], this.id)
    this.matchIds[newIdx] = this.AddMatch(this.positions[newIdx], this.selectHl)

    this.selected = newIdx
    this.EnsureVisible(this.positions[newIdx].spans[0][0])
    redraw
  enddef

  def Filter(id: number, key: string): bool
    if this.OnKey != null && call(this.OnKey, [id, this.selected, key])
      return true
    endif

    var total: number = len(this.buttons)

    if key == "\<CR>" || key == ' '
      popup_close(id, this.selected)
      return true
    elseif key == "\<Esc>" || key == "\<C-c>"
      popup_close(id, -1)
      return true
    elseif key == "\<Right>" || key == "\<Tab>" || key == 'l'
      this.SetSelected(
        PopupButtonMenu.NextIndex(this.selected, total, this.columns, 'right'))
      return true
    elseif key == "\<Left>" || key == "\<S-Tab>" || key == 'h'
      this.SetSelected(
        PopupButtonMenu.NextIndex(this.selected, total, this.columns, 'left'))
      return true
    elseif key == "\<Down>" || key == 'j'
      this.SetSelected(
        PopupButtonMenu.NextIndex(this.selected, total, this.columns, 'down'))
      return true
    elseif key == "\<Up>" || key == 'k'
      this.SetSelected(
        PopupButtonMenu.NextIndex(this.selected, total, this.columns, 'up'))
      return true
    elseif key == "\<ScrollWheelUp>"
      win_execute(id, 'normal! 3k')
      return true
    elseif key == "\<ScrollWheelDown>"
      win_execute(id, 'normal! 3j')
      return true
    elseif key == "\<LeftMouse>" || key == "\<LeftRelease>"
      var mousePos: dict<any> = getmousepos()
      if mousePos.winid == id
        for pos in this.positions
          for span in pos.spans
            if span[0] == mousePos.line && mousePos.column >= span[1]
                && mousePos.column <= span[1] + span[2] - 1
              popup_close(id, pos.idx)
              return true
            endif
          endfor
        endfor
        return true
      else
        popup_close(id, -1)
        return true
      endif
    endif

    return true
  enddef

  def HandleClose(id: number, result: number): void
    if result >= 0 && result < len(this.buttons)
      call(this.callback, [this.buttons[result]])
    else
      call(this.callback, [null])
    endif
  enddef

  # -------------------------- static helpers ------------------------------

  static def NextIndex(selected: number, total: number, columns: number,
      direction: string): number
    var col: number = selected % columns

    if direction == 'right'
      return (selected + 1) % total
    elseif direction == 'left'
      return (selected - 1 + total) % total
    elseif direction == 'down'
      var candidate: number = selected + columns
      return candidate < total ? candidate : col
    elseif direction == 'up'
      var candidate: number = selected - columns
      if candidate >= 0
        return candidate
      endif
      var last: number = col
      var i: number = col
      while i < total
        last = i
        i += columns
      endwhile
      return last
    endif
    return selected
  enddef
endclass
