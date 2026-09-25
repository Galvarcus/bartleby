vim9script
# tests/test_syntax.vim - per-column synID() checks for the 3 bartleby-*
# syntax files. Isolated from the real Binder/Inspector/Compile-select
# rendering (already covered by test_binder.vim etc): a scratch buffer is
# given known content in each format's exact shape, with filetype set
# directly, and each relevant column's actual syntax group is checked -
# visual inspection alone previously missed 2 real bugs here (see
# testing_checklist.md), so this always checks synID(), never just
# whether *something* highlights.
#
# Needs `:syntax on` to actually engage (requires $VIMRUNTIME to be set
# correctly - true for any normal Vim install, and for this sandbox only
# when invoked with VIMRUNTIME=... explicitly; see testing_checklist.md's
# sandbox-gotchas entry).

def GroupAt(lnum: number, col: number): string
  return synIDattr(synID(lnum, col, 1), 'name')
enddef

def Test_binder_title_line_is_fully_highlighted(): void
  new
  setlocal buftype=nofile
  setline(1, ['My Project'])
  setlocal filetype=bartleby-binder
  for col in range(1, 10)
    assert_equal('bartlebyBinderTitle', GroupAt(1, col))
  endfor
  bwipe!
enddef

def Test_binder_marker_and_role_label_are_isolated(): void
  new
  setlocal buftype=nofile
  # '  ▾ Chapter: 1/' - 2-space indent, 3-byte marker, space, the role
  # label, then the folder name '1' with the '/' that binder.vim adds.
  setline(1, ['Title'])
  setline(2, ['  ▾ Chapter: 1/'])
  setlocal filetype=bartleby-binder
  # Columns 3-5 are the 3 UTF-8 bytes of '▾'.
  assert_equal('bartlebyBinderMarker', GroupAt(2, 3))
  assert_equal('bartlebyBinderMarker', GroupAt(2, 4))
  assert_equal('bartlebyBinderMarker', GroupAt(2, 5))
  # Column 6 is the plain space between the marker and 'Chapter: '.
  assert_equal('', GroupAt(2, 6))
  # Columns 7-15 are 'Chapter: ' (9 characters).
  for col in range(7, 15)
    assert_equal('bartlebyBinderRoleLabel', GroupAt(2, col))
  endfor
  # Columns 16-17 are '1/', the folder name: Directory, not the label.
  assert_equal('bartlebyBinderDirectory', GroupAt(2, 16))
  assert_equal('bartlebyBinderDirectory', GroupAt(2, 17))
  bwipe!
enddef

def Test_binder_item_label_suffix_is_isolated_to_known_colors(): void
  new
  setlocal buftype=nofile
  setline(1, ['Title'])
  setline(2, ['  · Scene 1 (Red)'])
  setlocal filetype=bartleby-binder
  # 'Scene 1' itself (columns 6-12) is plain title text.
  for col in range(6, 12)
    assert_equal('', GroupAt(2, col))
  endfor
  # ' (Red)' (columns 13-18) is the label suffix.
  for col in range(13, 18)
    assert_equal('bartlebyBinderItemLabel', GroupAt(2, col))
  endfor
  bwipe!
enddef

def Test_binder_does_not_highlight_an_unknown_color_name(): void
  # A title that happens to end in " (Something)" where Something isn't
  # one of the real label names must never be mistaken for one - this is
  # exactly the kind of arbitrary-user-text case the file must not match.
  new
  setlocal buftype=nofile
  setline(1, ['Title'])
  setline(2, ['  · My Draft (Something)'])
  setlocal filetype=bartleby-binder
  for col in range(6, 24)
    assert_equal('', GroupAt(2, col))
  endfor
  bwipe!
enddef

# The compile pane's first two lines are the '*** Compile ***' header and
# the project title (see compile.vim's RedrawSelect()). Rows start on
# line 3, so every compile-pane test sets both lines first.
def CompileSelectBuffer(rows: list<string>): void
  new
  setlocal buftype=nofile
  setline(1, ['*** Compile ***', 'My Project'] + rows)
  setlocal filetype=bartleby-compile-select
enddef

def Test_compile_select_header_and_title(): void
  CompileSelectBuffer(['    [x] · Scene 1'])
  for col in range(1, 15)
    assert_equal('bartlebyCompileSelectHeader', GroupAt(1, col))
  endfor
  for col in range(1, 10)
    assert_equal('bartlebyCompileSelectTitle', GroupAt(2, col))
  endfor
  bwipe!
enddef

def Test_compile_select_checkbox_and_marker_are_isolated(): void
  CompileSelectBuffer(['    [x] · Scene 1'])
  # Columns 5-7 are '[x]'.
  for col in range(5, 7)
    assert_equal('bartlebyCompileSelectChecked', GroupAt(3, col))
  endfor
  # Columns 9-10 are '·' (2 UTF-8 bytes).
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 9))
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 10))
  # 'Scene 1' itself must not be highlighted.
  for col in range(12, 18)
    assert_equal('', GroupAt(3, col))
  endfor
  bwipe!
enddef

def Test_compile_select_unchecked_box_is_its_own_group(): void
  CompileSelectBuffer(['  [ ] · Dedication'])
  for col in range(3, 5)
    assert_equal('bartlebyCompileSelectUnchecked', GroupAt(3, col))
  endfor
  bwipe!
enddef

def Test_compile_select_folder_name_is_directory(): void
  # '    ▸ Front Matter/': 4 spaces, the 3-byte marker (columns 5-7), a
  # space, then the name and '/' (columns 9-21). A document title that
  # ends in '/' is not a folder.
  CompileSelectBuffer(['    ▸ Front Matter/', '  [x] · Notes/'])
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 5))
  for col in range(9, 21)
    assert_equal('bartlebyCompileSelectDirectory', GroupAt(3, col))
  endfor
  for col in range(9, 14)
    assert_equal('', GroupAt(4, col))
  endfor
  bwipe!
enddef

def Test_inspector_header_and_field_labels_are_isolated(): void
  new
  setlocal buftype=nofile
  setline(1, ['::Inspector::'])
  setline(2, ['Title: Scene 1'])
  setline(3, ['Label: Red'])
  setline(4, ['Target: -'])
  setline(5, ['Synopsis:'])
  setlocal filetype=bartleby-inspector
  for col in range(1, 13)
    assert_equal('bartlebyInspectorHeader', GroupAt(1, col))
  endfor
  # 'Title: ' (7 chars) is the field label; 'Scene 1' after it is not.
  for col in range(1, 7)
    assert_equal('bartlebyInspectorField', GroupAt(2, col))
  endfor
  for col in range(8, 14)
    assert_equal('', GroupAt(2, col))
  endfor
  # 'Label: ' (7 chars) likewise, on its own line.
  for col in range(1, 7)
    assert_equal('bartlebyInspectorField', GroupAt(3, col))
  endfor
  # 'Target: ' (8 chars).
  for col in range(1, 8)
    assert_equal('bartlebyInspectorField', GroupAt(4, col))
  endfor
  assert_equal('', GroupAt(4, 9)) # the '-' placeholder itself
  # 'Synopsis:' (9 chars, whole line, no trailing value on the same line).
  for col in range(1, 9)
    assert_equal('bartlebyInspectorSynopsisHeader', GroupAt(5, col))
  endfor
  bwipe!
enddef

export def RunAll(): void
  syntax on
  Test_binder_title_line_is_fully_highlighted()
  Test_binder_marker_and_role_label_are_isolated()
  Test_binder_item_label_suffix_is_isolated_to_known_colors()
  Test_binder_does_not_highlight_an_unknown_color_name()
  Test_compile_select_header_and_title()
  Test_compile_select_checkbox_and_marker_are_isolated()
  Test_compile_select_unchecked_box_is_its_own_group()
  Test_compile_select_folder_name_is_directory()
  Test_inspector_header_and_field_labels_are_isolated()
enddef
