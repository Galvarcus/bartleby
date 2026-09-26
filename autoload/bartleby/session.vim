vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# session.vim: saves and restores the session of each scrive: the active
# document, the cursor position, whether the Binder is open, and which
# Binder folders are collapsed. Also remembers the last opened scrive.
#
# Two capture functions, for two kinds of events. CaptureCurrentDoc runs
# on CursorHold, which Vim limits to idle moments, so it saves often
# without a change counter, and on VimLeavePre. CaptureBinderState runs
# when binder.vim shows, hides, or collapses, which are rare, explicit
# actions that need no autocommand.
#
# SessionState is defined before the functions that use it because Load
# and Save name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined.
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

##############################################################################
# SECTION: Last scrive. Saved for all scrives, so that :BartlebyOpen
# without a name, or a restore at startup, needs no scrive name.
##############################################################################

def LastScrivePath(): string
  return expand('~/.bartleby/last_scrive.json')
enddef

export def RememberLastScrive(scriveDir: string): void
  Pe.WriteJson(LastScrivePath(), {scriveDir: scriveDir})
enddef

export def LastScrive(): string
  return get(Pe.ReadJson(LastScrivePath()), 'scriveDir', '')
enddef

##############################################################################
# SECTION: Capture.
##############################################################################

def IsProjectDoc(project: Pj.Project, path: string): bool
  return path !=# '' && path =~# '^\V' .. escape(project.BinderRoot(), '\')
enddef

# FUNCTION: Save the document and cursor of the current window. Runs on
# CursorHold in a document buffer and on VimLeavePre. Both events give
# the current window, so no other window is looked up.
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

# FUNCTION: Save the Binder state. binder.vim calls this on its show,
# hide, and collapse actions, so no autocommand is needed.
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

##############################################################################
# SECTION: Restore.
##############################################################################
# FUNCTION: Restore the session of project, right after it opens.

export def Restore(project: Pj.Project): void
  var state: SessionState = Load(project)

  # Show the Binder first, whatever the saved state: its buffer must exist
  # to apply the collapsed folders. Its bufhidden is hide, so closing it
  # afterward, when the saved state says closed, keeps that state for the
  # next time it opens.
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
