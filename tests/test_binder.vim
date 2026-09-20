vim9script
# tests/test_binder.vim - binder.vim's cursor-to-row mapping and cursor
# restoration (CursorContext()/Render()). Both are script-local, along
# with every keymap handler - tested indirectly by driving the real
# buffer-local mappings with feedkeys('...', 'xt') (the 'x' flag executes
# immediately, 't' uses real typeahead so the mappings actually fire),
# then asserting on the resulting buffer/cursor/window state. Needs real
# files on disk, same as test_compile.vim, since OpenUnderCursor() checks
# filereadable() before opening.

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as Fx

# Opens Binder for a fresh copy of the fixture project (with real scene
# files written to disk) and returns {project, scene1, scene2}. Caller
# must CloseBinderAndCleanup() when done.
def OpenBinderWithContent(): dict<any>
  var project = Fx.BuildProject()
  var chapter1 = project.ItemAt(1).ChildAt(0)
  var chapter2 = project.ItemAt(1).ChildAt(1)
  var scene1 = chapter1.ChildAt(0)
  var scene2 = chapter2.ChildAt(0)
  Fx.WriteDocContent(project, scene1, ['Scene one text.'])
  Fx.WriteDocContent(project, scene2, ['Scene two text.'])
  B.Show(project)
  return {project: project, scene1: scene1, scene2: scene2}
enddef

def CloseBinderAndCleanup(fx: dict<any>): void
  # Close every window but one, then wipe whatever's left, so each test
  # starts the next from a clean single-window slate.
  only!
  bwipe!
  Fx.CleanupProjectFiles(fx.project)
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

# Regression coverage for the header-line cursor-offset math: opening the
# document under the cursor must land on the actual right file, not the
# wrong one (or nothing), when the tree has a title line ahead of it.
def Test_cr_on_a_scene_line_opens_the_correct_file(): void
  var fx = OpenBinderWithContent()
  # Manuscript(3)/Chapter 1(4)/Scene 1(5), with 2 title lines... walk
  # down to find Scene 1's actual line rather than hardcoding it, so this
  # test doesn't silently start asserting the wrong thing if the fixture
  # tree shape ever changes.
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
  # Still in the Binder buffer (no document opened), content unchanged.
  assert_equal('Bartleby-Binder', bufname('%'))
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
  var manuscriptLnum = 3 # 'Manuscript' - see Test_show_renders_the_tree_starting_at_line_2
  assert_match('Manuscript', getline(manuscriptLnum))
  cursor(manuscriptLnum, 1)
  feedkeys("\<Tab>", 'xt') # collapse
  # Manuscript's own row must still be exactly where the cursor is,
  # despite the buffer having been fully rewritten by Render().
  assert_match('Manuscript', getline('.'))
  assert_equal(manuscriptLnum, line('.'))
  # And collapsing actually did something observable: Chapter 1 (which
  # was on the very next line) is no longer anywhere in the buffer.
  assert_equal(0, search('Chapter\|^\s*1$', 'n'))
  CloseBinderAndCleanup(fx)
enddef

export def RunAll(): void
  Test_show_renders_project_name_as_title_line()
  Test_show_renders_the_tree_starting_at_line_2()
  Test_cr_on_a_scene_line_opens_the_correct_file()
  Test_cr_on_the_title_line_does_nothing()
  Test_tab_on_the_title_line_does_nothing()
  Test_cursor_stays_on_the_same_item_after_a_collapse_rerender()
enddef
