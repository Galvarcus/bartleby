vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# tree.vim: flattens the Binder tree of a scrive into an ordered list of
# Rows. Each Row knows its owner, so its item can be moved without
# walking the tree again. No UI and no changes: only rows from the tree
# and lookups by id, for binder.vim, which draws, and mutate.vim, which
# changes the tree.
#
# Row is defined before the functions that use it because Flatten,
# FindRowById, and IndexOfRowById name it in their signatures, and Vim9
# resolves a signature when the function is defined. A class used only
# inside a function body can come later. Moving Row after these functions
# gives error E1010, Type not recognized: Row.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj

# CLASS: One visible item of the tree, with its depth and its owner.
# ownerItem is null_object when item is at the top level, where the owner
# is the Project, not a folder.
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
      # A collapsed folder still gets its row, but its children are not
      # visited, so they get no rows. A folder inside a collapsed folder is
      # never visited either, whatever its own state.
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
