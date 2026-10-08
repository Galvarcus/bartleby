vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_scrivenings.vim: a Scrivening of scrivenings.vim, with real
# files. It shows the documents of a Manuscript folder and its folders in
# Binder order, each after its title line, writes only the documents that
# changed, and writes nothing when a title line is damaged. The title
# lines are protected, the documents open in one place only, and the
# features that follow the current document follow the one under the
# cursor.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/autosave.vim' as A
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/state.vim' as ST
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the fixture project, current, with its two scenes on
# disk, the second titled Departure.
def NewProject(): dict<any>
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var arrival = manuscript.ChildAt(0).ChildAt(0)
  var departure = manuscript.ChildAt(1).ChildAt(0)
  arrival.Rename('Arrival')
  departure.Rename('Departure')
  FI.WriteDocContent(project, arrival, ['The train came in.', 'It was late.'])
  FI.WriteDocContent(project, departure, ['The train left.'])
  ST.Set(project)
  var root: string = project.BinderRoot()
  return {project: project, manuscript: manuscript, arrival: arrival, departure: departure,
    arrivalPath: arrival.AbsPath(root), departurePath: departure.AbsPath(root)}
enddef

# FUNCTION: Close the Scrivening, also when a test left it damaged and
# unsaved, so that one failure does not stop the tests after it.
def Close(fx: dict<any>): void
  if !SV.Close()
    setbufvar(CO.SCRIVENINGS_BUF, '&modified', 0)
    SV.Close()
  endif
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: Return the lines of path, or an empty list when it is missing.
def LinesOf(path: string): list<string>
  return filereadable(path) ? readfile(path) : []
enddef

# FUNCTION: Return the title of the document under the cursor.
def TitleHere(project: any): string
  var doc = SV.DocumentHere(project)
  return doc is null_object ? '' : doc.title
enddef

def Test_a_scrivening_shows_the_folder_tree_in_binder_order(): void
  var fx = NewProject()
  assert_true(SV.Open(fx.project, fx.manuscript))
  assert_equal(CO.SCRIVENINGS_BUF, bufname())
  assert_equal(['── Chapter: 1 / Arrival ──', 'The train came in.', 'It was late.',
    '── Chapter: 2 / Departure ──', 'The train left.'], getline(1, '$'))
  assert_equal('Arrival', TitleHere(fx.project))
  cursor(5, 1)
  assert_equal(['Departure', 1], [TitleHere(fx.project), SV.LineInDocument()])
  Close(fx)
enddef

def Test_only_a_folder_in_the_manuscript_opens(): void
  var fx = NewProject()
  var research = fx.project.ChildAt(4)
  research.AddChild(BI.BinderItem.NewDocument('Notes', 'research/notes.md'))
  assert_false(SV.Open(fx.project, research))
  assert_notequal(CO.SCRIVENINGS_BUF, bufname())
  Close(fx)
enddef

def Test_saving_writes_only_the_documents_that_changed(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  # Changed on disk behind the Scrivening: an unchanged section must not
  # write over it.
  writefile(['Changed elsewhere.'], fx.arrivalPath)
  setline(5, 'The train left early.')
  write
  assert_false(&modified)
  assert_equal(['The train left early.'], LinesOf(fx.departurePath))
  assert_equal(['Changed elsewhere.'], LinesOf(fx.arrivalPath))
  Close(fx)
enddef

def Test_an_empty_document_has_a_line_to_type_in(): void
  var fx = NewProject()
  writefile([], fx.departurePath)
  SV.Open(fx.project, fx.manuscript)
  assert_equal(['── Chapter: 2 / Departure ──', ''], getline(4, '$'))
  write
  assert_equal([], LinesOf(fx.departurePath))
  setline(5, 'Now it has words.')
  write
  assert_equal(['Now it has words.'], LinesOf(fx.departurePath))
  Close(fx)
enddef

def Test_a_change_to_a_title_line_is_undone(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  for keys in ['4Gdd', '4Gx', '3GJ']
    feedkeys(keys, 'xt')
    doautocmd TextChanged
    assert_equal('── Chapter: 2 / Departure ──', getline(4), keys)
  endfor
  assert_equal(['The train left.'], getline(5, '$'))
  Close(fx)
enddef

def Test_a_damaged_title_line_saves_nothing(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(5, 'Not to be saved.')
  # As when the protection cannot undo: the mark of a title line is gone.
  prop_remove({type: 'BartlebyScriveningTitle', id: 2, all: true}, 1, line('$'))
  write
  assert_true(&modified)
  assert_equal(['The train left.'], LinesOf(fx.departurePath))
  set nomodified
  Close(fx)
enddef

def Test_backspace_and_delete_do_not_join_a_title_line(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  cursor(5, 1)
  feedkeys("i\<BS>\<Esc>", 'xt')
  cursor(3, 1)
  feedkeys("A\<Del>\<Esc>", 'xt')
  assert_equal(['── Chapter: 1 / Arrival ──', 'The train came in.', 'It was late.',
    '── Chapter: 2 / Departure ──', 'The train left.'], getline(1, '$'))
  Close(fx)
enddef

def Test_open_documents_are_saved_closed_and_opened_in_the_scrivening(): void
  var fx = NewProject()
  execute 'silent edit ' .. fnameescape(fx.departurePath)
  setline(1, 'Not saved yet.')
  SV.Open(fx.project, fx.manuscript)
  assert_equal(['Not saved yet.'], LinesOf(fx.departurePath))
  assert_equal(-1, bufnr(fx.departurePath))
  assert_equal('Departure', TitleHere(fx.project))
  Close(fx)
enddef

def Test_a_document_opened_alone_shows_in_the_scrivening(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  execute 'silent edit ' .. fnameescape(fx.departurePath)
  cursor(1, 1)
  # The redirection runs from a timer, once Vim has entered the buffer.
  doautocmd BufEnter
  sleep 50m
  assert_equal(CO.SCRIVENINGS_BUF, bufname())
  assert_equal(['Departure', 1], [TitleHere(fx.project), SV.LineInDocument()])
  assert_equal(-1, bufnr(fx.departurePath))
  Close(fx)
enddef

def Test_the_scrivening_follows_the_binder(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(5, 'Saved before the change.')
  var chapter1 = fx.manuscript.ChildAt(0)
  var later = BI.BinderItem.NewDocument('Later', 'manuscript/chapter-1/later.md')
  chapter1.AddChild(later)
  FI.WriteDocContent(fx.project, later, ['Even later.'])
  SV.SyncWithTree(fx.project)
  assert_equal(['Saved before the change.'], LinesOf(fx.departurePath))
  assert_equal(['── Chapter: 1 / Later ──', 'Even later.'], getline(4, 5))
  Close(fx)
enddef

def Test_auto_save_writes_the_scrivening(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(2, 'Saved by itself.')
  A.Save(true)
  assert_equal(['Saved by itself.', 'It was late.'], LinesOf(fx.arrivalPath))
  Close(fx)
enddef

def Test_the_session_records_the_document_under_the_cursor(): void
  var fx = NewProject()
  SS.ForgetKnownStates()
  SV.Open(fx.project, fx.manuscript)
  cursor(5, 1)
  SS.CaptureCurrentDoc()
  var saved = PE.ReadJson(fx.project.scriveDir .. '/session.json')
  assert_equal([fx.departure.relPath, 1], [get(saved, 'activeDocRelPath', ''), get(saved, 'cursorLine', 0)])
  SS.ForgetKnownStates()
  Close(fx)
enddef

def Test_the_inspector_follows_the_cursor(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  var editor: number = win_getid()
  I.Toggle()
  win_gotoid(editor)
  assert_match('Arrival', join(getbufline(CO.INSPECTOR_BUF, 1, '$')))
  cursor(5, 1)
  doautocmd CursorMoved
  assert_match('Departure', join(getbufline(CO.INSPECTOR_BUF, 1, '$')))
  I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  Close(fx)
enddef

def Test_a_restored_snapshot_shows_in_the_scrivening(): void
  var fx = NewProject()
  SN.Take(fx.project, fx.departure, '')
  SV.Open(fx.project, fx.manuscript)
  setline(5, 'Changed after the snapshot.')
  write
  var snapshot = SN.List(fx.project, fx.departure)[-1]
  SN.Restore(fx.project, fx.departure, snapshot)
  assert_equal('The train left.', getline(5))
  assert_false(&modified)
  Close(fx)
enddef

# FUNCTION: Quill applies to a Scrivening as to a document, when it
# applies on entry. The hook is the one that opening a scrive starts.
def Test_quill_applies_to_the_scrivening(): void
  var fx = NewProject()
  augroup bartleby_quill_auto
    autocmd!
    autocmd BufEnter * bartleby#quill#AutoApply()
  augroup END
  SV.Open(fx.project, fx.manuscript)
  assert_equal(g:bartleby_quill_auto, !!exists('b:bartleby_quill'))
  augroup bartleby_quill_auto
    autocmd!
  augroup END
  Close(fx)
enddef

# FUNCTION: Paragraph formatting, as in the auto mode of Quill, does not
# join a title line to the text of a scene, at its start or its end.
def Test_paragraph_formatting_leaves_the_title_lines(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setlocal formatoptions+=a textwidth=40
  # Joining a title line in formatting raised an internal error of Vim.
  try
    feedkeys("5GA and never came back.\<Esc>", 'xt')
    feedkeys("3GA It stopped twice on the way there.\<Esc>", 'xt')
    doautocmd TextChanged
  catch
    assert_report('formatting: ' .. v:exception)
  endtry
  var titles: list<string> = getline(1, '$')->filter((_, l) => l =~# '^──')
  assert_equal(['── Chapter: 1 / Arrival ──', '── Chapter: 2 / Departure ──'], titles)
  assert_match('never came back', join(getline(1, '$')))
  setlocal formatoptions-=a
  set nomodified
  Close(fx)
enddef

def Test_spotlight_dims_in_the_scrivening(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  cursor(5, 1)
  SP.Execute(false, '')
  assert_true(exists('w:bartleby_spotlight_matches'), 'Spotlight did not start')
  SP.Execute(true, '')
  Close(fx)
enddef

# FUNCTION: Focus shows the Scrivening in its own tab, and gives it back.
def Test_focus_works_on_the_scrivening(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  var buf: number = bufnr()
  F.Execute(false, '')
  assert_equal([buf, true], [bufnr(), !!exists('t:bartleby_focus_session')])
  cursor(5, 1)
  assert_equal('Departure', TitleHere(fx.project))
  F.Execute(true, '')
  assert_equal([buf, false], [bufnr(), !!exists('t:bartleby_focus_session')])
  Close(fx)
enddef

export def RunAll(): void
  Test_a_scrivening_shows_the_folder_tree_in_binder_order()
  Test_only_a_folder_in_the_manuscript_opens()
  Test_saving_writes_only_the_documents_that_changed()
  Test_an_empty_document_has_a_line_to_type_in()
  Test_a_change_to_a_title_line_is_undone()
  Test_a_damaged_title_line_saves_nothing()
  Test_backspace_and_delete_do_not_join_a_title_line()
  Test_open_documents_are_saved_closed_and_opened_in_the_scrivening()
  Test_a_document_opened_alone_shows_in_the_scrivening()
  Test_the_scrivening_follows_the_binder()
  Test_auto_save_writes_the_scrivening()
  Test_the_session_records_the_document_under_the_cursor()
  Test_the_inspector_follows_the_cursor()
  Test_a_restored_snapshot_shows_in_the_scrivening()
  Test_quill_applies_to_the_scrivening()
  Test_spotlight_dims_in_the_scrivening()
  Test_focus_works_on_the_scrivening()
  Test_paragraph_formatting_leaves_the_title_lines()
enddef
