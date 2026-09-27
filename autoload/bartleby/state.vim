vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# state.vim: the one scrive that is open in this Vim session. It is in
# its own autoload script, not in plugin/bartleby.vim, so every autoload
# script can read and set it: a plugin file is not a normal import
# target.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO

var current_project: PO.Project

export def Get(): PO.Project
  return current_project
enddef

export def Set(project: PO.Project): void
  current_project = project
enddef
