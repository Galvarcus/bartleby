vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# templates.vim: the starter Binder tree for each scrive type, and the
# folders and documents on disk behind it. Used once, when a scrive is
# created, see Create in scrive.vim.
#
# In a Novel or a Novel with Parts, a chapter is a folder of scenes, not
# one file, so its compiled heading comes from the folder title, never
# from file content, see ConcatenateManuscript in compile.vim. Every
# starter folder has a structureRole, so that the Binder shows Chapter
# and Part prefixes and folders move only where their role allows.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/slug.vim' as Sl

# FUNCTION: Return a chapter folder with one starter scene. relPath is in
# the chapter's own slug folder, so the scene files of different
# chapters do not collide on disk. docExt is always .md here, because
# screenplays do not use chapters.
def ChapterWithScene(chapterNumber: string): BI.BinderItem
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterNumber, BI.ROLE_CHAPTER)
  var relPath: string = 'chapter-' .. chapterNumber .. '/scene-01.md'
  chapter.SetChildren([BI.BinderItem.NewDocument('Scene 1', relPath)])
  return chapter
enddef

# FUNCTION: Return a folder with one starter document, for types that are
# a single flat file, such as the draft of a Short Story or the scenes of
# a Screenplay.
def FolderWithDoc(folderTitle: string, docTitle: string, docExt: string,
    role: string = BI.ROLE_NONE): BI.BinderItem
  var folder: BI.BinderItem = BI.BinderItem.NewFolder(folderTitle, role)
  var relPath: string = Sl.Slugify(folderTitle) .. '/' .. Sl.Slugify(docTitle) .. docExt
  folder.SetChildren([BI.BinderItem.NewDocument(docTitle, relPath)])
  return folder
enddef

# FUNCTION: Return the Front Matter folder. It starts empty. Add a
# dedication, acknowledgments, and similar pages as documents.
def FrontMatterFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder('Front Matter', BI.ROLE_FRONT_MATTER)
enddef

# FUNCTION: Return the Back Matter folder. It starts empty, like Front
# Matter, for pages such as an appendix or an author's note.
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

# FUNCTION: Create an empty file for every document in items, and its
# folder first, so that the tree from DefaultTree exists on disk. The
# Binder cannot open a document that does not exist.
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
