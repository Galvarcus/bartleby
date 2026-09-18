vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# outliner.vim - a flat, indented spreadsheet-style view of one folder's
# entire subtree: Title | Label | Status | Words | Target | Keywords, one
# row per binder item. A real buffer (not a popup) since it's read more
# like a table than picked from like a menu - it takes over the window
# Binder's own <CR> would have opened a document in, the same way the
# editor itself would. Label/Status edits reuse picker.vim, the exact
# widget the Binder uses for the same job - no duplicate picker logic.
#
# gs sorts the visible rows by a column (view-only - it does not reorder
# the underlying binder/project.json; that's what Binder's own J/K are
# for). Sorting necessarily drops the tree indentation, since a sorted
# order and a parent/child grouping can't both be shown at once - picking
# "Tree Order" again restores it.
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

const BUF_NAME: string = 'Bartleby-Outliner'
const HEADERS: list<string> = ['Title', 'Label', 'Status', 'Words', 'Target', 'Keywords']
const SORT_KEYS: list<string> = ['Tree Order', 'Title', 'Label', 'Status', 'Words']
# header line + separator line, before the first data row.
const HEADER_LINES: number = 2

# One row's column values, already stringified - RenderLines() only pads.
class Row
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

def RenderLines(rows: list<Row>): list<string>
  var widths: list<number> = HEADERS->mapnew((_, h) => strdisplaywidth(h))
  for row in rows
    widths[0] = max([widths[0], strdisplaywidth(row.title)])
    widths[1] = max([widths[1], strdisplaywidth(row.label)])
    widths[2] = max([widths[2], strdisplaywidth(row.status)])
    widths[3] = max([widths[3], strdisplaywidth(row.words)])
    widths[4] = max([widths[4], strdisplaywidth(row.target)])
  endfor

  def FormatRow(title: string, label: string, status: string, words: string,
      target: string, keywords: string): string
    return Pad(title, widths[0]) .. '  ' .. Pad(label, widths[1]) .. '  '
      .. Pad(status, widths[2]) .. '  ' .. Pad(words, widths[3]) .. '  '
      .. Pad(target, widths[4]) .. '  ' .. keywords
  enddef

  var header: string = FormatRow(HEADERS[0], HEADERS[1], HEADERS[2], HEADERS[3],
    HEADERS[4], HEADERS[5])
  var lines: list<string> = [header, repeat('-', strdisplaywidth(header))]
  for row in rows
    lines->add(FormatRow(row.title, row.label, row.status, row.words, row.target,
      row.keywords))
  endfor
  return lines
enddef

def Render(project: Pj.Project, folder: BI.BinderItem): void
  var sortKey: string = get(b:, 'bartleby_outline_sort', 'Tree Order')
  var showIndent: bool = sortKey ==# 'Tree Order'

  var treeRows: list<T.Row> = FlattenFolder(folder)
  var rows: list<Row> = treeRows->mapnew((_, tr) => BuildRow(tr, project.BinderRoot(), showIndent))
  if !showIndent
    rows = SortRows(rows, sortKey)
  endif

  setlocal modifiable
  deletebufline('%', 1, '$')
  setline(1, RenderLines(rows))
  setlocal nomodifiable
  b:bartleby_outline_rows = rows
  b:bartleby_outline_project = project
  b:bartleby_outline_folder = folder
enddef

def RowContext(): dict<any>
  var rows: list<Row> = get(b:, 'bartleby_outline_rows', [])
  var idx: number = line('.') - HEADER_LINES - 1
  var row: Row = idx >= 0 && idx < len(rows) ? rows[idx] : null_object
  return {
    project: get(b:, 'bartleby_outline_project', null_object),
    folder: get(b:, 'bartleby_outline_folder', null_object),
    row: row,
  }
enddef

def OpenUnderCursor(): void
  var ctx: dict<any> = RowContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var path: string = ctx.row.item.AbsPath(ctx.project.BinderRoot())
  if !filereadable(path)
    log.Error($'missing file on disk: {path}')
    return
  endif
  execute 'edit ' .. fnameescape(path)
enddef

def PickLabel(): void
  var ctx: dict<any> = RowContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var folder: BI.BinderItem = ctx.folder
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  Pk.PickOne('Label', D.LABELS, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetLabel(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project, folder)
  }, currentMeta.label)
enddef

def PickStatus(): void
  var ctx: dict<any> = RowContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var folder: BI.BinderItem = ctx.folder
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  Pk.PickOne('Status', D.STATUSES, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetStatus(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project, folder)
  }, currentMeta.status)
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

def PickSort(): void
  var ctx: dict<any> = RowContext()
  if ctx.project is null_object
    return
  endif
  var project: Pj.Project = ctx.project
  var folder: BI.BinderItem = ctx.folder
  var currentSort: string = get(b:, 'bartleby_outline_sort', 'Tree Order')
  Pk.PickOne('Sort by', SORT_KEYS, (choice: string) => {
    b:bartleby_outline_sort = choice
    Render(project, folder)
  }, currentSort)
enddef

def CloseOutliner(): void
  var prevBuf: number = get(b:, 'bartleby_outline_prevbuf', -1)
  if prevBuf != -1 && bufexists(prevBuf)
    execute 'buffer ' .. prevBuf
  endif
enddef

def SetupKeymaps(): void
  nnoremap <buffer> <silent> <CR> <ScriptCmd>OpenUnderCursor()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>CloseOutliner()<CR>
  nnoremap <buffer> <silent> l <ScriptCmd>PickLabel()<CR>
  nnoremap <buffer> <silent> s <ScriptCmd>PickStatus()<CR>
  nnoremap <buffer> <silent> gs <ScriptCmd>PickSort()<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowHelp()<CR>
enddef

# Takes over the editor window with an outliner of `folder`'s subtree -
# the same window the editor itself would open a document into, not a
# new split.
export def Show(project: Pj.Project, folder: BI.BinderItem): void
  var existingWinNr: number = bufwinnr(BUF_NAME)
  if existingWinNr != -1
    execute ':' .. existingWinNr .. 'wincmd w'
  else
    W.GoToEditorWindow()
  endif
  var prevBuf: number = bufnr('%')
  var bufNr: number = bufnr(BUF_NAME)
  if bufNr == -1
    execute 'edit ' .. BUF_NAME
  else
    execute 'buffer ' .. bufNr
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal nowrap nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-outline
  if !exists('b:bartleby_outline_prevbuf')
    b:bartleby_outline_prevbuf = prevBuf
  endif
  Render(project, folder)
  SetupKeymaps()
enddef
