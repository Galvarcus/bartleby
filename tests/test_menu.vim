vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_menu.vim: the native menu of menu.vim, the one that shows in the
# menu bar of gVim and MacVim and runs with :emenu. Vim runs a native entry
# in no script, so the entry must reach MenuInvoke by its autoload name.
# The popup menu is tested through the commands that use it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/bartlebymenu.vim' as BM
import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/state.vim' as ST
import 'Logger/messages.vim' as LM
import 'bartleby/variables/constants.vim' as CO

var invoked: list<string> = []

def Test_a_native_entry_runs_its_action(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_a', 'TestMenuA')
  menu.AddItem('Run', (item) => {
    invoked->add(item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuA.Run
  assert_equal(['Run'], invoked)
  menu.UnregisterVimMenu()
enddef

def Test_each_entry_runs_its_own_action(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_b', 'TestMenuB')
  menu.AddItem('First', (item) => {
    invoked->add('first')
  })
  var sub = menu.AddItem('Sub')
  sub.AddItem('Deep', (item) => {
    invoked->add('deep ' .. item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuB.Sub.Deep
  emenu TestMenuB.First
  assert_equal(['deep Deep', 'first'], invoked)
  menu.UnregisterVimMenu()
enddef

def Test_a_label_with_dots_and_spaces_runs(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_c', 'TestMenuC')
  menu.AddItem('Open file...', (item) => {
    invoked->add(item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuC.Open\ file\.\.\.
  assert_equal(['Open file...'], invoked)
  menu.UnregisterVimMenu()
enddef

# FUNCTION: :emenu runs a disabled entry, which the GUI shows greyed and never
# runs, so check the state that the GUI uses.
def Test_a_disabled_entry_is_registered_disabled(): void
  if !has('menu')
    return
  endif
  var menu = M.Menu.new('test_menu_d', 'TestMenuD')
  var item = menu.AddItem('Off', (it) => {
    invoked->add('ran')
  })
  item.enabled = false
  menu.AddItem('On', (it) => {
    invoked->add('ran')
  })
  menu.RegisterAsVimMenu()
  assert_false(menu_info('TestMenuD.Off', 'n').enabled)
  assert_true(menu_info('TestMenuD.On', 'n').enabled)
  menu.UnregisterVimMenu()
enddef

def Test_unregistering_removes_the_entries(): void
  if !has('menu')
    return
  endif
  var menu = M.Menu.new('test_menu_e', 'TestMenuE')
  menu.AddItem('Gone', (item) => {
    invoked->add('ran')
  })
  menu.RegisterAsVimMenu()
  menu.UnregisterVimMenu()
  assert_fails('emenu TestMenuE.Gone', 'E')
enddef

# FUNCTION: Bartleby's own native menu: an entry runs its Ex command. Close
# logs a message when nothing is open, which shows that the command ran.
def Test_an_entry_of_the_bartleby_menu_runs_its_command(): void
  if !has('menu')
    return
  endif
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  BM.RegisterNative()
  LM.Clear()
  execute 'emenu ' .. CO.PLUGIN_NAME .. '.Scrive.Close'
  var logged: string = LM.History()->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  assert_match('nothing of Bartleby is open', logged)
  execute 'aunmenu ' .. CO.PLUGIN_NAME
enddef

export def RunAll(): void
  Test_a_native_entry_runs_its_action()
  Test_each_entry_runs_its_own_action()
  Test_a_label_with_dots_and_spaces_runs()
  Test_a_disabled_entry_is_registered_disabled()
  Test_unregistering_removes_the_entries()
  Test_an_entry_of_the_bartleby_menu_runs_its_command()
enddef
