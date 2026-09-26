vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartlebymenu.vim: a menu of Bartleby's global commands in groups, built
# on menu.vim. It adds to commandpalette.vim: the palette is fast when you
# know what you want, and the menu lets you browse by group when you do
# not. Both have the same commands: the global ones. Binder actions such
# as New Chapter or Rename need an item under the cursor, so they are in
# neither.
#
# The menu is built once, at first use, and reused. Menu.new registers
# the menu by name for the hotkey, so building it on every open would
# leave old registrations.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as Sp
import autoload 'bartleby/lexicon.vim' as Lx

var menu: M.Menu = null_object

def RunEx(cmd: string): func(M.MenuItem)
  return (_: M.MenuItem) => {
    execute cmd
  }
enddef

def PromptThenEx(title: string, cmd: string): func(M.MenuItem)
  return (_: M.MenuItem) => {
    IP.PromptText(title, '', (name: string) => {
      if name !=# ''
        execute $'{cmd} {name}'
      endif
    })
  }
enddef

def BuildMenu(): M.Menu
  var m: M.Menu = M.Menu.new('bartleby', 'Bartleby')

  var scrive: M.MenuItem = m.AddItem('Scrive')
  scrive.AddItem('List...', RunEx('BartlebyList'))
  scrive.AddItem('Open...', PromptThenEx('Open Scrive', 'BartlebyOpen'))
  scrive.AddItem('New...', PromptThenEx('New Scrive', 'BartlebyNewScrive'))

  var binder: M.MenuItem = m.AddItem('Binder')
  binder.AddItem('Toggle', RunEx('BartlebyToggleBinder'))
  binder.AddItem('Search', RunEx('BartlebySearch'))

  var view: M.MenuItem = m.AddItem('View')
  view.AddItem('Toggle Inspector', RunEx('BartlebyToggleInspector'))
  view.AddItem('Toggle Focus', RunEx('BartlebyFocus'))
  view.AddItem('Toggle Spotlight', RunEx('BartlebySpotlight'))
  view.AddItem('Pick Spotlight Mode', (_: M.MenuItem) => Sp.PickMode())
  view.AddItem('Toggle Quill', RunEx('BartlebyQuill'))

  var doc: M.MenuItem = m.AddItem('Document')
  doc.AddItem('Take Snapshot', RunEx('BartlebySnapshot'))
  doc.AddItem('View Snapshots', RunEx('BartlebySnapshots'))
  if Lx.IsEnabled(Lx.KIND_DICTIONARY)
    doc.AddItem('Define Word', RunEx('BartlebyDefine'))
  endif
  if Lx.IsEnabled(Lx.KIND_THESAURUS)
    doc.AddItem('Thesaurus', RunEx('BartlebyThesaurus'))
  endif

  var project: M.MenuItem = m.AddItem('Project')
  project.AddItem('Edit Profile', RunEx('BartlebyProfile'))
  project.AddItem('Edit Info', RunEx('BartlebyProjectInfo'))
  project.AddItem('Compile', RunEx('BartlebyCompile'))

  return m
enddef

export def Toggle(): void
  if menu is null_object
    menu = BuildMenu()
  endif
  menu.Toggle()
enddef

# FUNCTION: In gVim, also register the menu as :amenu entries, so that it
# shows in the gVim menu bar and runs with :emenu. The popup menu does
# not change.
export def RegisterNative(): void
  if menu is null_object
    menu = BuildMenu()
  endif
  menu.RegisterAsVimMenu()
enddef
