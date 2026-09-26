vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# slug.vim: turns a display title into a safe name for folders and files
# on disk.
# License: GNU GPL 3.0
##############################################################################

export def Slugify(title: string): string
  var lowered: string = tolower(title)
  var slug: string = substitute(lowered, '[^a-z0-9]\+', '-', 'g')
  return substitute(slug, '^-\+\|-\+$', '', 'g')
enddef
