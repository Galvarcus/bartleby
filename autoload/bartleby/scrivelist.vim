vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrivelist.vim - :BartlebyList. Scans the binder root for *.bartleby
# folders, keeps only those with a valid project.json, and shows them in
# a popup list (Title | Type). <CR> opens the selection through
# :BartlebyOpen, so it behaves exactly like opening a scrive by name.
#
# When no valid scrive exists (a fresh install), this prompts for a name
# and runs :BartlebyNewScrive instead of reporting an error.
#
# Discovery reads project.json directly rather than through
# Project.Load() - Load() warns on a missing file, and a listing should
# skip a stray folder quietly, then report the count once.
#
# ScriveEntry is defined before the functions that use it, not just by
# convention: FindScrives() and ReadEntry() use it in their own return
# types, and Vim9 resolves a function's signature at definition time.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as Sc
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/helppopup.vim' as H
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const HEADERS: list<string> = ['Title', 'Type']
const COLUMN_GAP: string = '    '
const MAX_VISIBLE_ROWS: number = 15
const SCRIVELIST_ZINDEX: number = 250
const TYPE_LABELS: dict<string> = {
  [Pj.TYPE_NOVEL]: 'Novel',
  [Pj.TYPE_NOVEL_PARTS]: 'Novel with Parts',
  [Pj.TYPE_SHORT_STORY]: 'Short Story',
  [Pj.TYPE_SCREENPLAY]: 'Screenplay',
}

# One valid scrive. `name` is the folder's bare name (what :BartlebyOpen
# takes); `title` is project.json's own name, shown to the user.
export class ScriveEntry
  var name: string
  var title: string
  var projectType: string
endclass

# Every *.bartleby directory directly under `root`, valid or not.
export def CandidateDirs(root: string): list<string>
  if !isdirectory(root)
    return []
  endif
  return globpath(root, '*' .. Sc.SCRIVE_EXT, false, true)
    ->filter((_, p) => isdirectory(p))
enddef

# A ScriveEntry for `dir`, or null_object if its project.json is missing,
# unreadable, not a JSON object, has no `items` list, or names an unknown
# project type. A missing or empty `name` falls back to the folder name,
# same as Project.Load().
export def ReadEntry(dir: string): ScriveEntry
  var path: string = dir .. '/' .. Pj.PROJECT_FILE
  if !filereadable(path)
    return null_object
  endif
  var data: any
  try
    data = json_decode(join(readfile(path), "\n"))
  catch
    return null_object
  endtry
  if type(data) != v:t_dict
    return null_object
  endif
  if type(get(data, 'items', 0)) != v:t_list
    return null_object
  endif
  var projectType: any = get(data, 'projectType', '')
  if type(projectType) != v:t_string || !has_key(TYPE_LABELS, projectType)
    return null_object
  endif
  var folderName: string = fnamemodify(dir, ':t:r')
  var title: any = get(data, 'name', '')
  if type(title) != v:t_string || title ==# ''
    title = folderName
  endif
  return ScriveEntry.new(folderName, title, projectType)
enddef

# Every valid scrive under `root` (the binder root when omitted), sorted
# by title, case-insensitively.
export def FindScrives(root: string = ''): list<ScriveEntry>
  var scanRoot: string = root ==# '' ? Sc.BinderRoot() : root
  var entries: list<ScriveEntry> = []
  for dir in CandidateDirs(scanRoot)
    var entry: ScriveEntry = ReadEntry(dir)
    if entry isnot null_object
      entries->add(entry)
    endif
  endfor
  return entries->sort((a, b) => a.title ==? b.title ? 0 : (a.title >? b.title ? 1 : -1))
enddef

export def TypeLabel(projectType: string): string
  return get(TYPE_LABELS, projectType, projectType)
enddef

# :BartlebyList entry point.
export def Show(): void
  var dirs: list<string> = CandidateDirs(Sc.BinderRoot())
  var entries: list<ScriveEntry> = FindScrives()
  var skipped: number = len(dirs) - len(entries)
  if skipped > 0
    log.Warn($'skipped {skipped} folder(s) under {Sc.BinderRoot()} with no valid project.json')
  endif
  if empty(entries)
    PromptNewScrive()
    return
  endif
  ScriveListPopup.new(entries).Open()
enddef

def Pad(text: string, width: number): string
  return text .. repeat(' ', max([0, width - strdisplaywidth(text)]))
enddef

def PromptNewScrive(): void
  log.Info($'no scrives found under {Sc.BinderRoot()} - name a new one to create it')
  IP.PromptText('No scrives - create one', '', (name: string) => {
    if name !=# ''
      execute $'BartlebyNewScrive {name}'
    endif
  })
enddef

class ScriveListPopup
  var entries: list<ScriveEntry>
  var titleWidth: number = 0
  var selectedIdx: number = 0
  var scrollOffset: number = 0
  var winid: number = -1
  var bufnr: number = -1

  def new(this.entries)
    this.titleWidth = strdisplaywidth(HEADERS[0])
    for entry in this.entries
      this.titleWidth = max([this.titleWidth, strdisplaywidth(entry.title)])
    endfor
  enddef

  def FormatRow(title: string, typeLabel: string): string
    return Pad(title, this.titleWidth) .. COLUMN_GAP .. typeLabel
  enddef

  def Width(): number
    var typeWidth: number = strdisplaywidth(HEADERS[1])
    for entry in this.entries
      typeWidth = max([typeWidth, strdisplaywidth(TypeLabel(entry.projectType))])
    endfor
    return max([this.titleWidth + strdisplaywidth(COLUMN_GAP) + typeWidth, 30])
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('ScriveListHeader'))
      prop_type_add('ScriveListHeader', {highlight: 'Title'})
    endif
    if empty(prop_type_get('ScriveListSelected'))
      prop_type_add('ScriveListSelected', {highlight: 'PmenuSel'})
    endif
  enddef

  def Open(): void
    this.EnsurePropTypes()
    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    var width: number = this.Width()
    var height: number = min([len(this.entries), MAX_VISIBLE_ROWS]) + 2
    this.winid = popup_create(this.bufnr, {
      title: ' Scrives ',
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      zindex: SCRIVELIST_ZINDEX,
      mapping: false,
      filter: (id, key) => this.Filter(id, key),
    })
    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid)
      this.winid = -1
    endif
  enddef

  def VisibleSlice(): list<number>
    if this.selectedIdx < this.scrollOffset
      this.scrollOffset = this.selectedIdx
    elseif this.selectedIdx >= this.scrollOffset + MAX_VISIBLE_ROWS
      this.scrollOffset = this.selectedIdx - MAX_VISIBLE_ROWS + 1
    endif
    return [this.scrollOffset, min([len(this.entries), this.scrollOffset + MAX_VISIBLE_ROWS])]
  enddef

  def Render(): void
    var header: string = this.FormatRow(HEADERS[0], HEADERS[1])
    var lines: list<string> = [header, repeat('-', this.Width())]
    var [first: number, last: number] = this.VisibleSlice()
    for i in range(first, last - 1)
      var entry: ScriveEntry = this.entries[i]
      lines->add(this.FormatRow(entry.title, TypeLabel(entry.projectType)))
    endfor

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    prop_remove({type: 'ScriveListHeader', bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: 'ScriveListSelected', bufnr: this.bufnr}, 1, len(lines))
    prop_add(1, 1, {type: 'ScriveListHeader', bufnr: this.bufnr, length: strlen(header)})
    var selLnum: number = 3 + (this.selectedIdx - first)
    prop_add(selLnum, 1, {
      type: 'ScriveListSelected', bufnr: this.bufnr,
      length: max([strlen(lines[selLnum - 1]), 1]),
    })
  enddef

  # Opens the selection after this popup's filter call returns (timer 0),
  # so the scrive's windows are never built from inside a popup filter.
  def OpenSelected(): void
    var name: string = this.entries[this.selectedIdx].name
    this.Close()
    timer_start(0, (_) => {
      execute $'BartlebyOpen {name}'
    })
  enddef

  def ShowHelp(): void
    H.Show('Scrives', [
      ['<CR>', 'Open the selected scrive'],
      ['j / <Down>', 'Next scrive'],
      ['k / <Up>', 'Previous scrive'],
      ['q / <Esc>', 'Close'],
      ['?', 'This help'],
    ])
  enddef

  def Filter(winid: number, key: string): bool
    if key ==# 'j' || key ==# "\<Down>"
      this.selectedIdx = min([len(this.entries) - 1, this.selectedIdx + 1])
      this.Render()
    elseif key ==# 'k' || key ==# "\<Up>"
      this.selectedIdx = max([0, this.selectedIdx - 1])
      this.Render()
    elseif key ==# "\<CR>"
      this.OpenSelected()
    elseif key ==# '?'
      this.ShowHelp()
    elseif key ==# 'q' || key ==# "\<Esc>"
      this.Close()
    endif
    return true
  enddef
endclass
