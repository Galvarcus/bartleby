vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexicon_result.vim: the result of a dictionary or thesaurus lookup, the
# contract between lexicon.vim, every provider, and lexiconpopup.vim. A
# result is a dict:
#   status:      ok, notfound, or error
#   entries:     for status ok. Dictionary entries: {headword, display,
#                fl, defs}. Thesaurus entries: {headword, fl, senses,
#                ants}, where senses is a list of {label, syns}.
#   suggestions: spelling suggestions, for status notfound
#   message:     the error text, for status error
# display is the headword as shown, fl the part of speech as text, defs a
# list of short definitions, label a short definition of the sense, and
# syns and ants lists of words.
# License: GNU GPL 3.0
##############################################################################

# FUNCTION: Return a result with entries.
export def Ok(entries: list<dict<any>>): dict<any>
  return {status: 'ok', entries: entries, suggestions: [], message: ''}
enddef

# FUNCTION: Return a result for a word that was not found, with optional
# spelling suggestions.
export def NotFound(suggestions: list<any> = []): dict<any>
  return {status: 'notfound', entries: [], suggestions: suggestions, message: ''}
enddef

# FUNCTION: Return a result for a failed lookup.
export def Error(message: string): dict<any>
  return {status: 'error', entries: [], suggestions: [], message: message}
enddef
