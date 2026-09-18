vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# binderitem.vim - one node of a scrive's Binder tree. Folders and documents
# share a single class, discriminated by `kind`, rather than subclassing -
# this keeps tree (de)serialization a flat, uniform operation and sidesteps
# relying on Vim9 class inheritance still settling between 9.1 and 9.2.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/document.vim' as D

export const KIND_FOLDER: string = 'folder'
export const KIND_DOCUMENT: string = 'document'

# What a folder IS structurally, independent of its title - drives the
# Binder's "Chapter: <title>" / "Part: <title>" display, compile-time
# structure (which folders become \chapter/\part boundaries), and the
# move/indent restrictions (ROLE_PART/ROLE_CHAPTER may only exist under
# a ROLE_MANUSCRIPT folder; ROLE_CUSTOM may only exist at the top level).
# '' (the default) means "plain organizational folder, no special
# treatment" - every folder from before this field existed reads back
# as '', so old scrives keep working unchanged.
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

# Timestamp + incrementing counter - unique enough for the items a single
# Vim session creates; not meant to survive across machines/clocks.
var id_counter: number = 0

def NewId(): string
  id_counter += 1
  return printf('%s-%03d', strftime('%Y%m%d%H%M%S'), id_counter)
enddef

export class BinderItem
  var id: string
  var title: string
  var kind: string = KIND_FOLDER
  var structureRole: string = ROLE_NONE # folder-only, see const block above
  var relPath: string = ''             # document-only: path under binder/
  var children: list<BinderItem> = []  # folder-only

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

  # Replaces this folder's children wholesale. Exists because plain `var`
  # fields are only writable from inside the class - same reasoning as
  # Project.InitNew()/SeedTree(). Used by templates.vim while building a
  # starter tree.
  def SetChildren(newChildren: list<BinderItem>): void
    this.children = newChildren
  enddef

  # Tree-surgery primitives used by mutate.vim. All mutate this.children
  # from inside the class, same reasoning as SetChildren() above.
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

  # "Chapter: " / "Part: " prefix for roles that want one; '' otherwise
  # (front-matter, characters, research, custom, or any document).
  def DisplayLabel(): string
    var label: string = get(ROLE_LABELS, this.structureRole, '')
    return label ==# '' ? '' : $'{label}: '
  enddef

  # Absolute path to this document's text file. '' for folders.
  def AbsPath(binderRoot: string): string
    return this.IsDocument() ? binderRoot .. '/' .. this.relPath : ''
  enddef

  # Absolute path to this document's metadata sidecar. '' for folders.
  def MetaPath(binderRoot: string): string
    return this.IsDocument() ? fnamemodify(this.AbsPath(binderRoot), ':r') .. '.meta.json' : ''
  enddef

  # Lazy load - folders and never-annotated documents get plain defaults.
  def LoadMeta(binderRoot: string): D.DocMeta
    return this.IsDocument() ? D.DocMeta.Load(this.MetaPath(binderRoot)) : D.DocMeta.new()
  enddef

  # A document's own word count read straight off disk; a folder's is the
  # sum of its descendants'. Re-reads the file every call - fine at
  # scrive-sized trees, same tradeoff already accepted for LoadMeta().
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
