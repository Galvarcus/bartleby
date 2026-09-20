vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

# Plugin_Name: Bartleby
# License: GNU GPL 3.0
# ============================================================================
# menu.vim — generic, reusable TUI/GUI menu widget (Vim 9.2 classes)
#
# Design
# ------
# Two complementary, opt-in ways to present the same item tree:
#
#   1. Popup mode (the default, and the one the hotkey toggles):
#      rendered with Vim's own popup engine (popup_create()).
#      - In the GUI, the root is a titled, bordered popup positioned via
#        `pos` (cursor/center/coords), same as any submenu.
#      - In the terminal, the root instead renders as a full-width,
#        borderless, titleless menu bar along the top of the screen
#        (Midnight-Commander style). Selecting a bar item opens a
#        bordered, titleless dropdown one row below it, with its content
#        left-aligned under that item's label. Every level below the top
#        one — in both GUI and terminal — is a bordered, titleless popup
#        cascading to the right of its parent, as before.
#      This is what SetupToggle() wires a hotkey to.
#
#   2. Native mode (opt-in, via RegisterAsVimMenu()):
#      builds real :amenu entries from the same item tree, so the menu
#      also shows up in gVim's menu bar / can be run with :emenu. This is
#      independent of the popup and purely additive.
#
# Selection highlighting uses matchaddpos() via win_execute() rather than
# text-properties — text-properties only compose correctly for the first
# highlighted span per screen line in a multi-column/multi-match popup,
# which was a hard-won lesson from an earlier widget (popupbuttons.vim).
# ============================================================================

var menus: dict<any> = {}          # name -> Menu instance, for hotkey dispatch
var itemRegistry: dict<any> = {}   # id -> MenuItem, for native :amenu dispatch
var idSeed: number = 0

# Dispatch target for <ScriptCmd> mappings created by SetupToggle().
export def MenuToggle(name: string)
  if menus->has_key(name)
    menus[name].Toggle()
  endif
enddef

# Dispatch target for <ScriptCmd> entries created by RegisterAsVimMenu().
export def MenuInvoke(id: string)
  if itemRegistry->has_key(id)
    var it = itemRegistry[id]
    if it.Action != null_function
      it.Action(it)
    endif
  endif
enddef

# ----------------------------------------------------------------------------
export class MenuItem
  public var label: string
  public var Action: func = null_function     # func(item: MenuItem)
  public var data: any = v:none
  public var enabled: bool = true
  public var separator: bool = false
  public var items: list<any> = []            # child MenuItems (non-empty = submenu)

  def new(this.label, Action: func = null_function, data: any = v:none)
    this.Action = Action
    this.data = data
  enddef

  def IsSubmenu(): bool
    return len(this.items) > 0
  enddef

  def AddItem(label: string, Action: func = null_function, data: any = v:none): MenuItem
    var item = MenuItem.new(label, Action, data)
    this.items->add(item)
    return item
  enddef

  def AddSeparator()
    var sep = MenuItem.new('-')
    sep.separator = true
    this.items->add(sep)
  enddef
endclass

# ----------------------------------------------------------------------------
export class Menu
  # identity
  var name: string
  var title: string

  # content
  var items: list<any> = []

  # appearance — override any of these before opening
  public var normal_hl: string = 'Pmenu'
  public var select_hl: string = 'PmenuSel'
  public var disabled_hl: string = 'Comment'
  public var border: list<number> = [1, 1, 1, 1]
  public var padding: list<number> = [0, 1, 0, 1]
  public var minwidth: number = 14
  public var submenu_marker: string = ' >'
  public var pos: any = 'cursor'              # 'cursor' | 'center' | [line, col]

  # behaviour
  public var close_on_select: bool = true
  public var wrap_navigation: bool = true

  # internal state — do not set directly
  var _stack: list<number> = []           # popup ids, root..deepest
  var _itemsOf: dict<any> = {}            # winid -> items list shown there
  var _cur: dict<number> = {}             # winid -> selected index
  var _selMatch: dict<number> = {}        # winid -> matchid of selection hl
  var _isBar: dict<bool> = {}             # winid -> true if rendered as a menu bar
  var _barCols: dict<any> = {}            # winid -> list<number>, start col per item

  def new(this.name, title: string = '')
    this.title = title == '' ? this.name : title
    menus[this.name] = this
  enddef

  # ---------------- building ----------------

  def AddItem(label: string, Action: func = null_function, data: any = v:none): MenuItem
    var item = MenuItem.new(label, Action, data)
    this.items->add(item)
    return item
  enddef

  def AddSeparator()
    var sep = MenuItem.new('-')
    sep.separator = true
    this.items->add(sep)
  enddef

  # ---------------- hotkey ----------------

  # Map {lhs} in {mode} to toggle this menu open/closed.
  def SetupToggle(lhs: string, mode: string = 'n')
    execute $'{mode}noremap <silent> {lhs} <ScriptCmd>call MenuToggle("{this.name}")<CR>'
  enddef

  def IsOpen(): bool
    return len(this._stack) > 0 && !empty(popup_getpos(this._stack[0]))
  enddef

  def Toggle()
    if this.IsOpen()
      this.Close()
    else
      this.Open()
    endif
  enddef

  def Open()
    if this.IsOpen()
      return
    endif
    this._stack = []
    if has('gui_running')
      this._ShowLevel(this.items, -1, 0)
    else
      this._ShowBar()
    endif
  enddef

  def Close()
    # close deepest-first
    for id in reverse(copy(this._stack))
      if !empty(popup_getpos(id))
        popup_close(id)   # triggers callback -> _OnClose() cleans up state
      endif
    endfor
    this._stack = []
  enddef

  # ---------------- rendering ----------------

  def _Lines(items: list<any>): list<string>
    var w = this.minwidth
    for it in items
      w = max([w, strdisplaywidth(it.label) + (it.IsSubmenu() ? strlen(this.submenu_marker) : 0)])
    endfor
    var lines: list<string> = []
    for it in items
      if it.separator
        lines->add(repeat('-', w))
      else
        var suffix = it.IsSubmenu() ? this.submenu_marker : ''
        var pad = w - strdisplaywidth(it.label) - strdisplaywidth(suffix)
        lines->add(it.label .. repeat(' ', max([pad, 1])) .. suffix)
      endif
    endfor
    return lines
  enddef

  # Lay out the top-level items on one line, Midnight-Commander-bar style.
  # Returns the padded line plus each item's 1-based start column (so the
  # dropdown opened from an item can align its content to that column).
  # Separators are not supported on the bar; they get column -1.
  def _BarLine(items: list<any>): dict<any>
    var cols: list<number> = []
    var line = ' '
    var pos = 2
    for it in items
      if it.separator
        cols->add(-1)
        continue
      endif
      cols->add(pos)
      line ..= it.label .. '   '
      pos += strdisplaywidth(it.label) + 3
    endfor
    var width = &columns
    if strdisplaywidth(line) < width
      line ..= repeat(' ', width - strdisplaywidth(line))
    endif
    return {line: line, cols: cols}
  enddef

  # Terminal-Vim root: a full-width, borderless, titleless bar at the top
  # of the screen. GUI root uses _ShowLevel() instead — see Open().
  def _ShowBar()
    var items = this.items
    var built = this._BarLine(items)
    var winid = popup_create(built.line, {
      line: 1,
      col: 1,
      border: [0, 0, 0, 0],
      padding: [0, 0, 0, 0],
      highlight: this.normal_hl,
      wrap: false,
      mapping: false,
      zindex: 200,
      filter: (winid: number, key: string): bool => this._Filter(winid, key),
      callback: (winid: number, _result: any) => this._OnClose(winid),
    })
    this._stack->add(winid)
    this._itemsOf[winid] = items
    this._barCols[winid] = built.cols
    this._isBar[winid] = true
    this._cur[winid] = this._NextSelectable(items, -1, 1)
    this._Highlight(winid)
  enddef

  def _PosOpts(parentId: number, parentIdx: number): dict<any>
    if parentId != -1
      var pp = popup_getpos(parentId)
      var offset = (this.border[0] ? 1 : 0) + (this.title != '' ? 1 : 0)
      return {line: pp.line + offset + parentIdx, col: pp.col + pp.width}
    endif
    if type(this.pos) == v:t_list
      return {line: this.pos[0], col: this.pos[1]}
    elseif this.pos == 'center'
      return {pos: 'center'}
    else
      return {line: 'cursor+1', col: 'cursor'}
    endif
  enddef

  def _ShowLevel(items: list<any>, parentId: number, parentIdx: number, posOverride: dict<any> = {})
    var isRoot = parentId == -1 && empty(posOverride)
    var opts = empty(posOverride) ? this._PosOpts(parentId, parentIdx) : copy(posOverride)
    opts->extend({
      title: isRoot ? this.title : '',
      border: this.border,
      padding: this.padding,
      highlight: this.normal_hl,
      wrap: false,
      mapping: false,
      zindex: 200 + len(this._stack),
      filter: (winid: number, key: string): bool => this._Filter(winid, key),
      callback: (winid: number, _result: any) => this._OnClose(winid),
    })
    var winid = popup_create(this._Lines(items), opts)
    this._stack->add(winid)
    this._itemsOf[winid] = items
    this._cur[winid] = this._NextSelectable(items, -1, 1)
    this._Highlight(winid)
  enddef

  # ---------------- selection / highlighting ----------------

  def _NextSelectable(items: list<any>, from: number, dir: number): number
    var n = len(items)
    if n == 0
      return -1
    endif
    var idx = from
    for _ in range(n)
      idx += dir
      if this.wrap_navigation
        idx = (idx + n) % n
      elseif idx < 0 || idx >= n
        return from
      endif
      if !items[idx].separator
        return idx
      endif
    endfor
    return from
  enddef

  def _Highlight(winid: number)
    if this._selMatch->has_key(winid)
      win_execute(winid, $'silent! call matchdelete({this._selMatch[winid]})')
    endif
    var idx = get(this._cur, winid, -1)
    if idx == -1
      return
    endif
    var items = this._itemsOf[winid]
    var hl = items[idx].enabled ? this.select_hl : this.disabled_hl
    if get(this._isBar, winid, false)
      var col = this._barCols[winid][idx]
      var len = strdisplaywidth(items[idx].label)
      win_execute(winid, $'g:__menu_mid = matchaddpos("{hl}", [[1, {col}, {len}]])')
    else
      win_execute(winid, $'g:__menu_mid = matchaddpos("{hl}", [{idx + 1}])')
    endif
    this._selMatch[winid] = g:__menu_mid
    unlet g:__menu_mid
  enddef

  # ---------------- input handling ----------------

  def _Filter(winid: number, key: string): bool
    var items = this._itemsOf[winid]
    var idx = get(this._cur, winid, -1)
    if get(this._isBar, winid, false)
      if key == 'h' || key == "\<Left>"
        this._cur[winid] = this._NextSelectable(items, idx, -1)
        this._Highlight(winid)
        return true
      elseif key == 'l' || key == "\<Right>"
        this._cur[winid] = this._NextSelectable(items, idx, 1)
        this._Highlight(winid)
        return true
      elseif key == 'j' || key == "\<Down>" || key == "\<CR>" || key == ' '
        this._ActivateBar(winid, items, idx)
        return true
      elseif key == "\<Esc>" || key == 'q'
        this.Close()
        return true
      endif
      return false
    endif
    if key == 'j' || key == "\<Down>"
      this._cur[winid] = this._NextSelectable(items, idx, 1)
      this._Highlight(winid)
      return true
    elseif key == 'k' || key == "\<Up>"
      this._cur[winid] = this._NextSelectable(items, idx, -1)
      this._Highlight(winid)
      return true
    elseif key == "\<CR>" || key == 'l' || key == "\<Right>" || key == ' '
      this._Activate(winid, items, idx)
      return true
    elseif key == 'h' || key == "\<Left>"
      this._Back(winid)
      return true
    elseif key == "\<Esc>" || key == 'q'
      this.Close()
      return true
    endif
    return false
  enddef

  def _Activate(winid: number, items: list<any>, idx: number)
    if idx < 0 || idx >= len(items)
      return
    endif
    var item = items[idx]
    if item.separator || !item.enabled
      return
    endif
    if item.IsSubmenu()
      this._ShowLevel(item.items, winid, idx)
    else
      if this.close_on_select
        this.Close()
      endif
      if item.Action != null_function
        item.Action(item)
      endif
    endif
  enddef

  def _ActivateBar(winid: number, items: list<any>, idx: number)
    if idx < 0 || idx >= len(items)
      return
    endif
    var item = items[idx]
    if item.separator || !item.enabled
      return
    endif
    if item.IsSubmenu()
      var col = this._barCols[winid][idx]
      var leftInset = (this.border[3] ? 1 : 0) + this.padding[3]
      this._ShowLevel(item.items, -1, 0, {line: 2, col: max([col - leftInset, 1])})
    else
      if this.close_on_select
        this.Close()
      endif
      if item.Action != null_function
        item.Action(item)
      endif
    endif
  enddef

  def _Back(winid: number)
    if len(this._stack) <= 1
      this.Close()
      return
    endif
    if this._stack[-1] == winid
      popup_close(winid)
    endif
  enddef

  def _OnClose(winid: number)
    var i = index(this._stack, winid)
    if i != -1
      this._stack = this._stack[0 : i - 1]
    endif
    this._itemsOf->remove(winid)
    this._cur->remove(winid)
    this._selMatch->remove(winid)
    if this._isBar->has_key(winid)
      this._isBar->remove(winid)
    endif
    if this._barCols->has_key(winid)
      this._barCols->remove(winid)
    endif
  enddef

  # ---------------- optional: native GUI/terminal menu (:emenu) ----------------

  # Additionally builds real :amenu entries from this.items, so the same
  # menu also appears in gVim's menu bar and can be invoked with :emenu.
  # Independent of the popup — does not affect Toggle()/Open()/Close().
  def RegisterAsVimMenu(root: string = '', priority: string = '')
    var r = root == '' ? this.title : root
    this._BuildVimMenu(r, this.items, priority)
  enddef

  def UnregisterVimMenu(root: string = '')
    var r = root == '' ? this.title : root
    execute $'silent! aunmenu {r}'
  enddef

  def _BuildVimMenu(path: string, items: list<any>, priority: string)
    for item in items
      var mpath = $'{path}.{escape(item.label, ". \\")}'
      if item.separator
        execute $'amenu {priority} {mpath} <Nop>'
      elseif item.IsSubmenu()
        this._BuildVimMenu(mpath, item.items, priority)
      else
        idSeed += 1
        var id = $'{this.name}#{idSeed}'
        itemRegistry[id] = item
        execute $'amenu {priority} {mpath} <ScriptCmd>call MenuInvoke("{id}")<CR>'
        if !item.enabled
          execute $'amenu disable {mpath}'
        endif
      endif
    endfor
  enddef
endclass
