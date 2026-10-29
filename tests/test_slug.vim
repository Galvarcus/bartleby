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

# A name that the writer reads keeps the letters of the title, in any
# script, so that a folder on disk carries the name of the document.
def Test_a_name_keeps_every_letter_and_its_case(): void
  assert_equal('Über', SU.Safe('Über'))
  assert_equal('Café-Noir', SU.Safe('Café Noir'))
  assert_equal('日本語', SU.Safe('日本語'))
  assert_equal('A-Dark-and-Stormy-Night', SU.Safe('A Dark and Stormy Night'))
enddef

def Test_a_name_folds_what_a_file_system_forbids(): void
  assert_equal('Mr-Smith-s-Plan', SU.Safe('Mr. Smith''s "Plan"'))
  assert_equal('a-b-c-d-e-f-g-h-i-j', SU.Safe('a<b>c:d"e/f\g|h?i*j'))
  assert_equal('A-B', SU.Safe('A  --  B'))
  assert_equal('leading-and-trailing', SU.Safe('  leading and trailing  '))
  # Windows forbids a trailing dot and a trailing space, and neither can
  # survive the fold.
  assert_equal('trail', SU.Safe('trail. '))
  assert_equal('up-here', SU.Safe('../up/here'))
enddef

# A separator above ASCII is folded for the reason a space is: the writer
# cannot see it, and a name that holds one cannot be typed again.
def Test_a_name_folds_a_separator_above_ascii(): void
  assert_equal('no-break', SU.Safe("no\u00a0break"))
  assert_equal('', SU.Safe("\u3000\u00a0"))
  assert_equal('', SU.Safe('***'))
enddef

def Test_a_name_that_names_a_device_never_stands_alone(): void
  assert_equal('doc-Nul', SU.Safe('Nul'))
  assert_equal('doc-COM1', SU.Safe('COM1'))
  assert_equal('Console', SU.Safe('Console'))
  assert_equal('Nul-and-void', SU.Safe('Nul and void'))
enddef

# Windows reserves the superscript forms of COM1 to COM3 and LPT1 to
# LPT3 as well. Slugify destroyed them with every other character
# outside ASCII, and a name that keeps its letters can reach them.
def Test_a_name_that_names_a_device_in_superscript_is_guarded(): void
  assert_equal("doc-COM\u00b9", SU.Safe("COM\u00b9"))
  assert_equal("doc-lpt\u00b3", SU.Safe("lpt\u00b3"))
  # Only 1, 2 and 3 have a superscript that Windows reads as a digit.
  assert_equal("COM\u2074", SU.Safe("COM\u2074"))
enddef

# A path component holds 255 bytes, and a title of three bytes to the
# character reaches that in eighty-five characters.
def Test_a_long_name_is_capped_on_a_character(): void
  var long: string = repeat('日', 100)
  var name: string = SU.Safe(long)
  assert_true(strlen(name) <= 200, $'{strlen(name)} bytes is over the cap')
  assert_equal(66, strchars(name))
  assert_equal(long[0 : 2], name[0 : 2])
  # A cut that lands on a fold must not leave the name ending in one.
  assert_true(SU.Safe('a' .. repeat('-b', 200))[-1 : ] !=# SU.SEP)
enddef

def Test_a_name_is_unchanged_by_a_second_pass(): void
  for title in ['Über', 'Café Noir', '日本語', 'Nul', 'doc-Nul',
      'a/b\c', '  spaced  ', '***', repeat('日', 100)]
    assert_equal(SU.Safe(title), SU.Safe(SU.Safe(title)),
      $'the name of {title} changed on a second pass')
  endfor
enddef

export def RunAll(): void
  Test_a_title_becomes_lower_case_with_hyphens()
  Test_a_run_of_anything_else_becomes_one_hyphen()
  Test_a_separator_of_a_path_never_survives()
  Test_a_letter_outside_ascii_is_dropped()
  Test_a_slug_is_unchanged_by_a_second_pass()
  Test_a_slug_that_names_a_device_never_stands_alone()
  Test_a_title_that_merely_holds_a_device_name_is_left_alone()
  Test_a_name_keeps_every_letter_and_its_case()
  Test_a_name_folds_what_a_file_system_forbids()
  Test_a_name_folds_a_separator_above_ascii()
  Test_a_name_that_names_a_device_never_stands_alone()
  Test_a_name_that_names_a_device_in_superscript_is_guarded()
  Test_a_long_name_is_capped_on_a_character()
  Test_a_name_is_unchanged_by_a_second_pass()
enddef
