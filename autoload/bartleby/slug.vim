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

# The names that Windows reserves for devices. It answers with the device
# whatever extension follows, so nul.md is the NUL device rather than a
# file, and a document written to it is gone. The superscript forms that
# the same documentation lists cannot survive the reduction below, which
# keeps a to z and 0 to 9 alone.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/55
const DEVICES: list<string> = ['con', 'prn', 'aux', 'nul']
  + range(1, 9)->mapnew((_, n) => $'com{n}')
  + range(1, 9)->mapnew((_, n) => $'lpt{n}')
const DEVICE_PREFIX: string = 'doc-'

export def Slugify(title: string): string
  var lowered: string = tolower(title)
  var slug: string = substitute(lowered, '[^a-z0-9]\+', '-', 'g')
  slug = substitute(slug, '^-\+\|-\+$', '', 'g')
  return index(DEVICES, slug) < 0 ? slug : DEVICE_PREFIX .. slug
enddef
