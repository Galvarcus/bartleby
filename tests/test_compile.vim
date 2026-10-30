vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_compile.vim: the Concatenate functions of compile.vim, the
# exported entry points. WalkManuscript, WalkBook, WalkFrontOrBackMatter,
# JoinSiblingBlocks, and the other helpers are local to the script and
# reached through them. Needs real files on disk, because ReadDocLines
# reads them, so each test writes fixture text under the binder root of
# the project and removes it with FI.CleanupProjectFiles.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as FI
import 'Logger/messages.vim' as LM
import './test_texcheck.vim' as TTX

# FUNCTION: Build the shared fixture project, add one document each to
# Front Matter and Back Matter, which the fixture leaves empty, and write
# real text for every document. The caller must call
# FI.CleanupProjectFiles on the project.
def BuildProjectWithContent(): dict<any>
  var project = FI.BuildProject()
  var frontMatter = project.ChildAt(0)
  var manuscript = project.ChildAt(1)
  var backMatter = project.ChildAt(2)

  var dedication = BI.BinderItem.NewDocument('Dedication', 'front-matter/dedication.md')
  frontMatter.AddChild(dedication)
  var acknowledgments = BI.BinderItem.NewDocument('Acknowledgments', 'back-matter/acknowledgments.md')
  backMatter.AddChild(acknowledgments)

  var chapter1 = manuscript.ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  var scene2 = chapter2.ChildAt(0)

  FI.WriteDocContent(project, dedication, ['For my family.'])
  FI.WriteDocContent(project, scene1, ['It was a dark and stormy night.'])
  FI.WriteDocContent(project, scene2, ['The end was near.'])
  FI.WriteDocContent(project, acknowledgments, ['Thanks to everyone.'])

  return {project: project, dedication: dedication, scene1: scene1,
    scene2: scene2, acknowledgments: acknowledgments}
enddef

def AllDocIds(fx: dict<any>): list<string>
  return [fx.dedication.id, fx.scene1.id, fx.scene2.id, fx.acknowledgments.id]
enddef

# The engines compile to a slug, because a TeX engine is unreliable with
# a path outside ASCII, and the artifact is renamed once the run has
# succeeded.
def Test_an_output_path_takes_the_name_of_its_target(): void
  assert_equal('/out/Über.pdf', C.FinalPath('/out/ber.pdf', 'Über', 'pdf'))
  assert_equal('/out/日本語.epub',
    C.FinalPath('/out/untitled.epub', '日本語', 'epub'))
  # The extension is given, never read back: the extension of /out/.pdf
  # is empty, and the name would end in the dot Windows forbids.
  assert_equal('/out/日本語.pdf', C.FinalPath('/out/.pdf', '日本語', 'pdf'))
  # A name the fold empties leaves the path as the engine wrote it.
  assert_equal('/out/untitled.pdf', C.FinalPath('/out/untitled.pdf', '***', 'pdf'))
  # A name that a file system reads as a device is guarded, as a
  # document's name is.
  assert_equal('/out/doc-Nul.pdf', C.FinalPath('/out/nul.pdf', 'Nul', 'pdf'))
enddef

# A target's identity is the name the writer gave it, and the file is
# only where that name's settings live. Two names that reduce to one
# slug once shared a file, so the second save destroyed the first.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/58
def Test_two_target_names_of_one_slug_are_two_targets(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: '日本語', kind: 'Book', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: '中文', kind: 'Manuscript', format: 'PDF'}))
  assert_equal(sort(['日本語', '中文']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, '日本語').format)
  assert_equal('PDF', C.LoadTarget(project, '中文').format)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_name_outside_ascii_does_not_take_the_file_of_another(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'Über', kind: 'Book', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'ber', kind: 'Manuscript', format: 'PDF'}))
  assert_equal(sort(['Über', 'ber']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, 'Über').format)
  assert_equal('PDF', C.LoadTarget(project, 'ber').format)
  FI.CleanupProjectFiles(project)
enddef

# Two names that differ only in case are two targets, because a name is
# the writer's own text and the picker shows both.
def Test_two_target_names_that_differ_only_in_case_are_two_targets(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'draft', format: 'PDF'}))
  assert_equal(sort(['Draft', 'draft']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, 'Draft').format)
  assert_equal('PDF', C.LoadTarget(project, 'draft').format)
  FI.CleanupProjectFiles(project)
enddef

# Saving a name that is already stored is an edit of that target, not a
# second one beside it.
def Test_saving_one_name_twice_edits_the_target(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', kind: 'Book'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', kind: 'Manuscript'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('Manuscript', C.LoadTarget(project, 'Draft').kind)
  FI.CleanupProjectFiles(project)
enddef

# The target deleted is the one saved second, which does not hold the
# plain slug path, so a delete that went by the slug would take the
# first target's file and leave the named one listed.
def Test_deleting_a_target_leaves_the_other_of_one_slug(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '日本語'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '中文'}))
  C.DeleteTarget(project, '中文')
  assert_equal(['日本語'], C.ListTargets(project))
  assert_true(C.LoadTarget(project, '中文') is null_object)
  FI.CleanupProjectFiles(project)
enddef

# A damaged definition decodes to nothing, so it carries no name. It
# must not reach the picker as a blank entry that Run would compile, as
# it did when a definition was found by the slug of the name asked for.
def Test_a_damaged_definition_is_no_target(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir, 'p')
  writefile(['{not json'], dir .. '/broken.json')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_true(C.LoadTarget(project, '') is null_object)
  FI.CleanupProjectFiles(project)
enddef

# A free path is one that nothing holds, not one that can be read: a
# folder of that name holds it too, and a save that called it free wrote
# nowhere.
def Test_a_path_that_a_folder_holds_is_not_free(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir .. '/draft.json', 'p')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'PDF'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('PDF', C.LoadTarget(project, 'Draft').format)
  FI.CleanupProjectFiles(project)
enddef

# A scrive written before this change holds its definitions at the plain
# slug of each name, which is where a target of one name still goes.
def Test_a_definition_at_the_plain_slug_path_is_still_the_target(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir, 'p')
  writefile([json_encode({name: 'Legacy', kind: 'Book', format: 'EPUB'})],
    dir .. '/legacy.json')
  assert_equal('EPUB', C.LoadTarget(project, 'Legacy').format)
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Legacy', format: 'PDF'}))
  assert_equal(['legacy.json'],
    glob(dir .. '/*.json', true, true)->mapnew((_, f) => fnamemodify(f, ':t')))
  assert_equal('PDF', C.LoadTarget(project, 'Legacy').format)
  C.DeleteTarget(project, 'Legacy')
  assert_equal([], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

# Renaming a target is a delete of the old name and a save of the new,
# see the submit of the wizard, which must leave one file.
def Test_renaming_a_target_leaves_no_file_at_the_old_name(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Old', format: 'EPUB'}))
  C.DeleteTarget(project, 'Old')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'New', format: 'PDF'}))
  assert_equal(['New'], C.ListTargets(project))
  assert_equal(1, len(glob(dir .. '/*.json', true, true)))
  FI.CleanupProjectFiles(project)
enddef

# The slug of a name in a script of its own is empty, so the definition
# was saved as .json, which the *.json glob never returned, and the
# target vanished as soon as it was saved.
def Test_a_target_name_that_slugs_to_nothing_is_still_listed(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '日本語'}))
  assert_equal(['日本語'], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_a_target_is_listed_while_wildignore_names_its_extension(): void
  var project = FI.BuildProject()
  # FromDict, as the other tests build one: a class member is not
  # writable from outside the class.
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft'}))
  var saved: string = &wildignore
  set wildignore+=*.json
  try
    assert_equal(['Draft'], C.ListTargets(project))
  finally
    &wildignore = saved
  endtry
  FI.CleanupProjectFiles(project)
enddef

def Test_concatenate_manuscript_full_structure(): void
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: AllDocIds(fx)})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal([
    '# Dedication {-}', '', 'For my family.', '',
    '# 1', '', 'It was a dark and stormy night.', '',
    '# 2', '', 'The end was near.', '',
    '# Acknowledgments {-}', '', 'Thanks to everyone.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_respects_content_selection(): void
  var fx = BuildProjectWithContent()
  # Only the Dedication is included. Manuscript and Back Matter are not.
  var target = C.CompileTarget.FromDict({includedIds: [fx.dedication.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal(['# Dedication {-}', '', 'For my family.'], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter(): void
  var fx = BuildProjectWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  var scene1b = BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md')
  chapter1.AddChild(scene1b)
  FI.WriteDocContent(fx.project, scene1b, ['Morning came.'])

  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, scene1b.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  # Neither scene has a heading, so the separator between them is the scene
  # break itself, not left out as it is before a chapter heading.
  assert_equal([
    '# 1', '', 'It was a dark and stormy night.', '', '* * *', '', 'Morning came.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_with_nothing_included_is_empty(): void
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: []})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal([], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter(): void
  # This exact match also guards against a real bug: the outer join of
  # ConcatenateBook once used target.separator between these three blocks,
  # which put a stray scene break around the frontmatter, mainmatter, and
  # backmatter commands. Those are LaTeX transitions, not scene breaks.
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: AllDocIds(fx)})
  var lines = C.ConcatenateBook(fx.project, target)
  assert_equal([
    '```{=latex}', '\frontmatter', '```', '',
    '# Dedication {-}', '', 'For my family.', '',
    '```{=latex}', '\mainmatter', '```', '',
    '# 1', '', 'It was a dark and stormy night.', '',
    '# 2', '', 'The end was near.', '',
    '```{=latex}', '\backmatter', '```', '',
    '# Acknowledgments {-}', '', 'Thanks to everyone.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_omits_mainmatter_when_front_matter_not_included(): void
  var fx = BuildProjectWithContent()
  # The Dedication is excluded, so Front Matter adds nothing.
  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, fx.scene2.id]})
  var lines = C.ConcatenateBook(fx.project, target)
  assert_equal(-1, index(lines, '\frontmatter'))
  assert_equal(-1, index(lines, '\mainmatter'))
  # The Manuscript text is still present, without a wrapper.
  assert_true(index(lines, '# 1') >= 0)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_a_cover_path_from_home_is_expanded(): void
  assert_equal($HOME .. '/covers/book.png', C.CoverPath('~/covers/book.png'))
  assert_equal('', C.CoverPath(''))
enddef

# FUNCTION: expand() would read cover[1].png as a pattern and return
# cover1.png, a different file, when both exist.
def Test_a_cover_path_is_never_read_as_a_pattern(): void
  var dir: string = FI.TempPath()
  mkdir(dir, 'p')
  writefile([], dir .. '/cover1.png')
  writefile([], dir .. '/cover[1].png')
  var cwd: string = getcwd()
  execute 'cd ' .. fnameescape(dir)
  var got: string = C.CoverPath('cover[1].png')
  execute 'cd ' .. fnameescape(cwd)
  delete(dir, 'rf')
  # Through Canon, because Vim answers with the separator and the long
  # name of its own system, and the name is what this test is about.
  assert_equal(PA.Canon(dir .. '/cover[1].png'), PA.Canon(got))
enddef

# FUNCTION: A Book with a cover image that does not exist stops with an
# error that names the path, before Pandoc runs.
def Test_a_missing_cover_image_stops_the_compile(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'NoCover', kind: 'Book', format: 'PDF',
    includedIds: [scene.id], coverImage: '/no/such/folder/cover.png'})
  var before: number = len(LM.History())
  C.Execute(project, target)
  var logged: string = LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  # CoverPath makes the path absolute, and on Windows that means a drive
  # and backslashes, so the pattern comes from the path itself.
  assert_match($'cover image not found: {escape(C.CoverPath("/no/such/folder/cover.png"), "\\.*$^~[]")}',
    logged)
  assert_notmatch('compiling "NoCover"', logged)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: HTML and Markdown leave the cover out, so a missing cover image
# does not stop them.
def Test_a_missing_cover_does_not_stop_a_format_without_one(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'HtmlNoCover', kind: 'Book', format: 'HTML',
    includedIds: [scene.id], coverImage: '/no/such/folder/cover.png'})
  var before: number = len(LM.History())
  C.Execute(project, target)
  var logged: string = LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  assert_notmatch('cover image not found', logged)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Compile a Manuscript PDF with stand-in programs, that kpsewhich
# finds only the files of found and that the programs of others exist, and
# return what was logged.
def CompileWithStubs(found: list<string>, others: list<string>): string
  var dir: string = TTX.Stubs(found, false, others)
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'TexCheck', kind: 'Manuscript', format: 'PDF',
    includedIds: [scene.id]})
  var before: number = len(LM.History())
  TTX.UsePath(dir)
  C.Execute(project, target)
  TTX.RestorePath()
  FI.CleanupProjectFiles(project)
  delete(dir, 'rf')
  return LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
enddef

# FUNCTION: The point of the check: name the missing package before LaTeX
# runs, instead of a LaTeX error in the failure log.
def Test_a_missing_tex_package_stops_a_pdf_compile(): void
  var logged: string = CompileWithStubs(['sffms.cls', 'hyperref.sty'], ['pandoc', 'pdflatex'])
  assert_match('needs TeX files that are not installed: .*ulem\.sty', logged)
  assert_notmatch('compiling "TexCheck"', logged)
enddef

def Test_a_missing_tex_engine_stops_a_pdf_compile(): void
  var logged: string = CompileWithStubs([], ['pandoc'])
  assert_match('pdflatex not found', logged)
  assert_notmatch('compiling "TexCheck"', logged)
enddef

# FUNCTION: An unknown line style is single, an unknown header bold, and
# small caps bold in a Manuscript, whose typewriter font has none.
def Test_table_options_fall_back(): void
  assert_equal({border: 'none', vlines: 'single', header: 'italic'}, C.TableOpts('Book', 'none', 'single', 'italic'))
  assert_equal({border: 'single', vlines: 'single', header: 'bold'}, C.TableOpts('Book', 'double', 'dotted', 'shouting'))
  assert_equal('smallcaps', C.TableOpts('Book', 'none', 'none', 'smallcaps').header)
  assert_equal('bold', C.TableOpts('Manuscript', 'none', 'none', 'smallcaps').header)
  assert_equal('plain', C.TableOpts('Manuscript', 'none', 'none', 'plain').header)
enddef

def Test_table_css_draws_only_the_lines_asked_for(): void
  assert_equal([], C.TableCss({border: 'none', vlines: 'none', header: 'bold'}))
  var border: list<string> = C.TableCss({border: 'single', vlines: 'none', header: 'bold'})
  assert_equal(1, len(border))
  assert_match('^table {', border[0])
  var both: list<string> = C.TableCss({border: 'single', vlines: 'single', header: 'bold'})
  assert_equal(2, len(both))
  assert_match('border-left', both[1])
enddef

export def RunAll(): void
  Test_table_options_fall_back()
  Test_table_css_draws_only_the_lines_asked_for()
  Test_a_missing_tex_package_stops_a_pdf_compile()
  Test_a_missing_tex_engine_stops_a_pdf_compile()
  Test_a_cover_path_from_home_is_expanded()
  Test_a_cover_path_is_never_read_as_a_pattern()
  Test_a_missing_cover_image_stops_the_compile()
  Test_a_missing_cover_does_not_stop_a_format_without_one()
  Test_an_output_path_takes_the_name_of_its_target()
  Test_two_target_names_of_one_slug_are_two_targets()
  Test_a_name_outside_ascii_does_not_take_the_file_of_another()
  Test_two_target_names_that_differ_only_in_case_are_two_targets()
  Test_saving_one_name_twice_edits_the_target()
  Test_deleting_a_target_leaves_the_other_of_one_slug()
  Test_a_damaged_definition_is_no_target()
  Test_a_path_that_a_folder_holds_is_not_free()
  Test_a_definition_at_the_plain_slug_path_is_still_the_target()
  Test_renaming_a_target_leaves_no_file_at_the_old_name()
  Test_a_target_name_that_slugs_to_nothing_is_still_listed()
  Test_a_target_is_listed_while_wildignore_names_its_extension()
  Test_concatenate_manuscript_full_structure()
  Test_concatenate_manuscript_respects_content_selection()
  Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter()
  Test_concatenate_manuscript_with_nothing_included_is_empty()
  Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter()
  Test_concatenate_book_omits_mainmatter_when_front_matter_not_included()
enddef
