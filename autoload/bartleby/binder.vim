vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# binder.vim: the Binder sidebar. Draws the scrive tree and sets the keys
# that ask for input or confirmation before mutate.vim changes the tree.
# Every change follows the same steps: get the input, call mutate.vim,
# call project.Save, and call Render.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/templates.vim' as TE
import autoload 'bartleby/corkboard.vim' as CR
import autoload 'bartleby/outliner.vim' as O
import autoload 'bartleby/search.vim' as SE
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/slug.vim' as SU
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/log.vim' as L
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))
var binderShowRoleLabels: bool = g:bartleby_binder_show_role_labels

# Render draws the title line, the project name, above the tree. Every
# mapping from a cursor line to a tree row subtracts this.
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
      if meta.label !=# CO.LABELS[0]
        suffix = $' ({D.LabelName(meta.label)})'
      endif
    endif
    var label: string = binderShowRoleLabels ? row.item.DisplayLabel() : ''
    # A trailing slash marks a folder, for the Directory highlight in
    # syntax/bartleby-binder.vim. Display only: the stored title has no slash.
    var title: string = row.item.IsFolder() ? row.item.title .. '/' : row.item.title
    return repeat(INDENT, row.depth) .. marker .. label .. title .. suffix
  })
enddef

def FindOrCreateWindow(): number
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr != -1
    return winNr
  endif
  execute 'vertical topleft :30split ' .. CO.BINDER_BUF
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  # Long titles wrap at word boundaries. shift:2 starts each wrapped line
  # under the title text, after the marker.
  setlocal wrap linebreak breakindent breakindentopt=shift:2
  setlocal nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-binder
  setlocal winfixwidth
  return bufwinnr(CO.BINDER_BUF)
enddef

# FUNCTION: Draw the tree of project in the current window, which must
# already be the Binder, see Show. The rows of a collapsed folder are not
# drawn at all, see tree.vim Flatten. This is not a Vim fold. The
# collapsed folders are kept across renders in b:bartleby_collapsed.
def Render(project: PO.Project): void
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

  # After deletebufline and setline, the cursor is on line 1. Put it back
  # on the same item, at its new line, when the item still exists.
  var newIdx: number = previousId ==# '' ? -1 : T.IndexOfRowById(rows, previousId)
  if newIdx >= 0
    cursor(newIdx + 1 + HEADER_LINES, 1)
  endif
enddef

# FUNCTION: Return what every cursor command needs: the buffer's project,
# its rows, and the row under the cursor, or null_object when there is
# none, also on the title line.
def CursorContext(): dict<any>
  var project: PO.Project = get(b:, 'bartleby_project', null_object)
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
    log.Error(printf(IN.T("missing file on disk: %s"), path))
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
  var project: PO.Project = ctx.project
  CR.Show(project, ctx.row.item, (doc: BI.BinderItem) => {
    var path: string = doc.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Error(printf(IN.T("missing file on disk: %s"), path))
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
  var project: PO.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  IP.PromptText(IN.T("Snapshot label (optional)"), '', (label: string) => {
    SN.Take(project, doc, label)
  })
enddef

def ShowSnapshotReadOnly(doc: BI.BinderItem, snapshot: SN.Snapshot): void
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
  var project: PO.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  var snapshots: list<SN.Snapshot> = reverse(SN.List(project, doc))
  if empty(snapshots)
    log.Info(printf(IN.T("no snapshots for \"%s\""), doc.title))
    return
  endif
  var names: list<string> = snapshots->mapnew((_, s) => s.DisplayName())
  PI.PickOne(IN.T("Snapshots"), names, (choice: string) => {
    var snapshot: SN.Snapshot = snapshots[index(names, choice)]
    PI.PickOne(printf(IN.T(" %s "), choice), ['Restore', 'View', 'Cancel'], (action: string) => {
      if action ==# 'Restore'
        SN.Restore(project, doc, snapshot)
      elseif action ==# 'View'
        ShowSnapshotReadOnly(doc, snapshot)
      endif
    }, '', {Restore: IN.T("Restore"), View: IN.T("View"), Cancel: IN.T("Cancel")})
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
  SE.Run(ctx.project)
enddef

# FUNCTION: Add -2, -3, and so on to a relPath that is already taken on
# disk. dirSlug is empty for a document at the top level, outside any
# folder.
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
  IP.PromptText(IN.T("New document title"), '', (title: string) => {
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
      dirSlug = SU.Slugify(ctx.row.item.title)
    elseif ctx.row.ownerItem isnot null_object
      dirSlug = SU.Slugify(ctx.row.ownerItem.title)
    endif
  endif
  var relPath: string = UniqueRelPath(ctx.project.BinderRoot(), dirSlug, SU.Slugify(title), ctx.project.DocExt())
  var newItem: BI.BinderItem = BI.BinderItem.NewDocument(title, relPath)
  MU.AddNear(ctx.project, ctx.row, newItem)
  TE.Materialize([newItem], ctx.project.BinderRoot())
  ctx.project.Save()
  Render(ctx.project)
enddef

def AddFolder(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object
    return
  endif
  var options: list<string> = ['Custom']
  if ctx.project.projectType ==# CO.TYPE_NOVEL
    options->add('Chapter')
  elseif ctx.project.projectType ==# CO.TYPE_NOVEL_PARTS
    options->add('Part')
    var onOrInsidePart: bool = (ctx.row isnot null_object && ctx.row.item.structureRole ==# CO.ROLE_PART)
      || MU.FindAncestorWithRole(ctx.rows, ctx.row, CO.ROLE_PART) isnot null_object
    if onOrInsidePart
      options->add('Chapter')
    endif
  endif
  if len(options) ==# 1
    CreateFolder(ctx, 'Custom')
  else
    PI.PickOne(IN.T("Add Folder"), options, (choice: string) => {
      CreateFolder(ctx, choice)
    }, '', {Custom: IN.T("Folder"), Chapter: IN.T("Chapter"), Part: IN.T("Part")})
  endif
enddef

def CreateFolder(ctx: dict<any>, kind: string): void
  var promptTitle: string = kind ==# 'Custom' ? IN.T("New folder title")
    : kind ==# 'Part' ? IN.T("New Part title, or blank for the next number")
    : IN.T("New Chapter title, or blank for the next number")
  IP.PromptText(promptTitle, '', (title: string) => {
    FinishCreateFolder(ctx, kind, title)
  })
enddef

def FinishCreateFolder(ctx: dict<any>, kind: string, title: string): void
  if kind ==# 'Custom'
    if title ==# ''
      return
    endif
    ctx.project.AddChild(BI.BinderItem.NewFolder(title, CO.ROLE_CUSTOM))
    ctx.project.Save()
    Render(ctx.project)
    return
  endif

  if kind ==# 'Chapter'
    var container: BI.BinderItem
    if ctx.project.projectType ==# CO.TYPE_NOVEL_PARTS
      container = (ctx.row isnot null_object && ctx.row.item.structureRole ==# CO.ROLE_PART)
        ? ctx.row.item : MU.FindAncestorWithRole(ctx.rows, ctx.row, CO.ROLE_PART)
    else
      container = MU.FindManuscript(ctx.project)
    endif
    if container is null_object
      log.Error(IN.T("no Manuscript/Part folder found to add a chapter into"))
      return
    endif
    var chapter: BI.BinderItem = MU.AddChapter(container, ctx.row, title)
    TE.Materialize([chapter], ctx.project.BinderRoot())
  else
    var manuscript: BI.BinderItem = MU.FindManuscript(ctx.project)
    if manuscript is null_object
      log.Error(IN.T("no Manuscript folder found to add a part into"))
      return
    endif
    MU.AddPart(manuscript, ctx.row, title)
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

  if MU.IsImmutableFolder(item)
    if item.ChildCount() == 0
      log.Info(printf(IN.T("\"%s\" is already empty"), item.title))
      return
    endif
    var clearPrompt: string = printf(IN.T("Clear all contents of \"%s\"? The folder itself will remain."), item.title)
    DP.Confirm(clearPrompt, () => {
      MU.ClearChildren(item)
      log.Info(printf(IN.T("cleared \"%s\" - any files on disk were left untouched"), item.title))
      ctx.project.Save()
      Render(ctx.project)
    })
    return
  endif

  var prompt: string = item.IsFolder() && item.ChildCount() > 0
    ? printf(IN.T("Delete \"%s\" and everything inside it?"), item.title)
    : printf(IN.T("Delete \"%s\"?"), item.title)
  DP.Confirm(prompt, () => {
    MU.Remove(ctx.project, ctx.row)
    log.Info(IN.T("removed from binder - any files on disk were left untouched"))
    ctx.project.Save()
    Render(ctx.project)
  })
enddef

def RenameUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if MU.IsImmutableFolder(ctx.row.item)
    log.Info(printf(IN.T("\"%s\" cannot be renamed"), ctx.row.item.title))
    return
  endif
  var oldTitle: string = ctx.row.item.title
  IP.PromptText(IN.T("Rename to"), oldTitle, (newTitle: string) => {
    if newTitle ==# '' || newTitle ==# oldTitle
      return
    endif
    MU.Rename(ctx.row, newTitle)
    ctx.project.Save()
    Render(ctx.project)
  })
enddef

def Move(delta: number): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !MU.MoveWithinSiblings(ctx.project, ctx.row, delta)
    log.Info(IN.T("this item cannot be reordered here"))
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
  if !MU.Indent(ctx.project, ctx.row)
    log.Info(IN.T("no valid folder above to indent into"))
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
  if !MU.Outdent(ctx.project, ctx.rows, ctx.row)
    log.Info(IN.T("already at the top level, or not a valid destination for this item"))
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
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  PI.PickOne(IN.T("Label"), CO.LABELS, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetLabel(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, currentMeta.label, D.LabelNames())
enddef

def PickStatus(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDocument()
    return
  endif
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var currentMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  PI.PickOne(IN.T("Status"), CO.STATUSES, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetStatus(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, currentMeta.status, D.StatusNames())
enddef

# FUNCTION: Show or hide the Chapter and Part prefixes and draw again.
# The setting applies to the whole session, not only to this buffer.
def ToggleRoleLabels(): void
  binderShowRoleLabels = !binderShowRoleLabels
  var project: PO.Project = get(b:, 'bartleby_project', null_object)
  if project isnot null_object
    Render(project)
  endif
enddef

def ShowHelp(): void
  H.Show(IN.T("Binder"), [
    ['<CR>', IN.T("Open document / toggle folder")],
    ['<Tab>', IN.T("Toggle folder collapse")],
    ['a', IN.T("New document")],
    ['A', IN.T("New folder (Chapter/Part when applicable)")],
    ['dd', IN.T("Delete item under cursor")],
    ['r', IN.T("Rename item under cursor")],
    ['J / K', IN.T("Move item down / up")],
    ['>> / <<', IN.T("Indent / outdent item")],
    ['l', IN.T("Set label")],
    ['s', IN.T("Set status")],
    ['L', IN.T("Toggle Chapter:/Part: labels")],
    ['S', IN.T("Take snapshot")],
    ['gS', IN.T("View/restore snapshots")],
    ['gc', IN.T("Open Corkboard")],
    ['go', IN.T("Open Outliner")],
    ['/', IN.T("Search project")],
    ['q', IN.T("Close Binder")],
    ['?', IN.T("This help")],
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
  SS.CaptureBinderState()
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

# FUNCTION: Draw the tree of project in the sidebar, and create the
# sidebar if needed.
export def Show(project: PO.Project): void
  var winNr: number = FindOrCreateWindow()
  execute ':' .. winNr .. 'wincmd w'
  Render(project)
  SetupKeymaps()
enddef

export def Toggle(project: PO.Project): void
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr != -1
    execute ':' .. winNr .. 'close'
    SS.CaptureBinderState()
    return
  endif
  Show(project)
  SS.CaptureBinderState()
enddef

export def IsOpen(): bool
  return bufwinnr(CO.BINDER_BUF) != -1
enddef

# FUNCTION: Return the ids of the collapsed folders, for the session. The
# set lives in b:bartleby_collapsed on the Binder buffer, and other
# scripts use these two functions instead of that variable.
export def GetCollapsedIds(): list<string>
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr == -1
    return []
  endif
  return keys(getbufvar(winbufnr(winNr), 'bartleby_collapsed', {}))
enddef

export def ApplyCollapsedIds(ids: list<string>): void
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr == -1
    return
  endif
  var collapsed: dict<bool> = {}
  for id in ids
    collapsed[id] = true
  endfor
  setbufvar(winbufnr(winNr), 'bartleby_collapsed', collapsed)
enddef
