vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_inspector.vim: the Inspector follows the editor with a hook
# on every buffer change while it is open. Closed in any way, not only
# with Toggle, it stops: the hook removes itself. It opens again as often
# as it is closed, and shows only the document that it opens for: its
# buffer stays hidden while closed, and must take new text, see issue 1.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/state.vim' as ST
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

def Test_the_follow_hook_goes_when_the_inspector_closes_any_way(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['Text.'])
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(scene.AbsPath(project.BinderRoot()))
  var editor: number = win_getid()
  I.Toggle()
  assert_true(exists('#bartleby_inspector_follow#BufEnter'), 'no hook while open')
  # Closed without Toggle.
  execute ':' .. bufwinnr(CO.INSPECTOR_BUF) .. 'close'
  win_gotoid(editor)
  doautocmd BufEnter
  assert_false(exists('#bartleby_inspector_follow#BufEnter'), 'the hook stayed')
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Return the text of the Inspector buffer.
def InspectorText(): string
  return join(getbufline(CO.INSPECTOR_BUF, 1, '$'), "\n")
enddef

# FUNCTION: Open, close, and open the Inspector again with Toggle, as in
# issue 1, where the second opening failed with E21.
def Test_the_inspector_opens_again_after_it_closes(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['Text.'])
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(scene.AbsPath(project.BinderRoot()))
  for step in ['open', 'close', 'open again', 'close again', 'open a third time']
    try
      I.Toggle()
    catch
      assert_report($'{step}: {v:exception}')
    endtry
  endfor
  assert_true(bufwinnr(CO.INSPECTOR_BUF) != -1, 'the Inspector is not open')
  assert_match(scene.title, InspectorText())
  I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Opened again for another document, the Inspector shows only
# that document, even when it has fewer lines than the first.
def Test_the_inspector_opens_again_for_another_document_without_its_old_lines(): void
  var project = FI.BuildProject()
  var first = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var second = project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(project, first, ['Text.'])
  FI.WriteDocContent(project, second, ['Text.'])
  var meta = first.LoadMeta(project.BinderRoot())
  meta.SetSynopsis(repeat('A synopsis long enough to take several lines. ', 6))
  meta.Save(first.MetaPath(project.BinderRoot()))
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(first.AbsPath(project.BinderRoot()))
  I.Toggle()
  assert_match('A synopsis long enough', InspectorText())
  I.Toggle()
  execute 'silent edit ' .. fnameescape(second.AbsPath(project.BinderRoot()))
  try
    I.Toggle()
  catch
    assert_report('opening again: ' .. v:exception)
  endtry
  assert_notmatch('A synopsis long enough', InspectorText())
  silent! I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_the_follow_hook_goes_when_the_inspector_closes_any_way()
  Test_the_inspector_opens_again_after_it_closes()
  Test_the_inspector_opens_again_for_another_document_without_its_old_lines()
enddef
