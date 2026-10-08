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

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/lexicon.vim' as LE
import 'bartleby/variables/constants.vim' as CO

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
  var m: M.Menu = M.Menu.new(CO.MENU_NAME, CO.PLUGIN_NAME)

  var scrive: M.MenuItem = m.AddItem(IN.T("Scrive"))
  scrive.AddItem(IN.T("List..."), RunEx('BartlebyList'))
  scrive.AddItem(IN.T("Open..."), PromptThenEx(IN.T("Open Scrive"), 'BartlebyOpen'))
  scrive.AddItem(IN.T("New..."), PromptThenEx(IN.T("New Scrive"), 'BartlebyNewScrive'))

  var binder: M.MenuItem = m.AddItem(IN.T("Binder"))
  binder.AddItem(IN.T("Toggle"), RunEx('BartlebyToggleBinder'))
  binder.AddItem(IN.T("Search"), RunEx('BartlebySearch'))
  binder.AddItem(IN.T("Empty Trash"), RunEx('BartlebyEmptyTrash'))
  binder.AddItem(IN.T("Recover Files"), RunEx('BartlebyRecover'))
  binder.AddItem(IN.T("Tidy Files"), RunEx('BartlebyTidyFiles'))

  var view: M.MenuItem = m.AddItem(IN.T("View"))
  view.AddItem(IN.T("Toggle Inspector"), RunEx('BartlebyToggleInspector'))
  view.AddItem(IN.T("Toggle Focus"), RunEx('BartlebyFocus'))
  view.AddItem(IN.T("Toggle Spotlight"), RunEx('BartlebySpotlight'))
  view.AddItem(IN.T("Pick Spotlight Mode"), (_: M.MenuItem) => SP.PickMode())
  view.AddItem(IN.T("Toggle Quill"), RunEx('BartlebyQuill'))

  var doc: M.MenuItem = m.AddItem(IN.T("Document"))
  doc.AddItem(IN.T("Take Snapshot"), RunEx('BartlebySnapshot'))
  doc.AddItem(IN.T("View Snapshots"), RunEx('BartlebySnapshots'))
  if LE.IsEnabled(CO.KIND_DICTIONARY)
    doc.AddItem(IN.T("Define Word"), RunEx('BartlebyDefine'))
  endif
  if LE.IsEnabled(CO.KIND_THESAURUS)
    doc.AddItem(IN.T("Thesaurus"), RunEx('BartlebyThesaurus'))
  endif

  var project: M.MenuItem = m.AddItem(IN.T("Project"))
  project.AddItem(IN.T("Edit Profile"), RunEx('BartlebyProfile'))
  project.AddItem(IN.T("Edit Info"), RunEx('BartlebyProjectInfo'))
  project.AddItem(IN.T("Compile"), RunEx('BartlebyCompile'))

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
