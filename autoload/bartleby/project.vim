vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# project.vim: one scrive, a Bartleby writing project: its Binder tree
# and the loading and saving of project.json. No UI, and no knowledge of
# where scrives are on disk, see scrive.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/log.vim' as L
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))



# FUNCTION: Return each scrive type, as stored in project.json, to its
# name in the message language. CO.TYPES gives the order.
export def TypeNames(): dict<string>
  return {
    [CO.TYPE_NOVEL]: IN.T("Novel"),
    [CO.TYPE_NOVEL_PARTS]: IN.T("Novel with Parts"),
    [CO.TYPE_SHORT_STORY]: IN.T("Short Story"),
    [CO.TYPE_SCREENPLAY]: IN.T("Screenplay"),
  }
enddef

export class Project implements BI.ItemContainer
  # Absolute path of the .bartleby folder.
  var scriveDir: string
  var name: string = ''
  var projectType: string = CO.TYPE_NOVEL
  # The top-level binder items.
  var items: list<BI.BinderItem> = []

  def new(this.scriveDir)
  enddef

  # METHOD: Set the name and type of a new scrive, after construction and
  # before the first Save. A var field can be written only inside its
  # class, see Create in scrive.vim.
  def InitNew(newName: string, newType: string = CO.TYPE_NOVEL): void
    this.name = newName
    this.projectType = newType
  enddef

  # METHOD: Give a new, empty scrive its starter Binder tree. Called once,
  # after InitNew and before the first Save, for the same reason as InitNew.
  def SeedTree(newItems: list<BI.BinderItem>): void
    this.items = newItems
    this.EnsureTrash()
  enddef

  # METHOD: Add a top-level item, at the end but before the Trash, which
  # stays last. This and the next methods implement ItemContainer, see
  # binderitem.vim, for the top-level items, which have no owning folder.
  def AddChild(child: BI.BinderItem): void
    this.InsertChildAt(len(this.items), child)
  enddef

  # METHOD: Insert child at idx, but never after the Trash.
  def InsertChildAt(idx: number, child: BI.BinderItem): void
    var trashIdx: number = indexof(this.items, (_, item) => item.structureRole ==# CO.ROLE_TRASH)
    var at: number = trashIdx >= 0 && child.structureRole !=# CO.ROLE_TRASH
      ? min([idx, trashIdx]) : idx
    this.items->insert(child, at)
  enddef

  def RemoveChildAt(idx: number): void
    this.items->remove(idx)
  enddef

  def ChildAt(idx: number): BI.BinderItem
    return this.items[idx]
  enddef

  def ChildCount(): number
    return len(this.items)
  enddef

  def IndexOfChild(id: string): number
    for i in range(len(this.items))
      if this.items[i].id ==# id
        return i
      endif
    endfor
    return -1
  enddef

  def SwapChildren(i: number, j: number): void
    var tmp: BI.BinderItem = this.items[i]
    this.items[i] = this.items[j]
    this.items[j] = tmp
  enddef

  def BinderRoot(): string
    return this.scriveDir .. '/binder'
  enddef

  def ProjectFilePath(): string
    return this.scriveDir .. '/' .. CO.PROJECT_FILE
  enddef

  # METHOD: Return the document extension: .fountain for a screenplay, .md
  # for every other type.
  def DocExt(): string
    return this.projectType ==# CO.TYPE_SCREENPLAY ? '.fountain' : '.md'
  enddef

  def Load(): bool
    var path: string = this.ProjectFilePath()
    if !filereadable(path)
      log.Warn(printf(IN.T("project.json not found in %s"), this.scriveDir))
      return false
    endif
    var data: dict<any> = PE.ReadJson(path)
    this.name = get(data, 'name', fnamemodify(this.scriveDir, ':t:r'))
    this.projectType = get(data, 'projectType', CO.TYPE_NOVEL)
    var rawItems: list<dict<any>> = get(data, 'items', [])
    this.items = rawItems->mapnew((_, i) => BI.BinderItem.FromDict(i))
    this.EnsureTrash()
    return true
  enddef

  def Save(): void
    this.EnsureTrash()
    PE.WriteJson(this.ProjectFilePath(), {
      name: this.name,
      projectType: this.projectType,
      items: this.items->mapnew((_, i) => i.ToDict()),
    })
  enddef

  # METHOD: Return the Trash, the top level folder with ROLE_TRASH, or
  # null_object.
  def TrashFolder(): BI.BinderItem
    for item in this.items
      if item.structureRole ==# CO.ROLE_TRASH
        return item
      endif
    endfor
    return null_object
  enddef

  # METHOD: Make sure that the Trash exists and is the last folder at the
  # top level, whatever moved or was added after it. A scrive saved before
  # the Trash existed gets an empty one.
  def EnsureTrash(): void
    var trash: BI.BinderItem = this.TrashFolder()
    if trash is null_object
      trash = BI.BinderItem.NewFolder(IN.T("Trash"), CO.ROLE_TRASH)
    else
      this.items->filter((_, item) => item.id !=# trash.id)
    endif
    this.items->add(trash)
  enddef

  # METHOD: Find an item by id, depth first, or return null_object.
  def FindItem(id: string): BI.BinderItem
    def Walk(list: list<BI.BinderItem>): BI.BinderItem
      for item in list
        if item.id ==# id
          return item
        endif
        if item.IsFolder()
          var found: BI.BinderItem = Walk(item.children)
          if found isnot null_object
            return found
          endif
        endif
      endfor
      return null_object
    enddef
    return Walk(this.items)
  enddef

  # METHOD: Find a document by its absolute path, depth first. Return
  # null_object when the path is not a document of this scrive, as for a
  # buffer of another file.
  def FindItemByPath(path: string): BI.BinderItem
    var binderRoot: string = this.BinderRoot()
    def Walk(list: list<BI.BinderItem>): BI.BinderItem
      for item in list
        if item.IsDocument() && item.AbsPath(binderRoot) ==# path
          return item
        endif
        if item.IsFolder()
          var found: BI.BinderItem = Walk(item.children)
          if found isnot null_object
            return found
          endif
        endif
      endfor
      return null_object
    enddef
    return Walk(this.items)
  enddef
endclass
