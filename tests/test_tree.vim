vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_tree.vim: Flatten and IndexOfRowById of tree.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as Fx

def Test_flatten_produces_all_rows_in_depth_first_order(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  # 5 top-level folders, 2 chapters, and 2 scenes.
  assert_equal(9, len(rows))
  var titles = rows->mapnew((_, r) => r.item.title)
  assert_equal(['Front Matter', 'Manuscript', '1', 'Scene 1', '2', 'Scene 1',
    'Back Matter', 'Characters', 'Research'], titles)
enddef

def Test_flatten_assigns_correct_depth(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var depths = rows->mapnew((_, r) => r.depth)
  # Depths in tree order: Front Matter 0, Manuscript 0, Chapter 1 1, its
  # scene 2, Chapter 2 1, its scene 2, Back Matter 0, Characters 0, and
  # Research 0.
  assert_equal([0, 0, 1, 2, 1, 2, 0, 0, 0], depths)
enddef

def Test_flatten_assigns_correct_owner(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  # Row 0 is Front Matter: top level, no owner.
  assert_true(rows[0].ownerItem is null_object)
  # Row 2 is Chapter 1, owned by Manuscript, the item of row 1.
  assert_equal(rows[1].item.id, rows[2].ownerItem.id)
  # Row 3 is the scene in Chapter 1, owned by that chapter, the item of
  # row 2.
  assert_equal(rows[2].item.id, rows[3].ownerItem.id)
enddef

def Test_flatten_skips_children_of_a_collapsed_folder(): void
  var project = Fx.BuildProject()
  var manuscriptId = project.ItemAt(1).id
  var rows = T.Flatten(project, {[manuscriptId]: true})
  # The Manuscript row still shows. Its 2 chapters and their scenes do not.
  assert_equal(5, len(rows))
  var titles = rows->mapnew((_, r) => r.item.title)
  assert_equal(-1, index(titles, '1'))
  assert_equal(-1, index(titles, '2'))
enddef

def Test_flatten_nested_collapse_hides_grandchildren_too(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var chapter1Id = manuscript.ChildAt(0).id
  # Only the chapter is collapsed, not the Manuscript.
  var rows = T.Flatten(project, {[chapter1Id]: true})
  # Chapter 1 still shows, and its scene does not. Chapter 2 and its scene
  # do not change.
  assert_equal(8, len(rows))
  var chapter1Row = rows->copy()->filter((_, r) => r.item.id ==# chapter1Id)[0]
  assert_equal(0, len(rows->copy()->filter((_, r) => r.ownerItem isnot null_object
    && r.ownerItem.id ==# chapter1Id)))
enddef

def Test_index_of_row_by_id_finds_known_row(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var manuscriptId = project.ItemAt(1).id
  assert_equal(1, T.IndexOfRowById(rows, manuscriptId))
enddef

def Test_index_of_row_by_id_returns_minus_one_for_unknown_id(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  assert_equal(-1, T.IndexOfRowById(rows, 'no-such-id'))
enddef

export def RunAll(): void
  Test_flatten_produces_all_rows_in_depth_first_order()
  Test_flatten_assigns_correct_depth()
  Test_flatten_assigns_correct_owner()
  Test_flatten_skips_children_of_a_collapsed_folder()
  Test_flatten_nested_collapse_hides_grandchildren_too()
  Test_index_of_row_by_id_finds_known_row()
  Test_index_of_row_by_id_returns_minus_one_for_unknown_id()
enddef
