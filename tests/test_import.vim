vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_import.vim: import.vim, with real files on disk. An import
# copies a file into the binder folder and adds a document for it, titled
# from the file name, with the path from the layout and the document
# extension of the scrive. It accepts Markdown and plain text in every
# scrive type, and Fountain in a screenplay. It skips a file that it does
# not accept, one that it cannot read, and one that is already in the
# scrive, and counts each skip in the report.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/import.vim' as IM
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# The folder of the sources of one test, under its own temporary name, so
# that two tests cannot see each other's files.
var sources: string = ''

# FUNCTION: Write lines to name in a new sources folder, and return its
# path. The caller removes the folder with CleanupSources.
def Source(name: string, lines: list<string> = ['Text.']): string
  if sources ==# ''
    sources = tempname() .. '/sources'
    mkdir(sources, 'p')
  endif
  var path: string = $'{sources}/{name}'
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
  return path
enddef

# FUNCTION: Write lines to name in binary, for a source whose bytes a
# text write would change.
def SourceRaw(name: string, lines: list<string>): string
  var path: string = Source(name)
  writefile(lines, path, 'b')
  return path
enddef

def CleanupSources(): void
  if sources !=# ''
    delete(fnamemodify(sources, ':h'), 'rf')
    sources = ''
  endif
enddef

# FUNCTION: Return the row of the item with id in project, for the target
# of an import.
def RowOf(project: any, id: string): T.Row
  return T.FindRowById(T.Flatten(project), id)
enddef

# FUNCTION: Return a Novel fixture whose folder is its own temporary one,
# so that a test writes no file of another test.
def NovelProject(): any
  var project = FI.BuildProject()
  var moved = PO.Project.new(tempname() .. '/Novel.bartleby')
  moved.InitNew('Novel', CO.TYPE_NOVEL)
  moved.SeedTree(project.items)
  return moved
enddef

# FUNCTION: Return a Screenplay with one Manuscript folder, named
# Screenplay as templates.vim names it.
def ScreenplayProject(): any
  var project = PO.Project.new(tempname() .. '/Play.bartleby')
  project.InitNew('Play', CO.TYPE_SCREENPLAY)
  project.SeedTree([BI.BinderItem.NewFolder('Screenplay', CO.ROLE_MANUSCRIPT)])
  return project
enddef

def Titles(folder: any): list<string>
  return folder.children->mapnew((_, item) => item.title)
enddef

def Test_import_titles_a_document_from_the_file_name(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var path: string = Source('Arrival.md', ['The train was late.'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [path])

  assert_equal(1, len(importer.added))
  assert_equal([], importer.skipped)
  assert_equal(['Scene 1', 'Arrival'], Titles(chapter))
  var doc = importer.added[0]
  assert_equal('manuscript/chapter-1/arrival.md', doc.relPath)
  assert_equal(['The train was late.'], readfile(doc.AbsPath(project.BinderRoot())))
  # The source stays where it is.
  assert_true(filereadable(path))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_keeps_the_order_of_the_paths(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var paths: list<string> = ['One.md', 'Two.md', 'Three.md']->mapnew((_, n) => Source(n))
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), paths)

  assert_equal(['Scene 1', 'One', 'Two', 'Three'], Titles(chapter))
  assert_equal(['manuscript/chapter-1/one.md', 'manuscript/chapter-1/two.md',
    'manuscript/chapter-1/three.md'],
    importer.added->mapnew((_, d) => d.relPath))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_after_a_document_goes_next_to_it(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  chapter.AddChild(BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md'))
  var scene1 = chapter.ChildAt(0)
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, scene1.id), [Source('One.md'), Source('Two.md')])

  assert_equal(['Scene 1', 'One', 'Two', 'Scene 2'], Titles(chapter))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_at_the_top_level_stays_before_the_trash(): void
  var project = NovelProject()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [Source('Notes.md')])

  assert_equal('Notes', project.ChildAt(project.ChildCount() - 2).title)
  assert_equal(CO.ROLE_TRASH, project.ChildAt(project.ChildCount() - 1).structureRole)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_gives_the_copy_the_extension_of_the_scrive(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [Source('Plain.txt'), Source('Other.markdown')])
  assert_equal(['manuscript/chapter-1/plain.md', 'manuscript/chapter-1/other.md'],
    importer.added->mapnew((_, d) => d.relPath))
  FI.CleanupProjectFiles(project)

  var play = ScreenplayProject()
  var folder = play.ChildAt(0)
  var playImporter = IM.Importer.new(play)
  playImporter.Files(RowOf(play, folder.id), [Source('Scene.md'), Source('Open.fountain')])
  assert_equal(['screenplay/scene.fountain', 'screenplay/open.fountain'],
    playImporter.added->mapnew((_, d) => d.relPath))
  CleanupSources()
  FI.CleanupProjectFiles(play)
enddef

def Test_a_novel_refuses_fountain_and_a_screenplay_takes_it(): void
  var project = NovelProject()
  var path: string = Source('Open.fountain', ['INT. ROOM - DAY'])
  var importer = IM.Importer.new(project)
  assert_false(importer.Accepts(path))
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id), [path])
  assert_equal([], importer.added)
  assert_equal([path], importer.skipped)
  FI.CleanupProjectFiles(project)

  var play = ScreenplayProject()
  assert_true(IM.Importer.new(play).Accepts(path))
  CleanupSources()
  FI.CleanupProjectFiles(play)
enddef

def Test_import_skips_what_it_cannot_take(): void
  var project = NovelProject()
  var image: string = Source('Cover.png')
  var missing: string = $'{sources}/Gone.md'
  var noExt: string = Source('Readme')
  # A document of the scrive itself, which an import must not copy onto.
  var inside: string = project.BinderRoot() .. '/chapter-1/scene-01.md'
  mkdir(fnamemodify(inside, ':h'), 'p')
  writefile(['Text.'], inside)

  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id),
    [image, missing, noExt, inside])
  assert_equal([], importer.added)
  assert_equal([image, missing, noExt, inside], importer.skipped)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_keeps_the_bytes_of_the_source(): void
  var project = NovelProject()
  # No newline at the end, and a CR in the text, which a text copy would
  # change.
  var path: string = SourceRaw('Raw.md', ["One\r", 'Two'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id), [path])

  assert_equal(readfile(path, 'b'),
    readfile(importer.added[0].AbsPath(project.BinderRoot()), 'b'))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_two_sources_of_one_name_get_their_own_files(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var first: string = Source('a/Arrival.md', ['First.'])
  var second: string = Source('b/Arrival.md', ['Second.'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [first, second])

  assert_equal(['manuscript/chapter-1/arrival.md', 'manuscript/chapter-1/arrival-2.md'],
    importer.added->mapnew((_, d) => d.relPath))
  assert_equal(['Second.'],
    readfile(importer.added[1].AbsPath(project.BinderRoot())))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_report_counts_what_came_in_and_what_was_skipped(): void
  var project = NovelProject()
  var row: T.Row = RowOf(project, project.ChildAt(1).ChildAt(0).id)
  var importer = IM.Importer.new(project)
  importer.Files(row, [Source('One.md')])
  assert_equal('imported 1 document', importer.Report())

  var second = IM.Importer.new(project)
  var image: string = Source('Cover.png')
  second.Files(row, [Source('Two.md'), Source('Three.md'), image])
  assert_equal($'imported 2 documents, skipped 1 file: {image}', second.Report())
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_expand_paths_takes_wildcards_and_keeps_an_unmatched_path(): void
  var first: string = Source('globbed/One.md')
  var second: string = Source('globbed/Two.md')
  var missing: string = $'{sources}/globbed/Gone.md'
  assert_equal([first, second], IM.ExpandPaths([$'{sources}/globbed/*.md']))
  assert_equal([missing], IM.ExpandPaths([missing]))
  # A relative path becomes absolute, so that the import finds it from any
  # working directory.
  assert_equal([fnamemodify('rel.md', ':p')], IM.ExpandPaths(['rel.md']))
  CleanupSources()
enddef

export def RunAll(): void
  Test_import_titles_a_document_from_the_file_name()
  Test_import_keeps_the_order_of_the_paths()
  Test_import_after_a_document_goes_next_to_it()
  Test_import_at_the_top_level_stays_before_the_trash()
  Test_import_gives_the_copy_the_extension_of_the_scrive()
  Test_a_novel_refuses_fountain_and_a_screenplay_takes_it()
  Test_import_skips_what_it_cannot_take()
  Test_import_keeps_the_bytes_of_the_source()
  Test_two_sources_of_one_name_get_their_own_files()
  Test_the_report_counts_what_came_in_and_what_was_skipped()
  Test_expand_paths_takes_wildcards_and_keeps_an_unmatched_path()
enddef
