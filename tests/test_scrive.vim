vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_scrive.vim: tab completion of scrive names for :BartlebyOpen,
# MatchNames and CompleteNames, and ResolveName of scrive.vim. MatchNames
# takes the names as an argument, so its tests need no files. The tests of
# CompleteNames and ResolveName create scrive folders in the binder root
# and remove them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as Sc

const NAMES: list<string> = ['Other', 'My Novel', 'My Screenplay']

# FUNCTION: Create a scrive folder for each name in the binder root, and
# return their paths for RemoveScrives.
def MakeScrives(names: list<string>): list<string>
  var paths: list<string> = names->mapnew((_, n) => Sc.ScrivePath(n))
  for path in paths
    mkdir(path, 'p')
  endfor
  return paths
enddef

def RemoveScrives(paths: list<string>): void
  for path in paths
    delete(path, 'rf')
  endfor
enddef

def Test_prefix_match_ignores_case_and_is_sorted(): void
  assert_equal(['My Novel', 'My Screenplay'], Sc.MatchNames(NAMES, 'my', 'my'))
  assert_equal(['Other'], Sc.MatchNames(NAMES, 'o', 'o'))
enddef

def Test_empty_argument_lists_every_name(): void
  assert_equal(['My Novel', 'My Screenplay', 'Other'], Sc.MatchNames(NAMES, '', ''))
enddef

def Test_name_with_a_space_returns_the_rest_after_the_last_word(): void
  # Typed: My N. Vim replaces only N, the last word.
  assert_equal(['Novel'], Sc.MatchNames(NAMES, 'My N', 'N'))
  # Typed: My and a space. The last word is empty.
  assert_equal(['Novel', 'Screenplay'], Sc.MatchNames(NAMES, 'My ', ''))
enddef

def Test_no_match_is_empty(): void
  assert_equal([], Sc.MatchNames(NAMES, 'xyz', 'xyz'))
enddef

def Test_fuzzy_when_wildoptions_has_fuzzy(): void
  var saved = &wildoptions
  set wildoptions=fuzzy
  assert_equal(['My Novel'], Sc.MatchNames(NAMES, 'nvl', 'nvl'))
  &wildoptions = saved
enddef

def Test_complete_names_reads_the_whole_argument(): void
  var paths = MakeScrives(NAMES)
  var line = 'BartlebyOpen My N'
  assert_equal(['Novel'], Sc.CompleteNames('N', line, strlen(line)))
  RemoveScrives(paths)
enddef

def Test_resolve_name(): void
  var paths = MakeScrives(['My Novel'])
  assert_equal('My Novel', Sc.ResolveName('My Novel'))
  assert_equal('My Novel', Sc.ResolveName('my novel'))
  assert_equal('Unknown', Sc.ResolveName('Unknown'))
  RemoveScrives(paths)
enddef

def Test_resolve_name_does_not_guess_between_two_matches(): void
  var paths = MakeScrives(['Draft', 'DRAFT'])
  # Only on a file system that tells the two folders apart.
  if len(Sc.ListScrives()->filter((_, n) => n ==? 'draft')) == 2
    assert_equal('draft', Sc.ResolveName('draft'))
  endif
  RemoveScrives(paths)
enddef

export def RunAll(): void
  Test_prefix_match_ignores_case_and_is_sorted()
  Test_empty_argument_lists_every_name()
  Test_name_with_a_space_returns_the_rest_after_the_last_word()
  Test_no_match_is_empty()
  Test_fuzzy_when_wildoptions_has_fuzzy()
  Test_complete_names_reads_the_whole_argument()
  Test_resolve_name()
  Test_resolve_name_does_not_guess_between_two_matches()
enddef
