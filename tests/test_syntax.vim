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
  # '  ▾ Chapter: 1' - 2-space indent, 3-byte marker, space, then the
  # role label immediately after it, then the plain title '1'.
  setline(1, ['Title'])
  setline(2, ['  ▾ Chapter: 1'])
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
  # Column 16 is '1' - the plain, arbitrary title - must NOT be highlighted.
  assert_equal('', GroupAt(2, 16))
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

def Test_compile_select_checkbox_and_marker_are_isolated(): void
  new
  setlocal buftype=nofile
  setline(1, ['    [x] · Scene 1'])
  setlocal filetype=bartleby-compile-select
  # Columns 5-7 are '[x]'.
  for col in range(5, 7)
    assert_equal('bartlebyCompileSelectChecked', GroupAt(1, col))
  endfor
  # Columns 9-10 are '·' (2 UTF-8 bytes).
  assert_equal('bartlebyCompileSelectMarker', GroupAt(1, 9))
  assert_equal('bartlebyCompileSelectMarker', GroupAt(1, 10))
  # 'Scene 1' itself must not be highlighted.
  for col in range(12, 18)
    assert_equal('', GroupAt(1, col))
  endfor
  bwipe!
enddef

def Test_compile_select_unchecked_box_is_its_own_group(): void
  new
  setlocal buftype=nofile
  setline(1, ['    [ ] · Front Matter'])
  setlocal filetype=bartleby-compile-select
  for col in range(5, 7)
    assert_equal('bartlebyCompileSelectUnchecked', GroupAt(1, col))
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
  Test_compile_select_checkbox_and_marker_are_isolated()
  Test_compile_select_unchecked_box_is_its_own_group()
  Test_inspector_header_and_field_labels_are_isolated()
enddef
