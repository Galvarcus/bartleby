vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_inspector.vim: the Inspector follows the editor with a hook
# on every buffer change while it is open. Closed in any way, not only
# with Toggle, it stops: the hook removes itself.
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

export def RunAll(): void
  Test_the_follow_hook_goes_when_the_inspector_closes_any_way()
enddef
