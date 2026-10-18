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
  var dir: string = tempname()
  mkdir(dir, 'p')
  writefile([], dir .. '/cover1.png')
  writefile([], dir .. '/cover[1].png')
  var cwd: string = getcwd()
  execute 'cd ' .. fnameescape(dir)
  var got: string = C.CoverPath('cover[1].png')
  execute 'cd ' .. fnameescape(cwd)
  delete(dir, 'rf')
  assert_equal(dir .. '/cover[1].png', got)
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
  assert_match('cover image not found: /no/such/folder/cover.png', logged)
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
  Test_concatenate_manuscript_full_structure()
  Test_concatenate_manuscript_respects_content_selection()
  Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter()
  Test_concatenate_manuscript_with_nothing_included_is_empty()
  Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter()
  Test_concatenate_book_omits_mainmatter_when_front_matter_not_included()
enddef
