vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# corkboard.vim - index-card grid for one folder's direct-child documents,
# built on buttonspopup.vim's PopupButtonMenu. Each card is a real
# multi-line box: title on its own line, synopsis word-wrapped beneath it
# (see wrap.vim) - buttonspopup.vim renders a "\n"-containing Button label
# as a bordered box rather than its usual single-line '[ label ]' style.
# Picking a card calls back with its document (the caller decides what
# "picked" means - see binder.vim#OpenCorkboard for opening it in the
# editor). `e` quick-edits the focused card's synopsis without leaving the
# corkboard; J/K reorder it among its siblings. Both close and re-show the
# popup (buttonspopup.vim has no in-place "update these buttons" API),
# keeping the same card focused via opts.button.selected.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/mutate.vim' as M
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/buttonspopup.vim' as BP
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/wrap.vim' as Wr
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const CARD_CONTENT_WIDTH: number = 24
const CARD_SPACING: number = 2
const MAX_SYNOPSIS_LINES: number = 3
# Total on-screen width of one card, border + padding included - see
# buttonspopup.vim#RenderButton's box math (content + 2 border chars + 2
# padding spaces).
const CARD_TOTAL_WIDTH: number = CARD_CONTENT_WIDTH + 4

def Noop(): void
enddef

# How many CARD_TOTAL_WIDTH-wide columns (with CARD_SPACING between them)
# actually fit in the terminal, so the corkboard never asks for a grid
# wider than the TTY - a standard 80-column terminal fits 2 columns of the
# current default card width, not 3. MARGIN leaves room for the popup's
# own border/padding and a little breathing space at the screen edge.
def MaxColumns(): number
  const MARGIN: number = 4
  var available: number = &columns - MARGIN
  var maxFit: number = (available + CARD_SPACING) / (CARD_TOTAL_WIDTH + CARD_SPACING)
  return max([1, maxFit])
enddef

# Title on its own line, then up to MAX_SYNOPSIS_LINES word-wrapped lines
# of synopsis, joined with "\n" for buttonspopup.vim's box-card rendering.
# A synopsis longer than that many lines gets an ellipsis on the last one.
def CardLabel(item: BI.BinderItem, binderRoot: string): string
  var meta: D.DocMeta = item.LoadMeta(binderRoot)
  var cardLines: list<string> = [item.title]
  if meta.synopsis !=# ''
    var wrapped: list<string> = Wr.Wrap(meta.synopsis, CARD_CONTENT_WIDTH)
    if len(wrapped) > MAX_SYNOPSIS_LINES
      wrapped = wrapped[0 : MAX_SYNOPSIS_LINES - 1]
      wrapped[-1] = wrapped[-1] .. '…'
    endif
    cardLines += wrapped
  endif
  return join(cardLines, "\n")
enddef

def EditSynopsis(project: Pj.Project, folder: BI.BinderItem, doc: BI.BinderItem,
    OnDocumentPicked: func(BI.BinderItem)): void
  var meta: D.DocMeta = doc.LoadMeta(project.BinderRoot())
  IP.PromptText('Synopsis', meta.synopsis, (newSynopsis: string) => {
    if newSynopsis !=# meta.synopsis
      meta.SetSynopsis(newSynopsis)
      meta.Save(doc.MetaPath(project.BinderRoot()))
    endif
    Show(project, folder, OnDocumentPicked, doc.id)
  }, () => {
    Show(project, folder, OnDocumentPicked, doc.id)
  })
enddef

def Reorder(project: Pj.Project, folder: BI.BinderItem, doc: BI.BinderItem,
    delta: number, OnDocumentPicked: func(BI.BinderItem)): void
  # A minimal T.Row built by hand - MoveWithinSiblings only reads
  # .item/.ownerItem, so there's no need to flatten the whole scrive just
  # to reorder within one folder already in hand.
  var row: T.Row = T.Row.new(doc, 0, folder)
  if M.MoveWithinSiblings(project, row, delta)
    project.Save()
  else
    log.Info('already at that end of the folder')
  endif
  Show(project, folder, OnDocumentPicked, doc.id)
enddef

# Corkboard-only keys the base popup doesn't know about. true = handled.
def HandleExtraKey(project: Pj.Project, folder: BI.BinderItem, docs: list<BI.BinderItem>,
    OnDocumentPicked: func(BI.BinderItem), id: number, selectedIdx: number, key: string): bool
  var doc: BI.BinderItem = docs[selectedIdx]
  if key ==# 'e'
    popup_close(id, -1)
    EditSynopsis(project, folder, doc, OnDocumentPicked)
    return true
  elseif key ==# 'J'
    popup_close(id, -1)
    Reorder(project, folder, doc, 1, OnDocumentPicked)
    return true
  elseif key ==# 'K'
    popup_close(id, -1)
    Reorder(project, folder, doc, -1, OnDocumentPicked)
    return true
  endif
  return false
enddef

# Shows `folder`'s direct-child documents as a card grid. `OnDocumentPicked`
# is called with the chosen document when one is activated (Enter/Space/
# click) - not called at all on cancel. `preferredId` re-focuses a specific
# card after Edit/Reorder close-and-reopen this same corkboard.
export def Show(project: Pj.Project, folder: BI.BinderItem,
    OnDocumentPicked: func(BI.BinderItem), preferredId: string = ''): void
  # copy() first: filter() mutates its list in place, and folder.children
  # is the live tree - filtering it directly would silently delete every
  # non-document child from the actual binder.
  var docs: list<BI.BinderItem> = copy(folder.children)->filter((_, c) => c.IsDocument())
  if empty(docs)
    log.Info($'"{folder.title}" has no documents to show on the corkboard')
    return
  endif

  var buttons: list<BP.Button> = docs->mapnew((_, doc) =>
    BP.Button.new(CardLabel(doc, project.BinderRoot()), Noop, doc))

  var initialIdx: number = 0
  for i in range(len(docs))
    if docs[i].id ==# preferredId
      initialIdx = i
    endif
  endfor

  var menu: BP.PopupButtonMenu = BP.PopupButtonMenu.new(buttons, {
    popup: {title: $' {folder.title} '},
    button: {
      columns: min([len(docs), 3, MaxColumns()]),
      spacing: CARD_SPACING,
      width: CARD_CONTENT_WIDTH,
      selected: initialIdx,
    },
    on_key: (id: number, selectedIdx: number, key: string): bool =>
      HandleExtraKey(project, folder, docs, OnDocumentPicked, id, selectedIdx, key),
    callback: (selected: any) => {
      if selected != null
        OnDocumentPicked(selected.data)
      endif
    },
  })
  menu.Show()
enddef
