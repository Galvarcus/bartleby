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
# Mechanism (a mode is a func(): string returning the current DIM regex -
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
# (everything before the paragraph, everything after); Dialogue mode
# generalizes this to scattered spans by scanning each line for the
# quote pattern and dimming only the gaps between matches (see
# DialoguePattern()). A future pattern-based mode (Nouns, Verbs, ...)
# follows the same shape - compute the gaps around what should stay lit,
# never the lit text itself.
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
import autoload 'bartleby/picker.vim' as Pk

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var spotlightdefaultcoefficient: float = g:bartleby_spotlight_default_coefficient
var spotlightconcealguifg: string = g:bartleby_spotlight_conceal_guifg
var spotlightconcealctermfg: string = g:bartleby_spotlight_conceal_ctermfg
var spotlightbop: string = g:bartleby_spotlight_bop
var spotlighteop: string = g:bartleby_spotlight_eop
var spotlightparagraphspan: number = g:bartleby_spotlight_paragraph_span
var spotlightpriority: number = g:bartleby_spotlight_priority
var spotlightdialoguepattern: string = g:bartleby_spotlight_dialogue_pattern

# ---------------------------------------------------------------------
# Mode registry. Each handler is a func(): string returning the current
# DIM regex for that mode - the text that should be dimmed, never the
# text that should stay lit (see the module doc comment above for why).
# ---------------------------------------------------------------------

const MODE_PARAGRAPH: string = 'Paragraph'
const MODE_DIALOGUE: string = 'Dialogue'

var mode_handlers: dict<func(): string> = {}
var mode_order: list<string> = []

var dialogue_cache: dict<list<any>> = {}
const SPOTLIGHT_DIALOGUE_WINDOW_MARGIN: number = 200

# Same shared regex used by syntax/fountain.vim's fountainCharacter and
# fountainSceneHeading rules - keep the two in sync if either changes.
const FOUNTAIN_CHARACTER_PATTERN: string = '^\L*$'
const FOUNTAIN_SCENE_HEADING_PATTERN: string = '^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)\|^\.\a'

const GRAY_CONVERTER: dict<number> = {0: 231, 7: 254, 15: 256, 16: 231, 231: 256}

var current_mode: string = MODE_PARAGRAPH
var current_coeff: float = -1.0

def RegisterMode(name: string, Handler: func(): string): void
  if !has_key(mode_handlers, name)
    mode_order->add(name)
  endif
  mode_handlers[name] = Handler
enddef

# For the mode picker (PickMode()) and for validating a :BartlebySpotlight
# argument - every currently-registered mode, in registration order.
export def AvailableModes(): list<string>
  return copy(mode_order)
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
# Windowed to the visible viewport (+ a margin) rather than the whole
# buffer: a full-buffer scan builds one regex alternative per span, and
# on a large file this either crawls or hits E339 (pattern too long)
# outright - confirmed on a 10,000-line file. The existing CursorMoved
# re-application (see On()) already recomputes on every cursor move,
# including scrolls, so windowing loses nothing visible in practice -
# by the time text outside the margin would matter, the recompute has
# already caught up. Cached per-buffer by [changedtick, window range],
# since recomputing on every single cursor move within the SAME window
# would be pure waste - unlike Paragraph, nothing here depends on the
# exact cursor position, only on what's roughly in view.

def VisibleLineRange(): list<number>
  return [max([1, line('w0') - SPOTLIGHT_DIALOGUE_WINDOW_MARGIN]),
    min([line('$'), line('w$') + SPOTLIGHT_DIALOGUE_WINDOW_MARGIN])]
enddef

def DialoguePattern(): string
  var bufNr: number = bufnr('%')
  var [first: number, last: number] = VisibleLineRange()
  var cached: list<any> = get(dialogue_cache, bufNr, [])
  if len(cached) == 4 && cached[0] ==# b:changedtick && cached[1] == first && cached[2] == last
    return cached[3]
  endif

  var result: string = &filetype ==# 'fountain' ?
    FountainDialoguePattern(first, last) : ProseDialoguePattern(first, last)
  dialogue_cache[bufNr] = [b:changedtick, first, last, result]
  return result
enddef

def ProseDialoguePattern(first: number, last: number): string
  var quotePattern: string = spotlightdialoguepattern
  var patterns: list<string> = []
  for lnum in range(first, last)
    var text: string = getline(lnum)
    var searchFrom: number = 0
    var lastEnd: number = 0
    while true
      var mstart: number = match(text, quotePattern, searchFrom)
      if mstart == -1
        break
      endif
      var mend: number = matchend(text, quotePattern, searchFrom)
      if mstart > lastEnd
        patterns->add($'\%{lnum}l\%>{lastEnd}c\%<{mstart + 1}c.')
      endif
      lastEnd = mend
      searchFrom = mend
    endwhile
    if lastEnd < len(text)
      patterns->add($'\%{lnum}l\%>{lastEnd}c.')
    endif
  endfor
  return join(patterns, '\|')
enddef

# Fountain screenplays have no quoted dialogue at all - a character cue
# (an all-caps line, optionally with trailing parentheticals like
# "(V.O.)", that isn't itself a scene heading) is followed by one or
# more unquoted lines of spoken dialogue, ending at the next blank line.

def IsFountainCharacterCue(text: string): bool
  if text ==# '' || text =~# FOUNTAIN_SCENE_HEADING_PATTERN
    return false
  endif
  return text =~# FOUNTAIN_CHARACTER_PATTERN
enddef

def FountainDialoguePattern(first: number, last: number): string
  var patterns: list<string> = []
  var total: number = line('$')

  # A dialogue block is stateful across lines (cue, then its following
  # non-blank lines) - starting the window mid-block would otherwise
  # misclassify those lines as narration, since the scan never sees the
  # cue that opened it. Look backward from `first` to check.
  var lnum: number = first
  var back: number = first - 1
  while back >= 1 && getline(back) !=# ''
    if IsFountainCharacterCue(getline(back))
      # `first` starts inside this cue's dialogue block - skip to its
      # end without re-adding the cue line itself (outside the window).
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
    if IsFountainCharacterCue(getline(lnum))
      # The cue line itself dims (it's not spoken dialogue); the block
      # of non-blank lines right after it is the lit dialogue. This
      # inner scan may run a little past `last` to find the block's
      # real end - harmless, and needed for a correct boundary.
      patterns->add($'\%{lnum}l.')
      var dEnd: number = lnum + 1
      while dEnd <= total && getline(dEnd) !=# ''
        dEnd += 1
      endwhile
      lnum = dEnd
    else
      patterns->add($'\%{lnum}l.')
      lnum += 1
    endif
  endwhile
  return join(patterns, '\|')
enddef

RegisterMode(MODE_PARAGRAPH, ParagraphPattern)
RegisterMode(MODE_DIALOGUE, DialoguePattern)

# ---------------------------------------------------------------------
# Color math - unmodified port of Limelight's own s:hex2rgb/s:dim/etc.
# Blends Normal's fg toward its bg by `coeff` (0.0 = no dim, 1.0 = fully
# bg-colored) for a smooth true-color/256-color dim, rather than just
# swapping in a fixed highlight group.
# ---------------------------------------------------------------------

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

# ---------------------------------------------------------------------
# Per-window match bookkeeping. Matches are inherently window-scoped in
# Vim regardless of anything else, so even though Spotlight's on/off
# state is global (see IsOn() below - matches Limelight's own design),
# each window still needs its own dim match id. Lives in
# w:bartleby_spotlight_matches.
# ---------------------------------------------------------------------

class WindowMatches
  var dimMatchId: number = -1
  var prevPattern: string = ''

  def ClearHl(): void
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevPattern = ''
  enddef

  def RefreshDim(pattern: string): void
    if pattern ==# this.prevPattern
      return
    endif
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevPattern = pattern
    if pattern ==# ''
      return
    endif
    var priority: number = spotlightpriority
    this.dimMatchId = matchadd('SpotlightDim', pattern, priority)
  enddef
endclass

# ---------------------------------------------------------------------
# Session state and lifecycle.
# ---------------------------------------------------------------------

def CurrentHandler(): func(): string
  return get(mode_handlers, current_mode, mode_handlers[MODE_PARAGRAPH])
enddef

def RefreshCurrentWindow(): void
  var wm: WindowMatches = get(w:, 'bartleby_spotlight_matches', null_object)
  if wm is null_object
    wm = WindowMatches.new()
    w:bartleby_spotlight_matches = wm
  endif
  var Handler: func(): string = CurrentHandler()
  wm.RefreshDim(Handler())
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
    autocmd CursorMoved,CursorMovedI * RefreshCurrentWindow()
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

# ---------------------------------------------------------------------
# Public entry points.
# ---------------------------------------------------------------------

# Plain toggle, current mode - what <leader>bl calls.
export def Toggle(): void
  if IsOn()
    Off()
  else
    On('', -1.0)
  endif
enddef

# Radio-button mode picker (see picker.vim#PickOne's `current` param) -
# what <leader>bL calls. Picking a mode turns Spotlight on with it,
# switching live if it was already on with a different mode.
export def PickMode(): void
  Pk.PickOne('Spotlight Mode', AvailableModes(), (choice: string) => {
    On(choice, current_coeff)
  }, current_mode)
enddef

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
