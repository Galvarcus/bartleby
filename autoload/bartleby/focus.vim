vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# focus.vim - Focus: distraction-free composition mode, converted from
# Goyo (github.com/junegunn/goyo.vim) into a native vim9class component.
# Opens the current buffer alone in a new tab, framed by four invisible
# "pad" windows that center a fixed-width (and optionally fixed-height)
# writing column, with statusline/tabline/ruler hidden and chrome
# highlight groups blended into the background. Multiple concurrent
# sessions are supported (one per tab, mirroring Goyo's own t:-scoped
# state) via the tab-local t:bartleby_focus_session variable.
#
# Dropped from the original during conversion: decorative background
# patterns (goyo_decoration_*). Third-party statusline plugin
# integration (gitgutter/signify/airline/powerline/lightline) IS kept -
# see DisableThirdPartyStatuslines()/RestoreThirdPartyStatuslines() below -
# since a plugin actively managing its own statusline content (airline in
# particular) will keep reasserting it regardless of 'laststatus'. GVim
# IS a target for this project too, so guioptions handling (hiding
# scrollbars) is also kept, matching Goyo's own has('gui_running') guards.
#
# `User BartlebyFocusEnter`/`User BartlebyFocusLeave` autocmd events fire
# once setup/before teardown respectively (ported from Goyo's own User
# GoyoEnter/GoyoLeave) - the extension point for anything added later:
# a GUI font, entering GUI fullscreen, 'spell', an external dictionary
# lookup (e.g. sdcv) binding, etc. None of that needs to live in this
# file; it can all hook in independently via those two events.
#
# Paragraph dimming - what Limelight actually does - is deliberately NOT
# part of this file; that's Spotlight's job (phase 5b), used alongside
# Focus rather than folded into it.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var focuswidth: any = g:bartleby_focus_width
var focusheight: any = g:bartleby_focus_height
var focusmargintop: number = g:bartleby_focus_margin_top
var focusmarginbottom: number = g:bartleby_focus_margin_bottom
var focuslinenr: number = g:bartleby_focus_linenr
var focusbg: string = g:bartleby_focus_bg

def RelSize(expr: any, limit: number): number
  if type(expr) ==# v:t_number
    return expr
  endif
  var text: string = expr
  if text !~# '%$'
    return str2nr(text)
  endif
  return limit * str2nr(text[ : -2]) / 100
enddef

def ClampVal(val: number, lo: number, hi: number): number
  return min([max([val, lo]), hi])
enddef


# ---------------------------------------------------------------------
# Third-party statusline plugin integration. Several popular statusline
# plugins actively manage their own status line content via their own
# autocmds, which fights a bare `set laststatus=0` - airline in
# particular reasserts itself on window/buffer events regardless of
# 'laststatus'. All silent!-guarded, so this is a harmless no-op for
# anyone without a given plugin installed - ported directly from Goyo's
# own equivalent handling.
# ---------------------------------------------------------------------

def DisableThirdPartyStatuslines(): dict<bool>
  var disabled: dict<bool> = {}

  disabled.gitgutter = get(g:, 'gitgutter_enabled', 0) != 0
  if disabled.gitgutter
    silent! execute 'GitGutterDisable'
  endif

  disabled.signify = !empty(getbufvar(bufnr('%'), 'sy'))
  if disabled.signify
    silent! execute 'SignifyToggle'
  endif

  disabled.airline = exists('#airline')
  if disabled.airline
    silent! execute 'AirlineToggle'
  endif

  disabled.powerline = exists('#PowerlineMain')
  if disabled.powerline
    augroup PowerlineMain
      autocmd!
    augroup END
    augroup! PowerlineMain
  endif

  disabled.lightline = exists('#lightline')
  if disabled.lightline
    silent! call lightline#disable()
  endif

  return disabled
enddef

def RestoreThirdPartyStatuslines(disabled: dict<bool>): void
  if get(disabled, 'gitgutter', false)
    silent! execute 'GitGutterEnable'
  endif

  if get(disabled, 'signify', false)
    silent! execute 'SignifyToggle'
  endif

  if get(disabled, 'airline', false) && !exists('#airline')
    silent! execute 'AirlineToggle'
    # Airline needs two refreshes to avoid a rendering glitch on re-enable -
    # matches Goyo's own comment on this exact workaround.
    silent! execute 'AirlineRefresh'
    silent! execute 'AirlineRefresh'
  endif

  if get(disabled, 'powerline', false) && !exists('#PowerlineMain')
    doautocmd PowerlineStartup VimEnter
    silent! execute 'PowerlineReloadColorscheme'
  endif

  if get(disabled, 'lightline', false)
    silent! call lightline#enable()
  endif

  if exists('#Powerline')
    doautocmd Powerline ColorScheme
  endif
enddef

# ---------------------------------------------------------------------
# Global <C-w>{key} mappings, active for as long as any Focus session is
# open in any tab. Genuinely global (not buffer-local) because Vim window
# commands are - matches Goyo's own approach, including its handling of
# concurrent sessions: a second session's setup only maps keys the first
# didn't already claim, and tracks (in its own mappedKeys) only the ones
# it's responsible for unmapping again.
# ---------------------------------------------------------------------

def MapsNop(): list<string>
  var candidates: list<string> = ['R', 'H', 'J', 'K', 'L', '|', '_']
  var mapped: list<string> = candidates->filter((_, c) => maparg('<C-w>' .. c, 'n') ==# '')
  for c in mapped
    execute 'nnoremap <C-w>' .. escape(c, '|') .. ' <nop>'
  endfor
  return mapped
enddef

# Dispatches a <C-w>{key} resize mapping to whichever tab's session is
# current when the key is actually pressed - the mapping itself is
# global, but its effect should only ever touch the session for the tab
# you're in right now.
def FocusResizeKey(key: string): void
  if !exists('t:bartleby_focus_session')
    return
  endif
  var session: FocusSession = t:bartleby_focus_session
  var count: number = v:count1
  if key ==# '='
    session.ResetDimensions(session.dimExpr)
  elseif key ==# '>'
    session.AdjustWidth(2 * count)
  elseif key ==# '<'
    session.AdjustWidth(-2 * count)
  elseif key ==# '+'
    session.AdjustHeight(2 * count)
  elseif key ==# '-'
    session.AdjustHeight(-2 * count)
  endif
enddef

def MapsResize(): list<string>
  var keys: list<string> = ['=', '>', '<', '+', '-']
  var mapped: list<string> = keys->filter((_, c) => maparg('<C-w>' .. c, 'n') ==# '')
  for c in mapped
    execute $'nnoremap <silent> <C-w>{c} <ScriptCmd>FocusResizeKey({string(c)})<CR>'
  endfor
  return mapped
enddef

def UnmapCtrlW(keys: list<string>): void
  for c in keys
    execute 'nunmap <C-w>' .. escape(c, '|')
  endfor
enddef

# ---------------------------------------------------------------------
# Session lifecycle. Enter()/Exit() are free functions (not methods) so
# they can create/destroy the FocusSession object itself, plus drive the
# tab-split and global-option save/restore that surrounds it.
# ---------------------------------------------------------------------

def Enter(dimExpr: string): void
  if exists('t:bartleby_focus_session')
    return
  endif

  var dim: Dimensions = Dimensions.Parse(dimExpr)
  if dim is null_object
    log.Error($'invalid dimension expression: {dimExpr}')
    return
  endif

  var origTabNr: number = tabpagenr()
  var saved: dict<any> = {
    laststatus: &laststatus,
    showtabline: &showtabline,
    fillchars: &fillchars,
    winminwidth: &winminwidth,
    winwidth: &winwidth,
    winminheight: &winminheight,
    winheight: &winheight,
    ruler: &ruler,
    sidescroll: &sidescroll,
    sidescrolloff: &sidescrolloff,
  }
  if has('gui_running')
    saved.guioptions = &guioptions
  endif

  tab split
  var pluginState: dict<bool> = DisableThirdPartyStatuslines()
  var mappedKeys: list<string> = MapsNop() + MapsResize()
  var session: FocusSession = FocusSession.new(origTabNr, winbufnr(0), dim, dimExpr, saved,
    mappedKeys, pluginState)
  t:bartleby_focus_session = session

  session.HideLinenr()
  &winheight = max([&winminheight, 1])
  set winminheight=1
  set winheight=1
  set winminwidth=1 winwidth=1
  set laststatus=0
  set showtabline=0
  set noruler
  set fillchars+=vert:\ 
  set fillchars+=stl:\ 
  set fillchars+=stlnc:\ 
  set sidescroll=1
  set sidescrolloff=0

  # Hide left-hand scrollbars in GVim.
  if has('gui_running')
    set guioptions-=l
    set guioptions-=L
  endif

  var lBuf: number = session.InitPad('vertical topleft new')
  var rBuf: number = session.InitPad('vertical botright new')
  var tBuf: number = session.InitPad('topleft new')
  var bBuf: number = session.InitPad('botright new')
  session.SetPadBufs(lBuf, rBuf, tBuf, bBuf)

  session.ResizePads()
  session.Tranquilize()

  augroup bartleby_focus
    autocmd!
    autocmd TabLeave * ++nested FocusAutoExit()
    autocmd VimResized * FocusAutoResize()
    autocmd ColorScheme * FocusAutoTranquilize()
    autocmd BufWinEnter * FocusAutoHideChrome()
    autocmd WinEnter,WinLeave * FocusAutoHideStatusline()
  augroup END

  session.HideStatusline()

  # Extension point for anything that should activate alongside Focus -
  # a GUI font/fullscreen toggle, 'spell', an external dictionary lookup
  # binding, etc. None of that lives here; it hooks in independently via
  # e.g. `autocmd User BartlebyFocusEnter ...` (and the matching
  # BartlebyFocusLeave below to reverse it), without ever needing to
  # touch this file. Ported from Goyo's own User GoyoEnter/GoyoLeave.
  if exists('#User#BartlebyFocusEnter')
    doautocmd User BartlebyFocusEnter
  endif
enddef

def Exit(): void
  if !exists('t:bartleby_focus_session')
    return
  endif
  var session: FocusSession = t:bartleby_focus_session

  # Fired before any teardown begins, so a BartlebyFocusEnter hook's own
  # handler can still see/reverse whatever it set up (fullscreen, a
  # temporary mapping, ...) while the focus window is still current.
  if exists('#User#BartlebyFocusLeave')
    doautocmd User BartlebyFocusLeave
  endif

  augroup bartleby_focus
    autocmd!
  augroup END
  augroup bartleby_focus_pad
    autocmd!
  augroup END
  UnmapCtrlW(session.mappedKeys)

  var origTabNr: number = session.origTab
  var masterBuf: number = session.masterBuf
  var saved: dict<any> = session.saved
  var savedLine: number = line('.')
  var savedCol: number = col('.')

  if tabpagenr() ==# 1
    tabnew
    normal! gt
    bdelete
  endif
  tabclose
  execute 'tabnext ' .. origTabNr
  if winbufnr(0) ==# masterBuf
    cursor(savedLine, savedCol)
  endif
  RestoreThirdPartyStatuslines(session.pluginState)

  &winwidth = saved.winwidth
  &winminwidth = saved.winminwidth
  &winheight = max([saved.winminheight, 1])
  &winminheight = saved.winminheight
  &winheight = saved.winheight
  &laststatus = saved.laststatus
  &showtabline = saved.showtabline
  &fillchars = saved.fillchars
  &ruler = saved.ruler
  &sidescroll = saved.sidescroll
  &sidescrolloff = saved.sidescrolloff
  if has_key(saved, 'guioptions')
    &guioptions = saved.guioptions
  endif

  # tranquilize() overwrote highlight groups directly, and those are
  # global rather than tab-scoped - re-applying the colorscheme is what
  # actually undoes that, not anything tab-local closing away.
  if exists('g:colors_name')
    execute 'colorscheme ' .. g:colors_name
  else
    colorscheme default
  endif
enddef

# ---------------------------------------------------------------------
# Autocmd trampolines - all fired globally (TabLeave/VimResized/etc. have
# no buffer/window scoping to hang off of), each a no-op unless the
# *current* tab happens to have an active session.
# ---------------------------------------------------------------------

def FocusAutoExit(): void
  if exists('t:bartleby_focus_session')
    Exit()
  endif
enddef

def FocusAutoResize(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.ResizePads()
  endif
enddef

def FocusAutoTranquilize(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.Tranquilize()
  endif
enddef

def FocusAutoHideChrome(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.HideLinenr()
    session.HideStatusline()
  endif
enddef

def FocusAutoHideStatusline(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.HideStatusline()
  endif
enddef

# ---------------------------------------------------------------------
# Public entry points.
# ---------------------------------------------------------------------

# Plain toggle, no dimension argument - what <leader>bz calls.
export def Toggle(): void
  if exists('t:bartleby_focus_session')
    Exit()
  else
    Enter('')
  endif
enddef

# Backs :BartlebyFocus[!] [dim] - bang always exits; a bare dim argument
# while already active live-adjusts the running session instead of
# restarting it (matches Goyo's own :Goyo <dim> behavior).
export def Execute(bang: bool, dimExpr: string): void
  if bang
    Exit()
    return
  endif

  if !exists('t:bartleby_focus_session')
    Enter(dimExpr)
  elseif dimExpr !=# ''
    var session: FocusSession = t:bartleby_focus_session
    session.ResetDimensions(dimExpr)
  else
    Exit()
  endif
enddef

# A parsed set of pad dimensions - width/height of the centered writing
# column, plus xoff/yoff to shift it off-center if requested.
class Dimensions
  var width: number
  var height: number
  var xoff: number = 0
  var yoff: number = 0

  static def Default(): Dimensions
    var dim: Dimensions = Dimensions.new()
    dim.width = RelSize(focuswidth, &columns)
    if focusmargintop < 0 && focusmarginbottom < 0
      dim.height = RelSize(focusheight, &lines)
      dim.yoff = 0
    else
      var top: number = max([0, RelSize(focusmargintop < 0 ? 4 : focusmargintop, &lines)])
      var bot: number = max([0, RelSize(focusmarginbottom < 0 ? 4 : focusmarginbottom, &lines)])
      dim.height = &lines - top - bot
      dim.yoff = top - bot
    endif
    return dim
  enddef

  # Parses a Goyo-style dimension expression - "<width>[+-xoff]x<height>
  # [+-yoff]", every part optional, layered over the global defaults
  # above. null_object (not an error) on a malformed expression, so a
  # mistyped :BartlebyFocus argument can just no-op rather than crash.
  static def Parse(expr: string): Dimensions
    var dim: Dimensions = Dimensions.Default()
    if expr ==# ''
      return dim
    endif
    var parts: list<string> = matchlist(expr,
      '^\s*\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\%(x\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\)\?\s*$')
    if empty(parts)
      return null_object
    endif
    if parts[1] !=# ''
      dim.width = RelSize(parts[1], &columns)
    endif
    if parts[2] !=# ''
      dim.xoff = RelSize(parts[2], &columns)
    endif
    if parts[3] !=# ''
      dim.height = RelSize(parts[3], &lines)
    endif
    if parts[4] !=# ''
      dim.yoff = RelSize(parts[4], &lines)
    endif
    return dim
  enddef

  # Field writes from outside this class aren't allowed (E1335) - these
  # exist so FocusSession can clamp/adjust an existing Dimensions object
  # without needing to reconstruct one from scratch each time.
  def ClampTo(maxWidth: number, maxHeight: number): void
    this.width = ClampVal(this.width, 2, maxWidth)
    this.height = ClampVal(this.height, 2, maxHeight)
  enddef

  def AdjustWidth(delta: number): void
    this.width += delta
  enddef

  def AdjustHeight(delta: number): void
    this.height += delta
  enddef
endclass

# One active Focus session, living in its own tab. Mirrors Goyo's t:goyo_*
# tab-local variables as class fields instead, stored in
# t:bartleby_focus_session on the tab it owns.
export class FocusSession
  var origTab: number
  var masterBuf: number
  var dim: Dimensions
  var dimExpr: string
  var saved: dict<any>
  var mappedKeys: list<string>
  var pluginState: dict<bool>
  var padBufs: dict<number> = {}

  def new(this.origTab, this.masterBuf, this.dim, this.dimExpr, this.saved, this.mappedKeys,
      this.pluginState)
  enddef

  def SetPadBufs(l: number, r: number, t: number, b: number): void
    this.padBufs = {l: l, r: r, t: t, b: b}
  enddef

  # Bounces the user back out of a pad window the instant they wander
  # into one (WinEnter/CursorMoved on the pad's own buffer - see
  # SetupPad()), and treats a visibly-collapsed pad layout (someone
  # managed to close/resize one) as reason enough to give up and exit
  # cleanly rather than leave a broken layout on screen.
  def Blank(repel: string): void
    if bufwinnr(this.padBufs.r) <= bufwinnr(this.padBufs.l) + 1
        || bufwinnr(this.padBufs.b) <= bufwinnr(this.padBufs.t) + 3
      # Exit() changes the window layout (tabclose, tabnew, ...), which
      # newer Vim refuses to allow synchronously from within a WinEnter
      # autocmd (E1312). Defer it to run right after this autocmd
      # finishes instead, when that restriction no longer applies.
      timer_start(0, (_) => Exit())
      return
    endif
    execute 'noautocmd wincmd ' .. repel
  enddef

  def HideStatusline(): void
    setlocal statusline=\ 
  enddef

  def HideLinenr(): void
    if !focuslinenr
      setlocal nonumber
      if exists('&relativenumber')
        setlocal norelativenumber
      endif
    endif
    if exists('&colorcolumn')
      setlocal colorcolumn=
    endif
  enddef

  # Creates one pad window via `openCmd` (e.g. 'vertical topleft new'),
  # configures it as inert chrome, and returns to the window that was
  # current beforehand - called four times in Enter(), once per side.
  def InitPad(openCmd: string): number
    execute openCmd
    setlocal buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
    setlocal nonumber nocursorline nocursorcolumn winfixwidth winfixheight
    setlocal statusline=\ 
    if exists('&relativenumber')
      setlocal norelativenumber
    endif
    if exists('&colorcolumn')
      setlocal colorcolumn=
    endif
    var bufNr: number = winbufnr(0)
    execute ':' .. winnr('#') .. 'wincmd w'
    return bufNr
  enddef

  # Sizes and positions one already-created pad, and wires its
  # Blank()/HideStatusline() autocmds. `repel` is the wincmd direction to
  # bounce back in if the user ends up in this pad anyway.
  def SetupPad(bufNr: number, vert: bool, size: number, repel: string): void
    var win: number = bufwinnr(bufNr)
    execute ':' .. win .. 'wincmd w'
    execute (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])

    augroup bartleby_focus_pad
      execute $'autocmd WinEnter,CursorMoved <buffer> ++nested t:bartleby_focus_session.Blank({string(repel)})'
      autocmd WinLeave <buffer> ++nested t:bartleby_focus_session.HideStatusline()
    augroup END

    # Padding out short pad windows with blank lines hides GUI scrollbars
    # that would otherwise appear alongside an obviously-empty buffer.
    var diff: number = winheight(0) - line('$')
    if diff > 0
      setlocal modifiable
      append(0, repeat([''], diff))
      normal! gg
      setlocal nomodifiable
    endif

    execute ':' .. winnr('#') .. 'wincmd w'
  enddef

  def ResizePads(): void
    augroup bartleby_focus_pad
      autocmd!
    augroup END

    this.dim.ClampTo(&columns, &lines)

    var vmargin: number = max([0, (&lines - this.dim.height) / 2 - 1])
    var yoff: number = ClampVal(this.dim.yoff, -vmargin, vmargin)
    var top: number = vmargin + yoff
    var bot: number = vmargin - yoff - 1
    this.SetupPad(this.padBufs.t, false, top, 'j')
    this.SetupPad(this.padBufs.b, false, bot, 'k')

    var nwidth: number = max([len(string(line('$'))) + 1, &numberwidth])
    var width: number = this.dim.width + (&number ? nwidth : 0)
    var hmargin: number = max([0, (&columns - width) / 2 - 1])
    var xoff: number = ClampVal(this.dim.xoff, -hmargin, hmargin)
    this.SetupPad(this.padBufs.l, true, hmargin + xoff, 'l')
    this.SetupPad(this.padBufs.r, true, hmargin - xoff, 'h')
  enddef

  # Recolors the chrome highlight groups to blend into the background,
  # so the pad windows and (already-blanked) statusline/vertical-split
  # fillchars read as empty space rather than visible borders.
  def Tranquilize(): void
    var bg: string = synIDattr(synIDtrans(hlID('Normal')), 'bg#')
    var gui: bool = has('gui_running') || (has('termguicolors') && &termguicolors)
    var attr: string = gui ? 'gui' : 'cterm'
    var groups: list<string> = ['NonText', 'FoldColumn', 'ColorColumn',
      'VertSplit', 'StatusLine', 'StatusLineNC', 'SignColumn']
    for grp in groups
      if bg ==# '-1' || bg ==# ''
        execute $'highlight {grp} {attr}fg={focusbg} {attr}bg=NONE'
      else
        execute $'highlight {grp} {attr}fg={bg} {attr}bg={bg}'
      endif
      execute $'highlight {grp} {attr}=NONE'
    endfor
  enddef

  def AdjustWidth(delta: number): void
    this.dim.AdjustWidth(delta)
    this.ResizePads()
  enddef

  def AdjustHeight(delta: number): void
    this.dim.AdjustHeight(delta)
    this.ResizePads()
  enddef

  def ResetDimensions(expr: string): void
    var parsed: Dimensions = Dimensions.Parse(expr)
    if parsed isnot null_object
      this.dim = parsed
    endif
    this.ResizePads()
  enddef
endclass
