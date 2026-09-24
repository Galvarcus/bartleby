vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# binder.vim - the Binder sidebar: renders a scrive's tree, and wires the
# keymaps that read/prompt/confirm before handing actual tree surgery off
# to mutate.vim. Every mutation follows the same shape: gather input ->
# mutate.vim call -> project.Save() -> Render().
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/mutate.vim' as M
import autoload 'bartleby/templates.vim' as Tm
import autoload 'bartleby/corkboard.vim' as C
import autoload 'bartleby/outliner.vim' as O
import autoload 'bartleby/search.vim' as Se
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/slug.vim' as Sl
import autoload 'bartleby/picker.vim' as Pk
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/session.vim' as Sess
import autoload 'bartleby/snapshot.vim' as Sn
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var binderShowRoleLabels: bool = g:bartleby_binder_show_role_labels

const BUF_NAME: string = 'Bartleby-Binder'
# The title line (project name) added by Render() before the tree
# content - every place that maps a cursor line number to a tree row
# index needs to account for this offset.
const HEADER_LINES: number = 1
const INDENT: string = '  '

def RenderLines(rows: list<T.Row>, binderRoot: string, collapsed: dict<bool>): list<string>
  return rows->mapnew((_, row) => {
    var marker: string = '· '
    if row.item.IsFolder()
      marker = get(collapsed, row.item.id, false) ? '▸ ' : '▾ '
    endif
    var suffix: string = ''
    if row.item.IsDocument()
      var meta: D.DocMeta = row.item.LoadMeta(binderRoot)
      if meta.label !=# D.LABELS[0]
        suffix = $' ({meta.label})'
      endif
    endif
    var label: string = binderShowRoleLabels ? row.item.DisplayLabel() : ''
    # A trailing "/" marks folders, for syntax/bartleby-binder.vim's
    # Directory highlight. Display only - the stored title has no "/".
    var title: string = row.item.IsFolder() ? row.item.title .. '/' : row.item.title
    return repeat(INDENT, row.depth) .. marker .. label .. title .. suffix
  })
enddef

def FindOrCreateWindow(): number
  var winNr: number = bufwinnr(BUF_NAME)
  if winNr != -1
    return winNr
  endif
  execute 'vertical topleft :30split ' .. BUF_NAME
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal nowrap nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-binder
  setlocal winfixwidth
  return bufwinnr(BUF_NAME)
enddef

# Re-flattens and redraws `project`'s tree into the current (already-active)
# Binder buffer, honoring which folders are collapsed. Assumes the Binder
# window/buffer is already current - callers switch to it first (see
# Show()). A collapsed folder's descendants are real rows that simply
# don't exist in this render (see tree.vim#Flatten), not a Vim fold hiding
# lines that are still technically "there" - collapse state persists
# across renders via the buffer-local b:bartleby_collapsed set.
def Render(project: Pj.Project): void
  var previousRows: list<T.Row> = get(b:, 'bartleby_rows', [])
  var previousLine: number = line('.')
  var previousId: string = previousLine > HEADER_LINES && previousLine <= len(previousRows) + HEADER_LINES
    ? previousRows[previousLine - 1 - HEADER_LINES].item.id : ''

  var collapsed: dict<bool> = get(b:, 'bartleby_collapsed', {})
  var rows: list<T.Row> = T.Flatten(project, collapsed)
  setlocal modifiable
  deletebufline('%', 1, '$')
  setline(1, [$'{project.name}'] + RenderLines(rows, project.BinderRoot(), collapsed))
  setlocal nomodifiable
  b:bartleby_rows = rows
  b:bartleby_project = project

  # deletebufline()/setline() otherwise leave the cursor sitting wherever
  # it lands by default (line 1) - put it back on the same item, at its
  # (possibly shifted) new line, whenever that item still exists.
  var newIdx: number = previousId ==# '' ? -1 : T.IndexOfRowById(rows, previousId)
  if newIdx >= 0
    cursor(newIdx + 1 + HEADER_LINES, 1)
  endif
enddef

# Common prologue for every cursor-driven command below: the buffer's
# project, its rows, and the row under the cursor (null_object if none -
# including when the cursor sits on the title line).
def CursorContext(): dict<any>
  var project: Pj.Project = get(b:, 'bartleby_project', null_object)
  var rows: list<T.Row> = get(b:, 'bartleby_rows', [])
  var lineNr: number = line('.')
  var row: T.Row = lineNr > HEADER_LINES && lineNr <= len(rows) + HEADER_LINES
    ? rows[lineNr - 1 - HEADER_LINES] : null_object
  return {project: project, rows: rows, row: row, lineNr: lineNr}
enddef

def OpenUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !ctx.row.item.IsDocument()
    ToggleCollapse()
    return
  endif
  var path: string = ctx.row.item.AbsPath(ctx.project.BinderRoot())
  if !filereadable(path)
    log.Error($'missing file on disk: {path}')
    return
  endif
  W.GoToEditorWindow()
  execute 'edit ' .. fnameescape(path)
enddef

def OpenCorkboard(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  var project: Pj.Project = ctx.project
  C.Show(project, ctx.row.item, (doc: BI.BinderItem) => {
    var path: string = doc.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Error($'missing file on disk: {path}')
      return
    endif
    W.GoToEditorWindow()
    execute 'edit ' .. fnameescape(path)
  })
enddef

def TakeSnapshot(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  IP.PromptText('Snapshot label (optional)', '', (label: string) => {
    Sn.Take(project, doc, label)
  })
enddef

def ShowSnapshotReadOnly(doc: BI.BinderItem, snapshot: Sn.Snapshot): void
  W.GoToEditorWindow()
  execute 'enew'
  setline(1, snapshot.lines)
  execute 'silent file ' .. fnameescape($'[Snapshot] {doc.title} - {snapshot.DisplayName()}')
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable readonly
enddef

def ViewSnapshots(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  var snapshots: list<Sn.Snapshot> = reverse(Sn.List(project, doc))
  if empty(snapshots)
    log.Info($'no snapshots for "{doc.title}"')
    return
  endif
  var names: list<string> = snapshots->mapnew((_, s) => s.DisplayName())
  Pk.PickOne('Snapshots', names, (choice: string) => {
    var snapshot: Sn.Snapshot = snapshots[index(names, choice)]
    Pk.PickOne($' {choice} ', ['Restore', 'View', 'Cancel'], (action: string) => {
      if action ==# 'Restore'
        Sn.Restore(project, doc, snapshot)
      elseif action ==# 'View'
        ShowSnapshotReadOnly(doc, snapshot)
      endif
    })
  })
enddef

def OpenOutliner(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  O.Show(ctx.project, ctx.row.item)
enddef

def RunSearch(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object
    return
  endif
  Se.Run(ctx.project)
enddef

# Appends -2, -3, ... to a relPath already taken on disk. `dirSlug` may be
# '' for a root-level document with no enclosing folder.
def UniqueRelPath(binderRoot: string, dirSlug: string, titleSlug: string, ext: string): string
  var base: string = dirSlug ==# '' ? titleSlug : dirSlug .. '/' .. titleSlug
  var relPath: string = base .. ext
  var n: number = 2
  while filereadable(binderRoot .. '/' .. relPath)
    relPath = $'{base}-{n}{ext}'
    n += 1
  endwhile
  return relPath
enddef

def AddDocument(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object
    return
  endif
  IP.PromptText('New document title', '', (title: string) => {
    FinishAddDocument(ctx, title)
  })
enddef

def FinishAddDocument(ctx: dict<any>, title: string): void
  if title ==# ''
    return
  endif
  var dirSlug: string = ''
  if ctx.row isnot null_object
    if ctx.row.item.IsFolder()
      dirSlug = Sl.Slugify(ctx.row.item.title)
    elseif ctx.row.ownerItem isnot null_object
      dirSlug = Sl.Slugify(ctx.row.ownerItem.title)
    endif
  endif
  var relPath: string = UniqueRelPath(ctx.project.BinderRoot(), dirSlug, Sl.Slugify(title), ctx.project.DocExt())
  var newItem: BI.BinderItem = BI.BinderItem.NewDocument(title, relPath)
  M.AddNear(ctx.project, ctx.row, newItem)
  Tm.Materialize([newItem], ctx.project.BinderRoot())
  ctx.project.Save()
  Render(ctx.project)
enddef

def AddFolder(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object
    return
  endif
  var options: list<string> = ['Custom']
  if ctx.project.projectType ==# Pj.TYPE_NOVEL
    options->add('Chapter')
  elseif ctx.project.projectType ==# Pj.TYPE_NOVEL_PARTS
    options->add('Part')
    var onOrInsidePart: bool = (ctx.row isnot null_object && ctx.row.item.structureRole ==# BI.ROLE_PART)
      || M.FindAncestorWithRole(ctx.rows, ctx.row, BI.ROLE_PART) isnot null_object
    if onOrInsidePart
      options->add('Chapter')
    endif
  endif
  if len(options) ==# 1
    CreateFolder(ctx, 'Custom')
  else
    Pk.PickOne('Add Folder', options, (choice: string) => {
      CreateFolder(ctx, choice)
    })
  endif
enddef

def CreateFolder(ctx: dict<any>, kind: string): void
  var promptTitle: string = kind ==# 'Custom' ? 'New folder title' : $'New {kind} title (blank for next number)'
  IP.PromptText(promptTitle, '', (title: string) => {
    FinishCreateFolder(ctx, kind, title)
  })
enddef

def FinishCreateFolder(ctx: dict<any>, kind: string, title: string): void
  if kind ==# 'Custom'
    if title ==# ''
      return
    endif
    ctx.project.AddItem(BI.BinderItem.NewFolder(title, BI.ROLE_CUSTOM))
    ctx.project.Save()
    Render(ctx.project)
    return
  endif

  if kind ==# 'Chapter'
    var container: BI.BinderItem
    if ctx.project.projectType ==# Pj.TYPE_NOVEL_PARTS
      container = (ctx.row isnot null_object && ctx.row.item.structureRole ==# BI.ROLE_PART)
        ? ctx.row.item : M.FindAncestorWithRole(ctx.rows, ctx.row, BI.ROLE_PART)
    else
      container = M.FindManuscript(ctx.project)
    endif
    if container is null_object
      log.Error('no Manuscript/Part folder found to add a chapter into')
      return
    endif
    var chapter: BI.BinderItem = M.AddChapter(container, ctx.row, title)
    Tm.Materialize([chapter], ctx.project.BinderRoot())
  else
    var manuscript: BI.BinderItem = M.FindManuscript(ctx.project)
    if manuscript is null_object
      log.Error('no Manuscript folder found to add a part into')
      return
    endif
    M.AddPart(manuscript, ctx.row, title)
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def DeleteUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  var item: BI.BinderItem = ctx.row.item

  if M.IsImmutableFolder(item)
    if item.ChildCount() == 0
      log.Info($'"{item.title}" is already empty')
      return
    endif
    var clearPrompt: string = $'Clear all contents of "{item.title}"? The folder itself will remain.'
    if confirm(clearPrompt, "&Yes\n&No", 2) != 1
      return
    endif
    M.ClearChildren(item)
    log.Info($'cleared "{item.title}" - any files on disk were left untouched')
    ctx.project.Save()
    Render(ctx.project)
    return
  endif

  var prompt: string = item.IsFolder() && item.ChildCount() > 0
    ? $'Delete "{item.title}" and everything inside it?'
    : $'Delete "{item.title}"?'
  if confirm(prompt, "&Yes\n&No", 2) != 1
    return
  endif
  M.Remove(ctx.project, ctx.row)
  log.Info('removed from binder - any files on disk were left untouched')
  ctx.project.Save()
  Render(ctx.project)
enddef

def RenameUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if M.IsImmutableFolder(ctx.row.item)
    log.Info($'"{ctx.row.item.title}" cannot be renamed')
    return
  endif
  var oldTitle: string = ctx.row.item.title
  IP.PromptText('Rename to', oldTitle, (newTitle: string) => {
    if newTitle ==# '' || newTitle ==# oldTitle
      return
    endif
    M.Rename(ctx.row, newTitle)
    ctx.project.Save()
    Render(ctx.project)
  })
enddef

def Move(delta: number): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !M.MoveWithinSiblings(ctx.project, ctx.row, delta)
    log.Info('this item cannot be reordered here')
    return
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def IndentUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !M.Indent(ctx.project, ctx.row)
    log.Info('no valid folder above to indent into')
    return
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def OutdentUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !M.Outdent(ctx.project, ctx.rows, ctx.row)
    log.Info('already at the top level, or not a valid destination for this item')
    return
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def PickLabel(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  Pk.PickOne('Label', D.LABELS, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetLabel(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, currentMeta.label)
enddef

def PickStatus(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: Pj.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  Pk.PickOne('Status', D.STATUSES, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetStatus(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, currentMeta.status)
enddef

# Flips the Chapter:/Part: label prefix on/off and re-renders. Toggles
# the setting for the whole session (script-local), not just this buffer.
def ToggleRoleLabels(): void
  binderShowRoleLabels = !binderShowRoleLabels
  var project: Pj.Project = get(b:, 'bartleby_project', null_object)
  if project isnot null_object
    Render(project)
  endif
enddef

def ShowHelp(): void
  H.Show('Binder', [
    ['<CR>', 'Open document / toggle folder'],
    ['<Tab>', 'Toggle folder collapse'],
    ['a', 'New document'],
    ['A', 'New folder (Chapter/Part when applicable)'],
    ['dd', 'Delete item under cursor'],
    ['r', 'Rename item under cursor'],
    ['J / K', 'Move item down / up'],
    ['>> / <<', 'Indent / outdent item'],
    ['l', 'Set label'],
    ['s', 'Set status'],
    ['L', 'Toggle Chapter:/Part: labels'],
    ['S', 'Take snapshot'],
    ['gS', 'View/restore snapshots'],
    ['gc', 'Open Corkboard'],
    ['go', 'Open Outliner'],
    ['/', 'Search project'],
    ['q', 'Close Binder'],
    ['?', 'This help'],
  ])
enddef

def ToggleCollapse(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  var collapsed: dict<bool> = get(b:, 'bartleby_collapsed', {})
  var id: string = ctx.row.item.id
  if get(collapsed, id, false)
    remove(collapsed, id)
  else
    collapsed[id] = true
  endif
  b:bartleby_collapsed = collapsed
  Render(ctx.project)
  Sess.CaptureBinderState()
enddef

def SetupKeymaps(): void
  nnoremap <buffer> <silent> <CR> <ScriptCmd>OpenUnderCursor()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>close<CR>
  nnoremap <buffer> <silent> <Tab> <ScriptCmd>ToggleCollapse()<CR>
  nnoremap <buffer> <silent> a <ScriptCmd>AddDocument()<CR>
  nnoremap <buffer> <silent> A <ScriptCmd>AddFolder()<CR>
  nnoremap <buffer> <silent> dd <ScriptCmd>DeleteUnderCursor()<CR>
  nnoremap <buffer> <silent> r <ScriptCmd>RenameUnderCursor()<CR>
  nnoremap <buffer> <silent> J <ScriptCmd>Move(1)<CR>
  nnoremap <buffer> <silent> K <ScriptCmd>Move(-1)<CR>
  nnoremap <buffer> <silent> >> <ScriptCmd>IndentUnderCursor()<CR>
  nnoremap <buffer> <silent> << <ScriptCmd>OutdentUnderCursor()<CR>
  nnoremap <buffer> <silent> l <ScriptCmd>PickLabel()<CR>
  nnoremap <buffer> <silent> s <ScriptCmd>PickStatus()<CR>
  nnoremap <buffer> <silent> L <ScriptCmd>ToggleRoleLabels()<CR>
  nnoremap <buffer> <silent> S <ScriptCmd>TakeSnapshot()<CR>
  nnoremap <buffer> <silent> gS <ScriptCmd>ViewSnapshots()<CR>
  nnoremap <buffer> <silent> gc <ScriptCmd>OpenCorkboard()<CR>
  nnoremap <buffer> <silent> go <ScriptCmd>OpenOutliner()<CR>
  nnoremap <buffer> <silent> / <ScriptCmd>RunSearch()<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowHelp()<CR>
enddef

# Renders `project`'s binder tree into the sidebar, creating it if needed.
export def Show(project: Pj.Project): void
  var winNr: number = FindOrCreateWindow()
  execute ':' .. winNr .. 'wincmd w'
  Render(project)
  SetupKeymaps()
enddef

export def Toggle(project: Pj.Project): void
  var winNr: number = bufwinnr(BUF_NAME)
  if winNr != -1
    execute ':' .. winNr .. 'close'
    Sess.CaptureBinderState()
    return
  endif
  Show(project)
  Sess.CaptureBinderState()
enddef

export def IsOpen(): bool
  return bufwinnr(BUF_NAME) != -1
enddef

# Session persistence reads/restores collapse state through these two -
# b:bartleby_collapsed lives on the Binder buffer itself, not something
# an outside script should reach into directly.
export def GetCollapsedIds(): list<string>
  var winNr: number = bufwinnr(BUF_NAME)
  if winNr == -1
    return []
  endif
  return keys(getbufvar(winbufnr(winNr), 'bartleby_collapsed', {}))
enddef

export def ApplyCollapsedIds(ids: list<string>): void
  var winNr: number = bufwinnr(BUF_NAME)
  if winNr == -1
    return
  endif
  var collapsed: dict<bool> = {}
  for id in ids
    collapsed[id] = true
  endfor
  setbufvar(winbufnr(winNr), 'bartleby_collapsed', collapsed)
enddef
