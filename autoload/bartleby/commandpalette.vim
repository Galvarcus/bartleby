vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# commandpalette.vim - Phase 7c: a fuzzy-filtered list of Bartleby's
# global :Bartleby* commands, built on inputpopup.vim's filter field
# type (type a few letters, Up/Down to move, Enter to run).
#
# Invokes by Ex command string rather than importing the modules
# directly - most of the underlying wiring (OpenScrive, RunCompile,
# ToggleBinder, ...) lives as script-local functions inside
# plugin/bartleby.vim itself, not exported from an autoload module, so
# the :Bartleby* commands are this plugin's own public API surface and
# the natural thing to call through.
#
# Scoped to the global, always-available commands only - not
# Binder-cursor-dependent actions (New Chapter, Rename, ...), which
# only make sense with a specific item under the cursor and don't fit
# a flat, context-free palette cleanly.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as Sp

# Display name -> Ex command (no argument needed).
const COMMANDS: dict<string> = {
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

# Display name -> Ex command that still needs a typed argument, chained
# via a second PromptText prompt.
const COMMANDS_WITH_ARG: dict<string> = {
  'Open Scrive': 'BartlebyOpen',
  'New Scrive': 'BartlebyNewScrive',
}

# Entries with no Ex-command equivalent at all - called directly
# through their own exported module function instead.
const DIRECT_ACTIONS: dict<string> = {
  'Pick Spotlight Mode': 'spotlight',
}

export def Open(): void
  var names: list<string> = sort(keys(COMMANDS) + keys(COMMANDS_WITH_ARG) + keys(DIRECT_ACTIONS))
  IP.PromptFilter('Command Palette', names, (choice: string) => {
    Run(choice)
  })
enddef

def Run(choice: string): void
  if has_key(COMMANDS, choice)
    execute COMMANDS[choice]
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
