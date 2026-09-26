vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# snapshot.vim: manual checkpoints of one document's text. Not version
# control: no diffs and no branches, only copies that the author takes on
# purpose and can browse or restore later.
#
# Stored in <scrive>/snapshots/<doc-id>/<timestamp>.json, keyed by the
# document's id, which stays the same after a rename, unlike its path.
#
# Snapshot is defined before the functions that use it because List and
# Restore name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined.
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

  # METHOD: Return the name a picker shows: the label when one was given,
  # else the timestamp in readable form.
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

# FUNCTION: Return the snapshots of doc, oldest first.
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

# FUNCTION: Take a snapshot of the text of doc that is on disk now. A
# caller that wants unsaved changes must write first. Take only copies
# the file and knows no buffers, so it works the same from the Binder and
# from an open buffer.
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

# FUNCTION: Replace the file of doc with the content of snapshot. First
# takes a snapshot of the current text, so a restore can always be
# undone. Reloads the buffer when the document is open, so the editor
# shows the restored text at once.
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
