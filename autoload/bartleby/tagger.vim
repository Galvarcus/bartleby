vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# tagger.vim - runs the part-of-speech tagger for Spotlight's Nouns, Verbs,
# Adjectives, and Passive modes, and for the tagged versions of the other
# part-of-speech modes.
#
# g:bartleby_spotlight_tagger selects the tagger:
#   ''        no tagger (default). Tagger-only modes are hidden.
#   'spacy'   tools/pos/spacy_tagger.py, run with python3, using the model
#             in g:bartleby_spotlight_spacy_model.
#   [cmd...]  any command that speaks the same protocol. See the header
#             of tools/pos/spacy_tagger.py.
#
# The tagger starts on first use and keeps running, because loading a
# language model takes a second or more. Text goes to it one paragraph at
# a time. Results are cached by a SHA-256 hash of the paragraph text, so
# an unchanged paragraph is never sent again, and editing one paragraph
# resends only that one. Each result arrives asynchronously; OnUpdate()
# registers the function to call then (Spotlight's redraw).
#
# If the tagger cannot start or exits, the first line of its error output
# is logged once, and IsReady() stays false for the rest of the session.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/pos.vim' as P
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

var tagger_job: job = null_job
var failed: bool = false
var failure_reason: string = ''
var next_id: number = 1
# Request id -> paragraph hash, for requests not answered yet.
var pending: dict<string> = {}
# Paragraph hash -> {tokens: [[start, end, tag], ...],
#                    passive: [[start, end], ...]}
var cache: dict<dict<any>> = {}
var stderr_lines: list<string> = []
var generation: number = 0
var OnUpdateFn: func() = null_function

const CACHE_LIMIT: number = 5000

# The tagger command, or [] when none is set.
export def Command(): list<string>
  var setting: any = get(g:, 'bartleby_spotlight_tagger', '')
  if type(setting) == v:t_list
    return setting
  endif
  if setting ==# 'spacy'
    return ['python3', $'{P.PluginRoot()}/tools/pos/spacy_tagger.py',
      get(g:, 'bartleby_spotlight_spacy_model', 'en_core_web_sm')]
  endif
  return []
enddef

# True when a tagger is set, its program exists, and it has not failed.
export def IsReady(): bool
  var cmd: list<string> = Command()
  return !failed && !empty(cmd) && executable(cmd[0])
enddef

export def FailureReason(): string
  return failure_reason
enddef

# Changes each time a result arrives, so callers know to rebuild.
export def Generation(): number
  return generation
enddef

export def OnUpdate(Fn: func()): void
  OnUpdateFn = Fn
enddef

# The tags for `text` (one paragraph, lines joined with "\n"):
# {tokens, passive} with byte offsets into `text`. When they are not
# cached yet, requests them and returns {}.
export def Tags(text: string): dict<any>
  var hash: string = sha256(text)
  if has_key(cache, hash)
    return cache[hash]
  endif
  # No requests while typing: each key changes the paragraph, and one
  # request per key would queue faster than the tagger can answer. The
  # paragraph is tagged when you leave Insert mode.
  if !IsReady() || index(values(pending), hash) >= 0 || mode() =~# '^[iR]'
    return {}
  endif
  if !Start()
    return {}
  endif
  var id: number = next_id
  next_id += 1
  pending[string(id)] = hash
  ch_sendraw(tagger_job, json_encode({id: id, text: text}) .. "\n")
  return {}
enddef

export def Stop(): void
  if job_status(tagger_job) ==# 'run'
    job_stop(tagger_job)
  endif
  tagger_job = null_job
  pending = {}
enddef

# Stops the tagger and forgets its results and any failure, so that a
# changed g:bartleby_spotlight_tagger takes effect.
export def Reset(): void
  Stop()
  failed = false
  failure_reason = ''
  cache = {}
  generation += 1
enddef

def Start(): bool
  if job_status(tagger_job) ==# 'run'
    return true
  endif
  stderr_lines = []
  tagger_job = job_start(Command(), {
    in_mode: 'nl',
    out_mode: 'nl',
    err_mode: 'nl',
    out_cb: (_, line) => OnReply(line),
    err_cb: (_, line) => {
      stderr_lines->add(line)
    },
    exit_cb: (j, code) => OnExit(j, code),
  })
  if job_status(tagger_job) !=# 'run'
    Fail('the tagger command could not start: ' .. join(Command(), ' '))
    return false
  endif
  return true
enddef

def OnReply(line: string): void
  var reply: any
  try
    reply = json_decode(line)
  catch
    return
  endtry
  if type(reply) != v:t_dict
    return
  endif
  var key: string = string(get(reply, 'id', ''))
  if !has_key(pending, key)
    return
  endif
  if len(cache) >= CACHE_LIMIT
    cache = {}
  endif
  cache[pending[key]] = {
    tokens: get(reply, 'tokens', []),
    passive: get(reply, 'passive', []),
  }
  remove(pending, key)
  generation += 1
  if OnUpdateFn != null_function
    OnUpdateFn()
  endif
enddef

def OnExit(exited: job, code: number): void
  # A job that Stop() ended is no longer the current job: not a failure.
  if exited != tagger_job
    return
  endif
  if code != 0 && !failed
    var detail: string = empty(stderr_lines) ? $'exit code {code}' : stderr_lines[-1]
    Fail($'the part-of-speech tagger stopped: {detail}')
  endif
  tagger_job = null_job
  pending = {}
enddef

def Fail(reason: string): void
  failed = true
  failure_reason = reason
  log.Error(reason)
  generation += 1
  if OnUpdateFn != null_function
    OnUpdateFn()
  endif
enddef
