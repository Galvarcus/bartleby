vim9script
# tests/test_compile.vim - compile.vim's Concatenate* functions (the
# exported entry points; WalkManuscript/WalkBook/WalkFrontOrBackMatter/
# JoinSiblingBlocks/etc. are script-local and only reachable through
# these). Needs real files on disk - ReadDocLines() genuinely reads them -
# so each test writes fixture content under the project's own binder root
# and cleans it up via Fx.CleanupProjectFiles() when done.

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as Fx

# Builds the shared fixture project, adds one document each to Front
# Matter and Back Matter (the fixture alone has none), and writes real
# content for every document in the tree. Returns the project; caller
# must Fx.CleanupProjectFiles(project) when done.
def BuildProjectWithContent(): dict<any>
  var project = Fx.BuildProject()
  var frontMatter = project.ItemAt(0)
  var manuscript = project.ItemAt(1)
  var backMatter = project.ItemAt(2)

  var dedication = BI.BinderItem.NewDocument('Dedication', 'front-matter/dedication.md')
  frontMatter.AddChild(dedication)
  var acknowledgments = BI.BinderItem.NewDocument('Acknowledgments', 'back-matter/acknowledgments.md')
  backMatter.AddChild(acknowledgments)

  var chapter1 = manuscript.ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  var scene2 = chapter2.ChildAt(0)

  Fx.WriteDocContent(project, dedication, ['For my family.'])
  Fx.WriteDocContent(project, scene1, ['It was a dark and stormy night.'])
  Fx.WriteDocContent(project, scene2, ['The end was near.'])
  Fx.WriteDocContent(project, acknowledgments, ['Thanks to everyone.'])

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
  Fx.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_respects_content_selection(): void
  var fx = BuildProjectWithContent()
  # Only the Dedication is included - Manuscript and Back Matter excluded.
  var target = C.CompileTarget.FromDict({includedIds: [fx.dedication.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal(['# Dedication {-}', '', 'For my family.'], lines)
  Fx.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter(): void
  var fx = BuildProjectWithContent()
  var chapter1 = fx.project.ItemAt(1).ChildAt(0)
  var scene1b = BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md')
  chapter1.AddChild(scene1b)
  Fx.WriteDocContent(fx.project, scene1b, ['Morning came.'])

  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, scene1b.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  # Neither scene has its own heading, so the separator between them is
  # the "* * *" itself, not suppressed the way a chapter heading would be.
  assert_equal([
    '# 1', '', 'It was a dark and stormy night.', '', '* * *', '', 'Morning came.',
  ], lines)
  Fx.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_with_nothing_included_is_empty(): void
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: []})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal([], lines)
  Fx.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter(): void
  # This exact-match assertion is also the regression guard for a real
  # bug: ConcatenateBook()'s outer join once used target.separator
  # between these three blocks, producing a stray "* * *" immediately
  # around \frontmatter/\mainmatter/\backmatter (structural LaTeX
  # transitions, not scene breaks) - any reappearance of that fails here.
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
  Fx.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_omits_mainmatter_when_front_matter_not_included(): void
  var fx = BuildProjectWithContent()
  # Exclude the Dedication - Front Matter contributes nothing.
  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, fx.scene2.id]})
  var lines = C.ConcatenateBook(fx.project, target)
  assert_equal(-1, index(lines, '\frontmatter'))
  assert_equal(-1, index(lines, '\mainmatter'))
  # Manuscript content itself should still be present, unwrapped.
  assert_true(index(lines, '# 1') >= 0)
  Fx.CleanupProjectFiles(fx.project)
enddef

export def RunAll(): void
  Test_concatenate_manuscript_full_structure()
  Test_concatenate_manuscript_respects_content_selection()
  Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter()
  Test_concatenate_manuscript_with_nothing_included_is_empty()
  Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter()
  Test_concatenate_book_omits_mainmatter_when_front_matter_not_included()
enddef
