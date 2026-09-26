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

import autoload 'bartleby/project.vim' as Pj

var current_project: Pj.Project

export def Get(): Pj.Project
  return current_project
enddef

export def Set(project: Pj.Project): void
  current_project = project
enddef
