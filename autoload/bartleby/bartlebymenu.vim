vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartlebymenu.vim - Phase 7d: a categorized, hierarchical menu of
# Bartleby's global commands, built on the vendored menu.vim widget.
# Complements commandpalette.vim rather than replacing it - the palette
# is fast, type-to-filter access once you know roughly what you want;
# this is browsable-by-category access when you don't. Same command
# set as the palette (global, always-available commands only - not
# Binder-cursor-dependent actions like New Chapter or Rename, which
# need a specific item under the cursor and don't fit either widget's
# flat/categorized shape without that context).
#
# The menu tree is built once, at first use, and reused (menu.vim's
# own Menu.new() registers itself for hotkey dispatch by name, so
# rebuilding it on every open would leak stale registrations).
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as Sp

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

# For gVim users: also register the same tree as real :amenu entries, so
# it shows up in gVim's own menu bar and works with :emenu - independent
# of, and additional to, the popup/bar toggle above.
export def RegisterNative(): void
  if menu is null_object
    menu = BuildMenu()
  endif
  menu.RegisterAsVimMenu()
enddef
