vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# mutate.vim: changes to the Binder tree: insert, remove, move, reparent,
# and rename. Pure data operations on the change methods of Project and
# BinderItem, with no UI and no saving. After a true result, the caller
# saves and draws again.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/slug.vim' as Sl

# FUNCTION: Return the nearest ancestor of row whose structureRole is
# role, or null_object when there is none below the top level.
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

# FUNCTION: Return the one top-level Manuscript folder of the scrive, or
# null_object when it is missing, as in a project older than roles.
export def FindManuscript(project: Pj.Project): BI.BinderItem
  for i in range(project.ItemCount())
    if project.ItemAt(i).structureRole ==# BI.ROLE_MANUSCRIPT
      return project.ItemAt(i)
    endif
  endfor
  return null_object
enddef

# FUNCTION: Return the next unused number title, 1, 2, and so on, among
# the siblings with role. templates.vim numbers the same way, so an empty
# title gives the same result as in a new scrive.
def NextRoleNumber(siblings: list<BI.BinderItem>, role: string): string
  var n: number = 0
  for item in siblings
    if item.structureRole ==# role && item.title =~# '^\d\+$'
      n = max([n, str2nr(item.title)])
    endif
  endfor
  return string(n + 1)
enddef

# FUNCTION: Put newItem into the children of container: after the row at
# the cursor when that row is in container or is container, else at the
# end. The same rule as AddNear, but for one given container.
def AddIntoContainer(container: BI.BinderItem, row: T.Row, newItem: BI.BinderItem): void
  if row isnot null_object && row.ownerItem is container
    container.InsertChildAt(container.IndexOfChild(row.item.id) + 1, newItem)
  else
    container.AddChild(newItem)
  endif
enddef

# FUNCTION: Create a Chapter folder in container, which is the Manuscript
# folder for a Novel or a Part for a Novel with Parts. It holds a first
# document, Scene 1, which the caller creates on disk, as templates.vim
# does for a new scrive. An empty title becomes the next number among the
# sibling chapters.
export def AddChapter(container: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var chapterTitle: string = title ==# '' ? NextRoleNumber(container.children, BI.ROLE_CHAPTER) : title
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterTitle, BI.ROLE_CHAPTER)
  var relPath: string = $'chapter-{Sl.Slugify(chapterTitle)}/scene-01.md'
  chapter.AddChild(BI.BinderItem.NewDocument('Scene 1', relPath))
  AddIntoContainer(container, row, chapter)
  return chapter
enddef

# FUNCTION: Create an empty Part folder in the Manuscript folder, as the
# Part 2 of templates.vim starts empty. An empty title becomes the next
# number among the sibling parts.
export def AddPart(manuscript: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var partTitle: string = title ==# '' ? NextRoleNumber(manuscript.children, BI.ROLE_PART) : title
  var part: BI.BinderItem = BI.BinderItem.NewFolder(partTitle, BI.ROLE_PART)
  AddIntoContainer(manuscript, row, part)
  return part
enddef

# FUNCTION: Return true for the folders that the user must never
# restructure or lose: Front Matter, Manuscript, Back Matter, Characters,
# and Research. dd on one of them clears its contents instead of removing
# it, see DeleteUnderCursor in binder.vim. Rename, indent, and outdent are
# refused.
export def IsImmutableFolder(item: BI.BinderItem): bool
  return item.structureRole ==# BI.ROLE_FRONT_MATTER
    || item.structureRole ==# BI.ROLE_MANUSCRIPT
    || item.structureRole ==# BI.ROLE_BACK_MATTER
    || item.structureRole ==# BI.ROLE_CHARACTERS
    || item.structureRole ==# BI.ROLE_RESEARCH
enddef

# FUNCTION: Return true when an item with role may be a child of parent,
# where null_object means the top level. ROLE_PART and ROLE_CHAPTER may
# be only under a ROLE_MANUSCRIPT folder, directly or inside a Part.
# ROLE_CUSTOM may be only at the top level. Other roles and all documents
# may be anywhere.
def RoleAllowedUnder(role: string, parent: BI.BinderItem): bool
  if role ==# BI.ROLE_PART || role ==# BI.ROLE_CHAPTER
    return parent isnot null_object
      && (parent.structureRole ==# BI.ROLE_MANUSCRIPT || parent.structureRole ==# BI.ROLE_PART)
  endif
  if role ==# BI.ROLE_CUSTOM
    return parent is null_object
  endif
  if role ==# BI.ROLE_FRONT_MATTER || role ==# BI.ROLE_MANUSCRIPT
      || role ==# BI.ROLE_BACK_MATTER || role ==# BI.ROLE_CHARACTERS
      || role ==# BI.ROLE_RESEARCH
    return parent is null_object
  endif
  return true
enddef

# FUNCTION: Insert newItem right after row: a top-level sibling when row
# is at the top level, else a sibling in the owner folder of row.
def InsertAfter(project: Pj.Project, row: T.Row, newItem: BI.BinderItem): void
  if row.ownerItem is null_object
    var idx: number = project.IndexOfItem(row.item.id)
    project.InsertItemAt(idx + 1, newItem)
  else
    var idx: number = row.ownerItem.IndexOfChild(row.item.id)
    row.ownerItem.InsertChildAt(idx + 1, newItem)
  endif
enddef

# FUNCTION: Add newItem next to row: as a child when row is a folder, else
# as the next sibling. row is null_object for an empty binder, or when
# there is no cursor row. Then newItem goes at the end of the top level.
export def AddNear(project: Pj.Project, row: T.Row, newItem: BI.BinderItem): void
  if row is null_object
    project.AddItem(newItem)
  elseif row.item.IsFolder()
    row.item.AddChild(newItem)
  else
    InsertAfter(project, row, newItem)
  endif
enddef

# FUNCTION: Remove the item of row from the tree. Its files stay on disk:
# removing from the binder does not delete work.
export def Remove(project: Pj.Project, row: T.Row): void
  if row.ownerItem is null_object
    project.RemoveItemAt(project.IndexOfItem(row.item.id))
  else
    row.ownerItem.RemoveChildAt(row.ownerItem.IndexOfChild(row.item.id))
  endif
enddef

# FUNCTION: Remove all children of item but keep item, for the five
# structural folders, where dd clears the contents. As with Remove, only
# the tree changes and files stay on disk.
export def ClearChildren(item: BI.BinderItem): void
  item.SetChildren([])
enddef

# FUNCTION: Swap the item of row with its next or previous sibling. delta
# is 1 to move down or -1 to move up. Returns false at the end of the
# list.
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

# FUNCTION: Move the item of row out of its owner folder, to right after
# that folder. Returns false when row is already at the top level.
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

# FUNCTION: Move the item of row into its previous sibling when that
# sibling is a folder. Returns false when there is no previous sibling
# or it is a document.
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
