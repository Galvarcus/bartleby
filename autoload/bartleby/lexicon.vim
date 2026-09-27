vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexicon.vim: dictionary and thesaurus lookups: settings, keys,
# requests, and a cache, for every provider. The provider of a reference
# builds its URL and parses its response, as lexicon_mw.vim does for
# Merriam-Webster. The popups are in lexiconpopup.vim, and the result
# format in lexicon_result.vim.
#
# Each kind, dictionary and thesaurus, uses one reference of CO.REFERENCES:
# g:bartleby_<kind>_reference when set, else the one the language file
# names. A kind is on when its reference and provider exist, curl is
# installed, and, when the provider needs a key, the key is set in
# g:bartleby_<kind>_api_key or the provider's environment variable. For
# Merriam-Webster these are $BARTLEBY_MW_DICTIONARY_KEY and
# $BARTLEBY_MW_THESAURUS_KEY. It issues one key per product, so the two
# kinds are independent.
#
# curl runs through job_start, so Vim does not wait for the network. The
# URL can contain the key, so curl reads it on stdin as a config line,
# never on the command line, where process listings show it. It is never
# logged.
#
# Parsed results are cached in memory and on disk, in
# ~/.bartleby/lexicon_cache.json, by provider, reference, and word, never
# by key. Only ok and notfound results are cached. The disk cache holds at
# most g:bartleby_lexicon_cache_max_entries results and removes the oldest
# first. 0 turns the disk cache off. CACHE_VERSION changes when the parsed
# format or the cache key changes, which discards an older cache file.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/lexicon_mw.vim' as LM
import autoload 'bartleby/lexicon_result.vim' as LR
import autoload 'bartleby/log.vim' as L
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))

var memory_cache: dict<dict<any>> = {}
var disk_cache_loaded: bool = false



const CACHE_VERSION: number = 2

# FUNCTION: Return the configured reference for kind, or an empty dict
# when the name is not registered or belongs to the other kind. An empty
# setting means the reference of the language file.
export def Reference(kind: string): dict<string>
  var name: string = get(g:, $'bartleby_{kind}_reference', '')
  if name ==# ''
    name = LA.Get($'{kind}_reference', '')
  endif
  var ref: dict<string> = get(CO.REFERENCES, name, {})
  return get(ref, 'kind', '') ==# kind ? ref : {}
enddef

# FUNCTION: Return the API key for kind: the g: variable when set, else
# the environment variable of the reference's provider, else an empty
# string.
export def ApiKey(kind: string): string
  var key: string = get(g:, $'bartleby_{kind}_api_key', '')
  if key ==# ''
    var envName: string = get(get(Provider(get(Reference(kind), 'provider', '')), 'envKeys', {}), kind, '')
    key = envName ==# '' ? '' : (getenv(envName) ?? '')
  endif
  return trim(key)
enddef

# FUNCTION: Return why kind is off, or an empty string when it is on.
export def DisabledReason(kind: string): string
  var ref: dict<string> = Reference(kind)
  var provider: dict<any> = Provider(get(ref, 'provider', ''))
  if empty(ref) || empty(provider)
    var name: string = get(g:, $'bartleby_{kind}_reference', '')
    return printf(IN.T("no %s reference \"%s\" for this language"), KindName(kind),
      name ==# '' ? LA.Get($'{kind}_reference', '') : name)
  endif
  if provider.needsKey && ApiKey(kind) ==# ''
    var envName: string = get(provider.envKeys, kind, '')
    return printf(IN.T("%s lookups are off: set g:bartleby_%s_api_key or $%s"), KindName(kind), kind, envName)
  endif
  if !executable('curl')
    return printf(IN.T("%s lookups need curl, which was not found"), KindName(kind))
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

export def BuildUrl(kind: string, word: string): string
  var ref: dict<string> = Reference(kind)
  var F: func(dict<string>, string, string): string = Provider(ref.provider).buildUrl
  return F(ref, word, ApiKey(kind))
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

# FUNCTION: Parse a response body with the provider of kind's reference.
# The result follows lexicon_result.vim.
export def ParseResponse(kind: string, word: string, body: string): dict<any>
  var ref: dict<string> = Reference(kind)
  var provider: dict<any> = Provider(get(ref, 'provider', ''))
  if empty(provider)
    return LR.Error($'no {kind} reference for this language')
  endif
  var F: func(string, string, string): dict<any> = provider.parse
  return F(kind, word, body)
enddef

# FUNCTION: Look up word, already cleaned, and call Callback with the
# parsed result. A cached result also arrives through a timer, so the
# callback always runs after Lookup returns.
export def Lookup(kind: string, word: string, Callback: func(dict<any>)): void
  var reason: string = DisabledReason(kind)
  if reason !=# ''
    timer_start(0, (_) => Callback(LR.Error(reason)))
    return
  endif
  var ref: dict<string> = Reference(kind)
  var cacheKey: string = $'{ref.provider}:{ref.apiName}:{word}'
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

# FUNCTION: Return the translated name of kind, for messages.
def KindName(kind: string): string
  return kind ==# CO.KIND_THESAURUS ? IN.T("thesaurus") : IN.T("dictionary")
enddef

# FUNCTION: Return the provider name to its functions and key settings.
# To add a provider, write a script with BuildUrl and Parse, as
# lexicon_mw.vim, and add an entry here. envKeys names the environment
# variable that holds the key of each kind, when the provider needs one.
def Provider(name: string): dict<any>
  if name ==# 'merriam-webster'
    return {
      buildUrl: LM.BuildUrl,
      parse: LM.Parse,
      needsKey: true,
      envKeys: {
        [CO.KIND_DICTIONARY]: 'BARTLEBY_MW_DICTIONARY_KEY',
        [CO.KIND_THESAURUS]: 'BARTLEBY_MW_THESAURUS_KEY',
      },
    }
  endif
  return {}
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
      Callback(LR.Error($'lookup failed: {detail}'))
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
    Callback(LR.Error('could not start curl'))
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
    log.Warn(printf(IN.T("ignoring unreadable lexicon cache: %s"), CachePath()))
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
    log.Warn(printf(IN.T("could not write lexicon cache: %s"), CachePath()))
  endtry
enddef
