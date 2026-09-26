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

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as Pe
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

export const PROJECT_FILE: string = 'project.json'

export const TYPE_NOVEL: string = 'novel'
export const TYPE_NOVEL_PARTS: string = 'novel_parts'
export const TYPE_SHORT_STORY: string = 'short_story'
export const TYPE_SCREENPLAY: string = 'screenplay'

export class Project
  # Absolute path of the .bartleby folder.
  var scriveDir: string
  var name: string = ''
  var projectType: string = TYPE_NOVEL
  # The top-level binder items.
  var items: list<BI.BinderItem> = []

  def new(this.scriveDir)
  enddef

  # METHOD: Set the name and type of a new scrive, after construction and
  # before the first Save. A var field can be written only inside its
  # class, see Create in scrive.vim.
  def InitNew(newName: string, newType: string = TYPE_NOVEL): void
    this.name = newName
    this.projectType = newType
  enddef

  # METHOD: Give a new, empty scrive its starter Binder tree. Called once,
  # after InitNew and before the first Save, for the same reason as InitNew.
  def SeedTree(newItems: list<BI.BinderItem>): void
    this.items = newItems
  enddef

  # METHOD: Add a top-level item. The top-level items have no owning
  # BinderItem, so Project repeats the child methods of BinderItem for
  # them.
  #
  # REVIEW: A shared interface for Project and BinderItem would remove this
  # repetition.
  def AddItem(item: BI.BinderItem): void
    this.items->add(item)
  enddef

  def InsertItemAt(idx: number, item: BI.BinderItem): void
    this.items->insert(item, idx)
  enddef

  def RemoveItemAt(idx: number): void
    this.items->remove(idx)
  enddef

  def ItemAt(idx: number): BI.BinderItem
    return this.items[idx]
  enddef

  def ItemCount(): number
    return len(this.items)
  enddef

  def IndexOfItem(id: string): number
    for i in range(len(this.items))
      if this.items[i].id ==# id
        return i
      endif
    endfor
    return -1
  enddef

  def SwapItems(i: number, j: number): void
    var tmp: BI.BinderItem = this.items[i]
    this.items[i] = this.items[j]
    this.items[j] = tmp
  enddef

  def BinderRoot(): string
    return this.scriveDir .. '/binder'
  enddef

  def ProjectFilePath(): string
    return this.scriveDir .. '/' .. PROJECT_FILE
  enddef

  # METHOD: Return the document extension: .fountain for a screenplay, .md
  # for every other type.
  def DocExt(): string
    return this.projectType ==# TYPE_SCREENPLAY ? '.fountain' : '.md'
  enddef

  def Load(): bool
    var path: string = this.ProjectFilePath()
    if !filereadable(path)
      log.Warn($'project.json not found in {this.scriveDir}')
      return false
    endif
    var data: dict<any> = Pe.ReadJson(path)
    this.name = get(data, 'name', fnamemodify(this.scriveDir, ':t:r'))
    this.projectType = get(data, 'projectType', TYPE_NOVEL)
    var rawItems: list<dict<any>> = get(data, 'items', [])
    this.items = rawItems->mapnew((_, i) => BI.BinderItem.FromDict(i))
    return true
  enddef

  def Save(): void
    Pe.WriteJson(this.ProjectFilePath(), {
      name: this.name,
      projectType: this.projectType,
      items: this.items->mapnew((_, i) => i.ToDict()),
    })
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
