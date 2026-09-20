vim9script
# tests/fixtures.vim - shared, in-memory test data. No file I/O: builds a
# Project entirely via InitNew()/SeedTree()/AddChild(), the same public
# construction API templates.vim itself uses, rather than reading a JSON
# fixture from disk - keeps Tier 1 tests (see testing_feasibility_report.md)
# genuinely free of the filesystem, and keeps the fixture readable as plain
# Vim9 rather than a JSON blob to keep in sync by hand.

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj

# A Novel-type project with the standard 5 structural folders, and a
# Manuscript containing 2 Chapters, each with 1 Scene - enough shape to
# exercise nesting, ownership, and sibling ordering without being any
# larger than tests actually need.
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

# Writes `lines` to `item`'s real file under `project`'s binder root, for
# tests exercising code that actually reads document content from disk
# (compile.vim's ReadDocLines(), notably). Creates the containing
# directory if the fixture's relPath nests one (e.g. "chapter-1/...").
# Callers are responsible for cleanup - see CleanupProjectFiles().
export def WriteDocContent(project: Pj.Project, item: BI.BinderItem, lines: list<string>): void
  var path = item.AbsPath(project.BinderRoot())
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
enddef

# Removes a fixture project's entire on-disk directory (its binder root
# and everything under it) - call in a test's cleanup step whenever
# WriteDocContent() was used.
export def CleanupProjectFiles(project: Pj.Project): void
  delete(project.scriveDir, 'rf')
enddef
