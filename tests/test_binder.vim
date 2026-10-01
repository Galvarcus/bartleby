vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_binder.vim: the mapping from cursor line to row in
# binder.vim, and the cursor restore of CursorContext and Render. Both
# are local to the script, as are all key handlers, so the tests drive
# the real buffer mappings with feedkeys and the xt flags: x runs the keys
# at once, and t makes them typed, so the mappings apply. Then they check
# the buffer, cursor, and window. Needs real files on disk, as
# test_compile.vim does, because OpenUnderCursor checks filereadable.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Open the Binder for a new copy of the fixture project, with
# real scene files on disk, and return a dict of project, scene1, and
# scene2. The caller must call CloseBinderAndCleanup.
def OpenBinderWithContent(): dict<any>
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene1 = chapter1.ChildAt(0)
  var scene2 = chapter2.ChildAt(0)
  FI.WriteDocContent(project, scene1, ['Scene one text.'])
  FI.WriteDocContent(project, scene2, ['Scene two text.'])
  B.Show(project)
  return {project: project, scene1: scene1, scene2: scene2}
enddef

def CloseBinderAndCleanup(fx: dict<any>): void
  # Close every window but one, then wipe what is left, so that the next
  # test starts with one clean window.
  only!
  bwipe!
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_show_renders_project_name_as_title_line(): void
  var fx = OpenBinderWithContent()
  assert_equal(fx.project.name, getline(1))
  CloseBinderAndCleanup(fx)
enddef

def Test_show_renders_the_tree_starting_at_line_2(): void
  var fx = OpenBinderWithContent()
  assert_match('Front Matter', getline(2))
  assert_match('Manuscript', getline(3))
  CloseBinderAndCleanup(fx)
enddef

# FUNCTION: Regression test for the header line offset: CR on a document
# must open that document, not another one or nothing, when a title line
# is above the tree.
def Test_cr_on_a_scene_line_opens_the_correct_file(): void
  var fx = OpenBinderWithContent()
  # Find the line of Scene 1 instead of assuming it, so that this test does
  # not check the wrong line if the fixture tree changes.
  var target = 'Scene 1'
  var lnum = 1
  while lnum <= line('$') && getline(lnum) !~# '\V' .. target
    lnum += 1
  endwhile
  assert_true(lnum <= line('$'), 'fixture tree has no Scene 1 line to test against')
  cursor(lnum, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal('scene-01.md', expand('%:t'))
  assert_equal(fx.scene1.AbsPath(fx.project.BinderRoot()), expand('%:p'))
  CloseBinderAndCleanup(fx)
enddef

def Test_cr_on_the_title_line_does_nothing(): void
  var fx = OpenBinderWithContent()
  var before = getline(1, '$')
  cursor(1, 1)
  feedkeys("\<CR>", 'xt')
  # Still in the Binder buffer: no document opened and no text changed.
  assert_equal(CO.BINDER_BUF, bufname('%'))
  assert_equal(before, getline(1, '$'))
  CloseBinderAndCleanup(fx)
enddef

def Test_tab_on_the_title_line_does_nothing(): void
  var fx = OpenBinderWithContent()
  var before = getline(1, '$')
  cursor(1, 1)
  feedkeys("\<Tab>", 'xt')
  assert_equal(before, getline(1, '$'))
  CloseBinderAndCleanup(fx)
enddef

def Test_cursor_stays_on_the_same_item_after_a_collapse_rerender(): void
  var fx = OpenBinderWithContent()
  # The Manuscript line, see Test_show_renders_the_tree_starting_at_line_2.
  var manuscriptLnum = 3
  assert_match('Manuscript', getline(manuscriptLnum))
  cursor(manuscriptLnum, 1)
  # Collapse it.
  feedkeys("\<Tab>", 'xt')
  # The cursor must stay on the Manuscript row, although Render rewrote the
  # whole buffer.
  assert_match('Manuscript', getline('.'))
  assert_equal(manuscriptLnum, line('.'))
  # And collapsing had an effect: Chapter 1, on the next line before, is no
  # longer in the buffer.
  assert_equal(0, search('Chapter\|^\s*1$', 'n'))
  CloseBinderAndCleanup(fx)
enddef

# FUNCTION: Regression test for a real bug: closing the Binder saved its
# state after its window had closed, when GetCollapsedIds found no window
# and returned nothing, so every close erased the collapsed folders.
def Test_collapsed_folders_survive_closing_the_binder(): void
  var fx = OpenBinderWithContent()
  var manuscript = fx.project.ChildAt(1)
  cursor(3, 1)
  feedkeys("\<Tab>", 'xt')
  B.Toggle(fx.project)
  assert_false(B.IsOpen())
  assert_equal([manuscript.id], B.GetCollapsedIds())
  B.Toggle(fx.project)
  assert_true(B.IsOpen())
  assert_equal(0, search('Chapter\|^\s*1$', 'n'))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

export def RunAll(): void
  Test_show_renders_project_name_as_title_line()
  Test_show_renders_the_tree_starting_at_line_2()
  Test_cr_on_a_scene_line_opens_the_correct_file()
  Test_cr_on_the_title_line_does_nothing()
  Test_tab_on_the_title_line_does_nothing()
  Test_cursor_stays_on_the_same_item_after_a_collapse_rerender()
  Test_collapsed_folders_survive_closing_the_binder()
enddef
