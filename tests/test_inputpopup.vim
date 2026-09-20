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

export def RunAll(): void
  Test_enter_inserts_a_newline_rather_than_submitting()
  Test_typed_text_is_inserted_at_the_cursor()
  Test_backspace_at_line_start_merges_with_previous_line()
  Test_ctrl_s_submits_with_the_current_text()
  Test_esc_cancels_without_calling_on_submit()
enddef
