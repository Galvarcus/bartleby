vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# project.vim - a single scrive (Bartleby writing project): its root Binder
# tree plus project.json load/save. Owns no UI and no path-resolution
# knowledge about where scrives live on disk - see scrive.vim for that.
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
  var scriveDir: string                     # absolute path to the *.bartleby dir
  var name: string = ''
  var projectType: string = TYPE_NOVEL
  var items: list<BI.BinderItem> = []       # root-level binder items

  def new(this.scriveDir)
  enddef

  # Sets name/type on a brand-new scrive, right after construction and
  # before the first Save(). Exists because plain `var` fields are only
  # writable from inside the class - see scrive.vim#Create.
  def InitNew(newName: string, newType: string = TYPE_NOVEL): void
    this.name = newName
    this.projectType = newType
  enddef

  # Seeds a brand-new (empty) scrive with a starter Binder tree. Called
  # once, right after InitNew(), before the first Save() - same
  # not-writable-from-outside reason as InitNew() above.
  def SeedTree(newItems: list<BI.BinderItem>): void
    this.items = newItems
  enddef

  # Root-level counterparts to BinderItem's Child* methods - a scrive's own
  # top-level items have no owning BinderItem, so Project mirrors that API
  # for them. Some duplication vs. BinderItem; fine until 9.2 confirms
  # whether a shared interface is worth introducing here.
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

  # Screenplays are Fountain; every other scrive type is Markdown.
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

  # Depth-first search across the whole tree by id. null_object if absent.
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

  # Depth-first search across the whole tree by on-disk path (already
  # absolute). null_object if the path isn't one of this scrive's own
  # documents - e.g. the buffer belongs to some other file entirely.
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
