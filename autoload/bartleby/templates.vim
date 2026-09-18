vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# templates.vim - default Binder tree per scrive type, plus the on-disk
# skeleton (folders + starter documents) that backs it. Used once, at
# scrive-creation time - see scrive.vim#Create.
#
# Chapter is a folder of scenes (not a single file) for Novel/Novel with
# Parts, so a chapter's compiled heading comes from its own explicit
# title (BinderItem.title), never from file content - see compile.vim's
# ConcatenateDocs. Every default folder carries a structureRole so the
# Binder can show "Chapter: "/"Part: " labels and so move/indent
# restrictions can enforce where each kind of folder is allowed to live.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/slug.vim' as Sl

# A chapter folder containing one starter scene. relPath nests under the
# chapter's own slug so multiple chapters' scene-01.md don't collide on
# disk. docExt only ever '.md' here - screenplays don't use this shape.
def ChapterWithScene(chapterNumber: string): BI.BinderItem
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterNumber, BI.ROLE_CHAPTER)
  var relPath: string = 'chapter-' .. chapterNumber .. '/scene-01.md'
  chapter.SetChildren([BI.BinderItem.NewDocument('Scene 1', relPath)])
  return chapter
enddef

# A folder with one starter document inside it - still used for shapes
# that are genuinely a single flat file (Short Story's draft, a
# Screenplay's scenes), not a chapter/scene hierarchy.
def FolderWithDoc(folderTitle: string, docTitle: string, docExt: string,
    role: string = BI.ROLE_NONE): BI.BinderItem
  var folder: BI.BinderItem = BI.BinderItem.NewFolder(folderTitle, role)
  var relPath: string = Sl.Slugify(folderTitle) .. '/' .. Sl.Slugify(docTitle) .. docExt
  folder.SetChildren([BI.BinderItem.NewDocument(docTitle, relPath)])
  return folder
enddef

# Empty for now - cover image, dedication, acknowledgements, etc. get added
# as documents once "New Document" (phase 2) exists. Included on every
# scrive type for now; drop it per-type later if some don't want it.
def FrontMatterFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder('Front Matter', BI.ROLE_FRONT_MATTER)
enddef

# Prologue, appendices, author's note, etc. - same "empty for now" story
# as Front Matter.
def BackMatterFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder('Back Matter', BI.ROLE_BACK_MATTER)
enddef

export def DefaultTree(projectType: string, docExt: string): list<BI.BinderItem>
  if projectType ==# Pj.TYPE_NOVEL
    var manuscript: BI.BinderItem = BI.BinderItem.NewFolder('Manuscript', BI.ROLE_MANUSCRIPT)
    manuscript.SetChildren([ChapterWithScene('1')])
    return [
      FrontMatterFolder(),
      manuscript,
      BackMatterFolder(),
      BI.BinderItem.NewFolder('Characters', BI.ROLE_CHARACTERS),
      BI.BinderItem.NewFolder('Research', BI.ROLE_RESEARCH),
    ]
  elseif projectType ==# Pj.TYPE_NOVEL_PARTS
    var part1: BI.BinderItem = BI.BinderItem.NewFolder('1', BI.ROLE_PART)
    part1.SetChildren([ChapterWithScene('1')])
    var part2: BI.BinderItem = BI.BinderItem.NewFolder('2', BI.ROLE_PART)
    var manuscript: BI.BinderItem = BI.BinderItem.NewFolder('Manuscript', BI.ROLE_MANUSCRIPT)
    manuscript.SetChildren([part1, part2])
    return [
      FrontMatterFolder(),
      manuscript,
      BackMatterFolder(),
      BI.BinderItem.NewFolder('Characters', BI.ROLE_CHARACTERS),
      BI.BinderItem.NewFolder('Research', BI.ROLE_RESEARCH),
    ]
  elseif projectType ==# Pj.TYPE_SHORT_STORY
    return [
      FrontMatterFolder(),
      FolderWithDoc('Manuscript', 'Draft', docExt, BI.ROLE_MANUSCRIPT),
      BI.BinderItem.NewFolder('Research', BI.ROLE_RESEARCH),
    ]
  elseif projectType ==# Pj.TYPE_SCREENPLAY
    return [
      FrontMatterFolder(),
      FolderWithDoc('Screenplay', 'Scene 1', docExt, BI.ROLE_MANUSCRIPT),
      BI.BinderItem.NewFolder('Characters', BI.ROLE_CHARACTERS),
      BI.BinderItem.NewFolder('Research', BI.ROLE_RESEARCH),
    ]
  else
    return []
  endif
enddef

# Touches an empty file for every document in `items` (mkdir -p'ing its
# parent folder first), so the tree DefaultTree() describes actually
# exists on disk - the Binder can't open a document that isn't there yet.
export def Materialize(items: list<BI.BinderItem>, binderRoot: string): void
  for item in items
    if item.IsFolder()
      Materialize(item.children, binderRoot)
    else
      var path: string = item.AbsPath(binderRoot)
      if !filereadable(path)
        mkdir(fnamemodify(path, ':h'), 'p')
        writefile([], path)
      endif
    endif
  endfor
enddef
