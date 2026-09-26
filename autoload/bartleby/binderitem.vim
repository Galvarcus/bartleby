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

import autoload 'bartleby/document.vim' as D

export const KIND_FOLDER: string = 'folder'
export const KIND_DOCUMENT: string = 'document'

# What a folder is in the structure, independent of its title. The role
# sets the Binder prefix, as in Chapter: title, which folders become
# chapter and part divisions in a compile, and where a folder may move.
# ROLE_PART and ROLE_CHAPTER exist only under ROLE_MANUSCRIPT, and
# ROLE_CUSTOM only at the top level. An empty role, the default, is a
# plain folder. Folders saved before roles existed load with an empty
# role, so old scrives still work.
export const ROLE_NONE: string = ''
export const ROLE_FRONT_MATTER: string = 'front-matter'
export const ROLE_MANUSCRIPT: string = 'manuscript'
export const ROLE_PART: string = 'part'
export const ROLE_CHAPTER: string = 'chapter'
export const ROLE_CHARACTERS: string = 'characters'
export const ROLE_RESEARCH: string = 'research'
export const ROLE_BACK_MATTER: string = 'back-matter'
export const ROLE_CUSTOM: string = 'custom'

const ROLE_LABELS: dict<string> = {part: 'Part', chapter: 'Chapter'}

# Ids are a timestamp and a counter: unique within one Vim session, not
# across machines or clocks.
var id_counter: number = 0

def NewId(): string
  id_counter += 1
  return printf('%s-%03d', strftime('%Y%m%d%H%M%S'), id_counter)
enddef

export class BinderItem
  var id: string
  var title: string
  var kind: string = KIND_FOLDER
  # Folders only, see the ROLE constants.
  var structureRole: string = ROLE_NONE
  # Documents only: the path under binder/.
  var relPath: string = ''
  # Folders only.
  var children: list<BinderItem> = []

  static def NewFolder(title: string, role: string = ROLE_NONE): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = NewId()
    item.title = title
    item.kind = KIND_FOLDER
    item.structureRole = role
    return item
  enddef

  static def NewDocument(title: string, relPath: string): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = NewId()
    item.title = title
    item.kind = KIND_DOCUMENT
    item.relPath = relPath
    return item
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
    return this.kind ==# KIND_FOLDER
  enddef

  def IsDocument(): bool
    return this.kind ==# KIND_DOCUMENT
  enddef

  # METHOD: Return the Chapter or Part prefix for roles that have one, or
  # an empty string for other folders and for documents.
  def DisplayLabel(): string
    var label: string = get(ROLE_LABELS, this.structureRole, '')
    return label ==# '' ? '' : $'{label}: '
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

  # METHOD: Return the word count: a document's own, read from disk, or the
  # sum of a folder's descendants. The file is read on every call, which is
  # fast enough for a scrive, as with LoadMeta.
  def WordCount(binderRoot: string): number
    if this.IsDocument()
      var path: string = this.AbsPath(binderRoot)
      if !filereadable(path)
        return 0
      endif
      return len(split(join(readfile(path), ' ')))
    endif
    var total: number = 0
    for child in this.children
      total += child.WordCount(binderRoot)
    endfor
    return total
  enddef

  static def FromDict(src: dict<any>): BinderItem
    var item: BinderItem = BinderItem.new()
    item.id = get(src, 'id', '')
    item.title = get(src, 'title', '(untitled)')
    item.kind = get(src, 'kind', KIND_FOLDER)
    item.structureRole = get(src, 'structureRole', ROLE_NONE)
    item.relPath = get(src, 'relPath', '')
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
    return result
  enddef
endclass
