vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# quill.vim - Quill: buffer-local word-processing mode, converted from
# vim-pencil (github.com/preservim/vim-pencil) into a native vim9class
# component. For use with Focus and the default editor window - a scrive
# document buffer gets Quill applied automatically (see AutoApply()).
#
# Three wrap modes: off, hard (textwidth + autoformat while inserting),
# soft (display wrap, no textwidth, gj/gk-style navigation). Detection
# scans modelines/long lines like Pencil's own s:detect_wrap_mode().
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log
import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/windows.vim' as W

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var quillwrapmodedefault: string = g:bartleby_quill_wrap_mode_default
var quilltextwidth: number = g:bartleby_quill_textwidth
var quillautoformat: bool = g:bartleby_quill_autoformat
var quilljoinspaces: bool = g:bartleby_quill_joinspaces
var quillcursorwrap: bool = g:bartleby_quill_cursorwrap
var quillconceallevel: number = g:bartleby_quill_conceallevel
var quillconcealcursor: string = g:bartleby_quill_concealcursor
var quillautoapply: bool = g:bartleby_quill_auto
var quillautoformatconfig: dict<any> = g:bartleby_quill_autoformat_config
var quillautoformataliases: dict<any> = g:bartleby_quill_autoformat_aliases

const MODE_OFF: number = 0
const MODE_HARD: number = 1
const MODE_SOFT: number = 2

# ---------------------------------------------------------------------
# Wrap-mode detection - scans modelines and sampled lines for a hint,
# ported from Pencil's s:doModelines/s:doOne/s:detect_wrap_mode.
# ---------------------------------------------------------------------

def ScanModelineItem(item: string, maxTw: number): number
  var m: list<string> = matchlist(item, '^\([a-z]\+\)=\([a-zA-Z0-9_.-]\+\)$')
  if len(m) > 1 && m[1] =~# 'textwidth\|tw'
    return max([maxTw, str2nr(m[2])])
  endif
  return maxTw
enddef

def ScanModeline(line: string, maxTw: number): number
  var result: number = maxTw
  var m: list<string> = matchlist(line,
    '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\s*\%(set\s\+\)\?\([^:]\+\):\S\@!')
  if len(m) > 0
    for item in split(m[3])
      result = ScanModelineItem(item, result)
    endfor
  endif
  var m2: list<string> = matchlist(line, '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\(.\+\)')
  if len(m2) > 0
    for item in split(m2[3], '[ \t:]')
      result = ScanModelineItem(item, result)
    endfor
  endif
  return result
enddef

def MaxTextwidthFromModelines(): number
  var maxTw: number = -1
  if line('$') > &modelines
    var candidates: list<string> = getline(1, &modelines) + getline(line('$') - &modelines, '$')
    for l in candidates
      if l =~# ':'
        maxTw = ScanModeline(l, maxTw)
      endif
    endfor
  else
    for l in getline(1, '$')
      maxTw = ScanModeline(l, maxTw)
    endfor
  endif
  return maxTw
enddef

def DetectWrapMode(maxTextwidth: number): number
  if maxTextwidth > 0
    return MODE_HARD
  endif
  if maxTextwidth ==# 0 || quillwrapmodedefault ==# 'soft'
    return MODE_SOFT
  endif
  var sample: number = g:bartleby_quill_soft_detect_sample
  var threshold: number = g:bartleby_quill_soft_detect_threshold
  for l in getline(1, sample)
    if len(l) > threshold
      return MODE_SOFT
    endif
  endfor
  return quillwrapmodedefault ==# 'off' ? MODE_OFF : MODE_HARD
enddef

# ---------------------------------------------------------------------
# Per-buffer session. Lives in b:bartleby_quill.
# ---------------------------------------------------------------------

export class QuillSession
  var wrapMode: number = MODE_OFF
  var maxTextwidth: number = -1
  var suspendAf: bool = false
  var crMapped: bool = false
  var lastAutoformat: bool = false

  def SetWrapMode(mode: number): void
    this.wrapMode = mode
  enddef

  def SetMaxTextwidth(tw: number): void
    this.maxTextwidth = tw
  enddef

  def SetSuspendAf(val: bool): void
    this.suspendAf = val
  enddef

  def SetCrMapped(val: bool): void
    this.crMapped = val
  enddef

  def SetLastAutoformat(val: bool): void
    this.lastAutoformat = val
  enddef
endclass

def CurrentSession(): QuillSession
  var session: QuillSession = get(b:, 'bartleby_quill', null_object)
  if session is null_object
    session = QuillSession.new()
    b:bartleby_quill = session
  endif
  return session
enddef

# ---------------------------------------------------------------------
# Autoformat - enabled only in hard mode, only during Insert, and only
# when the cursor isn't in a blacklisted syntax region (code blocks,
# headings, etc.) per g:bartleby_quill_autoformat_config.
# ---------------------------------------------------------------------

def SynStackNames(lnum: number, col: number): list<string>
  return synstack(lnum, col)->mapnew((_, id) => synIDattr(id, 'name'))
enddef

def MaybeEnableAutoformat(): void
  var session: QuillSession = CurrentSession()
  if session.suspendAf
    session.SetSuspendAf(false)
    return
  endif

  var ft: string = get(quillautoformataliases, &filetype, &filetype)
  var cfg: dict<any> = get(quillautoformatconfig, ft, {})
  var black: list<string> = get(cfg, 'black', [])
  var white: list<string> = get(cfg, 'white', [])
  var blackRe: string = empty(black) ? '' : '\v(' .. join(black, '|') .. ')'
  var whiteRe: string = empty(white) ? '' : '\v(' .. join(white, '|') .. ')'
  var enforcePrevLine: bool = get(cfg, 'enforce-previous-line', false)

  var lnum: number = line('.')
  var names: list<string> = SynStackNames(lnum, col('.'))
  var okay: bool = true

  if !empty(blackRe)
    for name in names
      if match(name, blackRe) >= 0
        okay = false
        break
      endif
    endfor
  endif

  if !empty(whiteRe) && !okay
    if empty(synstack(lnum, 1)) || empty(synstack(lnum, col('$') - 1))
      for name in names
        if match(name, whiteRe) >= 0
          okay = true
          break
        endif
      endfor
    endif
  endif

  if !empty(blackRe) && enforcePrevLine && okay && lnum > 1
    for name in SynStackNames(lnum - 1, 1)
      if match(name, blackRe) >= 0
        okay = false
        break
      endif
    endfor
  endif

  if okay
    set formatoptions+=a
  endif
enddef

# af: 1=enable, 0=disable, -1=toggle.
export def SetAutoFormat(af: number): void
  var session: QuillSession = CurrentSession()
  var newAf: bool = af ==# -1 ? !session.lastAutoformat : af ==# 1
  var isHard: bool = session.wrapMode ==# MODE_HARD

  if newAf && isHard
    augroup bartleby_quill_autoformat
      autocmd! * <buffer>
      autocmd InsertEnter <buffer> MaybeEnableAutoformat()
      autocmd InsertLeave <buffer> set formatoptions-=a
    augroup END
  else
    augroup bartleby_quill_autoformat
      autocmd! * <buffer>
    augroup END
    if newAf && !isHard
      log.Warn('autoformat can only be enabled in hard line break mode')
      return
    endif
  endif
  session.SetLastAutoformat(newAf)
enddef

# ---------------------------------------------------------------------
# Init - applies wrap-mode settings/mappings to the current buffer.
# wrapArg: 'detect'|'off'|'hard'|'soft'|'toggle'.
# ---------------------------------------------------------------------

def ApplyHardSettings(session: QuillSession): void
  if &modeline ==# false && session.maxTextwidth > 0
    execute $'setlocal textwidth={session.maxTextwidth}'
  elseif &textwidth ==# 0
    execute $'setlocal textwidth={quilltextwidth}'
  else
    setlocal textwidth<
  endif
  setlocal nowrap
enddef

def ApplySoftSettings(): void
  setlocal textwidth=0
  setlocal wrap
  if exists('&linebreak')
    setlocal linebreak
    setlocal breakat-=*
  endif
  if exists('&breakindent')
    setlocal breakindent
  endif
enddef

def ClearWrapSettings(): void
  if exists('&breakindent')
    setlocal breakindent<
  endif
  if exists('&smartindent')
    setlocal smartindent<
  endif
  if exists('&cindent')
    setlocal cindent<
  endif
  if exists('&conceal')
    setlocal conceallevel<
    setlocal concealcursor<
  endif
  setlocal indentexpr<
  setlocal autoindent<
  setlocal list<
  setlocal wrapmargin<
  setlocal formatoptions<
enddef

def SetupNavigationMaps(wrapMode: number): void
  if wrapMode ==# MODE_SOFT
    nnoremap <buffer> <silent> $ g$
    nnoremap <buffer> <silent> 0 g0
    xnoremap <buffer> <silent> $ g$
    xnoremap <buffer> <silent> 0 g0
    noremap <buffer> <silent> <Home> g<Home>
    noremap <buffer> <silent> <End> g<End>
    nnoremap <buffer> <silent> g0 0
    nnoremap <buffer> <silent> g$ $
    xnoremap <buffer> <silent> g0 0
    xnoremap <buffer> <silent> g$ $
    inoremap <buffer> <silent> <Home> <C-o>g<Home>
    inoremap <buffer> <silent> <End> <C-o>g<End>
  else
    silent! nunmap <buffer> $
    silent! nunmap <buffer> 0
    silent! xunmap <buffer> $
    silent! xunmap <buffer> 0
    silent! nunmap <buffer> <Home>
    silent! nunmap <buffer> <End>
    silent! iunmap <buffer> <Home>
    silent! iunmap <buffer> <End>
  endif

  if wrapMode !=# MODE_OFF
    nnoremap <buffer> <silent> j gj
    nnoremap <buffer> <silent> k gk
    xnoremap <buffer> <silent> j gj
    xnoremap <buffer> <silent> k gk
    noremap <buffer> <silent> <Up> gk
    noremap <buffer> <silent> <Down> gj
    nnoremap <buffer> <silent> gj j
    nnoremap <buffer> <silent> gk k
    xnoremap <buffer> <silent> gj j
    xnoremap <buffer> <silent> gk k
    inoremap <buffer> <silent> <Up> <C-o>g<Up>
    inoremap <buffer> <silent> <Down> <C-o>g<Down>
  else
    silent! nunmap <buffer> j
    silent! nunmap <buffer> k
    silent! xunmap <buffer> j
    silent! xunmap <buffer> k
    silent! unmap <buffer> <Up>
    silent! unmap <buffer> <Down>
    silent! iunmap <buffer> <Up>
    silent! iunmap <buffer> <Down>
  endif
enddef

def SetupPunctuationMaps(session: QuillSession): void
  if session.wrapMode !=# MODE_OFF
    for ch in ['.', '!', '?', ',', ';', ':']
      execute $'inoremap <buffer> {ch} {ch}<C-g>u'
    endfor
    inoremap <buffer> <C-u> <C-g>u<C-u>
    inoremap <buffer> <C-w> <C-g>u<C-w>
    if empty(maparg('<CR>', 'i'))
      inoremap <buffer> <CR> <C-g>u<CR>
      session.SetCrMapped(true)
    else
      session.SetCrMapped(false)
    endif
  else
    for ch in ['.', '!', '?', ',', ';', ':']
      execute $'silent! iunmap <buffer> {ch}'
    endfor
    silent! iunmap <buffer> <C-u>
    silent! iunmap <buffer> <C-w>
    if session.crMapped
      silent! iunmap <buffer> <CR>
    endif
  endif
enddef

export def Init(wrapArg: string = 'detect'): void
  var session: QuillSession = CurrentSession()
  session.SetSuspendAf(false)

  var mode: number = session.wrapMode
  if (mode !=# MODE_OFF && wrapArg ==# 'toggle') || wrapArg =~# '^\(0\|off\|disable\|false\)$'
    mode = MODE_OFF
  elseif wrapArg ==# 'hard'
    mode = MODE_HARD
  elseif wrapArg ==# 'soft'
    mode = MODE_SOFT
  elseif wrapArg ==# 'on' || wrapArg ==# 'toggle'
    session.SetMaxTextwidth(MaxTextwidthFromModelines())
    mode = DetectWrapMode(session.maxTextwidth)
  else
    session.SetMaxTextwidth(MaxTextwidthFromModelines())
    mode = DetectWrapMode(session.maxTextwidth)
  endif
  session.SetWrapMode(mode)

  SetAutoFormat(mode ==# MODE_HARD && quillautoformat ? 1 : 0)

  if mode ==# MODE_HARD
    ApplyHardSettings(session)
  elseif mode ==# MODE_SOFT
    ApplySoftSettings()
  else
    ClearWrapSettings()
  endif

  if mode !=# MODE_OFF
    setlocal display+=lastline
    setlocal backspace=indent,eol,start
    if quilljoinspaces
      setlocal joinspaces
    else
      setlocal nojoinspaces
    endif
  endif

  if quillcursorwrap && mode !=# MODE_OFF
    setlocal whichwrap+=<,>,b,s,h,l,[,]
  endif

  if mode !=# MODE_OFF
    setlocal nolist
    setlocal wrapmargin=0
    setlocal autoindent
    setlocal indentexpr=
    if exists('&smartindent')
      setlocal nosmartindent
    endif
    if exists('&cindent')
      setlocal nocindent
    endif
    setlocal formatoptions+=n1t
    setlocal formatoptions-=vwa2
    if exists('&conceal')
      execute $'setlocal conceallevel={quillconceallevel}'
      execute $'setlocal concealcursor={quillconcealcursor}'
    endif
  endif

  SetupNavigationMaps(mode)
  SetupPunctuationMaps(session)
enddef

# ---------------------------------------------------------------------
# Statusline helper and public entry points.
# ---------------------------------------------------------------------

export def StatusIndicator(): string
  var session: QuillSession = get(b:, 'bartleby_quill', null_object)
  if session is null_object
    return ''
  endif
  var indicators: dict<string> = g:bartleby_quill_mode_indicators
  if session.wrapMode ==# MODE_SOFT
    return get(indicators, 'soft', 'S')
  elseif session.wrapMode ==# MODE_HARD
    return &formatoptions =~# 'a' ? get(indicators, 'auto', 'A') : get(indicators, 'hard', 'H')
  endif
  return get(indicators, 'off', '')
enddef

export def Toggle(): void
  Init('toggle')
enddef

# Auto-applies hard-wrap Quill to a document buffer belonging to the open
# scrive - wired to BufEnter in plugin/bartleby.vim, gated by
# g:bartleby_quill_auto.
export def AutoApply(): void
  if !quillautoapply || exists('b:bartleby_quill')
    return
  endif
  if W.IsChromeBuffer(bufnr('%'))
    return
  endif
  var project: Pj.Project = St.Get()
  if project is null_object
    return
  endif
  if project.FindItemByPath(expand('%:p')) is null_object
    return
  endif
  Init('detect')
enddef
