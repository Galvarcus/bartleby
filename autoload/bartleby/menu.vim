vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# menu.vim: a reusable menu widget for the terminal and the GUI.
# License: GNU GPL 3.0
#
# Design: one item tree, shown in two ways that can be used together.
#
#   1. Popup mode, the default, and the mode that the hotkey toggles.
#      Drawn with popup_create.
#      In the GUI, the root is a bordered popup with a title, placed by
#      pos: at the cursor, centered, or at a line and column.
#      In the terminal, the root is a menu bar across the top of the
#      screen, without border or title, like Midnight Commander. An
#      item on the bar opens a bordered dropdown one row below it,
#      aligned under the item's label.
#      In both, each deeper level is a bordered popup without a title,
#      to the right of its parent. SetupToggle maps a key to this mode.
#
#   2. Native mode, optional, through RegisterAsVimMenu. Builds :amenu
#      entries from the same tree, so the menu also appears in the gVim
#      menu bar and runs with :emenu. It does not change the popup.
#
# The selection highlight uses matchaddpos through win_execute, not text
# properties. Text properties show correct colors only for the first
# highlighted span on a line, which popupbuttons.vim showed earlier.
##############################################################################

# Menu name to Menu, for the hotkey dispatch.
var menus: dict<any> = {}
# Item id to MenuItem, for the native :amenu dispatch.
var itemRegistry: dict<any> = {}
var idSeed: number = 0

# FUNCTION: Toggle the menu with the given name. The target of the ScriptCmd
# mappings that SetupToggle creates.
export def MenuToggle(name: string)
  if menus->has_key(name)
    menus[name].Toggle()
  endif
enddef

# FUNCTION: Run the item with the given id. The target of the ScriptCmd
# entries that RegisterAsVimMenu creates.
export def MenuInvoke(id: string)
  if itemRegistry->has_key(id)
    var it = itemRegistry[id]
    if it.Action != null_function
      it.Action(it)
    endif
  endif
enddef

# CLASS: One menu entry: a label with an action, or a submenu.
export class MenuItem
  public var label: string
  # Called as Action(item) with this MenuItem.
  public var Action: func = null_function
  public var data: any = v:none
  public var enabled: bool = true
  public var separator: bool = false
  # Child MenuItems. A nonempty list makes this entry a submenu.
  public var items: list<any> = []

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

# CLASS: A menu of MenuItems, shown as popups or as a native menu.
export class Menu
  # Identity.
  var name: string
  var title: string

  # Content.
  var items: list<any> = []

  # Appearance. Change any of these before the menu opens.
  public var normal_hl: string = 'Pmenu'
  public var select_hl: string = 'PmenuSel'
  public var disabled_hl: string = 'Comment'
  public var border: list<number> = [1, 1, 1, 1]
  public var padding: list<number> = [0, 1, 0, 1]
  public var minwidth: number = 14
  public var submenu_marker: string = ' >'
  # One of cursor, center, or a list of line and column.
  public var pos: any = 'cursor'

  # Behavior.
  public var close_on_select: bool = true
  public var wrap_navigation: bool = true

  # Internal state. Do not set these directly.
  # Popup ids, from the root to the deepest level.
  var _stack: list<number> = []
  # Window id to the items shown in that window.
  var _itemsOf: dict<any> = {}
  # Window id to its selected index.
  var _cur: dict<number> = {}
  # Window id to the match id of its selection highlight.
  var _selMatch: dict<number> = {}
  # Window id to true when the window is a menu bar.
  var _isBar: dict<bool> = {}
  # Window id to the start column of each item on the bar.
  var _barCols: dict<any> = {}

  def new(this.name, title: string = '')
    this.title = title == '' ? this.name : title
    menus[this.name] = this
  enddef

  ############################################################################
  # SECTION: Building.
  ############################################################################

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

  ############################################################################
  # SECTION: Hotkey.
  ############################################################################

  # METHOD: Map lhs in mode to toggle this menu.
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
    # Close the deepest level first.
    for id in reverse(copy(this._stack))
      if !empty(popup_getpos(id))
        # This runs the popup callback, and _OnClose clears the state.
        popup_close(id)
      endif
    endfor
    this._stack = []
  enddef

  ############################################################################
  # SECTION: Rendering.
  ############################################################################

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

  # METHOD: Lay out the top-level items on one line, as a menu bar. Return
  # the padded line and the 1-based start column of each item, so that the
  # dropdown of an item aligns under it. The bar has no separators: a
  # separator gets column -1.
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

  # METHOD: Show the terminal root: a menu bar across the top of the screen,
  # without border or title. The GUI root uses _ShowLevel. See Open.
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

  ############################################################################
  # SECTION: Selection and highlighting.
  ############################################################################

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

  ############################################################################
  # SECTION: Input handling.
  ############################################################################

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

  ############################################################################
  # SECTION: Native menu for the GUI and :emenu, optional.
  ############################################################################

  # METHOD: Build :amenu entries from this.items, so that the menu also
  # appears in the gVim menu bar and runs with :emenu. The popup menu,
  # Toggle, Open, and Close do not change.
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
