vim9script
# tests/test_inputpopup.vim - InputPopup's multiline field key handling
# (Filter()/HandleMultilineKey() are effectively what's under test here).
# InputPopup is exported, so its methods are called directly rather than
# through feedkeys() - Open() must run first so this.bufnr/this.winid
# exist for Filter() to render into, even though no real keypress ever
# reaches the popup in this test.

import autoload 'bartleby/inputpopup.vim' as IP

def NewMultilinePopup(default: string): IP.InputPopup
  var fields: list<list<dict<any>>> = [[{name: 'text', type: 'multiline', rows: 5}]]
  var popup = IP.InputPopup.new(fields, {text: default}, {title: ' Test ', buttons: []})
  popup.Open()
  return popup
enddef

def Test_enter_inserts_a_newline_rather_than_submitting(): void
  var popup = NewMultilinePopup('First line')
  var submitted = false
  popup.OnSubmit((values: dict<any>) => {
    submitted = true
  })
  popup.Filter(popup.winid, "\<CR>")
  # Still open - Enter must not have submitted.
  assert_false(submitted)
  assert_equal("First line\n", popup.Values().text)
  popup.Close()
enddef

def Test_typed_text_is_inserted_at_the_cursor(): void
  var popup = NewMultilinePopup('')
  for c in 'Hi'
    popup.Filter(popup.winid, c)
  endfor
  assert_equal('Hi', popup.Values().text)
  popup.Close()
enddef

def Test_backspace_at_line_start_merges_with_previous_line(): void
  var popup = NewMultilinePopup("First\nSecond")
  # Field defaults start with the cursor at the end of the first line -
  # move to the start of the second line before backspacing.
  popup.Filter(popup.winid, "\<Down>")
  popup.Filter(popup.winid, "\<Home>")
  popup.Filter(popup.winid, "\<BS>")
  assert_equal('FirstSecond', popup.Values().text)
  popup.Close()
enddef

def Test_ctrl_s_submits_with_the_current_text(): void
  var popup = NewMultilinePopup('Draft text')
  var received = ''
  popup.OnSubmit((values: dict<any>) => {
    received = values.text
  })
  popup.Filter(popup.winid, "\<C-s>")
  assert_equal('Draft text', received)
enddef

def Test_esc_cancels_without_calling_on_submit(): void
  var popup = NewMultilinePopup('Draft text')
  var submitted = false
  popup.OnSubmit((values: dict<any>) => {
    submitted = true
  })
  popup.Filter(popup.winid, "\<Esc>")
  assert_false(submitted)
enddef

const FILTER_OPTIONS: list<string> = ['one', 'two', 'three', 'four', 'five', 'six']

# A filter list with 6 options and 3 visible rows.
def NewFilterPopup(title: string = 'Pick', minWidth: number = 0): IP.InputPopup
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'filter',
    options: FILTER_OPTIONS, maxVisible: 3}]]
  var popup = IP.InputPopup.new(fields, {}, {title: $' {title} ', buttons: [], min_width: minWidth})
  popup.Open()
  return popup
enddef

# The option text on each visible list row, without padding or scrollbar.
def VisibleRows(popup: IP.InputPopup): list<string>
  return getbufline(winbufnr(popup.winid), 2, 4)->mapnew((_, l) => trim(l))
enddef

def Test_filter_list_scrolls_with_the_selection(): void
  var popup = NewFilterPopup()
  assert_equal(['one', 'two', 'three'], VisibleRows(popup))
  for i in range(4)
    popup.Filter(popup.winid, "\<Down>")
  endfor
  # The fifth option is selected and visible.
  assert_equal(['three', 'four', 'five'], VisibleRows(popup))
  assert_equal('five', popup.Values().choice)
  popup.Filter(popup.winid, "\<PageUp>")
  assert_equal(['two', 'three', 'four'], VisibleRows(popup))
  assert_equal('two', popup.Values().choice)
  popup.Close()
enddef

def Test_filter_scrollbar_only_when_the_list_scrolls(): void
  var popup = NewFilterPopup()
  var buf = winbufnr(popup.winid)
  var bar = range(2, 4)->mapnew((_, l) => prop_list(l, {bufnr: buf, types: ['InputPopupScrollbar', 'InputPopupThumb']})->len())
  assert_equal([1, 1, 1], bar)
  # Typing narrows the list to fewer rows than are visible: no scrollbar.
  for c in 'fi'
    popup.Filter(popup.winid, c)
  endfor
  bar = range(2, 4)->mapnew((_, l) => prop_list(l, {bufnr: buf, types: ['InputPopupScrollbar', 'InputPopupThumb']})->len())
  assert_equal([0, 0, 0], bar)
  popup.Close()
enddef

def Test_popup_is_wide_enough_for_its_title(): void
  var title = 'A title much longer than any option'
  var popup = NewFilterPopup(title)
  assert_true(popup_getoptions(popup.winid).minwidth >= strdisplaywidth(title) + 2)
  popup.Close()
  popup = NewFilterPopup('Pick', 40)
  assert_equal(40, popup_getoptions(popup.winid).minwidth)
  popup.Close()
enddef

export def RunAll(): void
  Test_enter_inserts_a_newline_rather_than_submitting()
  Test_typed_text_is_inserted_at_the_cursor()
  Test_backspace_at_line_start_merges_with_previous_line()
  Test_ctrl_s_submits_with_the_current_text()
  Test_esc_cancels_without_calling_on_submit()
  Test_filter_list_scrolls_with_the_selection()
  Test_filter_scrollbar_only_when_the_list_scrolls()
  Test_popup_is_wide_enough_for_its_title()
enddef
