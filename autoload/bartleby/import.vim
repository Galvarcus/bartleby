vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import.vim: brings files from outside a scrive into it. Each file is
# copied into the binder folder and gets a document in the Binder, titled
# from the file name. The copy holds the bytes of the source and takes the
# document extension of the scrive, which Recover, Tidy, and Compile need
# to find it. The source file stays where it is.
#
# A file that the scrive type does not accept, that cannot be read, or
# that is already in the scrive is skipped and counted, so that one file
# cannot stop an import. No UI and no saving: binder.vim saves the project
# and draws the Binder again, see ImportPaths there.
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

# FUNCTION: Return path absolute, with forward slashes and without a
# trailing one, so that two paths compare as strings on any system.
def Normalized(path: string): string
  return substitute(fnamemodify(path, ':p'), '\\', '/', 'g')
    ->substitute('/$', '', '')
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

# CLASS: One import into one scrive: the extensions that it accepts, the
# documents that it added, and the sources that it skipped.
export class Importer
  var project: PO.Project
  # The accepted extensions of the scrive type, lowercase.
  var exts: list<string>
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

  # METHOD: Import each path, in the order given, next to row: into row
  # when it is a folder, else after it, where a new document goes. Each
  # document after the first goes after the one before it, so that the
  # Binder keeps the order of the paths.
  def Files(row: T.Row, paths: list<string>): void
    var anchor: T.Row = row
    for path in paths
      if !this.Accepts(path)
        this.skipped->add(path)
        continue
      endif
      var doc: BI.BinderItem = this._AddFile(anchor, path)
      anchor = T.FindRowById(T.Flatten(this.project), doc.id)
    endfor
  enddef

  # METHOD: Return what this import did, for its caller to report.
  def Report(): string
    var msg: string = MB.ImportedDoc(len(this.added))
    if empty(this.skipped)
      return msg
    endif
    return msg .. SEP .. MB.SkippedFile(len(this.skipped), join(this.skipped, SEP))
  enddef

  # METHOD: Add a document for path next to row, and copy the bytes of
  # path into its file. Accepts has checked path.
  def _AddFile(row: T.Row, path: string): BI.BinderItem
    var doc: BI.BinderItem = BI.BinderItem.NewDocument(fnamemodify(path, ':t:r'), '')
    MU.AddNear(this.project, row, doc)
    # The file follows the place of the document in the tree, as for a new
    # document, so that Tidy Files has nothing to move after an import.
    LY.Place(this.project, doc)
    var dst: string = doc.AbsPath(this.project.BinderRoot())
    mkdir(fnamemodify(dst, ':h'), 'p')
    # Binary both ways, so that the copy keeps the line endings of the
    # source and its last line as it is.
    writefile(readfile(path, 'b'), dst, 'b')
    this.added->add(doc)
    return doc
  enddef

  # METHOD: Return true when path is already in the binder folder of this
  # scrive, where an import would copy a document onto itself.
  def _Inside(path: string): bool
    return stridx(Normalized(path), Normalized(this.project.BinderRoot()) .. '/') == 0
  enddef
endclass
