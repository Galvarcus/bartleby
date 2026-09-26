vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# pos.vim - the parts of Spotlight's part-of-speech modes that need no
# tagger: word lists, a tokenizer, word-list and pattern classification,
# which lines count as prose, and turning lit spans into dim positions.
# All pure functions, so tests can call them directly.
#
# Word lists live in tools/pos/<language>.json, one file per language,
# selected by g:bartleby_spotlight_language. g:bartleby_spotlight_words_add
# and g:bartleby_spotlight_words_remove change a mode's list:
#   {Fillers: ['kind of'], Pronouns: ['yall']}
# Mode names map to list keys in MODE_LISTS.
#
# Spans are [start, end] byte offsets in a line, 0-based, end exclusive.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var posscriptpath: string = expand('<sfile>:p')
var loaded_lists: dict<dict<any>> = {}

# Mode name -> word-list key in tools/pos/<language>.json.
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

# Shared with syntax/fountain.vim's fountainCharacter and
# fountainSceneHeading rules. Keep them in sync.
export const FOUNTAIN_CHARACTER_PATTERN: string = '^\L*$'
export const FOUNTAIN_SCENE_HEADING_PATTERN: string = '^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)\|^\.\a'

# A word: letters, with inner apostrophes ("don't", "o’clock").
const WORD_PATTERN: string = '\v[[:alpha:]]+%([''’][[:alpha:]]+)*'
const CONTRACTION_PATTERN: string = '\c\v%(n[''’]t|[''’]%(re|ve|ll|d|m))$'
const S_CONTRACTION_PATTERN: string = '\c\v^(.+)[''’]s$'
# "n't" contractions whose base is not the part before "n't".
const NT_BASES: dict<string> = {ca: 'can', wo: 'will', sha: 'shall', ai: 'am'}

export def PluginRoot(): string
  return fnamemodify(posscriptpath, ':h:h:h')
enddef

# The word lists for `language`, with the user's additions and removals
# applied, as dicts for fast lookup: {pronouns: {i: true, ...}, ...}.
# Cached after the first load. {} if the language file is missing.
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

# Forgets loaded lists, so changed settings take effect.
export def ClearLists(): void
  loaded_lists = {}
enddef

# Every word in `text`: [[start, end], ...].
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

# True for "don't", "they're", "we'll", "I'd", "I'm", and for "'s" only
# after a word in the s_contraction_words list ("it's", "that's"). After
# any other word, "'s" is usually possessive ("John's hat"), so it does
# not count.
export def IsContraction(word: string, lists: dict<any>): bool
  if word =~ CONTRACTION_PATTERN
    return true
  endif
  var parts: list<string> = matchlist(word, S_CONTRACTION_PATTERN)
  return !empty(parts) && has_key(get(lists, 's_contraction_words', {}), tolower(parts[1]))
enddef

# A word in the adverbs list, or a word ending in "-ly" that is not in
# adverb_exceptions ("family", "friendly"). A heuristic: the tagger is
# used instead when one is set.
export def IsHeuristicAdverb(word: string, lists: dict<any>): bool
  var lower: string = tolower(word)
  if has_key(get(lists, 'adverbs', {}), lower)
    return true
  endif
  return lower =~# '..ly$' && !has_key(get(lists, 'adverb_exceptions', {}), lower)
enddef

# The spans of `text` that `mode` lights, by word list or pattern.
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
      # "it's" and "they're" count as pronouns, "don't" as an auxiliary:
      # try the word, then its base form (see ContractionBase()).
      var lower: string = tolower(word)
      lit = has_key(words, lower) || has_key(words, ContractionBase(lower))
    endif
    if lit
      spans->add([start, end])
    endif
  endfor
  return spans
enddef

# False for lines that are structure, not prose: Markdown headings, and
# in Fountain, scene headings, character cues, and transitions. A mode
# lights nothing on these lines. Blank lines are not prose either.
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

# The dim positions for one line, for matchaddpos(): the gaps between the
# lit `spans`, as [lnum, col, length] with a 1-based byte column. Gaps of
# only whitespace are skipped: they show no difference when dimmed, and
# fewer positions keep redraws fast.
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

# The word a contraction is built on: "don't" -> "do", "can't" -> "can",
# "won't" -> "will", "they're" -> "they". `word` is lowercase.
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
