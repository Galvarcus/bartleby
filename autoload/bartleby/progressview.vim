vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# progressview.vim: the views of the writing goals of progress.vim. A form
# sets the session goal, the daily goal, and the tracker. A popup shows the
# progress as a NaNoWriMo sheet does: the figures of the tracker, then a
# row for each day, or without a tracker, the days of the history.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/progress.vim' as P
import autoload 'bartleby/state.vim' as ST

var log = L.New(expand('<sfile>:t'))

# The days of the history that the popup shows without a tracker.
const HISTORY_DAYS: number = 30
const POPUP_ZINDEX: number = 250

# FUNCTION: Show the form of the goals and the tracker of the open scrive,
# filled with them, and set them on Save.
export def EditGoals(): void
  if ST.Get() is null_object
    log.Warn(IN.T("no scrive open - run :BartlebyOpen <name> first"))
    return
  endif
  P.Refresh()
  var goals: dict<number> = P.Goals()
  var tracker: dict<any> = P.Tracker()
  var Text = (n: number) => n > 0 ? string(n) : ''
  var fields: list<list<dict<any>>> = [
    [{name: 'session', type: 'text'}, {name: 'daily', type: 'text'}],
    [{name: 'target', type: 'text'}],
    [{name: 'start', type: 'text'}, {name: 'days', type: 'text'}],
  ]
  var values: dict<string> = {
    session: Text(goals.session),
    daily: Text(goals.daily),
    target: Text(get(tracker, 'target', 0)),
    start: get(tracker, 'start', P.DayOf(localtime())),
    days: string(get(tracker, 'days', 30)),
  }
  var form = IP.InputPopup.new(fields, values, {
    title: IN.T(" Writing goals. 0 or empty is off "),
    labels: {
      session: IN.T("Session goal"),
      daily: IN.T("Daily goal"),
      target: IN.T("Tracker target"),
      start: IN.T("Start date"),
      days: IN.T("Days"),
    },
    widths: {session: 8, daily: 8, target: 8, start: 10, days: 4},
    submit_label: IN.T("Save"),
  })
  form.OnSubmit((v: dict<any>) => {
    var error: string = P.SetGoals(str2nr(v.session), str2nr(v.daily), str2nr(v.target),
      trim(v.start), str2nr(v.days))
    if error !=# ''
      log.Error(error)
    endif
  })
  form.Open()
enddef

# FUNCTION: Return text, padded with spaces to width.
def Pad(text: string, width: number): string
  return text .. repeat(' ', max([width - strdisplaywidth(text), 0]))
enddef

# FUNCTION: Return the lines of a table of rows of cells, each column as
# wide as its widest cell.
def Table(rows: list<list<string>>): list<string>
  var widths: list<number> = []
  for row in rows
    for i in range(len(row))
      if i >= len(widths)
        widths->add(0)
      endif
      widths[i] = max([widths[i], strdisplaywidth(row[i])])
    endfor
  endfor
  return rows->mapnew((_, row) => row->mapnew((i, cell) => Pad(cell, widths[i]))->join('  ')->trim('', 2))
enddef

# FUNCTION: Return the lines of the popup on the day today: the goals, the
# figures of the tracker, an empty line, and a table with a row for each
# day, after its header.
export def Lines(today: string): list<string>
  var goals: dict<number> = P.Goals()
  var written: dict<number> = P.Written()
  var T = P.Thousands
  var lines: list<string> = []
  var summary: list<list<string>> = []
  if goals.session > 0
    summary->add([IN.T("Session"), $'{T(max([written.session, 0]))} / {T(goals.session)}'])
  endif
  if goals.daily > 0
    summary->add([IN.T("Today"), $'{T(max([written.today, 0]))} / {T(goals.daily)}'])
  endif
  var tracker: dict<any> = P.Tracker()
  var f: dict<any> = P.TrackerFigures(today)
  if !empty(f)
    var gap: string = f.difference >= 0
      ? printf(IN.T("%s over"), T(f.difference)) : printf(IN.T("%s under"), T(-f.difference))
    summary += Table([
      [IN.T("Target"), T(tracker.target), IN.T("Day"), printf(IN.T("%d of %d"), f.dayNumber, tracker.days),
        IN.T("Written"), T(f.written)],
      [IN.T("Start"), tracker.start, IN.T("Days to go"), string(f.daysToGo),
        IN.T("Should have"), T(f.shouldHave)],
      [IN.T("End"), f.end, IN.T("On track"), gap, IN.T("Per day"), T(f.perDay)],
      [IN.T("Pace"), printf(IN.T("%s a day"), T(f.pace)), IN.T("Finish"), f.finish ==# '' ? '-' : f.finish, '', ''],
    ])->mapnew((_, line) => [line])
    summary->add([f.done ? IN.T("You did it! Winner!") : IN.T("You can do this!")])
  endif
  lines += summary->mapnew((_, row) => len(row) == 1 ? row[0] : join(row, ': '))
  if !empty(lines)
    lines->add('')
  endif
  var history: dict<number> = {}
  for [day, words] in P.History()
    history[day] = words
  endfor
  var rows: list<list<string>> = []
  if !empty(f)
    rows->add([IN.T("Day"), IN.T("Date"), IN.T("Words"), IN.T("Total")])
    var start: number = P.DayNumber(tracker.start)
    var total: number = 0
    for i in range(tracker.days)
      var day: string = P.DateOf(start + i)
      var future: bool = day > today
      total += get(history, day, 0)
      rows->add([string(i + 1), day, has_key(history, day) ? T(history[day]) : '',
        future ? '' : T(total)])
    endfor
  else
    rows->add([IN.T("Date"), IN.T("Words")])
    for [day, words] in P.History()[-HISTORY_DAYS :]
      rows->add([day, T(words)])
    endfor
  endif
  return lines + Table(rows)
enddef

# FUNCTION: Show the progress of the open scrive in a popup: j and k
# scroll, e edits the goals, q and Esc close.
export def Show(): void
  if ST.Get() is null_object
    log.Warn(IN.T("no scrive open - run :BartlebyOpen <name> first"))
    return
  endif
  P.Refresh()
  var lines: list<string> = Lines(P.DayOf(localtime()))
  if empty(prop_type_get('BartlebyProgressHeader'))
    prop_type_add('BartlebyProgressHeader', {highlight: 'Title'})
  endif
  # The header of the table is the line after the first empty line, or
  # the first line when there is no summary.
  var header: number = index(lines, '') + 1
  var content: list<dict<any>> = lines->mapnew((i, line) => i == header && line !=# ''
    ? {text: line, props: [{col: 1, length: strlen(line), type: 'BartlebyProgressHeader'}]}
    : {text: line})
  popup_create(content, {
    title: $' {IN.T("Writing progress")}  (e: {IN.T("goals")}, q: {IN.T("close")}) ',
    border: [], padding: [0, 1, 0, 1], scrollbar: true, zindex: POPUP_ZINDEX,
    maxheight: max([&lines - 6, 5]), mapping: false,
    filter: (winid: number, key: string): bool => {
      if key ==# 'q' || key == "\<Esc>"
        popup_close(winid)
      elseif key ==# 'e'
        popup_close(winid)
        EditGoals()
      elseif key ==# 'j' || key == "\<Down>"
        popup_setoptions(winid, {firstline: popup_getoptions(winid).firstline + 1})
      elseif key ==# 'k' || key == "\<Up>"
        popup_setoptions(winid, {firstline: max([popup_getoptions(winid).firstline - 1, 1])})
      endif
      return true
    },
  })
enddef
