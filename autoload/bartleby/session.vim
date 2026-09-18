vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# session.vim - Phase 7a: per-scrive session persistence (active document,
# cursor position, Binder open/closed, Binder's collapsed-folder state)
# plus remembering the last-opened scrive globally.
#
# Capture is split into two focused entry points rather than one big
# "capture everything" function, since they're triggered by genuinely
# different events: CaptureCurrentDoc() from CursorHold (Vim's own idle
# detection - naturally throttled, so this is "continuous" persistence
# without needing a custom change-counter) and from VimLeavePre;
# CaptureBinderState() called directly by binder.vim's own
# toggle/collapse actions, since those are already explicit, infrequent
# events with no need for a separate autocommand.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/persist.vim' as Pe
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

export class SessionState
  var activeDocRelPath: string = ''
  var cursorLine: number = 1
  var cursorCol: number = 1
  var binderOpen: bool = true
  var collapsedIds: list<string> = []

  static def FromDict(src: dict<any>): SessionState
    var s: SessionState = SessionState.new()
    s.activeDocRelPath = get(src, 'activeDocRelPath', '')
    s.cursorLine = get(src, 'cursorLine', 1)
    s.cursorCol = get(src, 'cursorCol', 1)
    s.binderOpen = get(src, 'binderOpen', true)
    s.collapsedIds = get(src, 'collapsedIds', [])
    return s
  enddef

  def ToDict(): dict<any>
    return {activeDocRelPath: this.activeDocRelPath, cursorLine: this.cursorLine,
      cursorCol: this.cursorCol, binderOpen: this.binderOpen, collapsedIds: this.collapsedIds}
  enddef
endclass

def SessionPath(project: Pj.Project): string
  return project.scriveDir .. '/session.json'
enddef

def Load(project: Pj.Project): SessionState
  var path: string = SessionPath(project)
  if !filereadable(path)
    return SessionState.new()
  endif
  return SessionState.FromDict(Pe.ReadJson(path))
enddef

def Save(project: Pj.Project, state: SessionState): void
  Pe.WriteJson(SessionPath(project), state.ToDict())
enddef

# ---------------------------------------------------------------------
# Last-opened scrive, globally (not per-scrive) - lets :BartlebyOpen
# with no argument, or an auto-restore on startup, resume without
# retyping the scrive name.
# ---------------------------------------------------------------------

def LastScrivePath(): string
  return expand('~/.bartleby/last_scrive.json')
enddef

export def RememberLastScrive(scriveDir: string): void
  Pe.WriteJson(LastScrivePath(), {scriveDir: scriveDir})
enddef

export def LastScrive(): string
  return get(Pe.ReadJson(LastScrivePath()), 'scriveDir', '')
enddef

# ---------------------------------------------------------------------
# Capture.
# ---------------------------------------------------------------------

def IsProjectDoc(project: Pj.Project, path: string): bool
  return path !=# '' && path =~# '^\V' .. escape(project.BinderRoot(), '\')
enddef

# Wired to CursorHold on any document buffer, and to VimLeavePre - both
# read the CURRENT window/buffer's own state directly, which is exactly
# what those two events already give you, so no cross-window lookup is
# needed here.
export def CaptureCurrentDoc(): void
  var project: Pj.Project = St.Get()
  if project is null_object
    return
  endif
  var path: string = expand('%:p')
  if !IsProjectDoc(project, path)
    return
  endif
  var v: dict<any> = Load(project).ToDict()
  v.activeDocRelPath = path[len(project.BinderRoot()) + 1 : ]
  v.cursorLine = line('.')
  v.cursorCol = col('.')
  Save(project, SessionState.FromDict(v))
enddef

# Called directly by binder.vim's own toggle/collapse actions - already
# explicit, infrequent user actions, so no separate autocommand needed.
export def CaptureBinderState(): void
  var project: Pj.Project = St.Get()
  if project is null_object
    return
  endif
  var v: dict<any> = Load(project).ToDict()
  v.binderOpen = B.IsOpen()
  v.collapsedIds = B.GetCollapsedIds()
  Save(project, SessionState.FromDict(v))
enddef

# ---------------------------------------------------------------------
# Restore - called right after a scrive is opened.
# ---------------------------------------------------------------------

export def Restore(project: Pj.Project): void
  var state: SessionState = Load(project)

  # Binder is always shown first, regardless of the saved open/closed
  # state - its buffer has to exist for the collapsed-folder state to
  # be applied and rendered at all, and bufhidden=hide means closing it
  # afterward (if the saved state says it should be closed) keeps that
  # state ready for whenever it's next opened.
  B.Show(project)
  B.ApplyCollapsedIds(state.collapsedIds)
  B.Show(project)

  if state.activeDocRelPath !=# ''
    var path: string = project.BinderRoot() .. '/' .. state.activeDocRelPath
    if filereadable(path)
      W.GoToEditorWindow()
      execute 'edit ' .. fnameescape(path)
      cursor(state.cursorLine, state.cursorCol)
    else
      log.Warn($'session: previously active document no longer exists: {path}')
    endif
  endif

  if !state.binderOpen
    B.Toggle(project)
  endif
enddef
