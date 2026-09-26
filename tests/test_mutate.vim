vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_mutate.vim: the tree changes and structure rules of
# mutate.vim. RoleAllowedUnder, NextRoleNumber, and AddIntoContainer are
# local to the script. RoleAllowedUnder is tested through the results of
# Indent and Outdent, which use it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/mutate.vim' as M
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as Fx

def Test_is_immutable_folder_true_for_all_5_structural_roles(): void
  assert_true(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_FRONT_MATTER)))
  assert_true(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_MANUSCRIPT)))
  assert_true(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_BACK_MATTER)))
  assert_true(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_CHARACTERS)))
  assert_true(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_RESEARCH)))
enddef

def Test_is_immutable_folder_false_for_chapter_part_custom_and_documents(): void
  assert_false(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_CHAPTER)))
  assert_false(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_PART)))
  assert_false(M.IsImmutableFolder(BI.BinderItem.NewFolder('x', BI.ROLE_CUSTOM)))
  assert_false(M.IsImmutableFolder(BI.BinderItem.NewDocument('x', 'x.md')))
enddef

def Test_indent_refused_on_an_immutable_folder(): void
  # Back Matter, a protected folder, is right after Manuscript at the top
  # level. Indenting it would make it a child of Manuscript, which must be
  # refused.
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var backMatterRow = T.FindRowById(rows, project.ItemAt(2).id)
  assert_false(M.Indent(project, backMatterRow))
  # Confirm that nothing moved.
  assert_equal(5, project.ItemCount())
enddef

def Test_indent_allowed_for_a_chapter_into_a_preceding_chapter(): void
  # Only Part and Chapter must be under Manuscript or a Part, see
  # RoleAllowedUnder. The case worth checking is a Chapter that indents
  # into a Part, so build that tree directly.
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var part = BI.BinderItem.NewFolder('Part One', BI.ROLE_PART)
  # Take Chapter 1 out again.
  manuscript.RemoveChildAt(0)
  part.AddChild(BI.BinderItem.NewFolder('1', BI.ROLE_CHAPTER))
  manuscript.InsertChildAt(0, part)
  var rows = T.Flatten(project)
  # Chapter 2.
  var chapterRow = T.FindRowById(rows, manuscript.ChildAt(1).id)
  # Chapter 2 is after the Part, as a child of Manuscript. Indenting it
  # must succeed and make it a child of the Part.
  assert_true(M.Indent(project, chapterRow))
  assert_equal(2, part.ChildCount())
enddef

def Test_outdent_refused_when_it_would_leave_manuscript_role_restriction(): void
  # The parent of a Chapter directly in Manuscript is at the top level: its
  # grandparent is the Project, null_object for RoleAllowedUnder. Outdenting
  # it would put it at the top level, which ROLE_CHAPTER never allows.
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  assert_false(M.Outdent(project, rows, chapter1Row))
enddef

def Test_outdent_returns_false_for_an_already_root_level_item(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var frontMatterRow = T.FindRowById(rows, project.ItemAt(0).id)
  assert_false(M.Outdent(project, rows, frontMatterRow))
enddef

def Test_remove_deletes_a_root_level_item(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var researchRow = T.FindRowById(rows, project.ItemAt(4).id)
  M.Remove(project, researchRow)
  assert_equal(4, project.ItemCount())
enddef

def Test_remove_deletes_a_nested_item_from_its_owner(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  M.Remove(project, chapter1Row)
  assert_equal(1, manuscript.ChildCount())
  assert_equal('2', manuscript.ChildAt(0).title)
enddef

def Test_clear_children_empties_a_folder_without_removing_it(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  assert_equal(2, manuscript.ChildCount())
  M.ClearChildren(manuscript)
  assert_equal(0, manuscript.ChildCount())
  # The folder itself is not touched: still there, the same object.
  assert_equal(5, project.ItemCount())
  assert_equal(manuscript.id, project.ItemAt(1).id)
enddef

def Test_move_within_siblings_swaps_two_chapters(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  assert_true(M.MoveWithinSiblings(project, chapter1Row, 1))
  assert_equal('2', manuscript.ChildAt(0).title)
  assert_equal('1', manuscript.ChildAt(1).title)
enddef

def Test_move_within_siblings_false_at_a_list_edge(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  # Chapter 1 is already first, so moving it up does nothing.
  assert_false(M.MoveWithinSiblings(project, chapter1Row, -1))
enddef

def Test_move_within_siblings_refuses_non_chapter_non_part_folders(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  # Back Matter is a structural folder, but neither a Chapter nor a Part.
  var backMatterRow = T.FindRowById(rows, project.ItemAt(2).id)
  assert_false(M.MoveWithinSiblings(project, backMatterRow, 1))
enddef

def Test_find_manuscript_locates_the_manuscript_folder(): void
  var project = Fx.BuildProject()
  var manuscript = M.FindManuscript(project)
  assert_false(manuscript is null_object)
  assert_equal(BI.ROLE_MANUSCRIPT, manuscript.structureRole)
enddef

def Test_find_ancestor_with_role_finds_manuscript_from_a_scene(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var rows = T.Flatten(project)
  var sceneRow = T.FindRowById(rows, chapter1.ChildAt(0).id)
  var found = M.FindAncestorWithRole(rows, sceneRow, BI.ROLE_MANUSCRIPT)
  assert_false(found is null_object)
  assert_equal(manuscript.id, found.id)
enddef

def Test_find_ancestor_with_role_returns_null_when_absent(): void
  var project = Fx.BuildProject()
  var rows = T.Flatten(project)
  var frontMatterRow = T.FindRowById(rows, project.ItemAt(0).id)
  assert_true(M.FindAncestorWithRole(rows, frontMatterRow, BI.ROLE_PART) is null_object)
enddef

def Test_add_chapter_creates_a_folder_with_a_starter_scene(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var chapter = M.AddChapter(manuscript, null_object, 'New Chapter')
  assert_equal('New Chapter', chapter.title)
  assert_equal(BI.ROLE_CHAPTER, chapter.structureRole)
  assert_equal(1, chapter.ChildCount())
  assert_equal('Scene 1', chapter.ChildAt(0).title)
  # Added at the end, because row is null_object.
  assert_equal(3, manuscript.ChildCount())
enddef

def Test_add_chapter_blank_title_auto_numbers(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var chapter = M.AddChapter(manuscript, null_object, '')
  # The 2 chapters are 1 and 2, so the next number is 3.
  assert_equal('3', chapter.title)
enddef

def Test_add_part_creates_an_empty_folder(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var part = M.AddPart(manuscript, null_object, 'Part One')
  assert_equal('Part One', part.title)
  assert_equal(BI.ROLE_PART, part.structureRole)
  assert_equal(0, part.ChildCount())
enddef

def Test_rename_changes_the_items_title(): void
  var project = Fx.BuildProject()
  var manuscript = project.ItemAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  M.Rename(chapter1Row, 'Prologue')
  assert_equal('Prologue', manuscript.ChildAt(0).title)
enddef

export def RunAll(): void
  Test_is_immutable_folder_true_for_all_5_structural_roles()
  Test_is_immutable_folder_false_for_chapter_part_custom_and_documents()
  Test_indent_refused_on_an_immutable_folder()
  Test_indent_allowed_for_a_chapter_into_a_preceding_chapter()
  Test_outdent_refused_when_it_would_leave_manuscript_role_restriction()
  Test_outdent_returns_false_for_an_already_root_level_item()
  Test_remove_deletes_a_root_level_item()
  Test_remove_deletes_a_nested_item_from_its_owner()
  Test_clear_children_empties_a_folder_without_removing_it()
  Test_move_within_siblings_swaps_two_chapters()
  Test_move_within_siblings_false_at_a_list_edge()
  Test_move_within_siblings_refuses_non_chapter_non_part_folders()
  Test_find_manuscript_locates_the_manuscript_folder()
  Test_find_ancestor_with_role_finds_manuscript_from_a_scene()
  Test_find_ancestor_with_role_returns_null_when_absent()
  Test_add_chapter_creates_a_folder_with_a_starter_scene()
  Test_add_chapter_blank_title_auto_numbers()
  Test_add_part_creates_an_empty_folder()
  Test_rename_changes_the_items_title()
enddef
