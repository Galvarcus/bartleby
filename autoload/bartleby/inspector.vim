vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inspector.vim - a right-hand split showing the current editor document's
# synopsis and keywords, editable in place and synced back to its
# .meta.json sidecar as you type (TextChanged/TextChangedI) and on :w
# (BufWriteCmd - buftype=acwrite, so :w doesn't try to write the scratch
# buffer itself to disk). A plain buffer, not a popup - synopsis text can
# run long and wants normal Vim editing.
#
# While open, it follows whichever document the editor window shows -
# opening a different one (from Binder, Corkboard, Outliner, or plain :e)
# refreshes the Inspector for it automatically, via a BufEnter autocmd
# that ignores Bartleby's own chrome windows (windows.vim#IsChromeBuffer).
#
# Title/Label/Status are shown for context but are NOT synced back -
# editing those lines has no effect. Renaming lives in the Binder's own
# `r`, and Label/Status already have their own pickers there (and in the
# Outliner) - this only owns the two fields that don't have one yet.
# Custom metadata isn't shown here either; it has no editing UI anywhere
# yet, so there's nothing meaningful to sync.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/windows.vim' as W
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const BUF_NAME: string = 'Bartleby-Inspector'
const KEYWORDS_PREFIX: string = 'Keywords:'
const SYNOPSIS_HEADER: string = 'Synopsis:'

def RenderContent(item: BI.BinderItem, meta: D.DocMeta): list<string>
  var lines: list<string> = [
    $'Title: {item.title}',
    $'Label: {meta.label}',
    $'Status: {meta.status}',
    '',
    $'{KEYWORDS_PREFIX} {join(meta.keywords, ", ")}',
    '',
    SYNOPSIS_HEADER,
  ]
  if meta.synopsis !=# ''
    lines += split(meta.synopsis, "\n")
  endif
  return lines
enddef

def Sync(): void
  var project: Pj.Project = get(b:, 'bartleby_inspector_project', null_object)
  var item: BI.BinderItem = get(b:, 'bartleby_inspector_item', null_object)
  if project is null_object || item is null_object
    return
  endif

  var lines: list<string> = getline(1, '$')
  var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())

  for l in lines
    if l =~# '^' .. KEYWORDS_PREFIX
      var rest: string = trim(strpart(l, len(KEYWORDS_PREFIX)))
      meta.SetKeywords(rest ==# '' ? [] : split(rest, ',\s*'))
    endif
  endfor

  var synopsisIdx: number = index(lines, SYNOPSIS_HEADER)
  if synopsisIdx >= 0
    meta.SetSynopsis(trim(join(lines[synopsisIdx + 1 : ], "\n")))
  endif

  meta.Save(item.MetaPath(project.BinderRoot()))
  setlocal nomodified
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
  deletebufline(bufNr, 1, '$')
  setbufline(bufNr, 1, RenderContent(item, meta))
  setbufvar(bufNr, '&modified', 0)
  setbufvar(bufNr, 'bartleby_inspector_project', project)
  setbufvar(bufNr, 'bartleby_inspector_item', item)
enddef

# Fired on every BufEnter while the Inspector is open - refreshes it for
# whatever document just became active in a plain editor window. Ignores
# Bartleby's own chrome buffers (Binder, Inspector itself, Outliner) and
# anything that isn't a document in the open scrive at all.
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
  setlocal buftype=acwrite bufhidden=hide noswapfile nobuflisted
  setlocal nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-inspector
  setlocal winfixwidth
  setline(1, RenderContent(item, meta))
  setlocal nomodified
  b:bartleby_inspector_project = project
  b:bartleby_inspector_item = item

  augroup bartleby_inspector_sync
    autocmd! * <buffer>
    autocmd TextChanged,TextChangedI,BufWriteCmd <buffer> Sync()
  augroup END

  augroup bartleby_inspector_follow
    autocmd!
    autocmd BufEnter * FollowEditor()
  augroup END
enddef
