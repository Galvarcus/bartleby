vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import.vim: brings files and folders from outside a scrive into it. Each
# file is copied into the binder folder and gets a document in the Binder,
# titled from the file name, and each folder gets a Binder folder that
# holds what was in it. The copy holds the bytes of the source and takes
# the document extension of the scrive, which Recover, Tidy, and Compile
# need to find it. The source stays where it is.
#
# An import runs in two steps. Plan works out what would come in, without
# changing anything, so that the caller can report the counts and ask
# first. Apply then adds it. A file that the scrive type does not accept,
# that cannot be read, or that is already in the scrive is skipped and
# counted, so that one file cannot stop an import.
#
# No UI and no saving: binder.vim asks, saves the project, and draws the
# Binder again, see ImportPaths there.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/locale/binder.vim' as MB
import 'bartleby/variables/constants.vim' as CO

# Between the parts of a report, and between the skipped names in it.
const SEP: string = ', '
# Each run of digits in a sort key is padded to this width, which holds
# every number that Vim can count, so that a plain compare of two keys
# gives the natural order.
const NUM_FMT: string = '%020d'

# FUNCTION: Return path absolute, with forward slashes and without a
# trailing one, so that two paths compare as strings on any system.
def Normalized(path: string): string
  return substitute(fnamemodify(path, ':p'), '\\', '/', 'g')
    ->substitute('/$', '', '')
enddef

# FUNCTION: Return the name of the folder at dir, without the trailing
# slash that ExpandPaths leaves on a folder.
def FolderName(dir: string): string
  return fnamemodify(substitute(dir, '[/\\]$', '', ''), ':t')
enddef

# FUNCTION: Return a sort key for name, with each run of digits padded,
# so that Chapter 2 comes before Chapter 10.
def SortKey(name: string): string
  return substitute(name, '\d\+', '\=printf(NUM_FMT, str2nr(submatch(0)))', 'g')
enddef

# FUNCTION: Return names in their natural order, see SortKey.
def Sorted(names: list<string>): list<string>
  return names
    ->mapnew((_, n) => [SortKey(n), n])
    ->sort((a, b) => a[0] ==# b[0] ? 0 : a[0] ># b[0] ? 1 : -1)
    ->mapnew((_, keyed) => keyed[1])
enddef

# FUNCTION: Return each path absolute, with its home directory and its
# wildcards expanded, in the order given. A path that matches nothing
# stays as it is, so that the import reports it by the name that the user
# gave.
export def ExpandPaths(paths: list<string>): list<string>
  var found: list<string> = []
  for path in paths
    # Nosuf, so that a wildignore of the user cannot drop a file that the
    # user named for the import.
    var matches: list<string> = glob(path, true, true)
    found += (empty(matches) ? [path] : matches)->mapnew((_, p) => fnamemodify(p, ':p'))
  endfor
  return found
enddef

# CLASS: One import into one scrive: the extensions that it accepts, what
# Plan found, the documents that Apply added, and the sources that it
# skipped.
export class Importer
  var project: PO.Project
  # The accepted extensions of the scrive type, lowercase.
  var exts: list<string>
  # What Plan found, in the order of the paths. Each entry is a document,
  # with its path, or a folder, with its item tree and the source file of
  # each document in it, by item id.
  var entries: list<dict<any>> = []
  # How many documents and folders Plan found, for the question that the
  # caller asks before Apply.
  var docs: number = 0
  var folders: number = 0
  var added: list<BI.BinderItem> = []
  var skipped: list<string> = []

  def new(this.project)
    this.exts = this.project.projectType ==# CO.TYPE_SCREENPLAY
      ? CO.IMPORT_EXTS_SCREENPLAY
      : CO.IMPORT_EXTS_TEXT
  enddef

  # METHOD: Return true when this scrive takes path: a readable file, with
  # an accepted extension, outside the scrive.
  def Accepts(path: string): bool
    return filereadable(path)
      && index(this.exts, '.' .. tolower(fnamemodify(path, ':e'))) >= 0
      && !this._Inside(path)
  enddef

  # METHOD: Work out what an import of paths would add, and change
  # nothing. A folder that holds no file that this scrive takes is
  # skipped, as a file of the wrong kind is.
  def Plan(paths: list<string>): void
    for path in paths
      if isdirectory(path)
        var scan: dict<any> = this._ScanFolder(path)
        if empty(scan)
          this.skipped->add(path)
          continue
        endif
        this.entries->add({kind: CO.KIND_FOLDER, item: scan.item, sources: scan.sources})
        this.docs += scan.docs
        this.folders += scan.folders
      elseif this.Accepts(path)
        this.entries->add({kind: CO.KIND_DOC, path: path})
        this.docs += 1
      else
        this.skipped->add(path)
      endif
    endfor
  enddef

  # METHOD: Add what Plan found next to row: into row when it is a folder,
  # else after it, where a new document goes. Each entry goes after the
  # one before it, so that the Binder keeps the order of the paths.
  def Apply(row: T.Row): void
    var anchor: T.Row = row
    for entry in this.entries
      var item: BI.BinderItem = entry.kind ==# CO.KIND_FOLDER
        ? this._AddTree(anchor, entry)
        : this._AddFile(anchor, entry.path)
      anchor = T.FindRowById(T.Flatten(this.project), item.id)
    endfor
  enddef

  # METHOD: Import each path, in the order given, next to row. Plan and
  # Apply in one call, for an import that needs no question first.
  def Files(row: T.Row, paths: list<string>): void
    this.Plan(paths)
    this.Apply(row)
  enddef

  # METHOD: Return what this import did, for its caller to report.
  def Report(): string
    var parts: list<string> = [MB.ImportedDoc(len(this.added))]
    if this.folders > 0
      parts->add(MB.FolderAdded(this.folders))
    endif
    if !empty(this.skipped)
      parts->add(MB.SkippedFile(len(this.skipped), join(this.skipped, SEP)))
    endif
    return join(parts, SEP)
  enddef

  # METHOD: Return the tree that an import of dir would add: its folder
  # item with everything inside it, the source file of each document by
  # item id, and how many documents and folders it holds. Names are taken
  # in their natural order, and a hidden name, a file that this scrive
  # does not take, and a folder that is a symbolic link, which could lead
  # back into the tree, are skipped. A folder that holds no document is
  # left out, and gives an empty dict.
  def _ScanFolder(dir: string): dict<any>
    var children: list<BI.BinderItem> = []
    var sources: dict<string> = {}
    var docs: number = 0
    var folders: number = 1
    for name in Sorted(readdir(dir))
      var path: string = $'{dir}/{name}'
      if name[0] ==# '.'
        continue
      endif
      if isdirectory(path)
        if getftype(path) ==# 'link'
          this.skipped->add(path)
          continue
        endif
        var sub: dict<any> = this._ScanFolder(path)
        if empty(sub)
          continue
        endif
        children->add(sub.item)
        sources->extend(sub.sources)
        docs += sub.docs
        folders += sub.folders
      elseif this.Accepts(path)
        var doc: BI.BinderItem = BI.BinderItem.NewDocument(fnamemodify(path, ':t:r'), '')
        children->add(doc)
        sources[doc.id] = path
        docs += 1
      else
        this.skipped->add(path)
      endif
    endfor
    if docs == 0
      return {}
    endif
    var item: BI.BinderItem = BI.BinderItem.NewFolder(FolderName(dir))
    item.SetChildren(children)
    return {item: item, sources: sources, docs: docs, folders: folders}
  enddef

  # METHOD: Add the scanned tree of entry next to row, and copy the file
  # of every document in it.
  def _AddTree(row: T.Row, entry: dict<any>): BI.BinderItem
    var root: BI.BinderItem = entry.item
    MU.AddNear(this.project, row, root)
    var inserted: T.Row = T.FindRowById(T.Flatten(this.project), root.id)
    # The roles come before the paths: layout.vim puts chapter- in front
    # of the folder name of a chapter.
    this._SetRoles(root, inserted.ownerItem)
    LY.Place(this.project, root)
    this._WriteDocs(root, entry.sources)
    return root
  enddef

  # METHOD: Give item, and every folder in it, its role from its parent,
  # top down, where null_object means the top level.
  def _SetRoles(item: BI.BinderItem, parent: BI.BinderItem): void
    var role: string = this._RoleUnder(parent)
    # The rules of the Binder have the last word, in case the two ever
    # disagree. A refused role becomes a plain folder.
    item.SetRole(MU.RoleAllowedUnder(role, parent) ? role : CO.ROLE_NONE)
    for child in item.children
      if child.IsFolder()
        this._SetRoles(child, item)
      endif
    endfor
  enddef

  # METHOD: Return the role of an imported folder whose parent is parent:
  # Custom at the top level, Part under the Manuscript of a novel with
  # parts, Chapter under the Manuscript of a novel or under a Part, and no
  # role anywhere else, which includes the Manuscript of a short story or
  # a screenplay, where the documents are not grouped in chapters.
  def _RoleUnder(parent: BI.BinderItem): string
    if parent is null_object
      return CO.ROLE_CUSTOM
    endif
    if parent.structureRole ==# CO.ROLE_MANUSCRIPT
      if this.project.projectType ==# CO.TYPE_NOVEL_PARTS
        return CO.ROLE_PART
      endif
      return this.project.projectType ==# CO.TYPE_NOVEL ? CO.ROLE_CHAPTER : CO.ROLE_NONE
    endif
    if parent.structureRole ==# CO.ROLE_PART
      return CO.ROLE_CHAPTER
    endif
    return CO.ROLE_NONE
  enddef

  # METHOD: Copy the file of every document in item, in the order of the
  # tree, so that added holds them in that order.
  def _WriteDocs(item: BI.BinderItem, sources: dict<string>): void
    for child in item.children
      if child.IsFolder()
        this._WriteDocs(child, sources)
      else
        this._WriteCopy(sources[child.id], child)
        this.added->add(child)
      endif
    endfor
  enddef

  # METHOD: Add a document for path next to row, and copy path into its
  # file. Accepts has checked path.
  def _AddFile(row: T.Row, path: string): BI.BinderItem
    var doc: BI.BinderItem = BI.BinderItem.NewDocument(fnamemodify(path, ':t:r'), '')
    MU.AddNear(this.project, row, doc)
    # The file follows the place of the document in the tree, as for a new
    # document, so that Tidy Files has nothing to move after an import.
    LY.Place(this.project, doc)
    this._WriteCopy(path, doc)
    this.added->add(doc)
    return doc
  enddef

  # METHOD: Copy src into the file of doc, its folder first. Binary both
  # ways, so that the copy keeps the line endings of the source and its
  # last line as it is.
  def _WriteCopy(src: string, doc: BI.BinderItem): void
    var dst: string = doc.AbsPath(this.project.BinderRoot())
    mkdir(fnamemodify(dst, ':h'), 'p')
    writefile(readfile(src, 'b'), dst, 'b')
  enddef

  # METHOD: Return true when path is already in the binder folder of this
  # scrive, where an import would copy a document onto itself.
  def _Inside(path: string): bool
    return stridx(Normalized(path), Normalized(this.project.BinderRoot()) .. '/') == 0
  enddef
endclass
