vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# mutate.vim - Binder tree surgery: insert/remove/move/reparent/rename.
# Pure data operations against Project's/BinderItem's own mutation methods -
# no UI, no persistence. Callers Save() and re-render after a truthy return.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/slug.vim' as Sl

# Walks up from `row` through its ancestors, returning the nearest one
# with structureRole == role (null_object if none found before root).
export def FindAncestorWithRole(rows: list<T.Row>, row: T.Row, role: string): BI.BinderItem
  var current: BI.BinderItem = row is null_object ? null_object : row.ownerItem
  while current isnot null_object
    if current.structureRole ==# role
      return current
    endif
    var parentRow: T.Row = T.FindRowById(rows, current.id)
    current = parentRow is null_object ? null_object : parentRow.ownerItem
  endwhile
  return null_object
enddef

# The scrive's single top-level Manuscript folder, or null_object if
# somehow absent (a project predating structureRole, say).
export def FindManuscript(project: Pj.Project): BI.BinderItem
  for i in range(project.ItemCount())
    if project.ItemAt(i).structureRole ==# BI.ROLE_MANUSCRIPT
      return project.ItemAt(i)
    endif
  endfor
  return null_object
enddef

# Next unused bare-number title ("1", "2", ...) among `siblings` sharing
# `role` - matches templates.vim's own default numbering, so a blank
# title at creation time behaves the same as the scrive's starting tree.
def NextRoleNumber(siblings: list<BI.BinderItem>, role: string): string
  var n: number = 0
  for item in siblings
    if item.structureRole ==# role && item.title =~# '^\d\+$'
      n = max([n, str2nr(item.title)])
    endif
  endfor
  return string(n + 1)
enddef

# Places `newItem` into `container`'s children: as the next sibling near
# the cursor if `row` is itself a child of `container` (or IS `container`),
# otherwise appended to the end - the same "near cursor, else append"
# shape as AddNear, just scoped to a specific container rather than
# wherever the cursor happens to be.
def AddIntoContainer(container: BI.BinderItem, row: T.Row, newItem: BI.BinderItem): void
  if row isnot null_object && row.ownerItem is container
    container.InsertChildAt(container.IndexOfChild(row.item.id) + 1, newItem)
  else
    container.AddChild(newItem)
  endif
enddef

# Creates a new Chapter folder (with a starter "Scene 1" document, not
# yet materialized on disk - the caller does that, same as templates.vim's
# own scrive-creation path) inside `container` (the Manuscript folder for
# Novel, or a specific Part for Novel with Parts). Title defaults to the
# next sequential bare number among sibling chapters when blank.
export def AddChapter(container: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var chapterTitle: string = title ==# '' ? NextRoleNumber(container.children, BI.ROLE_CHAPTER) : title
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterTitle, BI.ROLE_CHAPTER)
  var relPath: string = $'chapter-{Sl.Slugify(chapterTitle)}/scene-01.md'
  chapter.AddChild(BI.BinderItem.NewDocument('Scene 1', relPath))
  AddIntoContainer(container, row, chapter)
  return chapter
enddef

# Creates a new (empty) Part folder inside the Manuscript folder, matching
# how templates.vim's own default Part 2 starts empty. Title defaults to
# the next sequential bare number among sibling parts when blank.
export def AddPart(manuscript: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var partTitle: string = title ==# '' ? NextRoleNumber(manuscript.children, BI.ROLE_PART) : title
  var part: BI.BinderItem = BI.BinderItem.NewFolder(partTitle, BI.ROLE_PART)
  AddIntoContainer(manuscript, row, part)
  return part
enddef

# True if placing an item with `role` as a child of `parent` (null_object
# meaning root level) is structurally valid: ROLE_PART/ROLE_CHAPTER may
# only live under a ROLE_MANUSCRIPT folder (directly, or nested under
# another Part); ROLE_CUSTOM may only live at the root. Everything else
# (front-matter/characters/research/back-matter/'', and all documents,
# which never carry a structural role) is unrestricted.
def RoleAllowedUnder(role: string, parent: BI.BinderItem): bool
  if role ==# BI.ROLE_PART || role ==# BI.ROLE_CHAPTER
    return parent isnot null_object
      && (parent.structureRole ==# BI.ROLE_MANUSCRIPT || parent.structureRole ==# BI.ROLE_PART)
  endif
  if role ==# BI.ROLE_CUSTOM
    return parent is null_object
  endif
  return true
enddef

# Inserts `newItem` right after `row` in the tree: a root-level sibling if
# `row` is root-level, otherwise a sibling inside `row`'s own owner folder.
def InsertAfter(project: Pj.Project, row: T.Row, newItem: BI.BinderItem): void
  if row.ownerItem is null_object
    var idx: number = project.IndexOfItem(row.item.id)
    project.InsertItemAt(idx + 1, newItem)
  else
    var idx: number = row.ownerItem.IndexOfChild(row.item.id)
    row.ownerItem.InsertChildAt(idx + 1, newItem)
  endif
enddef

# Adds `newItem` relative to `row`: a child if `row` is a folder, otherwise
# a sibling right after it. `row` is null_object for an empty binder, or
# when adding with no particular cursor context - either way, appends
# root-level.
export def AddNear(project: Pj.Project, row: T.Row, newItem: BI.BinderItem): void
  if row is null_object
    project.AddItem(newItem)
  elseif row.item.IsFolder()
    row.item.AddChild(newItem)
  else
    InsertAfter(project, row, newItem)
  endif
enddef

# Removes `row`'s item from the tree. Leaves any underlying document files
# untouched on disk - deleting from the binder is not deleting work.
export def Remove(project: Pj.Project, row: T.Row): void
  if row.ownerItem is null_object
    project.RemoveItemAt(project.IndexOfItem(row.item.id))
  else
    row.ownerItem.RemoveChildAt(row.ownerItem.IndexOfChild(row.item.id))
  endif
enddef

# Swaps `row`'s item with its next/previous sibling in the same owner list.
# `delta` is +1 (move down) or -1 (move up). No-op (false) at a list edge.
export def MoveWithinSiblings(project: Pj.Project, row: T.Row, delta: number): bool
  if row.item.IsFolder() && row.item.structureRole !=# BI.ROLE_CHAPTER
      && row.item.structureRole !=# BI.ROLE_PART
    return false
  endif
  if row.ownerItem is null_object
    var idx: number = project.IndexOfItem(row.item.id)
    var target: number = idx + delta
    if target < 0 || target >= project.ItemCount()
      return false
    endif
    project.SwapItems(idx, target)
  else
    var idx: number = row.ownerItem.IndexOfChild(row.item.id)
    var target: number = idx + delta
    if target < 0 || target >= row.ownerItem.ChildCount()
      return false
    endif
    row.ownerItem.SwapChildren(idx, target)
  endif
  return true
enddef

# Promotes `row`'s item to be a sibling of its current owner folder, right
# after it. No-op (false) if `row` is already root-level.
export def Outdent(project: Pj.Project, rows: list<T.Row>, row: T.Row): bool
  if row.ownerItem is null_object
    return false
  endif
  var grandparentRow: T.Row = T.FindRowById(rows, row.ownerItem.id)
  var newParent: BI.BinderItem = grandparentRow.ownerItem
  if !RoleAllowedUnder(row.item.structureRole, newParent)
    return false
  endif
  row.ownerItem.RemoveChildAt(row.ownerItem.IndexOfChild(row.item.id))
  InsertAfter(project, grandparentRow, row.item)
  return true
enddef

# Demotes `row`'s item into its previous sibling, if that sibling is a
# folder. No-op (false) otherwise (no previous sibling, or it's a document).
export def Indent(project: Pj.Project, row: T.Row): bool
  var siblingIdx: number
  if row.ownerItem is null_object
    siblingIdx = project.IndexOfItem(row.item.id) - 1
    if siblingIdx < 0 || !project.ItemAt(siblingIdx).IsFolder()
      return false
    endif
    if !RoleAllowedUnder(row.item.structureRole, project.ItemAt(siblingIdx))
      return false
    endif
    project.ItemAt(siblingIdx).AddChild(row.item)
    project.RemoveItemAt(siblingIdx + 1)
  else
    siblingIdx = row.ownerItem.IndexOfChild(row.item.id) - 1
    if siblingIdx < 0 || !row.ownerItem.ChildAt(siblingIdx).IsFolder()
      return false
    endif
    if !RoleAllowedUnder(row.item.structureRole, row.ownerItem.ChildAt(siblingIdx))
      return false
    endif
    row.ownerItem.ChildAt(siblingIdx).AddChild(row.item)
    row.ownerItem.RemoveChildAt(siblingIdx + 1)
  endif
  return true
enddef

export def Rename(row: T.Row, newTitle: string): void
  row.item.Rename(newTitle)
enddef
