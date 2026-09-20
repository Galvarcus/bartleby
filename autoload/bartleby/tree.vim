vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# tree.vim - flattens a scrive's Binder tree into an ordered list of Rows,
# each carrying enough owner info to relocate its item without re-walking
# the tree. No UI, no mutation - just tree -> rows and id -> row lookups,
# shared by binder.vim (rendering) and mutate.vim (tree surgery).
#
# Row is defined before the functions below on purpose, not just by
# convention: Flatten/FindRowById/IndexOfRowById all use Row in their
# own signatures (list<Row> etc.), and Vim9 resolves a function's
# parameter/return types eagerly at definition time - unlike a class
# used only inside a function body (a local var type, or via .new()),
# which can forward-reference a class defined later in the file just
# fine. Confirmed by trying the reorder: moving Row after these
# functions throws E1010 "Type not recognized: Row" at the first one's
# own signature line, before the file even finishes compiling.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj

# ownerItem is null_object when `item` is root-level (its owner is the
# Project itself, not a folder).
export class Row
  var item: BI.BinderItem
  var depth: number
  var ownerItem: BI.BinderItem
endclass

export def Flatten(project: Pj.Project, collapsed: dict<bool> = {}): list<Row>
  var rows: list<Row> = []
  def Walk(items: list<BI.BinderItem>, depth: number, ownerItem: BI.BinderItem): void
    for item in items
      rows->add(Row.new(item, depth, ownerItem))
      # A collapsed folder's row still renders - its children just aren't
      # walked at all, so they never become rows in the first place. That
      # naturally handles nested collapse too: a folder inside a collapsed
      # one is never visited, regardless of its own collapsed state.
      if item.IsFolder() && !get(collapsed, item.id, false)
        Walk(item.children, depth + 1, item)
      endif
    endfor
  enddef
  Walk(project.items, 0, null_object)
  return rows
enddef

export def FindRowById(rows: list<Row>, id: string): Row
  for row in rows
    if row.item.id ==# id
      return row
    endif
  endfor
  return null_object
enddef

export def IndexOfRowById(rows: list<Row>, id: string): number
  for i in range(len(rows))
    if rows[i].item.id ==# id
      return i
    endif
  endfor
  return -1
enddef
