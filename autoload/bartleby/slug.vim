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

export const SEP: string = '-'

# Every ASCII character that is not a letter or a digit: the control
# characters, the space, and the punctuation, which together hold every
# character that Windows forbids in a name, the trailing dot and the
# trailing space included.
const ASCII_FOLD_PAT: string = '[\u0000-\u002f\u003a-\u0040\u005b-\u0060\u007b-\u007f]\+'

# The separators and the invisibles above ASCII, which a name keeps out
# for the reason it keeps out the space: a writer cannot see one, and a
# name that holds one cannot be typed again.
const SPACE_FOLD_PAT: string = '[\u00a0\u1680\u2000-\u200f\u2028-\u202f\u205f-\u2060\u3000\ufeff]\+'

# The characters that a slug holds, and nothing else.
const ASCII_ALNUM_PAT: string = '[a-z0-9]'

const EDGE_PAT: string = '^-\+\|-\+$'

# A path component holds 255 bytes on every file system of the past
# decade, and a title of three bytes to the character fills one in
# eighty-five. What the cap leaves over takes the longest role prefix, a
# -NN for a name already in use, and an extension.
const MAX_BYTES: number = 200

# The names that Windows reserves for devices. It answers with the device
# whatever extension follows, so nul.md is the NUL device rather than a
# file, and a document written to it is gone. The same documentation
# lists the superscript forms of 1, 2 and 3, which only a name that keeps
# the letters of its title can reach.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/55
const DEVICES: list<string> = ['con', 'prn', 'aux', 'nul']
  + range(1, 9)->mapnew((_, n) => $'com{n}')
  + range(1, 9)->mapnew((_, n) => $'lpt{n}')
  + ["com\u00b9", "com\u00b2", "com\u00b3"]
  + ["lpt\u00b9", "lpt\u00b2", "lpt\u00b3"]
const DEVICE_PREFIX: string = 'doc-'

# FUNCTION: Return the name a title reduces to, in ASCII alone, for the
# working files that pandoc and the engines read. It folds one character
# at a time, with whatever combining marks that character carries,
# because a collection matches on the base character and takes the marks
# along with it: the e of a decomposed accent passed the class that a to
# z keeps, and the mark stayed in a name that must hold none. A byte
# above ASCII here is a path that no TeX engine is reliable with, and a
# name that one file system stores in the other spelling, which the glob
# that trims the logs then does not match.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/65
export def Slugify(title: string): string
  var slug: string = substitute(tolower(title), '.',
    (m) => strlen(m[0]) == 1 && m[0] =~# ASCII_ALNUM_PAT ? m[0] : SEP, 'g')
  # Folding a character at a time leaves a run of hyphens where folding
  # the whole run left one.
  slug = substitute(slug, SEP .. '\+', SEP, 'g')
  return Guarded(substitute(Capped(slug), EDGE_PAT, '', 'g'))
enddef

# FUNCTION: Return the name on disk of a title the writer typed: its own
# letters, in any script, with its case, and a hyphen for every run of
# what a file system forbids.
export def Safe(title: string): string
  var name: string = substitute(title, SPACE_FOLD_PAT, SEP, 'g')
  name = substitute(name, ASCII_FOLD_PAT, SEP, 'g')
  return Guarded(substitute(Capped(name), EDGE_PAT, '', 'g'))
enddef

# FUNCTION: Return name within max bytes, cut on whole characters, so
# that no cut leaves half of one or strands a combining mark. A caller
# strips the edges after it, so that no cut leaves a trailing hyphen.
# One character and its marks are one cut, so a name of a letter and
# many marks can be cut to nothing, which a caller answers as it answers
# a title that keeps nothing. The budget is an argument because a log
# name holds two of these and a path component holds 255 bytes.
export def Capped(name: string, max: number = MAX_BYTES): string
  var out: string = name
  while strlen(out) > max
    out = strcharpart(out, 0, strchars(out, 1) - 1, 1)
  endwhile
  return out
enddef

# FUNCTION: Return name, or name behind DEVICE_PREFIX when it names a
# device. The comparison folds case, because Safe keeps the case that
# Slugify has already folded away.
def Guarded(name: string): string
  return index(DEVICES, tolower(name)) < 0 ? name : DEVICE_PREFIX .. name
enddef
