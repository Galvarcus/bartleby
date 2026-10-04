vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# session.vim: saves and loads the session of each scrive: the active
# document, the cursor position, whether the Binder is open, and which
# Binder folders are collapsed. Also remembers the last opened scrive.
# restore.vim restores a loaded session. This script imports nothing that
# leads back to binder.vim, so the two import each other in one direction
# only: binder.vim reports its state here.
#
# Two capture functions, for two kinds of events. CaptureCurrentDoc runs
# on CursorHold, which Vim limits to idle moments, so it saves often
# without a change counter, and on VimLeavePre. binder.vim calls
# CaptureBinderState with its state when it shows, hides, or collapses,
# which are rare, explicit actions that need no autocommand.
#
# SessionState is defined before the functions that use it because Load
# and Save name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/persist.vim' as PE

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

def SessionPath(project: PO.Project): string
  return project.scriveDir .. '/session.json'
enddef

export def Load(project: PO.Project): SessionState
  var path: string = SessionPath(project)
  if !filereadable(path)
    return SessionState.new()
  endif
  return SessionState.FromDict(PE.ReadJson(path))
enddef

# The state last read or written for each session file. A capture starts
# from it instead of the file, and writes only a state that differs, so
# that a pause with nothing changed costs no file access.
var known: dict<dict<any>> = {}

# FUNCTION: Return the state of the session of project, as a dict that the
# caller may change: the state last read or written, or else the file.
def Current(project: PO.Project): dict<any>
  var path: string = SessionPath(project)
  if !has_key(known, path)
    known[path] = Load(project).ToDict()
  endif
  return deepcopy(known[path])
enddef

def Save(project: PO.Project, state: SessionState): void
  var path: string = SessionPath(project)
  var data: dict<any> = state.ToDict()
  if get(known, path, {}) == data
    return
  endif
  if PE.WriteJson(path, data)
    known[path] = data
  endif
enddef

# FUNCTION: Forget the states read and written, so that the next capture
# reads the file. The tests use it.
export def ForgetKnownStates(): void
  known = {}
enddef

##############################################################################
# SECTION: Last scrive. Saved for all scrives, so that :BartlebyOpen
# without a name, or a restore at startup, needs no scrive name.
##############################################################################

def LastScrivePath(): string
  return expand('~/.bartleby/last_scrive.json')
enddef

export def RememberLastScrive(scriveDir: string): void
  PE.WriteJson(LastScrivePath(), {scriveDir: scriveDir})
enddef

export def LastScrive(): string
  return get(PE.ReadJson(LastScrivePath()), 'scriveDir', '')
enddef

##############################################################################
# SECTION: Capture.
##############################################################################

def IsProjectDoc(project: PO.Project, path: string): bool
  return path !=# '' && path =~# '^\V' .. escape(project.BinderRoot(), '\')
enddef

# FUNCTION: Save the document and cursor of the current window. Runs on
# CursorHold in a document buffer and on VimLeavePre. Both events give
# the current window, so no other window is looked up.
export def CaptureCurrentDoc(): void
  var project: PO.Project = ST.Get()
  if project is null_object
    return
  endif
  var path: string = expand('%:p')
  if !IsProjectDoc(project, path)
    return
  endif
  var v: dict<any> = Current(project)
  v.activeDocRelPath = path[len(project.BinderRoot()) + 1 : ]
  v.cursorLine = line('.')
  v.cursorCol = col('.')
  Save(project, SessionState.FromDict(v))
enddef

# FUNCTION: Save the Binder state: whether it is open, and the ids of its
# collapsed folders. binder.vim calls this on its show, hide, and collapse
# actions, so no autocommand is needed.
export def CaptureBinderState(binderOpen: bool, collapsedIds: list<string>): void
  var project: PO.Project = ST.Get()
  if project is null_object
    return
  endif
  var v: dict<any> = Current(project)
  v.binderOpen = binderOpen
  v.collapsedIds = collapsedIds
  Save(project, SessionState.FromDict(v))
enddef
