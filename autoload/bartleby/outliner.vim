vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# outliner.vim: a flat, indented table of the whole subtree of one
# folder, one row per binder item, with the columns Title, Label, Status,
# Words, Target, and Keywords.
#
# A popup, not a buffer. An earlier version used a real buffer, which took
# the window that opens documents and caused many window bugs: the
# Outliner and a document competed for the same editor window. A popup
# takes no window, so there is nothing to compete for. The grid of
# buttonspopup.vim does not fit: its columns are equal buttons, not named
# table columns of different types, so the Outliner has its own popup.
#
# gs sorts the rows by a column. This changes only the view, not the
# binder or project.json: J and K in the Binder change the order. A sorted
# view cannot show the tree, so it has no indent. Tree Order restores it.
#
# l, s, and gs use PickOne from picker.vim, as the Binder does. The picker
# opens above this popup, with a higher zindex. This popup stays open and
# updates when the picker closes.
#
# Row is defined before the functions that use it because several of
# them name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined. A class used only inside a
# function body can come later.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/picker.vim' as Pk
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/helppopup.vim' as H
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const HEADERS: list<string> = ['Title', 'Label', 'Status', 'Words', 'Target', 'Keywords']
const SORT_KEYS: list<string> = ['Tree Order', 'Title', 'Label', 'Status', 'Words']
const MAX_VISIBLE_ROWS: number = 20
const OUTLINER_ZINDEX: number = 250

# CLASS: The column values of one row, already strings. FormatRow only
# pads them.
export class Row
  var item: BI.BinderItem
  var title: string
  var label: string
  var status: string
  var words: string
  var target: string
  var keywords: string
endclass

def FlattenFolder(folder: BI.BinderItem): list<T.Row>
  var rows: list<T.Row> = []
  def Walk(items: list<BI.BinderItem>, depth: number): void
    for item in items
      rows->add(T.Row.new(item, depth, null_object))
      if item.IsFolder()
        Walk(item.children, depth + 1)
      endif
    endfor
  enddef
  Walk(folder.children, 0)
  return rows
enddef

def BuildRow(treeRow: T.Row, binderRoot: string, showIndent: bool): Row
  var titleText: string = showIndent
    ? repeat('  ', treeRow.depth) .. treeRow.item.title
    : treeRow.item.title
  var words: string = string(treeRow.item.WordCount(binderRoot))

  if !treeRow.item.IsDocument()
    return Row.new(treeRow.item, titleText, '-', '-', words, '-', '')
  endif

  var meta: D.DocMeta = treeRow.item.LoadMeta(binderRoot)
  var target: string = meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : '-'
  return Row.new(treeRow.item, titleText, meta.label, meta.status, words, target,
    join(meta.keywords, ', '))
enddef

def SortRows(rows: list<Row>, key: string): list<Row>
  var sorted: list<Row> = copy(rows)
  if key ==# 'Title'
    sorted->sort((a, b) => a.title ==# b.title ? 0 : (a.title ># b.title ? 1 : -1))
  elseif key ==# 'Label'
    sorted->sort((a, b) => a.label ==# b.label ? 0 : (a.label ># b.label ? 1 : -1))
  elseif key ==# 'Status'
    sorted->sort((a, b) => a.status ==# b.status ? 0 : (a.status ># b.status ? 1 : -1))
  elseif key ==# 'Words'
    sorted->sort((a, b) => str2nr(a.words) - str2nr(b.words))
  endif
  return sorted
enddef

def Pad(text: string, width: number): string
  return text .. repeat(' ', max([0, width - strdisplaywidth(text)]))
enddef

def ColumnWidths(rows: list<Row>): list<number>
  var widths: list<number> = HEADERS->mapnew((_, h) => strdisplaywidth(h))
  for row in rows
    widths[0] = max([widths[0], strdisplaywidth(row.title)])
    widths[1] = max([widths[1], strdisplaywidth(row.label)])
    widths[2] = max([widths[2], strdisplaywidth(row.status)])
    widths[3] = max([widths[3], strdisplaywidth(row.words)])
    widths[4] = max([widths[4], strdisplaywidth(row.target)])
  endfor
  return widths
enddef

def FormatRow(widths: list<number>, title: string, label: string, status: string,
    words: string, target: string, keywords: string): string
  return Pad(title, widths[0]) .. '  ' .. Pad(label, widths[1]) .. '  '
    .. Pad(status, widths[2]) .. '  ' .. Pad(words, widths[3]) .. '  '
    .. Pad(target, widths[4]) .. '  ' .. keywords
enddef

class OutlinerPopup
  var project: Pj.Project
  var folder: BI.BinderItem
  var sortKey: string = 'Tree Order'
  var rows: list<Row> = []
  var widths: list<number> = []
  var selectedIdx: number = 0
  var scrollOffset: number = 0
  var winid: number = -1
  var bufnr: number = -1
  var pendingG: bool = false

  def new(this.project, this.folder)
  enddef

  def Rebuild(): void
    var showIndent: bool = this.sortKey ==# 'Tree Order'
    var treeRows: list<T.Row> = FlattenFolder(this.folder)
    var built: list<Row> = treeRows->mapnew(
      (_, tr) => BuildRow(tr, this.project.BinderRoot(), showIndent))
    this.rows = showIndent ? built : SortRows(built, this.sortKey)
    this.widths = ColumnWidths(this.rows)
    this.selectedIdx = min([this.selectedIdx, max([0, len(this.rows) - 1])])
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('OutlinerHeader'))
      prop_type_add('OutlinerHeader', {highlight: 'Title'})
    endif
    if empty(prop_type_get('OutlinerSelected'))
      prop_type_add('OutlinerSelected', {highlight: 'PmenuSel'})
    endif
  enddef

  def Open(): void
    this.Rebuild()
    this.EnsurePropTypes()

    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    var width: number = max([WidthsSum(this.widths) + 10, 30])
    var height: number = min([max([len(this.rows), 1]), MAX_VISIBLE_ROWS]) + 2

    this.winid = popup_create(this.bufnr, {
      title: $' Outliner: {this.folder.title} ',
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      zindex: OUTLINER_ZINDEX,
      mapping: false,
      filter: (id, key) => this.Filter(id, key),
    })
    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid)
    endif
  enddef

  def VisibleSlice(): list<number>
    var visibleRows: number = MAX_VISIBLE_ROWS
    if this.selectedIdx < this.scrollOffset
      this.scrollOffset = this.selectedIdx
    elseif this.selectedIdx >= this.scrollOffset + visibleRows
      this.scrollOffset = this.selectedIdx - visibleRows + 1
    endif
    var last: number = min([len(this.rows), this.scrollOffset + visibleRows])
    return [this.scrollOffset, last]
  enddef

  def Render(): void
    if this.bufnr == -1
      return
    endif
    var header: string = FormatRow(this.widths, HEADERS[0], HEADERS[1], HEADERS[2],
      HEADERS[3], HEADERS[4], HEADERS[5])
    var lines: list<string> = [header, repeat('-', strdisplaywidth(header))]

    var [first: number, last: number] = this.VisibleSlice()
    for i in range(first, last - 1)
      var row: Row = this.rows[i]
      lines->add(FormatRow(this.widths, row.title, row.label, row.status, row.words,
        row.target, row.keywords))
    endfor
    if empty(this.rows)
      lines->add('(empty)')
    endif

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    prop_remove({type: 'OutlinerHeader', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'OutlinerSelected', bufnr: this.bufnr}, 1, len(lines))
    prop_add(1, 1, {type: 'OutlinerHeader', bufnr: this.bufnr, length: strlen(header)})
    if !empty(this.rows)
      var selLnum: number = 3 + (this.selectedIdx - first)
      prop_add(selLnum, 1, {
        type: 'OutlinerSelected', bufnr: this.bufnr, length: strlen(lines[selLnum - 1]),
      })
    endif
  enddef

  def SelectedRow(): Row
    return empty(this.rows) ? null_object : this.rows[this.selectedIdx]
  enddef

  def OpenSelectedDoc(): void
    var row: Row = this.SelectedRow()
    if row is null_object || !row.item.IsDocument()
      return
    endif
    var path: string = row.item.AbsPath(this.project.BinderRoot())
    if !filereadable(path)
      log.Error($'missing file on disk: {path}')
      return
    endif
    this.Close()
    W.GoToEditorWindow()
    execute 'edit ' .. fnameescape(path)
  enddef

  def PickLabel(): void
    var row: Row = this.SelectedRow()
    if row is null_object || !row.item.IsDocument()
      return
    endif
    var item: BI.BinderItem = row.item
    var currentMeta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
    Pk.PickOne('Label', D.LABELS, (choice: string) => {
      var meta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
      meta.SetLabel(choice)
      meta.Save(item.MetaPath(this.project.BinderRoot()))
      this.Rebuild()
      this.Render()
    }, currentMeta.label)
  enddef

  def PickStatus(): void
    var row: Row = this.SelectedRow()
    if row is null_object || !row.item.IsDocument()
      return
    endif
    var item: BI.BinderItem = row.item
    var currentMeta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
    Pk.PickOne('Status', D.STATUSES, (choice: string) => {
      var meta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
      meta.SetStatus(choice)
      meta.Save(item.MetaPath(this.project.BinderRoot()))
      this.Rebuild()
      this.Render()
    }, currentMeta.status)
  enddef

  def PickSort(): void
    Pk.PickOne('Sort by', SORT_KEYS, (choice: string) => {
      this.sortKey = choice
      this.Rebuild()
      this.Render()
    }, this.sortKey)
  enddef

  def ShowHelp(): void
    H.Show('Outliner', [
      ['<CR>', 'Open document under cursor'],
      ['l', 'Set label'],
      ['s', 'Set status'],
      ['gs', 'Sort'],
      ['q', 'Close Outliner'],
      ['?', 'This help'],
    ])
  enddef

  def Filter(winid: number, key: string): bool
    if this.pendingG
      this.pendingG = false
      if key ==# 's'
        this.PickSort()
      endif
      return true
    endif

    if key ==# 'j' || key ==# "\<Down>"
      this.selectedIdx = min([max([len(this.rows) - 1, 0]), this.selectedIdx + 1])
      this.Render()
    elseif key ==# 'k' || key ==# "\<Up>"
      this.selectedIdx = max([0, this.selectedIdx - 1])
      this.Render()
    elseif key ==# "\<CR>"
      this.OpenSelectedDoc()
    elseif key ==# 'l'
      this.PickLabel()
    elseif key ==# 's'
      this.PickStatus()
    elseif key ==# 'g'
      this.pendingG = true
    elseif key ==# '?'
      this.ShowHelp()
    elseif key ==# 'q' || key ==# "\<Esc>"
      this.Close()
    endif
    return true
  enddef
endclass

def WidthsSum(widths: list<number>): number
  var total: number = 0
  for w in widths
    total += w
  endfor
  return total + (len(widths) - 1) * 2
enddef

export def Show(project: Pj.Project, folder: BI.BinderItem): void
  var popup: OutlinerPopup = OutlinerPopup.new(project, folder)
  popup.Open()
enddef
