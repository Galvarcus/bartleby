vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# spotlight.vim - Spotlight: paragraph/pattern-based prose highlighting,
# converted from Limelight (github.com/junegunn/limelight.vim) into a
# native vim9class component. Used alongside Focus, not folded into it -
# Focus owns the distraction-free window layout, Spotlight owns what gets
# visually emphasized within it.
#
# Mechanism (a mode returns what to DIM -
# NOT a "bright overlay" pattern): this went through a real design
# mistake worth recording. The first version dimmed everything with one
# match, then tried to restore the in-focus region with a second,
# higher-priority "bright" match. That looked right in isolation, but it
# silently broke syntax highlighting inside the bright region - any
# matchadd() match that defines a color, at any priority, always wins
# over syntax highlighting underneath it, since syntax sits below all
# matchadd() priorities regardless of the numbers used. A "bright" match
# with every attribute set to NONE doesn't fix it either (confirmed by
# testing) - it just makes the *next-highest* matchadd() match win, which
# is still the dim match, never the real syntax color. There is no
# override-based fix. So instead, exactly like Limelight's own original
# design: dim ONLY the text that should be dimmed, and never touch the
# in-focus region with a match at all - then it keeps its syntax
# highlighting for the simple reason that nothing ever overwrote it.
# Paragraph mode is a direct port of Limelight's own two-region dim
# (everything before the paragraph, everything after), as one regex.
# Every other mode lights scattered spans (quoted speech, or words of one
# part of speech), so it computes the dim gaps between them and applies
# them with matchaddpos(), not as a regex. A regex with one alternative
# per gap redraws far too slowly: measured on 1,100 gaps, 157 ms per
# redraw as a regex against 1 ms as positions.
#
# Part-of-speech modes (Nouns, Adverbs, Passive, ...) take their words
# from word lists and patterns (pos.vim), or from a part-of-speech tagger
# when one is set (tagger.vim). Nouns, Verbs, Adjectives, and Passive
# need the tagger and are hidden without one.
#
# Color math (Dim(), Hex2Rgb(), GrayContiguous(), GrayAnsi(),
# ValidateCoeff()) is a faithful, unmodified port of Limelight's own
# gui/256-color blending - genuinely nicer than a flat highlight-group
# swap, so kept as-is rather than simplified away.
#
# Dropped from the original: the operator/visual-mode fixed-range feature
# (w:limelight_range and its <Plug> mapping) - not asked for this round;
# flag it if worth adding back.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/pos.vim' as P
import autoload 'bartleby/tagger.vim' as Tg

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var spotlightdefaultcoefficient: float = g:bartleby_spotlight_default_coefficient
var spotlightconcealguifg: string = g:bartleby_spotlight_conceal_guifg
var spotlightconcealctermfg: string = g:bartleby_spotlight_conceal_ctermfg
var spotlightbop: string = g:bartleby_spotlight_bop
var spotlighteop: string = g:bartleby_spotlight_eop
var spotlightparagraphspan: number = g:bartleby_spotlight_paragraph_span
var spotlightpriority: number = g:bartleby_spotlight_priority
var spotlightdialoguepattern: string = g:bartleby_spotlight_dialogue_pattern
var spotlightlanguage: string = g:bartleby_spotlight_language

##############################################################################
# Mode registry. A handler takes the mode name and returns what to dim -
# the text that should be dimmed, never the text that stays lit:
#   {key: string, pattern: string}          a regex (Paragraph)
#   {key: string, positions: list<any>}     matchaddpos() positions
# `key` identifies the result, so an unchanged result is not reapplied.
# Handlers are plain functions that receive the mode name, not closures.
##############################################################################

const MODE_PARAGRAPH: string = 'Paragraph'
const MODE_DIALOGUE: string = 'Dialogue'
const MODE_PASSIVE: string = 'Passive'
const PICKER_TITLE: string = 'Spotlight Mode: '

var mode_handlers: dict<func(string): dict<any>> = {}
var mode_available: dict<func(): bool> = {}
var mode_order: list<string> = []

# Last positions per buffer, keyed by mode, text, window range, and
# tagger results. See CachedPositions().
var span_cache: dict<dict<any>> = {}
const SPOTLIGHT_DIALOGUE_WINDOW_MARGIN: number = 200
const SPOTLIGHT_POS_WINDOW_MARGIN: number = 50
# How far past the window edge a paragraph is followed, so that a
# paragraph cut by the edge is still classified as a whole.
const SPOTLIGHT_PARAGRAPH_LIMIT: number = 200

# Part-of-speech modes, in picker order, and the Universal POS tags that
# light a word when a tagger is set. [] means the mode always uses its
# word list or pattern (pos.vim). Nouns, Verbs, and Adjectives have no
# word list, so they need the tagger, as does Passive.
const POS_MODES: list<string> = [
  'Nouns', 'Verbs', 'Adjectives', 'Adverbs', 'Pronouns', 'Determiners',
  'Prepositions', 'Conjunctions', 'Auxiliaries', 'Contractions', 'Fillers',
]
const POS_TAGS: dict<list<string>> = {
  Nouns: ['NOUN', 'PROPN'],
  Verbs: ['VERB'],
  Adjectives: ['ADJ'],
  Adverbs: ['ADV'],
  Pronouns: ['PRON'],
  Determiners: ['DET'],
  Prepositions: ['ADP'],
  Conjunctions: ['CCONJ', 'SCONJ'],
  Auxiliaries: ['AUX'],
  Contractions: [],
  Fillers: [],
}
const TAGGER_ONLY_MODES: list<string> = ['Nouns', 'Verbs', 'Adjectives', 'Passive']

const GRAY_CONVERTER: dict<number> = {0: 231, 7: 254, 15: 256, 16: 231, 231: 256}

var current_mode: string = MODE_PARAGRAPH
var current_coeff: float = -1.0

def RegisterMode(name: string, Handler: func(string): dict<any>,
    Available: func(): bool): void
  if !has_key(mode_handlers, name)
    mode_order->add(name)
  endif
  mode_handlers[name] = Handler
  mode_available[name] = Available
enddef

# For the mode picker (PickMode()) and for validating a :BartlebySpotlight
# argument - every mode usable now, in registration order.
export def AvailableModes(): list<string>
  return mode_order->copy()->filter((_, name) => mode_available[name]())
enddef

def IsModeAvailable(name: string): bool
  return has_key(mode_handlers, name) && mode_available[name]()
enddef

def Always(): bool
  return true
enddef

def TaggerReady(): bool
  return Tg.IsReady()
enddef

# True when `mode` takes its words from the tagger now.
def UsesTagger(mode: string): bool
  return mode ==# MODE_PASSIVE || (!empty(get(POS_TAGS, mode, [])) && Tg.IsReady())
enddef

# Everything before and after the paragraph containing the cursor - a
# direct port of Limelight's own s:getpos()/s:hl(). g:bartleby_spotlight_
# paragraph_span (Limelight's g:limelight_paragraph_span) includes that
# many additional paragraphs on each side before dimming starts.
def ParagraphPattern(): string
  var emptyAdjust: number = getline('.') =~# '^\s*$' ? 1 : 0
  var span: number = max([0, spotlightparagraphspan - emptyAdjust])

  var pos: list<number> = getcurpos()
  var start: number = 0
  for i in range(0, span)
    start = searchpos(spotlightbop, i == 0 ? 'cbW' : 'bW')[0]
  endfor
  setpos('.', pos)

  var endLine: number = 0
  for _ in range(0, span)
    endLine = searchpos(spotlighteop, 'W')[0]
  endfor
  setpos('.', pos)

  # \%<0l (when start is 0, meaning bop never matched - cursor's
  # paragraph is the buffer's first) matches no line at all, a
  # deliberately harmless no-op rather than a special case - same trick
  # Limelight's own s:hl() relies on.
  var patterns: list<string> = [$'\%<{start}l.']
  if endLine > 0
    patterns->add($'\%>{endLine}l.')
  endif
  return join(patterns, '\|')
enddef

# Everything NOT inside a double-quoted span (straight or curly quotes) -
# direct speech in standard English prose convention. Scans each line for
# the quote pattern and dims only the gaps between matches, so a quoted
# span is never touched by any match at all (see the module doc comment
# for why that matters). Doesn't span multiple paragraphs/lines (neither
# does typical dialogue formatting - a speaker's line that runs on past a
# paragraph break conventionally drops the closing quote and reopens a
# new one, which is its own hard problem this regex doesn't attempt).
# Override the quote pattern itself via g:bartleby_spotlight_dialogue_
# pattern for other quoting conventions (e.g. guillemets, single quotes).
#
# Windowed to the visible viewport plus a margin, and cached per buffer
# by [changedtick, window range] (see CachedPositions()). Scrolling
# recomputes through the CursorMoved and WinScrolled autocommands, so
# text outside the margin is processed before it becomes visible.

def VisibleLineRange(margin: number): list<number>
  return [max([1, line('w0') - margin]), min([line('$'), line('w$') + margin])]
enddef

def ParagraphSpec(mode: string): dict<any>
  var pattern: string = ParagraphPattern()
  return {key: $'{mode}:{pattern}', pattern: pattern}
enddef

# The positions of mode `mode` for the window range, reused while the
# buffer text, the range, and the tagger results stay the same.
def CachedPositions(mode: string, margin: number,
    Compute: func(string, number, number): list<any>): dict<any>
  var bufNr: number = bufnr('%')
  var [first: number, last: number] = VisibleLineRange(margin)
  # The Insert-mode state is part of the key: the tagger skips requests
  # while you type, so a result computed in Insert mode must not be
  # reused after it.
  var typing: string = mode() =~# '^[iR]' ? 'i' : 'n'
  var key: string = $'{mode}:{bufNr}:{b:changedtick}:{first}:{last}:{Tg.Generation()}:{typing}'
  var cached: dict<any> = get(span_cache, bufNr, {})
  if get(cached, 'key', '') ==# key
    return cached
  endif
  var spec: dict<any> = {key: key, positions: Compute(mode, first, last)}
  span_cache[bufNr] = spec
  return spec
enddef

# Dim positions for a whole non-blank line.
def WholeLine(lnum: number, text: string): list<any>
  return text =~ '\S' ? [[lnum]] : []
enddef

def DialogueSpec(mode: string): dict<any>
  return CachedPositions(mode, SPOTLIGHT_DIALOGUE_WINDOW_MARGIN, DialoguePositions)
enddef

def DialoguePositions(mode: string, first: number, last: number): list<any>
  return &filetype ==# 'fountain' ? FountainDialoguePositions(first, last)
    : ProseDialoguePositions(first, last)
enddef

def ProseDialoguePositions(first: number, last: number): list<any>
  var positions: list<any> = []
  for lnum in range(first, last)
    var text: string = getline(lnum)
    var spans: list<list<number>> = []
    var from: number = 0
    while true
      var found: list<any> = matchstrpos(text, spotlightdialoguepattern, from)
      if found[1] < 0 || found[2] <= found[1]
        break
      endif
      spans->add([found[1], found[2]])
      from = found[2]
    endwhile
    positions += empty(spans) ? WholeLine(lnum, text) : P.GapPositions(lnum, text, spans)
  endfor
  return positions
enddef

# Fountain screenplays have no quoted dialogue at all - a character cue
# (an all-caps line, optionally with trailing parentheticals like
# "(V.O.)", that isn't itself a scene heading) is followed by one or
# more unquoted lines of spoken dialogue, ending at the next blank line.
def IsFountainCharacterCue(text: string): bool
  if text ==# '' || text =~# P.FOUNTAIN_SCENE_HEADING_PATTERN
    return false
  endif
  return text =~# P.FOUNTAIN_CHARACTER_PATTERN
enddef

def FountainDialoguePositions(first: number, last: number): list<any>
  var positions: list<any> = []
  var total: number = line('$')

  # A dialogue block is stateful across lines (cue, then its following
  # non-blank lines) - starting the window mid-block would otherwise
  # misclassify those lines as narration, since the scan never sees the
  # cue that opened it. Look backward from `first` to check.
  var lnum: number = first
  var back: number = first - 1
  while back >= 1 && getline(back) !=# ''
    if IsFountainCharacterCue(getline(back))
      var dEnd: number = back + 1
      while dEnd <= total && getline(dEnd) !=# ''
        dEnd += 1
      endwhile
      lnum = dEnd
      break
    endif
    back -= 1
  endwhile

  while lnum <= last
    var text: string = getline(lnum)
    positions += WholeLine(lnum, text)
    if IsFountainCharacterCue(text)
      # The cue line dims (it's not spoken dialogue); the block of
      # non-blank lines right after it is the lit dialogue.
      lnum += 1
      while lnum <= total && getline(lnum) !=# ''
        lnum += 1
      endwhile
    else
      lnum += 1
    endif
  endwhile
  return positions
enddef

def PosSpec(mode: string): dict<any>
  return CachedPositions(mode, SPOTLIGHT_POS_WINDOW_MARGIN, PosPositions)
enddef

# Lights the words of part of speech `mode` and dims the rest of each
# prose line. Structure lines (headings, Fountain cues) dim entirely.
# The range is widened to whole paragraphs, so that the tagger always
# sees complete sentences and each paragraph keeps one cache entry.
def PosPositions(mode: string, first: number, last: number): list<any>
  var ft: string = &filetype
  var total: number = line('$')
  var start: number = first
  while start > 1 && first - start < SPOTLIGHT_PARAGRAPH_LIMIT
      && P.IsProseLine(getline(start - 1), ft)
    start -= 1
  endwhile
  var stop: number = last
  while stop < total && stop - last < SPOTLIGHT_PARAGRAPH_LIMIT
      && P.IsProseLine(getline(stop + 1), ft)
    stop += 1
  endwhile

  var tagged: bool = UsesTagger(mode)
  var lists: dict<any> = tagged ? {} : P.Lists(spotlightlanguage)
  var positions: list<any> = []
  var lnum: number = start
  while lnum <= stop
    var text: string = getline(lnum)
    if !P.IsProseLine(text, ft)
      positions += WholeLine(lnum, text)
      lnum += 1
      continue
    endif
    var blockStart: number = lnum
    var lines: list<string> = []
    while lnum <= stop && P.IsProseLine(getline(lnum), ft)
      lines->add(getline(lnum))
      lnum += 1
    endwhile
    positions += tagged ? TaggedPositions(mode, blockStart, lines)
      : LexicalPositions(mode, blockStart, lines, lists)
  endwhile
  return positions
enddef

def LexicalPositions(mode: string, blockStart: number, lines: list<string>,
    lists: dict<any>): list<any>
  var positions: list<any> = []
  for i in range(len(lines))
    positions += P.GapPositions(blockStart + i, lines[i], P.LexicalSpans(mode, lines[i], lists))
  endfor
  return positions
enddef

# Positions from the tagger's results for one paragraph. While the
# results are not ready, the paragraph is left undimmed; the tagger's
# update then redraws it.
def TaggedPositions(mode: string, blockStart: number, lines: list<string>): list<any>
  var tags: dict<any> = Tg.Tags(join(lines, "\n"))
  if empty(tags)
    return []
  endif
  var spans: list<any>
  if mode ==# MODE_PASSIVE
    spans = tags.passive
  else
    var wanted: list<string> = POS_TAGS[mode]
    spans = tags.tokens->copy()->filter((_, t) => index(wanted, t[2]) >= 0)
  endif

  # Paragraph byte offsets -> per-line spans. A span that crosses a line
  # break (a passive "was / opened") is split at it.
  var perLine: list<list<list<number>>> = []
  var starts: list<number> = []
  var offset: number = 0
  for text in lines
    perLine->add([])
    starts->add(offset)
    offset += strlen(text) + 1
  endfor
  for span in spans
    for i in range(len(lines))
      var lineStart: number = starts[i]
      var lineEnd: number = lineStart + strlen(lines[i])
      if span[0] < lineEnd && span[1] > lineStart
        perLine[i]->add([max([span[0], lineStart]) - lineStart, min([span[1], lineEnd]) - lineStart])
      endif
    endfor
  endfor

  var positions: list<any> = []
  for i in range(len(lines))
    positions += P.GapPositions(blockStart + i, lines[i], perLine[i])
  endfor
  return positions
enddef

RegisterMode(MODE_PARAGRAPH, ParagraphSpec, Always)
RegisterMode(MODE_DIALOGUE, DialogueSpec, Always)
for posMode in POS_MODES
  RegisterMode(posMode, PosSpec, index(TAGGER_ONLY_MODES, posMode) >= 0 ? TaggerReady : Always)
endfor
RegisterMode(MODE_PASSIVE, PosSpec, TaggerReady)

##############################################################################
# Color math - unmodified port of Limelight's own s:hex2rgb/s:dim/etc.
# Blends Normal's fg toward its bg by `coeff` (0.0 = no dim, 1.0 = fully
# bg-colored) for a smooth true-color/256-color dim, rather than just
# swapping in a fixed highlight group.
##############################################################################

def Hex2Rgb(str: string): list<number>
  var hex: string = substitute(str, '^#', '', '')
  return [str2nr(hex[0 : 1], 16), str2nr(hex[2 : 3], 16), str2nr(hex[4 : 5], 16)]
enddef

def GrayContiguous(col: number): number
  var val: number = get(GRAY_CONVERTER, col, col)
  if val < 231 || val > 256
    throw Unsupported()
  endif
  return val
enddef

def GrayAnsi(col: number): number
  if col ==# 231
    return 0
  elseif col ==# 256
    return 231
  endif
  return col
enddef

def ValidateCoeff(coeff: float): float
  var c: float = coeff < 0 ? spotlightdefaultcoefficient : coeff
  if c < 0 || c > 1
    throw 'Invalid g:bartleby_spotlight_default_coefficient. Expected: 0.0 ~ 1.0'
  endif
  return c
enddef

def Unsupported(): string
  var isGui: bool = has('gui_running')
  var varName: string = $'g:bartleby_spotlight_conceal_{isGui ? "gui" : "cterm"}fg'
  var concealSet: bool = isGui ? spotlightconcealguifg !=# '' : spotlightconcealctermfg !=# ''
  if concealSet
    return 'Cannot calculate background color.'
  endif
  return $'Unsupported color scheme. {varName} required.'
enddef

# Recomputes and applies the 'SpotlightDim' highlight group for the
# current colorscheme/coeff. Throws (Unsupported() or a coefficient
# range error) rather than failing silently - callers decide how to
# surface that.
def Dim(coeff: float): void
  var synid: number = synIDtrans(hlID('Normal'))
  var fg: string = synIDattr(synid, 'fg#')
  var bg: string = synIDattr(synid, 'bg#')

  if has('gui_running') || (has('termguicolors') && &termguicolors)
    var dim: string
    if coeff < 0 && spotlightconcealguifg !=# ''
      dim = spotlightconcealguifg
    elseif fg ==# '' || bg ==# ''
      throw Unsupported()
    else
      var c: float = ValidateCoeff(coeff)
      var fgRgb: list<number> = Hex2Rgb(fg)
      var bgRgb: list<number> = Hex2Rgb(bg)
      var dimRgb: list<number> = [
        float2nr(bgRgb[0] * c + fgRgb[0] * (1 - c)),
        float2nr(bgRgb[1] * c + fgRgb[1] * (1 - c)),
        float2nr(bgRgb[2] * c + fgRgb[2] * (1 - c)),
      ]
      dim = '#' .. join(dimRgb->mapnew((_, v) => printf('%02x', v)), '')
    endif
    execute $'highlight SpotlightDim guifg={dim} guisp=bg'
  elseif str2nr(&t_Co) ==# 256
    var dim: any
    if coeff < 0 && spotlightconcealctermfg !=# ''
      dim = spotlightconcealctermfg
    elseif str2nr(fg) <= -1 || str2nr(bg) <= -1
      throw Unsupported()
    else
      var c: float = ValidateCoeff(coeff)
      var fgGray: number = GrayContiguous(str2nr(fg))
      var bgGray: number = GrayContiguous(str2nr(bg))
      dim = GrayAnsi(float2nr(bgGray * c + fgGray * (1 - c)))
    endif
    execute $'highlight SpotlightDim ctermfg={dim}'
  else
    throw 'Unsupported terminal. Sorry.'
  endif
enddef

##############################################################################
# Per-window match bookkeeping. Matches are inherently window-scoped in
# Vim regardless of anything else, so even though Spotlight's on/off
# state is global (see IsOn() below - matches Limelight's own design),
# each window still needs its own dim match id. Lives in
# w:bartleby_spotlight_matches.
##############################################################################

class WindowMatches
  var dimMatchId: number = -1
  var prevKey: string = ''

  def ClearHl(): void
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevKey = ''
  enddef

  # `spec` is a mode handler's result: {key, pattern} or {key, positions}.
  def RefreshDim(spec: dict<any>): void
    if spec.key ==# this.prevKey
      return
    endif
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevKey = spec.key
    if has_key(spec, 'pattern')
      if spec.pattern !=# ''
        this.dimMatchId = matchadd('SpotlightDim', spec.pattern, spotlightpriority)
      endif
    elseif !empty(spec.positions)
      this.dimMatchId = matchaddpos('SpotlightDim', spec.positions, spotlightpriority)
    endif
  enddef
endclass

##############################################################################
# Session state and lifecycle.
##############################################################################

def CurrentHandler(): func(string): dict<any>
  return get(mode_handlers, current_mode, mode_handlers[MODE_PARAGRAPH])
enddef

def RefreshCurrentWindow(): void
  var wm: WindowMatches = get(w:, 'bartleby_spotlight_matches', null_object)
  if wm is null_object
    wm = WindowMatches.new()
    w:bartleby_spotlight_matches = wm
  endif
  var Handler: func(string): dict<any> = CurrentHandler()
  wm.RefreshDim(Handler(current_mode))
enddef

def RedimSafely(): void
  try
    Dim(current_coeff)
  catch
    Off()
    log.Error(v:exception)
  endtry
enddef

def CleanupIfOff(): void
  if !IsOn()
    var wm: WindowMatches = get(w:, 'bartleby_spotlight_matches', null_object)
    if wm isnot null_object
      wm.ClearHl()
    endif
  endif
enddef

export def IsOn(): bool
  return exists('#bartleby_spotlight')
enddef

def On(mode: string, coeffArg: float): void
  var actualMode: string = mode ==# '' ? current_mode : mode
  if !has_key(mode_handlers, actualMode)
    log.Error($'unknown Spotlight mode: {actualMode}')
    return
  endif
  if !mode_available[actualMode]()
    var reason: string = Tg.FailureReason()
    log.Error($'Spotlight mode {actualMode} needs a part-of-speech tagger - '
      .. (reason ==# '' ? 'set g:bartleby_spotlight_tagger' : reason))
    return
  endif
  current_mode = actualMode
  current_coeff = coeffArg

  try
    Dim(current_coeff)
  catch
    log.Error(v:exception)
    return
  endtry

  RefreshCurrentWindow()

  augroup bartleby_spotlight
    autocmd!
    autocmd CursorMoved,CursorMovedI,WinScrolled * RefreshCurrentWindow()
    # mode() still reports Insert mode during InsertLeave, and the tagger
    # sends no requests in Insert mode, so refresh just after it.
    autocmd InsertLeave * timer_start(0, (_) => RefreshCurrentWindow())
    autocmd ColorScheme * RedimSafely()
  augroup END
  augroup bartleby_spotlight_cleanup
    autocmd!
    autocmd WinEnter * CleanupIfOff()
  augroup END
enddef

export def Off(): void
  var wm: WindowMatches = get(w:, 'bartleby_spotlight_matches', null_object)
  if wm isnot null_object
    wm.ClearHl()
  endif
  augroup bartleby_spotlight
    autocmd!
  augroup END
  augroup! bartleby_spotlight
  unlet! w:bartleby_spotlight_matches
enddef

##############################################################################
# Public entry points.
##############################################################################

# Plain toggle, current mode - what <leader>bl calls.
export def Toggle(): void
  if IsOn()
    Off()
  else
    On('', -1.0)
  endif
enddef

# Searchable list of the available modes - what <leader>bL calls.
# Picking a mode turns Spotlight on with it, switching live if it was
# already on with a different mode.
export def PickMode(): void
  var modes: list<string> = AvailableModes()
  # Wide enough for the title with the longest mode name, plus 2, so the
  # title never shows truncated and the width does not change with the
  # current mode.
  var longest: number = max(modes->mapnew((_, m) => strdisplaywidth(m)))
  var width: number = strdisplaywidth(PICKER_TITLE) + longest + 2
  IP.PromptFilter(PICKER_TITLE .. current_mode, modes, (choice: string) => {
    On(choice, current_coeff)
  }, 10, width)
enddef

# Called by tagger.vim when results arrive or the tagger fails. Redraws
# the current window, or turns Spotlight off if the current mode can no
# longer run (tagger.vim has already reported why).
def OnTaggerUpdate(): void
  if !IsOn()
    return
  endif
  if !IsModeAvailable(current_mode)
    Off()
    return
  endif
  RefreshCurrentWindow()
enddef

Tg.OnUpdate(OnTaggerUpdate)

# Backs :BartlebySpotlight[!] [mode-name|coefficient] - bang always turns
# off; a bare mode name switches to it (turning on if needed); anything
# else is parsed as a coefficient (matches Limelight's own :Limelight
# <coefficient>).
export def Execute(bang: bool, args: string): void
  if bang
    if IsOn()
      Off()
    endif
    return
  endif

  if args ==# ''
    Toggle()
    return
  endif

  if has_key(mode_handlers, args)
    On(args, current_coeff)
  else
    On('', str2float(args))
  endif
enddef
