vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# snapshot.vim - Phase 7b: a manual, Scrivener-style checkpoint of a
# single document's text, not version control - no diffing, no
# branching, just point-in-time copies the author took on purpose and
# can browse or restore later.
#
# Stored under <scrive>/snapshots/<doc-id>/<timestamp>.json - keyed by
# the document's own stable id (survives a rename; its relPath
# wouldn't) rather than its file path.
#
# Snapshot is defined before the functions that use it, not just by
# convention: List/Restore both use Snapshot in their own parameter or
# return type, and Vim9 resolves a function's signature eagerly at
# definition time - unlike a class used only inside a function body,
# which can forward-reference one defined later in the file just fine.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as Pe
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var snapshotretention: number = g:bartleby_snapshot_retention

var id_counter: number = 0

def NewTimestamp(): string
  id_counter += 1
  return printf('%s-%03d', strftime('%Y%m%d%H%M%S'), id_counter)
enddef

export class Snapshot
  var timestamp: string = ''
  var label: string = ''
  var lines: list<string> = []

  static def FromDict(src: dict<any>): Snapshot
    var s: Snapshot = Snapshot.new()
    s.timestamp = get(src, 'timestamp', '')
    s.label = get(src, 'label', '')
    s.lines = get(src, 'lines', [])
    return s
  enddef

  def ToDict(): dict<any>
    return {timestamp: this.timestamp, label: this.label, lines: this.lines}
  enddef

  # What a picker shows for this snapshot: the label if one was given,
  # otherwise a readable rendering of the timestamp.
  def DisplayName(): string
    if this.label !=# ''
      return this.label
    endif
    var t: string = this.timestamp
    if strlen(t) >= 14
      return printf('%s-%s-%s %s:%s:%s', t[0 : 3], t[4 : 5], t[6 : 7], t[8 : 9], t[10 : 11], t[12 : 13])
    endif
    return t
  enddef
endclass

def SnapshotDir(project: Pj.Project, doc: BI.BinderItem): string
  return $'{project.scriveDir}/snapshots/{doc.id}'
enddef

def SnapshotPath(project: Pj.Project, doc: BI.BinderItem, timestamp: string): string
  return $'{SnapshotDir(project, doc)}/{timestamp}.json'
enddef

# Oldest-first.
export def List(project: Pj.Project, doc: BI.BinderItem): list<Snapshot>
  var dir: string = SnapshotDir(project, doc)
  if !isdirectory(dir)
    return []
  endif
  var files: list<string> = sort(globpath(dir, '*.json', false, true))
  return files->mapnew((_, f) => Snapshot.FromDict(Pe.ReadJson(f)))
enddef

def EnforceRetention(project: Pj.Project, doc: BI.BinderItem): void
  var snapshots: list<Snapshot> = List(project, doc)
  var excess: number = len(snapshots) - snapshotretention
  if excess <= 0
    return
  endif
  for i in range(excess)
    var path: string = SnapshotPath(project, doc, snapshots[i].timestamp)
    if filereadable(path)
      delete(path)
    endif
  endfor
enddef

# Snapshots whatever is CURRENTLY ON DISK for `doc` - callers that want
# to snapshot unsaved editor changes must :write first (Take() itself
# stays a pure "copy the file" operation, no buffer awareness, so it
# behaves the same whether called from Binder or an open buffer).
export def Take(project: Pj.Project, doc: BI.BinderItem, label: string): void
  var path: string = doc.AbsPath(project.BinderRoot())
  if !filereadable(path)
    log.Error($'missing file on disk: {path}')
    return
  endif
  var v: dict<any> = {}
  v.timestamp = NewTimestamp()
  v.label = label
  v.lines = readfile(path)
  Pe.WriteJson(SnapshotPath(project, doc, v.timestamp), v)
  EnforceRetention(project, doc)
  log.Info($'snapshot taken: {doc.title}{label ==# "" ? "" : $" ({label})"}')
enddef

# Overwrites doc's file with `snapshot`'s content - takes an automatic
# "before restore" snapshot of the current state first, so this is
# never truly destructive without another snapshot to undo it.
# Reloads the buffer if the document is currently open, so the editor
# view reflects the restored content immediately.
export def Restore(project: Pj.Project, doc: BI.BinderItem, snapshot: Snapshot): void
  Take(project, doc, 'before restore')
  var path: string = doc.AbsPath(project.BinderRoot())
  writefile(snapshot.lines, path)
  var winId: number = bufwinid(bufnr(path))
  if winId != -1
    win_execute(winId, 'edit!')
  endif
  log.Info($'restored "{doc.title}" to snapshot from {snapshot.DisplayName()}')
enddef
