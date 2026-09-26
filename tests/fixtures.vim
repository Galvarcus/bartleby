vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/fixtures.vim: shared test data, built in memory. BuildProject uses
# InitNew, SeedTree, and AddChild, the construction API that
# templates.vim uses, instead of reading a JSON fixture from disk. This
# keeps Tier 1 tests free of the filesystem, and the fixture stays
# readable Vim9 code instead of JSON that must be kept in step by hand.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj

# FUNCTION: Return a Novel project with the five structural folders, and
# a Manuscript with 2 chapters of 1 scene each: enough to test nesting,
# owners, and sibling order, and no larger.
export def BuildProject(): Pj.Project
  var project = Pj.Project.new('/tmp/bartleby-test-fixture.bartleby')
  project.InitNew('Fixture Project', Pj.TYPE_NOVEL)

  var frontMatter = BI.BinderItem.NewFolder('Front Matter', BI.ROLE_FRONT_MATTER)
  var manuscript = BI.BinderItem.NewFolder('Manuscript', BI.ROLE_MANUSCRIPT)
  var backMatter = BI.BinderItem.NewFolder('Back Matter', BI.ROLE_BACK_MATTER)
  var characters = BI.BinderItem.NewFolder('Characters', BI.ROLE_CHARACTERS)
  var research = BI.BinderItem.NewFolder('Research', BI.ROLE_RESEARCH)

  var chapter1 = BI.BinderItem.NewFolder('1', BI.ROLE_CHAPTER)
  chapter1.AddChild(BI.BinderItem.NewDocument('Scene 1', 'chapter-1/scene-01.md'))
  var chapter2 = BI.BinderItem.NewFolder('2', BI.ROLE_CHAPTER)
  chapter2.AddChild(BI.BinderItem.NewDocument('Scene 1', 'chapter-2/scene-01.md'))
  manuscript.AddChild(chapter1)
  manuscript.AddChild(chapter2)

  project.SeedTree([frontMatter, manuscript, backMatter, characters, research])
  return project
enddef

# FUNCTION: Write lines to the real file of item under the binder root of
# project, for tests of code that reads document text from disk, such as
# ReadDocLines in compile.vim. Creates the folder when relPath has one,
# as in chapter-1/scene-01.md. The caller cleans up, see
# CleanupProjectFiles.
export def WriteDocContent(project: Pj.Project, item: BI.BinderItem, lines: list<string>): void
  var path = item.AbsPath(project.BinderRoot())
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
enddef

# FUNCTION: Remove the whole folder of a fixture project on disk, its
# binder root and everything in it. Call it at the end of every test that
# used WriteDocContent.
export def CleanupProjectFiles(project: Pj.Project): void
  delete(project.scriveDir, 'rf')
enddef
