vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_slug.vim: slug.vim, which turns a title into a name on disk.
# A slug that names a Windows device is the one that cannot be left as it
# is: that system answers with the device whatever extension follows, so a
# document titled Nul was written to NUL and lost.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/55
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/slug.vim' as SU

def Test_a_title_becomes_lower_case_with_hyphens(): void
  assert_equal('a-dark-and-stormy-night', SU.Slugify('A Dark and Stormy Night'))
  assert_equal('chapter-1', SU.Slugify('Chapter 1!'))
  assert_equal('1984', SU.Slugify('1984'))
  assert_equal('', SU.Slugify('***'))
enddef

def Test_a_run_of_anything_else_becomes_one_hyphen(): void
  assert_equal('a-b', SU.Slugify('A  --  B'))
  assert_equal('leading-and-trailing', SU.Slugify('  leading and trailing  '))
  assert_equal("mr-smith-s-plan", SU.Slugify('Mr. Smith''s "Plan"'))
enddef

def Test_a_separator_of_a_path_never_survives(): void
  assert_equal('a-b-c', SU.Slugify('a/b\c'))
  assert_equal('up-here', SU.Slugify('../up/here'))
enddef

# A letter outside a to z is dropped rather than turned into its nearest
# plain letter, so Uber and Ober give the same name and a title in a
# script of its own gives none at all. layout.vim answers an empty slug
# with untitled.
def Test_a_letter_outside_ascii_is_dropped(): void
  assert_equal('caf-noir', SU.Slugify('Café Noir'))
  assert_equal('nicode-ber', SU.Slugify('Ünicode Über'))
  assert_equal('', SU.Slugify('日本語'))
enddef

# The layout asks for the name of a title whenever it lays a scrive out,
# so a slug of a slug must be the same slug, or a document would move on
# every pass.
def Test_a_slug_is_unchanged_by_a_second_pass(): void
  for title in ['A Dark and Stormy Night', 'Chapter 1!', 'Nul', 'doc-nul',
      'Café Noir', 'a/b\c', '  spaced  ', '***']
    assert_equal(SU.Slugify(title), SU.Slugify(SU.Slugify(title)),
      $'the slug of {title} changed on a second pass')
  endfor
enddef

def Test_a_slug_that_names_a_device_never_stands_alone(): void
  assert_equal('doc-nul', SU.Slugify('Nul'))
  assert_equal('doc-con', SU.Slugify('con'))
  assert_equal('doc-prn', SU.Slugify('PRN'))
  assert_equal('doc-aux', SU.Slugify('Aux'))
  assert_equal('doc-com1', SU.Slugify('COM1'))
  assert_equal('doc-lpt9', SU.Slugify('lpt9'))
  # The name is reached after the reduction, so punctuation does not hide
  # it.
  assert_equal('doc-nul', SU.Slugify('NUL!'))
  assert_equal('doc-nul', SU.Slugify('-nul-'))
enddef

def Test_a_title_that_merely_holds_a_device_name_is_left_alone(): void
  assert_equal('nul-and-void', SU.Slugify('Nul and void'))
  assert_equal('console', SU.Slugify('Console'))
  assert_equal('auxiliary', SU.Slugify('Auxiliary'))
  # Only COM1 to COM9 are reserved, and LPT1 to LPT9.
  assert_equal('com10', SU.Slugify('COM10'))
  assert_equal('com0', SU.Slugify('COM0'))
  # An extension in the title is reduced to a hyphen, so the stem is no
  # longer the reserved name that Windows answers for.
  assert_equal('nul-md', SU.Slugify('nul.md'))
  assert_equal('com1-txt', SU.Slugify('COM1.txt'))
enddef

export def RunAll(): void
  Test_a_title_becomes_lower_case_with_hyphens()
  Test_a_run_of_anything_else_becomes_one_hyphen()
  Test_a_separator_of_a_path_never_survives()
  Test_a_letter_outside_ascii_is_dropped()
  Test_a_slug_is_unchanged_by_a_second_pass()
  Test_a_slug_that_names_a_device_never_stands_alone()
  Test_a_title_that_merely_holds_a_device_name_is_left_alone()
enddef
