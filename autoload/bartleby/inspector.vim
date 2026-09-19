vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inspector.vim - a right-hand, read-only split showing the current
# editor document's Title/Label/Status/Target/Keywords/Synopsis.
#
# Read-only, not editable-in-place: an earlier design let Keywords and
# Synopsis be edited by typing directly into the buffer (synced back via
# TextChanged/BufWriteCmd). Replaced with a single `e` key that opens
# the right popup for whichever field the cursor is on - Label/Status
# reuse picker.vim's PickOne, the same widget Binder uses for the same
# job; Target gets a plain numeric PromptText (word count, 0/blank
# clears it); Keywords gets a single-line PromptText, the same widget
# Binder's rename (`r`) uses; Synopsis gets PromptMultiline, since it
# can run to several paragraphs and a single-line prompt would lose
# that. Title
# isn't editable here at all - renaming lives in Binder's own `r`.
#
# While open, it follows whichever document the editor window shows -
# opening a different one (from Binder, Corkboard, Outliner, or plain :e)
# refreshes the Inspector for it automatically, via a BufEnter autocmd
# that ignores Bartleby's own chrome windows (windows.vim#IsChromeBuffer).
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/picker.vim' as Pk
import autoload 'bartleby/inputpopup.vim' as IP
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const BUF_NAME: string = 'Bartleby-Inspector'
const FRAME_TITLE: string = '::Inspector::'
# line numbers within RenderContent()'s own output - kept as named
# constants since EditUnderCursor() needs to know exactly which line is
# which without re-deriving it from the rendered text.
const LINE_TITLE: number = 2
const LINE_LABEL: number = 3
const LINE_STATUS: number = 4
const LINE_TARGET: number = 5
const LINE_KEYWORDS: number = 7
const LINE_SYNOPSIS_HEADER: number = 9

def RenderContent(item: BI.BinderItem, meta: D.DocMeta): list<string>
  var lines: list<string> = [
    FRAME_TITLE,
    $'Title: {item.title}',
    $'Label: {meta.label}',
    $'Status: {meta.status}',
    $'Target: {meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : "-"}',
    '',
    $'Keywords: {join(meta.keywords, ", ")}',
    '',
    'Synopsis:',
  ]
  if meta.synopsis !=# ''
    lines += split(meta.synopsis, "\n")
  endif
  return lines
enddef

# Rewrites the Inspector buffer's content for `item`, without switching
# windows/focus away from wherever the editor currently is - setbufline()/
# deletebufline()/setbufvar() all take an explicit target buffer, so this
# never needs to touch the editor window at all.
def RefreshFor(project: Pj.Project, item: BI.BinderItem): void
  var bufNr: number = bufnr(BUF_NAME)
  if bufNr == -1
    return
  endif
  var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  setbufvar(bufNr, '&modifiable', 1)
  deletebufline(bufNr, 1, '$')
  setbufline(bufNr, 1, RenderContent(item, meta))
  setbufvar(bufNr, '&modifiable', 0)
  setbufvar(bufNr, '&modified', 0)
  setbufvar(bufNr, 'bartleby_inspector_project', project)
  setbufvar(bufNr, 'bartleby_inspector_item', item)
enddef

def CurrentContext(): dict<any>
  return {
    project: get(b:, 'bartleby_inspector_project', null_object),
    item: get(b:, 'bartleby_inspector_item', null_object),
  }
enddef

def EditUnderCursor(): void
  var ctx: dict<any> = CurrentContext()
  if ctx.project is null_object || ctx.item is null_object
    return
  endif
  var project: Pj.Project = ctx.project
  var item: BI.BinderItem = ctx.item
  var lnum: number = line('.')

  if lnum == LINE_LABEL
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    Pk.PickOne('Label', D.LABELS, (choice: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetLabel(choice)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    }, meta.label)
  elseif lnum == LINE_STATUS
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    Pk.PickOne('Status', D.STATUSES, (choice: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetStatus(choice)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    }, meta.status)
  elseif lnum == LINE_TARGET
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    var current: string = meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : ''
    IP.PromptText('Target word count', current, (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetWordCountTarget(max([0, str2nr(text)]))
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  elseif lnum == LINE_KEYWORDS
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    IP.PromptText('Keywords', join(meta.keywords, ', '), (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetKeywords(text ==# '' ? [] : split(text, ',\s*'))
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  elseif lnum >= LINE_SYNOPSIS_HEADER
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    IP.PromptMultiline('Synopsis', meta.synopsis, (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetSynopsis(text)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  endif
enddef

# Fired on every BufEnter while the Inspector is open - refreshes it for
# whatever document just became active in a plain editor window. Ignores
# Bartleby's own chrome buffers (Binder, Inspector itself) and anything
# that isn't a document in the open scrive at all.
def FollowEditor(): void
  if W.IsChromeBuffer(bufnr('%'))
    return
  endif
  var project: Pj.Project = St.Get()
  if project is null_object
    return
  endif
  var item: BI.BinderItem = project.FindItemByPath(expand('%:p'))
  if item is null_object
    return
  endif
  RefreshFor(project, item)
enddef

def SetupKeymaps(): void
  nnoremap <buffer> <silent> e <ScriptCmd>EditUnderCursor()<CR>
enddef

# Opens (or closes, if already open) the Inspector for whichever document
# is open in the current window.
export def Toggle(): void
  var winNr: number = bufwinnr(BUF_NAME)
  if winNr != -1
    execute ':' .. winNr .. 'close'
    augroup bartleby_inspector_follow
      autocmd!
    augroup END
    return
  endif

  var project: Pj.Project = St.Get()
  if project is null_object
    log.Warn('no scrive open')
    return
  endif
  var path: string = expand('%:p')
  var item: BI.BinderItem = project.FindItemByPath(path)
  if item is null_object
    log.Info('current buffer is not a document in the open scrive')
    return
  endif

  var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  execute 'vertical botright :40split ' .. BUF_NAME
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-inspector
  setlocal winfixwidth
  setline(1, RenderContent(item, meta))
  setlocal nomodifiable
  setlocal nomodified
  b:bartleby_inspector_project = project
  b:bartleby_inspector_item = item
  SetupKeymaps()

  augroup bartleby_inspector_follow
    autocmd!
    autocmd BufEnter * FollowEditor()
  augroup END
enddef
