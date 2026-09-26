vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexicon.vim: Merriam-Webster dictionary and thesaurus lookups through
# dictionaryapi.com: settings, requests, response parsing, and a cache.
# The popups are in lexiconpopup.vim.
#
# Each kind, dictionary and thesaurus, is on only when its own API key is
# set, in g:bartleby_<kind>_api_key or else $BARTLEBY_MW_<KIND>_KEY, and
# curl is installed. Merriam-Webster issues one key per product, so the
# two kinds are independent.
#
# REFERENCES is the hook for other Merriam-Webster references. It holds
# only the Collegiate Dictionary and Collegiate Thesaurus now. To add one,
# add an entry with its apiName and the kind whose parser fits its JSON,
# for example learners: {apiName: 'learners', kind: 'dictionary'}. Then
# g:bartleby_<kind>_reference selects it.
#
# curl runs through job_start, so Vim does not wait for the network. The
# URL contains the key, so curl reads it on stdin as a config line, never
# on the command line, where process listings show it. It is never
# logged.
#
# Parsed results are cached in memory and on disk, in
# ~/.bartleby/lexicon_cache.json, by reference and word, never by key.
# Only ok and notfound results are cached. The disk cache holds at most
# g:bartleby_lexicon_cache_max_entries results and removes the oldest
# first. 0 turns the disk cache off. CACHE_VERSION changes when the
# parsed format changes, which discards an older cache file.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

var memory_cache: dict<dict<any>> = {}
var disk_cache_loaded: bool = false

export const KIND_DICTIONARY: string = 'dictionary'
export const KIND_THESAURUS: string = 'thesaurus'

export const REFERENCES: dict<dict<string>> = {
  collegiate: {
    apiName: 'collegiate',
    kind: KIND_DICTIONARY,
    title: 'Merriam-Webster Dictionary',
  },
  thesaurus: {
    apiName: 'thesaurus',
    kind: KIND_THESAURUS,
    title: 'Merriam-Webster Thesaurus',
  },
}

const CACHE_VERSION: number = 1
const ENV_KEYS: dict<string> = {
  [KIND_DICTIONARY]: 'BARTLEBY_MW_DICTIONARY_KEY',
  [KIND_THESAURUS]: 'BARTLEBY_MW_THESAURUS_KEY',
}

# FUNCTION: Return the API key for kind: the g: variable when set, else
# the environment variable, else an empty string.
export def ApiKey(kind: string): string
  var key: string = get(g:, $'bartleby_{kind}_api_key', '')
  if key ==# ''
    key = getenv(ENV_KEYS[kind]) ?? ''
  endif
  return trim(key)
enddef

# FUNCTION: Return the configured reference for kind, or an empty dict
# when the name is not registered or belongs to the other kind.
export def Reference(kind: string): dict<string>
  var name: string = get(g:, $'bartleby_{kind}_reference', '')
  var ref: dict<string> = get(REFERENCES, name, {})
  return get(ref, 'kind', '') ==# kind ? ref : {}
enddef

# FUNCTION: Return why kind is off, or an empty string when it is on.
export def DisabledReason(kind: string): string
  if ApiKey(kind) ==# ''
    return $'{kind} lookups are off - set g:bartleby_{kind}_api_key (or ${ENV_KEYS[kind]})'
  endif
  if empty(Reference(kind))
    var name: string = get(g:, $'bartleby_{kind}_reference', '')
    return $'g:bartleby_{kind}_reference "{name}" is not a known {kind} reference'
  endif
  if !executable('curl')
    return $'{kind} lookups need curl, which was not found'
  endif
  return ''
enddef

export def IsEnabled(kind: string): bool
  return DisabledReason(kind) ==# ''
enddef

# FUNCTION: Make a lookup word from raw text: trim it, drop a possessive
# s, strip punctuation at both ends, join inner spaces, and lowercase it.
export def CleanWord(raw: string): string
  var word: string = trim(raw)
  word = substitute(word, "['’]s$", '', '')
  word = substitute(word, "^[[:punct:]“”‘’]\\+", '', '')
  word = substitute(word, "[[:punct:]“”‘’]\\+$", '', '')
  word = substitute(word, '\s\+', ' ', 'g')
  return tolower(word)
enddef

# FUNCTION: Percent-encode every byte outside the RFC 3986 unreserved set.
export def UrlEncode(text: string): string
  var encoded: string = ''
  for ch in split(text, '\zs')
    if ch =~# '^[A-Za-z0-9._~-]$'
      encoded ..= ch
    else
      for byte in str2blob([ch])
        encoded ..= printf('%%%02X', byte)
      endfor
    endif
  endfor
  return encoded
enddef

export def BuildUrl(kind: string, word: string): string
  var base: string = substitute(g:bartleby_lexicon_base_url, '/\+$', '', '')
  return $'{base}/{Reference(kind).apiName}/json/{UrlEncode(word)}?key={ApiKey(kind)}'
enddef

# FUNCTION: Give replacement the capitalization of original: all capitals
# when original has more than one letter and all are capitals, a capital
# first letter, or no change.
export def MatchCase(original: string, replacement: string): string
  if strchars(original) > 1 && original =~# '^\u\+$'
    return toupper(replacement)
  endif
  if original =~# '^\u'
    return toupper(strcharpart(replacement, 0, 1)) .. strcharpart(replacement, 1)
  endif
  return replacement
enddef

# FUNCTION: Parse a Merriam-Webster response body. Return a dict:
#   status:      ok, notfound, or error
#   entries:     dictionary: [{headword, display, fl, defs}]
#                thesaurus:  [{headword, fl, senses: [{label, syns}], ants}]
#   suggestions: spelling suggestions when status is notfound
#   message:     error text when status is error
# Merriam-Webster answers a bad key with plain text, not JSON. A body that
# is not JSON becomes an error with its first line.
export def ParseResponse(kind: string, word: string, body: string): dict<any>
  var text: string = trim(body)
  if text ==# ''
    return ErrorResult('empty response from Merriam-Webster')
  endif
  var data: any
  try
    data = json_decode(text)
  catch
    return ErrorResult('Merriam-Webster: ' .. strcharpart(split(text, "\n")[0], 0, 120))
  endtry
  if type(data) != v:t_list
    return ErrorResult('unexpected response from Merriam-Webster')
  endif
  if empty(data) || data->copy()->filter((_, v) => type(v) != v:t_string)->empty()
    return {status: 'notfound', entries: [], suggestions: data, message: ''}
  endif

  var raw: list<dict<any>> = data->copy()->filter((_, v) => type(v) == v:t_dict)
  var matching: list<dict<any>> = raw->copy()->filter((_, e) => IsEntryFor(e, word))
  var chosen: list<dict<any>> = empty(matching) ? raw : matching

  var entries: list<dict<any>> = kind ==# KIND_THESAURUS
    ? chosen->mapnew((_, e) => ThesaurusEntry(e))
    : chosen->mapnew((_, e) => DictionaryEntry(e))
  entries = entries->filter((_, e) => !empty(e))
  if empty(entries)
    return {status: 'notfound', entries: [], suggestions: [], message: ''}
  endif
  return {status: 'ok', entries: entries, suggestions: [], message: ''}
enddef

# FUNCTION: Look up word, already cleaned, and call Callback with the
# parsed result. A cached result also arrives through a timer, so the
# callback always runs after Lookup returns.
export def Lookup(kind: string, word: string, Callback: func(dict<any>)): void
  var reason: string = DisabledReason(kind)
  if reason !=# ''
    timer_start(0, (_) => Callback(ErrorResult(reason)))
    return
  endif
  var cacheKey: string = $'{Reference(kind).apiName}:{word}'
  var cached: dict<any> = CacheGet(cacheKey)
  if !empty(cached)
    timer_start(0, (_) => Callback(cached))
    return
  endif
  StartRequest(kind, word, cacheKey, Callback)
enddef

# FUNCTION: Remove every cached result, in memory and on disk.
export def ClearCache(): void
  memory_cache = {}
  disk_cache_loaded = true
  if filereadable(CachePath())
    delete(CachePath())
  endif
enddef

def ErrorResult(message: string): dict<any>
  return {status: 'error', entries: [], suggestions: [], message: message}
enddef

def StripSyllables(headword: string): string
  return substitute(headword, '\*', '', 'g')
enddef

def IsEntryFor(entry: dict<any>, word: string): bool
  var meta: dict<any> = get(entry, 'meta', {})
  var stems: list<any> = get(meta, 'stems', [])
  if index(stems->mapnew((_, s) => tolower(s)), word) >= 0
    return true
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', '')
  return tolower(StripSyllables(hw)) ==# word
enddef

def DictionaryEntry(entry: dict<any>): dict<any>
  var defs: list<any> = get(entry, 'shortdef', [])->filter((_, d) => type(d) == v:t_string)
  if empty(defs)
    return {}
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', get(get(entry, 'meta', {}), 'id', ''))
  return {
    headword: StripSyllables(hw),
    display: substitute(hw, '\*', '·', 'g'),
    fl: get(entry, 'fl', ''),
    defs: defs,
  }
enddef

def ThesaurusEntry(entry: dict<any>): dict<any>
  var meta: dict<any> = get(entry, 'meta', {})
  var synLists: list<any> = get(meta, 'syns', [])
  var shortdefs: list<any> = get(entry, 'shortdef', [])
  var senses: list<dict<any>> = []
  for i in range(len(synLists))
    if !empty(synLists[i])
      senses->add({label: get(shortdefs, i, ''), syns: synLists[i]})
    endif
  endfor
  var ants: list<any> = flattennew(get(meta, 'ants', []))->uniq()
  if empty(senses) && empty(ants)
    return {}
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', get(meta, 'id', ''))
  return {
    headword: StripSyllables(hw),
    fl: get(entry, 'fl', ''),
    senses: senses,
    ants: ants,
  }
enddef

def StartRequest(kind: string, word: string, cacheKey: string,
    Callback: func(dict<any>)): void
  var out: list<string> = []
  var err: list<string> = []
  var state: dict<any> = {closed: false, exited: false, done: false, code: -1}

  # Output is complete only after both callbacks: exit_cb can arrive while
  # output is still waiting in the channel.
  var Finish = () => {
    if !state.closed || !state.exited || state.done
      return
    endif
    state.done = true
    if state.code != 0
      var detail: string = empty(err) ? $'exit code {state.code}' : trim(split(join(err, ''), "\n")[0])
      Callback(ErrorResult($'lookup failed: {detail}'))
      return
    endif
    var result: dict<any> = ParseResponse(kind, word, join(out, ''))
    if result.status !=# 'error'
      CachePut(cacheKey, result)
    endif
    Callback(result)
  }

  var job: job = job_start(['curl', '--silent', '--show-error',
      '--max-time', string(g:bartleby_lexicon_timeout), '--config', '-'], {
    in_io: 'pipe',
    out_mode: 'raw',
    err_mode: 'raw',
    out_cb: (_, msg) => {
      out->add(msg)
    },
    err_cb: (_, msg) => {
      err->add(msg)
    },
    close_cb: (_) => {
      state.closed = true
      Finish()
    },
    exit_cb: (_, code) => {
      state.exited = true
      state.code = code
      Finish()
    },
  })
  if job_status(job) ==# 'fail'
    Callback(ErrorResult('could not start curl'))
    return
  endif
  ch_sendraw(job, $'url = "{BuildUrl(kind, word)}"' .. "\n")
  ch_close_in(job)
enddef

def CachePath(): string
  return expand('~/.bartleby/lexicon_cache.json')
enddef

def LoadDiskCache(): void
  if disk_cache_loaded
    return
  endif
  disk_cache_loaded = true
  if g:bartleby_lexicon_cache_max_entries <= 0 || !filereadable(CachePath())
    return
  endif
  try
    var data: any = json_decode(join(readfile(CachePath()), "\n"))
    if type(data) == v:t_dict && get(data, 'version', 0) == CACHE_VERSION
      memory_cache = extend(get(data, 'entries', {}), memory_cache)
    endif
  catch
    log.Warn($'ignoring unreadable lexicon cache: {CachePath()}')
  endtry
enddef

def CacheGet(key: string): dict<any>
  LoadDiskCache()
  return has_key(memory_cache, key) ? memory_cache[key].result : {}
enddef

def CachePut(key: string, result: dict<any>): void
  memory_cache[key] = {time: localtime(), result: result}
  var limit: number = g:bartleby_lexicon_cache_max_entries
  if limit <= 0
    return
  endif
  if len(memory_cache) > limit
    var excess: number = len(memory_cache) - limit
    var oldestFirst: list<string> = keys(memory_cache)
      ->sort((a, b) => memory_cache[a].time - memory_cache[b].time)
    for staleKey in oldestFirst[0 : excess - 1]
      remove(memory_cache, staleKey)
    endfor
  endif
  try
    mkdir(fnamemodify(CachePath(), ':h'), 'p')
    writefile([json_encode({version: CACHE_VERSION, entries: memory_cache})], CachePath())
  catch
    log.Warn($'could not write lexicon cache: {CachePath()}')
  endtry
enddef
