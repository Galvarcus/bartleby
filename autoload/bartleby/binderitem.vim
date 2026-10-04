vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# binderitem.vim: one node of a scrive's Binder tree. Folders and
# documents share one class, told apart by kind, instead of subclasses.
# This keeps saving and loading the tree simple and uniform, and does
# not depend on Vim9 class inheritance, which changed between 9.1 and
# 9.2.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/document.vim' as D
import 'bartleby/variables/constants.vim' as CO



# Ids are a timestamp and a counter: unique within one Vim session, not
# across machines or clocks.
var id_counter: number = 0

def NewId(): string
  id_counter += 1
  return printf('%s-%03d', strftime('%Y%m%d%H%M%S'), id_counter)
enddef

# INTERFACE: A list of binder items that can be changed in place: the
# children of a folder, or the top-level items of a scrive. BinderItem and
# Project implement it, so code that changes the tree, see mutate.vim,
# has one code path for both. The owner of a top-level row is the
# Project, and of any other row its folder.
#
# An item is typed any here, not BinderItem: Vim9 resolves a signature
# when it is defined, and this interface must come before BinderItem,
# which implements it. Each class declares the exact type in its own
# methods, so a wrong type is still rejected when the method runs.
export interface ItemContainer
  def AddChild(child: any): void
  def InsertChildAt(idx: number, child: any): void
  def RemoveChildAt(idx: number): void
  def ChildAt(idx: number): any
  def ChildCount(): number
  def IndexOfChild(id: string): number
  def SwapChildren(i: number, j: number): void
endinterface

# FUNCTION: Return the Binder prefix of each role that has one, in the
# message language, as in Chapter: title. The roles are in constants.vim.
# A role also sets which folders become chapter and part divisions in a
# compile, and where a folder may move. A folder saved before roles
# existed loads with an empty role, a plain folder, so old scrives still
# work. syntax/bartleby-binder.vim matches these prefixes.
export def RolePrefixes(): dict<string>
  return {[CO.ROLE_PART]: IN.T("Part: "), [CO.ROLE_CHAPTER]: IN.T("Chapter: ")}
enddef

export class BinderItem implements ItemContainer
  var id: string
  var title: string
  var kind: string = CO.KIND_FOLDER
  # Folders only, see the ROLE constants in constants.vim.
  var structureRole: string = CO.ROLE_NONE
  # Documents only: the path under binder/.
  var relPath: string = ''
  # Folders only.
  var children: list<BinderItem> = []
  # Where an item directly in the Trash came from, for Restore in
  # trash.vim: the id of its folder, empty for the top level, and its index
  # there. trashIndex is -1 for every other item.
  var trashOrigin: string = ''
  var trashIndex: number = -1

  static def NewFolder(title: string, role: string = CO.ROLE_NONE): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = NewId()
    item.title = title
    item.kind = CO.KIND_FOLDER
    item.structureRole = role
    return item
  enddef

  static def NewDocument(title: string, relPath: string): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = NewId()
    item.title = title
    item.kind = CO.KIND_DOCUMENT
    item.relPath = relPath
    return item
  enddef

  # METHOD: Remember where an item in the Trash came from: the id of its
  # folder, empty for the top level, and its index there.
  def MarkTrashed(origin: string, index: number): void
    this.trashOrigin = origin
    this.trashIndex = index
  enddef

  # METHOD: Forget where the item came from, once it leaves the Trash.
  def ClearTrashOrigin(): void
    this.trashOrigin = ''
    this.trashIndex = -1
  enddef

  # METHOD: Replace all children of this folder. A var field can be written
  # only inside its class, as with Project.InitNew and SeedTree.
  # templates.vim uses this to build a starter tree.
  def SetChildren(newChildren: list<BinderItem>): void
    this.children = newChildren
  enddef

  # METHOD: Add a child. This and the next methods change the tree for
  # mutate.vim. They change this.children inside the class, as SetChildren
  # does.
  def AddChild(child: BinderItem): void
    this.children->add(child)
  enddef

  def InsertChildAt(idx: number, child: BinderItem): void
    this.children->insert(child, idx)
  enddef

  def RemoveChildAt(idx: number): void
    this.children->remove(idx)
  enddef

  def ChildAt(idx: number): BinderItem
    return this.children[idx]
  enddef

  def ChildCount(): number
    return len(this.children)
  enddef

  def IndexOfChild(id: string): number
    for i in range(len(this.children))
      if this.children[i].id ==# id
        return i
      endif
    endfor
    return -1
  enddef

  def SwapChildren(i: number, j: number): void
    var tmp: BinderItem = this.children[i]
    this.children[i] = this.children[j]
    this.children[j] = tmp
  enddef

  def Rename(newTitle: string): void
    this.title = newTitle
  enddef

  def IsFolder(): bool
    return this.kind ==# CO.KIND_FOLDER
  enddef

  def IsDocument(): bool
    return this.kind ==# CO.KIND_DOCUMENT
  enddef

  # METHOD: Return the Chapter or Part prefix for roles that have one, or
  # an empty string for other folders and for documents.
  def DisplayLabel(): string
    return get(RolePrefixes(), this.structureRole, '')
  enddef

  # METHOD: Return the absolute path of this document's text file, or an
  # empty string for a folder.
  def AbsPath(binderRoot: string): string
    return this.IsDocument() ? binderRoot .. '/' .. this.relPath : ''
  enddef

  # METHOD: Return the absolute path of this document's metadata file, or
  # an empty string for a folder.
  def MetaPath(binderRoot: string): string
    return this.IsDocument() ? fnamemodify(this.AbsPath(binderRoot), ':r') .. '.meta.json' : ''
  enddef

  # METHOD: Load the metadata when needed. Folders, and documents without
  # metadata, get the defaults.
  def LoadMeta(binderRoot: string): D.DocMeta
    return this.IsDocument() ? D.DocMeta.Load(this.MetaPath(binderRoot)) : D.DocMeta.new()
  enddef

  static def FromDict(src: dict<any>): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = get(src, 'id', '')
    item.title = get(src, 'title', '(untitled)')
    item.kind = get(src, 'kind', CO.KIND_FOLDER)
    item.structureRole = get(src, 'structureRole', CO.ROLE_NONE)
    item.relPath = get(src, 'relPath', '')
    item.trashOrigin = get(src, 'trashOrigin', '')
    item.trashIndex = get(src, 'trashIndex', -1)
    var rawChildren: list<dict<any>> = get(src, 'children', [])
    item.children = rawChildren->mapnew((_, c) => BinderItem.FromDict(c))
    return item
  enddef

  def ToDict(): dict<any>
    var result: dict<any> = {id: this.id, title: this.title, kind: this.kind}
    if this.IsDocument()
      result.relPath = this.relPath
    else
      result.structureRole = this.structureRole
      result.children = this.children->mapnew((_, c) => c.ToDict())
    endif
    if this.trashIndex >= 0
      result.trashOrigin = this.trashOrigin
      result.trashIndex = this.trashIndex
    endif
    return result
  enddef
endclass
