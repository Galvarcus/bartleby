vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# pos.vim: the parts of Spotlight's part-of-speech modes that need no
# tagger: word lists, a tokenizer, classification by word list and
# pattern, which lines count as prose, and conversion of bright spans to
# dim positions. All pure functions, so tests can call them directly.
#
# The word lists are in tools/pos/<language>.json, one file per language,
# selected by g:bartleby_spotlight_language. g:bartleby_spotlight_words_add
# and g:bartleby_spotlight_words_remove change the list of a mode, by
# mode name, with single words:
#   {Fillers: ['anyway'], Pronouns: ['yall']}
# MODE_LISTS maps mode names to list keys.
#
# A span is [start, end]: byte offsets in a line, 0-based, end exclusive.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var posscriptpath: string = expand('<sfile>:p')
var loaded_lists: dict<dict<any>> = {}

# Mode name to its list key in tools/pos/<language>.json.
export const MODE_LISTS: dict<string> = {
  Pronouns: 'pronouns',
  Determiners: 'determiners',
  Prepositions: 'prepositions',
  Conjunctions: 'conjunctions',
  Auxiliaries: 'auxiliaries',
  Fillers: 'fillers',
  Adverbs: 'adverbs',
  Contractions: 's_contraction_words',
}

# Shared with the fountainCharacter and fountainSceneHeading rules in
# syntax/fountain.vim. Keep them the same.
export const FOUNTAIN_CHARACTER_PATTERN: string = '^\L*$'
export const FOUNTAIN_SCENE_HEADING_PATTERN: string = '^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)\|^\.\a'

# A word: letters, with inner apostrophes, as in don't.
const WORD_PATTERN: string = '\v[[:alpha:]]+%([''’][[:alpha:]]+)*'
const CONTRACTION_PATTERN: string = '\c\v%(n[''’]t|[''’]%(re|ve|ll|d|m))$'
const S_CONTRACTION_PATTERN: string = '\c\v^(.+)[''’]s$'
# Contractions ending in n't whose base is not the text before n't.
const NT_BASES: dict<string> = {ca: 'can', wo: 'will', sha: 'shall', ai: 'am'}

export def PluginRoot(): string
  return fnamemodify(posscriptpath, ':h:h:h')
enddef

# FUNCTION: Return the word lists for language, with the user's additions
# and removals, as dicts for fast lookup: {pronouns: {i: true}}. Cached
# after the first load. An empty dict when the language file is missing.
export def Lists(language: string): dict<any>
  if has_key(loaded_lists, language)
    return loaded_lists[language]
  endif
  var path: string = $'{PluginRoot()}/tools/pos/{language}.json'
  var raw: dict<any> = {}
  try
    raw = json_decode(join(readfile(path), "\n"))
  catch
    log.Error($'no word lists for language "{language}": {path}')
    loaded_lists[language] = {}
    return {}
  endtry
  var lists: dict<any> = {}
  for [key, words] in items(raw)
    if type(words) == v:t_list
      lists[key] = ToSet(words)
    endif
  endfor
  for [mode, words] in items(get(g:, 'bartleby_spotlight_words_add', {}))
    var key: string = get(MODE_LISTS, mode, '')
    if key !=# ''
      extend(lists, {[key]: extend(get(lists, key, {}), ToSet(words))})
    endif
  endfor
  for [mode, words] in items(get(g:, 'bartleby_spotlight_words_remove', {}))
    var key: string = get(MODE_LISTS, mode, '')
    if key !=# '' && has_key(lists, key)
      for word in words
        if has_key(lists[key], tolower(word))
          remove(lists[key], tolower(word))
        endif
      endfor
    endif
  endfor
  loaded_lists[language] = lists
  return lists
enddef

# FUNCTION: Forget the loaded lists, so that changed settings apply.
export def ClearLists(): void
  loaded_lists = {}
enddef

# FUNCTION: Return the span of every word in text.
export def Tokens(text: string): list<list<number>>
  var tokens: list<list<number>> = []
  var from: number = 0
  while true
    var found: list<any> = matchstrpos(text, WORD_PATTERN, from)
    if found[1] < 0
      break
    endif
    tokens->add([found[1], found[2]])
    from = found[2]
  endwhile
  return tokens
enddef

# FUNCTION: Return true for a contraction such as don't, they're, we'll,
# I'd, or I'm, and for 's only after a word in s_contraction_words, as in
# it's or that's. After other words, 's usually shows possession, as in
# John's hat, so it does not count.
export def IsContraction(word: string, lists: dict<any>): bool
  if word =~ CONTRACTION_PATTERN
    return true
  endif
  var parts: list<string> = matchlist(word, S_CONTRACTION_PATTERN)
  return !empty(parts) && has_key(get(lists, 's_contraction_words', {}), tolower(parts[1]))
enddef

# FUNCTION: Return true for a word in the adverbs list, or a word ending
# in ly that is not in adverb_exceptions, such as family or friendly. A
# heuristic: the tagger replaces it when one is set.
export def IsHeuristicAdverb(word: string, lists: dict<any>): bool
  var lower: string = tolower(word)
  if has_key(get(lists, 'adverbs', {}), lower)
    return true
  endif
  return lower =~# '..ly$' && !has_key(get(lists, 'adverb_exceptions', {}), lower)
enddef

# FUNCTION: Return the spans of text that mode keeps bright, by word list
# or pattern.
export def LexicalSpans(mode: string, text: string, lists: dict<any>): list<list<number>>
  var spans: list<list<number>> = []
  var key: string = get(MODE_LISTS, mode, '')
  var words: dict<any> = get(lists, key, {})
  for [start, end] in Tokens(text)
    var word: string = strpart(text, start, end - start)
    var lit: bool
    if mode ==# 'Contractions'
      lit = IsContraction(word, lists)
    elseif mode ==# 'Adverbs'
      lit = IsHeuristicAdverb(word, lists)
    else
      # it's and they're count as pronouns and don't as an auxiliary: try the
      # word, then its base, see ContractionBase.
      var lower: string = tolower(word)
      lit = has_key(words, lower) || has_key(words, ContractionBase(lower))
    endif
    if lit
      spans->add([start, end])
    endif
  endfor
  return spans
enddef

# FUNCTION: Return false for a line that is structure, not prose: a
# Markdown heading, and in Fountain a scene heading, character cue, or
# transition. A mode keeps nothing bright on these lines. A blank line is
# not prose either.
export def IsProseLine(text: string, filetype: string): bool
  if text !~ '\S'
    return false
  endif
  if filetype ==# 'fountain'
    return text !~# FOUNTAIN_SCENE_HEADING_PATTERN
      && text !~# FOUNTAIN_CHARACTER_PATTERN
      && text !~# '^\s*>'
  endif
  return text !~# '^\s*#'
enddef

# FUNCTION: Return the dim positions of one line for matchaddpos: the gaps
# between the bright spans, as [lnum, col, length] with a 1-based byte
# column. Gaps of only spaces are skipped: dimming them shows no change,
# and fewer positions keep redraws fast.
export def GapPositions(lnum: number, text: string, spans: list<list<number>>): list<list<number>>
  var positions: list<list<number>> = []
  var cursor: number = 0
  for [start, end] in sort(copy(spans), (a, b) => a[0] - b[0])
    if start > cursor && strpart(text, cursor, start - cursor) =~ '\S'
      positions->add([lnum, cursor + 1, start - cursor])
    endif
    cursor = max([cursor, end])
  endfor
  if cursor < strlen(text) && strpart(text, cursor) =~ '\S'
    positions->add([lnum, cursor + 1, strlen(text) - cursor])
  endif
  return positions
enddef

# FUNCTION: Return the word a contraction is built on: don't gives do,
# can't gives can, won't gives will, and they're gives they. word is
# lowercase.
def ContractionBase(word: string): string
  if word =~ "n['’]t$"
    var base: string = substitute(word, "n['’]t$", '', '')
    return get(NT_BASES, base, base)
  endif
  return matchstr(word, "^[^'’]*")
enddef

def ToSet(words: list<any>): dict<bool>
  var set: dict<bool> = {}
  for word in words
    set[tolower(word)] = true
  endfor
  return set
enddef
