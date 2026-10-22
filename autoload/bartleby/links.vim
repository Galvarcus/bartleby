vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# links.vim: links between the documents of a scrive. [[Mara]] links to the
# document titled Mara, and [[Mara|the captain]] links to it and reads the
# captain. gf on a link opens the document, a rename offers to update the
# links to it, and compile shows each link as its text. In a screenplay,
# [[ ]] is a Fountain note, which gf follows and compile leaves out.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/doctemplates.vim' as DT

# A link: [[target]] or [[target|text]]. A target holds no ] and no |, and
# a text holds no ].
const LINK_PAT: string = '\[\[\([^]|]\+\)\%(|\([^]]*\)\)\?\]\]'
# Between the folders of a path, in the list of documents with one title.
const CRUMB_SEP: string = ' / '
# The text before the cursor that opens a link, and the end of a link.
const LINK_OPEN_PAT: string = '\[\[$'
const LINK_CLOSE: string = ']]'
# The menu shows for one title too, and nothing is inserted until a title
# is picked. Vim inserts the first one at once otherwise.
const COMPLETE_OPTS: list<string> = ['menuone', 'noinsert']

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Return the link that covers byte column col of line, as {target,
# text}, or an empty dict. text is the target when the link has none of its
# own. col counts from 1, as col() does.
export def At(line: string, col: number): dict<string>
  var from: number = 0
  while true
    var found: list<any> = matchstrpos(line, LINK_PAT, from)
    if found[1] < 0 || found[1] >= col
      return {}
    endif
    if col <= found[2]
      var parts: list<string> = matchlist(found[0], LINK_PAT)
      var target: string = trim(parts[1])
      return {target: target, text: parts[2] ==# '' ? target : parts[2]}
    endif
    from = found[2]
  endwhile
  return {}
enddef

# FUNCTION: Return lines with each link replaced by its text, for compile.
export def Plain(lines: list<string>): list<string>
  return lines->mapnew((_, line) => substitute(line, LINK_PAT,
    (m: list<string>): string => m[2] ==# '' ? trim(m[1]) : m[2], 'g'))
enddef

# FUNCTION: Return the documents of project titled title, outside the Trash:
# the exact matches, or else the matches that ignore case.
export def Find(project: PO.Project, title: string): list<BI.BinderItem>
  return Match(Docs(project, false), title)
enddef

def Match(docs: list<BI.BinderItem>, title: string): list<BI.BinderItem>
  var exact: list<BI.BinderItem> = docs->copy()->filter((_, d) => d.title ==# title)
  return !empty(exact) ? exact : docs->copy()->filter((_, d) => d.title ==? title)
enddef

# FUNCTION: Return the documents of project in tree order: those in the
# Trash, or those outside it.
def Docs(project: PO.Project, inTrash: bool): list<BI.BinderItem>
  return T.Flatten(project)->filter((_, r) => r.item.IsDoc() && TR.RowInTrash(r) == inTrash)
    ->mapnew((_, r) => r.item)
enddef

# FUNCTION: Return the path of each document of project, by id: the titles
# of its folders and its own, which tell documents with one title apart.
def Paths(project: PO.Project): dict<string>
  var titles: list<string> = []
  var paths: dict<string> = {}
  for r in T.Flatten(project)
    titles = slice(titles, 0, r.depth) + [r.item.title]
    if r.item.IsDoc()
      paths[r.item.id] = join(titles, CRUMB_SEP)
    endif
  endfor
  return paths
enddef

# FUNCTION: After [[ in insert mode, offer the titles of the documents
# outside the Trash, in tree order, each with its folders. A title ends
# the link, unless ]] already follows the cursor.
export def CompleteTitles(): void
  var col: number = col('.')
  var line: string = getline('.')
  var project: PO.Project = ST.Get()
  if project is null_object || strpart(line, 0, col - 1) !~# LINK_OPEN_PAT
    return
  endif
  var close: string = strpart(line, col - 1, len(LINK_CLOSE)) ==# LINK_CLOSE ? '' : LINK_CLOSE
  var paths: dict<string> = Paths(project)
  # dup keeps documents that share a title, which Vim would show once.
  var items: list<dict<any>> = Docs(project, false)->mapnew((_, d) => ({
    word: d.title .. close,
    abbr: d.title,
    menu: strpart(paths[d.id], 0, len(paths[d.id]) - len(d.title) - len(CRUMB_SEP)),
    dup: 1,
  }))
  if empty(items)
    return
  endif
  SetCompleteOpts()
  complete(col, items)
enddef

# FUNCTION: Set the options of the title menu for this buffer, and restore
# the user's own when the menu closes.
def SetCompleteOpts(): void
  b:bartleby_link_completeopt = &l:completeopt
  &l:completeopt = (split(&completeopt, ',') + COMPLETE_OPTS)->sort()->uniq()->join(',')
  augroup bartleby_link_complete
    autocmd! * <buffer>
    autocmd CompleteDone <buffer> ++once RestoreCompleteOpts()
  augroup END
enddef

def RestoreCompleteOpts(): void
  &l:completeopt = b:bartleby_link_completeopt
  unlet b:bartleby_link_completeopt
enddef

# FUNCTION: Open the document of the link under the cursor. Off a link, or
# with no scrive open, do what gf does without Bartleby.
export def Follow(): void
  var link: dict<string> = At(getline('.'), col('.'))
  var project: PO.Project = ST.Get()
  if empty(link) || project is null_object
    try
      normal! gf
    catch
      echohl ErrorMsg
      echomsg substitute(v:exception, '^Vim(normal):', '', '')
      echohl None
    endtry
    return
  endif
  var found: list<BI.BinderItem> = Find(project, link.target)
  if len(found) ==# 1
    B.OpenDoc(project, found[0])
  elseif len(found) > 1
    PI.PickOne(MB.PickLinked(link.target), found->mapnew((_, d) => d.id), (id: string) => {
      B.OpenDoc(project, project.FindItem(id))
    }, '', Paths(project))
  elseif !empty(Match(Docs(project, true), link.target))
    log.Info(MB.LinkInTrash(link.target))
  else
    OfferToCreate(project, link.target)
  endif
enddef

# FUNCTION: Offer to create a document titled title next to the document of
# the current buffer, with the first template there, and open it. A link outside the documents of the
# scrive has no place for one.
def OfferToCreate(project: PO.Project, title: string): void
  var here: BI.BinderItem = SV.DocHere(project)
  if here is null_object
    log.Info(MB.NoLinked(title))
    return
  endif
  DP.Confirm(MB.CreateLinked(title), () => {
    var row: T.Row = T.FindRowById(T.Flatten(project), here.id)
    if row isnot null_object
      B.OpenDoc(project, B.AddDocNear(project, row, title, DT.FirstLines(project, row, title)))
    endif
  }, true)
enddef

# FUNCTION: Return lines with each link to oldTitle pointing to newTitle, and
# the number of links that changed. A link keeps the text that it shows, so
# a rename does not change the compiled text: [[Mara]] becomes
# [[Mara Jones|Mara]]. A target matches oldTitle when it differs only in
# case, as when the link is followed.
export def Retitle(lines: list<string>, oldTitle: string, newTitle: string): list<any>
  var count: number = 0
  var out: list<string> = lines->mapnew((_, line) => substitute(line, LINK_PAT,
    (m: list<string>): string => {
      if trim(m[1]) !=? oldTitle
        return m[0]
      endif
      count += 1
      var text: string = m[2] ==# '' ? trim(m[1]) : m[2]
      return text ==# newTitle ? $'[[{newTitle}]]' : $'[[{newTitle}|{text}]]'
    }, 'g'))
  return [out, count]
enddef

# FUNCTION: Count the links to oldTitle in the documents of project, and with
# write, point them at newTitle. Return the count. An open buffer of a
# document changes in place, with its own undo, and a closed one changes on
# disk. An open Scrivening is saved first and built again after, so that it
# neither loses the change nor writes its old text over it.
export def Retarget(project: PO.Project, oldTitle: string, newTitle: string, write: bool = true): number
  if write
    SV.SaveIfModified()
  endif
  var loaded: dict<number> = {}
  for info in getbufinfo({bufloaded: 1})
    if info.name !=# ''
      loaded[fnamemodify(info.name, ':p')] = info.bufnr
    endif
  endfor
  var total: number = 0
  for doc in Docs(project, false) + Docs(project, true)
    var path: string = doc.AbsPath(project.BinderRoot())
    var bufNr: number = get(loaded, path, -1)
    var lines: list<string> = bufNr > 0 ? getbufline(bufNr, 1, '$')
      : (filereadable(path) ? readfile(path) : [])
    var [out, count] = Retitle(lines, oldTitle, newTitle)
    if count ==# 0
      continue
    endif
    total += count
    if !write
      continue
    endif
    if bufNr > 0
      for i in range(len(lines))
        if lines[i] !=# out[i]
          setbufline(bufNr, i + 1, out[i])
        endif
      endfor
    else
      writefile(out, path)
    endif
  endfor
  if write && total > 0
    SV.SyncWithTree(project, true)
  endif
  return total
enddef

# FUNCTION: After a document was renamed from oldTitle, offer to point the
# links to it at newTitle. Not while another document still has oldTitle,
# which the links then lead to.
export def OfferRetarget(project: PO.Project, oldTitle: string, newTitle: string): void
  if !empty(Find(project, oldTitle))
    return
  endif
  var count: number = Retarget(project, oldTitle, newTitle, false)
  if count ==# 0
    return
  endif
  DP.Confirm(MB.UpdateLinks(count), () => {
    log.Info(MB.LinksUpdated(Retarget(project, oldTitle, newTitle)))
  }, true)
enddef
