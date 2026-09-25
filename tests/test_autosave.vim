vim9script
# tests/test_autosave.vim - autosave.vim: saves only changed documents of
# the open scrive, honors the interval, always saves when forced, runs a
# deferred save when the interval ends, and does nothing when turned off.

import autoload 'bartleby/autosave.vim' as As
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/state.vim' as St

def Setup(): dict<any>
  var root: string = tempname()
  var project = Pj.Project.new(root .. '/Test.bartleby')
  project.InitNew('Test', Pj.TYPE_NOVEL)
  St.Set(project)
  var doc: string = project.BinderRoot() .. '/scene.md'
  mkdir(fnamemodify(doc, ':h'), 'p')
  writefile(['start'], doc)
  var outside: string = root .. '/notes.md'
  writefile(['start'], outside)
  return {root: root, doc: doc, outside: outside}
enddef

def Teardown(fx: dict<any>): void
  silent! bwipe!
  g:bartleby_autosave = true
  g:bartleby_autosave_interval = 30
  delete(fx.root, 'rf')
enddef

def Edit(text: string): void
  setline(1, text)
enddef

def Test_saves_a_changed_scrive_document(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  assert_true(As.IsScriveDocument())
  Edit('changed')
  As.Save(false)
  assert_equal(['changed'], readfile(fx.doc))
  assert_false(&modified)
  Teardown(fx)
enddef

def Test_ignores_files_outside_the_binder(): void
  var fx = Setup()
  execute 'edit ' .. fx.outside
  assert_false(As.IsScriveDocument())
  Edit('changed')
  As.Save(true)
  assert_equal(['start'], readfile(fx.outside))
  Teardown(fx)
enddef

def Test_interval_skips_then_force_saves(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  Edit('first')
  As.Save(false)
  Edit('second')
  As.Save(false)
  assert_equal(['first'], readfile(fx.doc))
  assert_true(get(b:, 'bartleby_autosave_pending', false))
  As.Save(true)
  assert_equal(['second'], readfile(fx.doc))
  Teardown(fx)
enddef

def Test_deferred_save_runs_when_the_interval_ends(): void
  var fx = Setup()
  g:bartleby_autosave_interval = 1
  execute 'edit ' .. fx.doc
  Edit('first')
  As.Save(false)
  Edit('second')
  As.Save(false)
  assert_equal(['first'], readfile(fx.doc))
  sleep 1500m
  assert_equal(['second'], readfile(fx.doc))
  Teardown(fx)
enddef

def Test_does_nothing_when_turned_off(): void
  var fx = Setup()
  g:bartleby_autosave = false
  execute 'edit ' .. fx.doc
  Edit('changed')
  As.Save(true)
  assert_equal(['start'], readfile(fx.doc))
  Teardown(fx)
enddef

def Test_keeps_change_marks(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  append(1, ['two', 'three'])
  var before = [line("'["), line("']")]
  As.Save(true)
  assert_equal(before, [line("'["), line("']")])
  Teardown(fx)
enddef

export def RunAll(): void
  Test_saves_a_changed_scrive_document()
  Test_ignores_files_outside_the_binder()
  Test_interval_skips_then_force_saves()
  Test_deferred_save_runs_when_the_interval_ends()
  Test_does_nothing_when_turned_off()
  Test_keeps_change_marks()
enddef
