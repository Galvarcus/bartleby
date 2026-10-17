vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_links.vim: links between documents. Finding the link under the
# cursor, matching its title, gf, creating a missing document, updating the
# links when a document is renamed, and how compile shows them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI

# FUNCTION: The fixture project, with a document titled Mara in Characters,
# and a file on disk for each document.
def Project(): any
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  chars.AddChild(BI.BinderItem.NewDocument('Mara', 'characters/mara.md'))
  for item in [Scene(project, 0), Scene(project, 1), chars.ChildAt(0)]
    FI.WriteDocContent(project, item, ['text'])
  endfor
  return project
enddef

# FUNCTION: The document Scene 1 of chapter n + 1. Both are titled Scene 1.
def Scene(project: any, n: number): any
  return project.ChildAt(1).ChildAt(n).ChildAt(0)
enddef

def Edit(project: any, item: any, lines: list<string>): void
  FI.WriteDocContent(project, item, lines)
  execute 'edit! ' .. fnameescape(item.AbsPath(project.BinderRoot()))
enddef

def Cleanup(project: any): void
  popup_clear()
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_link_is_found_anywhere_on_its_brackets(): void
  var line: string = 'See [[Mara]] now'
  for col in [5, 6, 8, 11, 12]
    assert_equal({target: 'Mara', text: 'Mara'}, LK.At(line, col), $'col {col}')
  endfor
  assert_equal({}, LK.At(line, 4))
  assert_equal({}, LK.At(line, 13))
enddef

def Test_a_link_with_its_own_text_and_two_links_on_a_line(): void
  var line: string = '[[A]] and [[Mara|the captain]]'
  assert_equal({target: 'A', text: 'A'}, LK.At(line, 2))
  assert_equal({target: 'Mara', text: 'the captain'}, LK.At(line, 20))
  assert_equal({target: 'Mara', text: 'Mara'}, LK.At('[[ Mara ]]', 4))
enddef

def Test_a_title_matches_exactly_or_else_without_case(): void
  var project = Project()
  assert_equal(['Mara'], LK.Find(project, 'Mara')->mapnew((_, d) => d.title))
  assert_equal(['Mara'], LK.Find(project, 'mara')->mapnew((_, d) => d.title))
  assert_equal(2, len(LK.Find(project, 'Scene 1')))
  assert_equal([], LK.Find(project, 'Nobody'))
  Cleanup(project)
enddef

def Test_a_document_in_the_trash_is_not_a_target(): void
  var project = Project()
  var rows = T.Flatten(project)
  TR.MoveToTrash(project, T.FindRowById(rows, project.ChildAt(3).ChildAt(0).id))
  assert_equal([], LK.Find(project, 'Mara'))
  Cleanup(project)
enddef

def Test_gf_on_a_link_opens_its_document(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['She met [[Mara]] at dawn.'])
  cursor(1, 12)
  LK.Follow()
  assert_match('characters/mara\.md$', expand('%:p'))
  Cleanup(project)
enddef

def Test_gf_on_a_title_that_two_documents_share_offers_a_choice(): void
  var project = Project()
  ST.Set(project)
  Edit(project, project.ChildAt(3).ChildAt(0), ['See [[Scene 1]].'])
  cursor(1, 8)
  var before: number = len(popup_list())
  LK.Follow()
  assert_equal(before + 1, len(popup_list()))
  Cleanup(project)
enddef

def Test_gf_on_a_missing_title_offers_to_create_it(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See [[Nobody]].'])
  cursor(1, 8)
  var before: number = len(popup_list())
  LK.Follow()
  assert_equal(before + 1, len(popup_list()))
  Cleanup(project)
enddef

def Test_a_created_document_goes_next_to_the_current_one(): void
  var project = Project()
  var scene = Scene(project, 0)
  var item = B.AddDocNear(project, T.FindRowById(T.Flatten(project), scene.id), 'Nobody')
  assert_equal(['Scene 1', 'Nobody'], project.ChildAt(1).ChildAt(0).children->mapnew((_, c) => c.title))
  assert_true(filereadable(item.AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

# FUNCTION: Off a link, gf does what it does without Bartleby: it opens the
# file named under the cursor.
def Test_gf_off_a_link_opens_the_file_under_the_cursor(): void
  var file: string = tempname()
  writefile(['x'], file)
  enew!
  setline(1, file)
  # Vim's own gf will not leave a modified buffer without 'hidden'.
  setlocal nomodified
  cursor(1, 2)
  LK.Follow()
  assert_equal(file, expand('%:p'))
  silent! :%bwipe!
  delete(file)
enddef

def Test_a_rename_points_links_at_the_new_title_and_keeps_their_text(): void
  var [out, count] = LK.Retitle(['[[Mara]] and [[mara|her]] but [[Marat]]'], 'Mara', 'Mara Jones')
  assert_equal(['[[Mara Jones|Mara]] and [[Mara Jones|her]] but [[Marat]]'], out)
  assert_equal(2, count)
enddef

def Test_a_rename_updates_open_buffers_and_closed_files(): void
  var project = Project()
  FI.WriteDocContent(project, Scene(project, 1), ['Ask [[Mara]].'])
  Edit(project, Scene(project, 0), ['See [[Mara]].'])
  project.ChildAt(3).ChildAt(0).Rename('Mara Jones')
  assert_equal(2, LK.Retarget(project, 'Mara', 'Mara Jones'))
  assert_equal(['See [[Mara Jones|Mara]].'], getline(1, '$'))
  assert_equal(['Ask [[Mara Jones|Mara]].'], readfile(Scene(project, 1).AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

def Test_counting_links_changes_nothing(): void
  var project = Project()
  FI.WriteDocContent(project, Scene(project, 1), ['Ask [[Mara]].'])
  assert_equal(1, LK.Retarget(project, 'Mara', 'Mara Jones', false))
  assert_equal(['Ask [[Mara]].'], readfile(Scene(project, 1).AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

# FUNCTION: A link reads as its text in a Manuscript or a Book. In a
# screenplay [[ ]] is a Fountain note, which the screenplay compiler drops.
def Test_compile_shows_links_as_their_text_except_in_a_screenplay(): void
  var project = Project()
  var scene = Scene(project, 0)
  FI.WriteDocContent(project, scene, ['She met [[Mara|the captain]].'])
  var play = C.CompileTarget.FromDict({name: 'P', kind: 'Screenplay', format: 'PDF', includedIds: [scene.id]})
  var book = C.CompileTarget.FromDict({name: 'B', kind: 'Book', format: 'HTML', includedIds: [scene.id]})
  assert_equal(['She met [[Mara|the captain]].'], C.ConcatenateDocs(project, play, ''))
  assert_true(index(C.ConcatenateBook(project, book), 'She met the captain.') >= 0)
  Cleanup(project)
enddef

def Test_gf_is_mapped_to_follow_a_link(): void
  assert_equal('<Plug>(BartlebyFollowLink)', maparg('gf', 'n'))
enddef

export def RunAll(): void
  Test_a_link_is_found_anywhere_on_its_brackets()
  Test_a_link_with_its_own_text_and_two_links_on_a_line()
  Test_a_title_matches_exactly_or_else_without_case()
  Test_a_document_in_the_trash_is_not_a_target()
  Test_gf_on_a_link_opens_its_document()
  Test_gf_on_a_title_that_two_documents_share_offers_a_choice()
  Test_gf_on_a_missing_title_offers_to_create_it()
  Test_a_created_document_goes_next_to_the_current_one()
  Test_gf_off_a_link_opens_the_file_under_the_cursor()
  Test_a_rename_points_links_at_the_new_title_and_keeps_their_text()
  Test_a_rename_updates_open_buffers_and_closed_files()
  Test_counting_links_changes_nothing()
  Test_compile_shows_links_as_their_text_except_in_a_screenplay()
  Test_gf_is_mapped_to_follow_a_link()
enddef
