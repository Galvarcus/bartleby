vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inspector.vim: a read-only split on the right that shows the Title,
# Label, Status, Target, Keywords, and Synopsis of the document in the
# editor.
#
# The e key edits the field under the cursor with the fitting popup:
#   Label, Status  PickOne from picker.vim, as in the Binder.
#   Target         PromptText for a word count. 0 or empty clears it.
#   Keywords       PromptText, as the Binder uses for renaming.
#   Synopsis       PromptMultiline, because a synopsis can have several
#                  paragraphs.
# The title cannot be changed here. Rename with r in the Binder.
#
# While it is open, the Inspector follows the document in the editor
# window. Opening another document, from the Binder, the Corkboard, the
# Outliner, or with :e, updates it through a BufEnter autocommand that
# ignores Bartleby's own panes, see IsChromeBuffer in windows.vim.
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
# Line numbers in the output of RenderContent, so that EditUnderCursor
# knows which field is on which line. Line 2, the title, has no
# constant: the title cannot be changed here.
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

# FUNCTION: Write the Inspector buffer for item without moving the focus
# from the editor. setbufline, deletebufline, and setbufvar take a target
# buffer, so the editor window is not touched.
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

# FUNCTION: Update the Inspector for the document that just became active
# in an editor window. Runs on every BufEnter while the Inspector is
# open. Ignores Bartleby's own panes, such as the Binder and the
# Inspector, and anything that is not a document of the open scrive.
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

# FUNCTION: Open the Inspector for the document in the current window, or
# close it when it is open.
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
