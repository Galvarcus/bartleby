vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# commandpalette.vim: a list of Bartleby's global commands that narrows
# as you type, built on the filter field of inputpopup.vim. Type a few
# letters, move with Up and Down, and run with Enter.
#
# It runs Ex commands instead of importing modules: most functions behind
# the commands, such as OpenScrive and RunCompile, are local to
# plugin/bartleby.vim, so the :Bartleby commands are the public API.
#
# Only global commands are listed. Binder actions such as New Chapter and
# Rename need an item under the cursor, so they do not fit a list without
# context.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as Sp
import autoload 'bartleby/lexicon.vim' as Lx

# Display name to Ex command, for commands without an argument.
const COMMANDS: dict<string> = {
  'List Scrives': 'BartlebyList',
  'Toggle Binder': 'BartlebyToggleBinder',
  'Search Scrive': 'BartlebySearch',
  'Toggle Inspector': 'BartlebyToggleInspector',
  'Toggle Focus': 'BartlebyFocus',
  'Toggle Spotlight': 'BartlebySpotlight',
  'Toggle Quill': 'BartlebyQuill',
  'Edit Profile': 'BartlebyProfile',
  'Edit Project Info': 'BartlebyProjectInfo',
  'Compile': 'BartlebyCompile',
  'Take Snapshot': 'BartlebySnapshot',
  'View Snapshots': 'BartlebySnapshots',
}

# Display name to Ex command, for commands that need an argument, asked
# for with a second PromptText.
const COMMANDS_WITH_ARG: dict<string> = {
  'Open Scrive': 'BartlebyOpen',
  'New Scrive': 'BartlebyNewScrive',
}

# Entries with no Ex command, called through an exported function of
# their module.
const DIRECT_ACTIONS: dict<string> = {
  'Pick Spotlight Mode': 'spotlight',
}

# Display name to lexicon kind, see EnabledLookups.
const LOOKUPS: dict<string> = {
  'Define Word': 'dictionary',
  'Thesaurus': 'thesaurus',
}

export def Open(): void
  var names: list<string> = sort(keys(COMMANDS) + keys(COMMANDS_WITH_ARG)
    + keys(DIRECT_ACTIONS) + keys(EnabledLookups()))
  IP.PromptFilter('Command Palette', names, (choice: string) => {
    Run(choice)
  })
enddef

# FUNCTION: Return the lookup entries for the kinds that have an API key.
# They act on the word under the cursor in the window where the palette
# opened.
def EnabledLookups(): dict<string>
  var lookups: dict<string> = {}
  for [name, kind] in items(LOOKUPS)
    if Lx.IsEnabled(kind)
      lookups[name] = kind
    endif
  endfor
  return lookups
enddef

def Run(choice: string): void
  if has_key(COMMANDS, choice)
    execute COMMANDS[choice]
    return
  endif
  if has_key(LOOKUPS, choice)
    execute LOOKUPS[choice] ==# Lx.KIND_THESAURUS ? 'BartlebyThesaurus' : 'BartlebyDefine'
    return
  endif
  if has_key(COMMANDS_WITH_ARG, choice)
    var cmd: string = COMMANDS_WITH_ARG[choice]
    IP.PromptText(choice, '', (name: string) => {
      if name !=# ''
        execute $'{cmd} {name}'
      endif
    })
    return
  endif
  if choice ==# 'Pick Spotlight Mode'
    Sp.PickMode()
  endif
enddef
