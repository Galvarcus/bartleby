vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autosave.vim - saves changed scrive documents while you work.
#
# Scope: only buffers whose file is under the open scrive's binder
# folder. Every other buffer is left alone. Focus mode shows the same
# buffer, so it is covered too.
#
# plugin/bartleby.vim calls Save() on these events:
#   CursorHold, InsertLeave - at most one write per buffer every
#     g:bartleby_autosave_interval seconds, so a low 'updatetime' does
#     not cause frequent disk writes. A write skipped for this reason
#     runs once when the interval ends (see ScheduleSave()).
#   FocusLost, BufLeave - always, so nothing is left unsaved when you
#     switch away.
#
# Save() uses :update, which writes only a changed buffer, under
# :lockmarks, so the '[ and '] marks of your last change are kept.
# g:bartleby_autosave = false turns the feature off.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/project.vim' as Pj
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

# True when the current buffer is a document of the open scrive.
export def IsScriveDocument(): bool
  if &buftype !=# '' || expand('%:p') ==# ''
    return false
  endif
  var project: Pj.Project = St.Get()
  if project is null_object
    return false
  endif
  return stridx(expand('%:p'), project.BinderRoot() .. '/') == 0
enddef

# Saves the current buffer if it is a changed scrive document. With
# `force` false, skips the write when this buffer was saved less than
# g:bartleby_autosave_interval seconds ago.
export def Save(force: bool): void
  if !g:bartleby_autosave || !&modified || &readonly || !&modifiable
    return
  endif
  if !IsScriveDocument()
    return
  endif
  var now: number = localtime()
  var wait: number = g:bartleby_autosave_interval - (now - get(b:, 'bartleby_autosave_time', 0))
  if !force && wait > 0
    ScheduleSave(wait)
    return
  endif
  try
    lockmarks silent update
    b:bartleby_autosave_time = now
  catch
    log.Warn($'auto-save failed for {expand("%:t")}: {v:exception}')
  endtry
enddef

# A write skipped by the interval runs once when the interval ends, so a
# pause after an edit never leaves it unsaved. One pending timer per
# buffer. The timer saves only if that buffer is still current and Vim
# is not in Insert or Replace mode. When you left the buffer, BufLeave
# already saved it. When you are typing, InsertLeave saves it later.
def ScheduleSave(seconds: number): void
  if get(b:, 'bartleby_autosave_pending', false)
    return
  endif
  b:bartleby_autosave_pending = true
  var buf: number = bufnr('%')
  timer_start(seconds * 1000, (_) => {
    setbufvar(buf, 'bartleby_autosave_pending', false)
    if bufnr('%') == buf && mode() !~# '^[iR]'
      Save(false)
    endif
  })
enddef
