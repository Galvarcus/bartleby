vim9script
# tests/test_outliner.vim - outliner.vim's popup Filter() logic.
# OutlinerPopup is script-local (unlike InputPopup), so it can't be
# constructed directly from here - tested instead by opening a real
# popup via the exported Show() and driving it with feedkeys('...', 'xt'),
# confirmed to correctly reach a popup's filter callback even headless
# (popup key-dispatch is Vim's own internal machinery, not terminal
# rendering). Chained pickers are verified via popup_list()/
# popup_getoptions() title inspection rather than trying to read
# private state.

import autoload 'bartleby/outliner.vim' as O
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as Fx

def OpenOutlinerWithContent(): dict<any>
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  var scene2 = chapter2.ChildAt(0)
  Fx.WriteDocContent(project, scene1, ['Scene one content.'])
  Fx.WriteDocContent(project, scene2, ['Scene two content.'])
  O.Show(project, manuscript)
  return {project: project, scene1: scene1, scene2: scene2}
enddef

def ClosePopupsAndCleanup(fx: dict<any>): void
  for id in popup_list()
    popup_close(id)
  endfor
  Fx.CleanupProjectFiles(fx.project)
enddef

# Regression coverage for a real bug: <CR> on a document row previously
# opened it in whatever window happened to be current when Outliner was
# shown (Binder itself, in the plain/fresh case) rather than a real
# editor window, since a popup never changes window focus on its own.
# Deliberately the freshest, most minimal scenario - nothing else open -
# per testing_checklist.md's own guidance on this bug class.
def Test_cr_opens_the_correct_document_in_a_fresh_session(): void
  var fx = OpenOutlinerWithContent()
  # Row 0 is Chapter '1' (a folder); row 1 is its Scene 1.
  feedkeys("j", 'xt')
  feedkeys("\<CR>", 'xt')
  assert_equal('scene-01.md', expand('%:t'))
  assert_equal(fx.scene1.AbsPath(fx.project.BinderRoot()), expand('%:p'))
  bwipe!
  ClosePopupsAndCleanup(fx)
enddef

def Test_cr_on_a_folder_row_does_not_open_anything(): void
  var fx = OpenOutlinerWithContent()
  var before = expand('%:p')
  feedkeys("\<CR>", 'xt') # row 0, Chapter '1' - a folder, not a document
  assert_equal(before, expand('%:p'))
  ClosePopupsAndCleanup(fx)
enddef

def Test_j_then_j_reaches_the_second_chapters_scene(): void
  var fx = OpenOutlinerWithContent()
  # Rows: 0 Chapter '1', 1 Scene 1, 2 Chapter '2', 3 Scene 1 (chapter 2's).
  feedkeys("jjj", 'xt')
  feedkeys("\<CR>", 'xt')
  assert_equal(fx.scene2.AbsPath(fx.project.BinderRoot()), expand('%:p'))
  bwipe!
  ClosePopupsAndCleanup(fx)
enddef

# Regression coverage for a real bug: a popup filter receives one key at
# a time with no built-in multi-key buffering, so an early draft of this
# sequence wrongly fired Status (bound to bare 's') instead of Sort.
def Test_gs_opens_the_sort_popup_not_the_status_popup(): void
  var fx = OpenOutlinerWithContent()
  feedkeys("j", 'xt') # move onto a document row first
  feedkeys("gs", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Sort by ') >= 0)
  assert_equal(-1, index(titles, ' Status '))
  ClosePopupsAndCleanup(fx)
enddef

def Test_bare_s_opens_the_status_popup(): void
  var fx = OpenOutlinerWithContent()
  feedkeys("j", 'xt')
  feedkeys("s", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Status ') >= 0)
  ClosePopupsAndCleanup(fx)
enddef

def Test_bare_l_opens_the_label_popup(): void
  var fx = OpenOutlinerWithContent()
  feedkeys("j", 'xt')
  feedkeys("l", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Label ') >= 0)
  ClosePopupsAndCleanup(fx)
enddef

export def RunAll(): void
  Test_cr_opens_the_correct_document_in_a_fresh_session()
  Test_cr_on_a_folder_row_does_not_open_anything()
  Test_j_then_j_reaches_the_second_chapters_scene()
  Test_gs_opens_the_sort_popup_not_the_status_popup()
  Test_bare_s_opens_the_status_popup()
  Test_bare_l_opens_the_label_popup()
enddef
