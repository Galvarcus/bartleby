vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# state.vim - the single scrive open in this Vim session. Phase 1 is
# single-project; a per-tab/window notion could replace this later if
# concurrent scrives turn out to matter. Kept in its own script (rather
# than plugin/bartleby.vim, which held it originally) so any autoload
# script - not just the plugin's own commands - can read/write it. A
# plugin/ file isn't a normal import target for other scripts.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj

var current_project: Pj.Project

export def Get(): Pj.Project
  return current_project
enddef

export def Set(project: Pj.Project): void
  current_project = project
enddef
